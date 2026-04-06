# Architecture Report: VPStudio Search/Discover

**Layer:** Views + ViewModels (Search, Discover, Explore)  
**Date:** 2026-03-20  
**Scope:** `VPStudio/Views/Windows/Search/`, `VPStudio/Views/Windows/Discover/`, `VPStudio/ViewModels/Search/`, `VPStudio/ViewModels/Discover/`, `VPStudio/Models/ExploreGenreCatalog.swift`

---

## 1. Architecture Overview

### Pattern: `@Observable` + `@MainActor` ViewModels

The codebase uses Apple's modern Observation framework (`@Observable`, `@MainActor`) rather than Combine's `@Published`. ViewModels are plain Swift classes annotated `@Observable @MainActor`, created with `@State` in the parent view and passed down via `@Bindable` for two-way binding.

**SearchViewModel** owns all search logic: query management, debouncing, pagination, genre/mood-card browsing, AI recommendations, recent searches, and TMDB API coordination.

**DiscoverViewModel** owns all home-screen content: trending/popular/top-rated/now-playing rows, continue-watching from local DB, featured hero backdrops, and AI-curated recommendations.

**DiscoverFilters** is a plain `Sendable` struct that lives in `MetadataProvider.swift` — it is the shared contract between ViewModels and the `MetadataProvider` network layer.

---

## 2. Clean Structural Choices

### 2a. `ExplorePhase` decouples UI from data state

`SearchViewModel` derives `explorePhase` from underlying boolean flags (`isSearching`, `error`, `results`, `selectedGenre`, `activeMoodCard`). The View reads only `explorePhase` via a `switch`, so header/search-bar/filter-bar never re-render when results change. The ViewModel comment explicitly calls this out. ✅

### 2b. `SearchResultsGrid` extracted to minimize re-renders

`SearchResultsGrid` is a private nested struct (not a separate file) that re-renders only when `results` or `isLoadingMore` change. The comment explains the intent: "only this subview re-renders when results change." This is the right granularity. ✅

### 2c. `ExplorePhase` is a plain enum, not a state machine enum with associated values

The five cases (`idle`, `searching`, `results`, `empty`, `error`) are mutually exclusive and stateless — exactly what a UI phase enum should be. ✅

### 2d. `activeMoodCard` as an explicit "browse mode" signal

`SearchViewModel` uses `activeMoodCard: ExploreMoodCard?` as a clear signal that the current results came from a mood-card tap rather than text search. The `isGenreBrowsing` computed property makes this explicit. ✅

### 2e. `searchGeneration` for stale-result discard

`searchGeneration` is a monotonically-increasing `Int` captured at search start. Each async Task compares it on completion to detect cancellation/stale responses. This correctly handles the case where a second search starts before the first completes. ✅

### 2f. `genreCacheByType` keyed by `MediaType`

Genre list is cached per `MediaType` to avoid redundant API calls when switching between Movies/TV Shows. The cache is invalidated when the API key changes. ✅

### 2g. `ExploreGenreCatalog` is a pure static catalog

`ExploreMoodCard` instances are defined as a static array in `ExploreGenreCatalog`. No network dependency, no loading state, no async complexity — just data. ✅

### 2h. `DiscoverViewModel.load` uses structured concurrency correctly

`async let` fetches all categories concurrently, then a first-error-wins strategy determines whether to surface an error. This maximizes parallelism while keeping error handling deterministic. ✅

---

## 3. Messy / Problematic Areas

### 3a. SearchView is enormous (~800 lines in a single file)

`SearchView.swift` mixes:
- The root `SearchView` struct (~140 lines of `body`)
- `SearchQueryBar` private subview (~55 lines)
- `SearchResultsGrid` private subview (~20 lines)
- `InlineFilterChip` public view (~40 lines)
- `SearchLanguageOption` enum (~50 lines)
- `SearchViewModel` class (~640 lines — this is a SECOND file worth of code inside the same file)

**The View file contains the ViewModel.** This violates single-responsibility and makes navigation/find-in-file painful. View and ViewModel should always be in separate files. ❌

### 3b. Filter state exists in TWO places: View AND ViewModel

`SearchView` owns:
```swift
@State private var selectedYear: Int? = nil
@State private var selectedLanguages: Set<String> = ["en-US"]
```

`SearchViewModel` also owns:
```swift
var yearFilter: Int?
var languageFilters: Set<String> = ["en-US"]
```

The `ExploreFilterSheet` binds to the **View's** state. On apply, it calls `viewModel.applyYearFilter()` / `viewModel.applyLanguageFilters()` which copies View state → ViewModel state. On sheet open, an `onChange(of: isShowingFilters)` syncs ViewModel → View state.

This round-trip exists because the sheet needs local editable state. The fix would be to have the ViewModel own a `SearchFilterDraft` (which already exists!) and bind the sheet directly to it. The `SearchFilterDraft` struct is already defined in the file but is **never used for this purpose**. ❌

### 3c. `inlineFilterBar` synthesizes active filters from 4 separate booleans

The filter bar reads `viewModel.yearRangePreset`, `viewModel.yearFilter`, `viewModel.languageFilters`, `viewModel.selectedGenre`, `viewModel.sortOption` to construct pill chips. There is no single `activeFilters` array to iterate — instead there are 4 independent `@ViewBuilder` branches. Adding a new filter type requires touching 5+ places. ❌

### 3d. `activeMoodCard` is an implicit state machine with hidden rules

`selectMoodCard()` can set `activeMoodCard`, which then influences:
- `isGenreBrowsing` (genre browse vs text search)
- `loadMore()` dispatch (mood-card paginate vs genre paginate vs text paginate)
- `requery()` behavior
- `clear()` resets it

But these rules are scattered across 6+ methods. The state transitions (`selectGenre` → `browseGenre`, `selectMoodCard` → `discoverMoodCard`, `search`) have overlapping but non-identical reset logic. The `clear()` function resets everything except `query` — but `activeMoodCard` IS cleared in `clear()`. The mental model is: "there are three entry points (text search, genre browse, mood card) and they each partially reset each other's state." This is a distributed state machine that is hard to reason about. ❌

### 3e. `ExploreFilterSheet` re-fetches genres as a side effect of `onChange`

When the sheet opens (`isShowingFilters` becomes `true`), if `viewModel.genres.isEmpty`, `viewModel.loadGenres()` is called. This means opening the filter sheet can trigger a network request as a side effect of a binding toggle. There is no loading state shown for this — the genres just appear after the sheet is already open. ❌

### 3f. `SearchView.onChange(of: viewModel.selectedType)` has branching side effects

```swift
.onChange(of: viewModel.selectedType) { _, _ in
    if let card = viewModel.activeMoodCard {
        viewModel.selectMoodCard(card)  // re-derive genre IDs for new type
    } else if viewModel.selectedGenre != nil {
        viewModel.loadGenres()
        viewModel.selectGenre(viewModel.selectedGenre)  // reload + re-apply same genre
    } else {
        viewModel.requery()
    }
}
```

Three different behaviors depending on which of three internal state variables is non-nil. This is a dispatch table masquerading as an `onChange`. ❌

### 3g. `userRatings` is owned by the View, not the ViewModel

`SearchView` and `DiscoverView` both own `@State private var userRatings: [String: TasteEvent] = [:]` and both have `loadUserRatings()` methods that hit the database. `DiscoverViewModel` does not know about user ratings — it passes raw `MediaPreview` arrays to `MediaRow`, and the View layer annotates them with `userRatings` before calling `MediaCardView`.

This means:
- The UI layer owns a database-fetched cache
- Two views both call `fetchTasteEvents` separately
- No shared cache across the two screens
- ViewModels cannot include ratings in sorting/filtering logic

This is a separation-of-concerns violation. ❌

### 3h. `refreshLocalPersonalizationState` runs inside `onReceive` callbacks

Both `DiscoverView` and `SearchView` respond to `.tasteProfileDidChange` notifications by reloading ratings and calling ViewModel refresh. These are fire-and-forget `Task` closures. If the view disappears between the notification and task completion, the `Task` may complete against a deallocated view. The `.onDisappear` cancel is present but there's no `Task` cancellation tracking. ❌

### 3i. DiscoverView has 8 hardcoded `MediaRow` calls

```swift
MediaRow(title: "Trending Now", ...)   // hardcoded row 1
MediaRow(title: "Trending TV Shows", ...) // hardcoded row 2
MediaRow(title: "Popular", ...)        // hardcoded row 3
...
MediaRow(title: "Now Playing", ...)    // hardcoded row 8
```

The View does not know these are 8 different TMDB categories — it just renders them. If you wanted to add a ninth row or make rows conditional, you must edit the View. This data is not driven by a `[MediaRowDescriptor]` array that the ViewModel owns. ❌

### 3j. `EnvironmentPreviewRow.swift` is in Discover/ but imports visionOS-only types

`EnvironmentPreviewRow.swift` (which is in `Views/Windows/Discover/`) contains:
```swift
#if os(visionOS)
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
```

This file is exclusively compiled for visionOS. The filename suggests a "preview row" component but it actually contains `EnvironmentPickerSheet` and `EnvironmentPreviewCard` — a full environment picker modal, not a row in the Discover sense. Misleading name, wrong directory. ❌

### 3k. `recentSearches` save/load races

`saveRecentSearches` and `loadRecentSearches` both dispatch `Task`s that run without awaiting. `loadRecentSearches` sets `self.recentSearches` from a background task. If the view is dismissed before it completes, the task still runs. If the user opens the view again quickly, two loads could race. ❌

### 3l. Hero auto-advance uses a `while !Task.isCancelled` loop

```swift
.task {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(8))
        ...
        withAnimation { currentHeroIndex = ... }
    }
}
```

This is a valid pattern but `currentHeroIndex` is a plain `@State Int` updated from a background-safe context. The animation fires on the main actor correctly, but the loop itself doesn't use `actorIsolation` semantics — it relies on `Task.isCancelled` checked on each iteration. ✅ (acceptable, but fragile if cancellation isn't cooperative)

### 3m. `filterOutWatchedAndRated` in DiscoverViewModel makes multiple database round-trips

The function makes **4 separate `await database.fetch...()` calls** sequentially: `fetchTasteEvents`, `fetchWatchHistory`, `fetchLibraryEntries` (×3 for different list types), and `fetchMediaItems` to resolve library titles. These could all be batched into 1–2 calls with proper SQL joins or a single repository method. ❌

### 3n. `SearchViewModel.clear()` does not cancel `genreLoadTask`

`cancelInFlightWork()` cancels `searchTask`, `loadMoreTask`, `debounceTask`, `aiTask`, and `genreLoadTask`. However `SearchView.clear()` calls `cancelInFlightWork()` — so `genreLoadTask` IS cancelled. But `selectGenre(nil)` explicitly does NOT cancel any task — it just clears state and calls `requery()`. This is fine but inconsistent: some state transitions cancel, others don't. ❌

### 3o. `SearchFilterDraft` exists but is unused for filter binding

`SearchFilterDraft` is a `Sendable` struct capturing all filter state. It is constructed in `currentFilterDraft` computed property. But `ExploreFilterSheet` binds to raw `@Binding` properties instead of a `SearchFilterDraft`. The `applyFilterDraft` method exists in the ViewModel but is never called from the View. Dead code that hints at a better design. ❌

---

## 4. Architectural Choices Likely Contributing to UX Friction

| Issue | How it manifests in UX |
|---|---|
| **Filter state in two places** (3b) | Filter sheet may show stale values; sync bugs on rapid apply/cancel |
| **`inlineFilterBar` as imperative ViewBuilder** (3c) | Filter chips don't animate predictably; hard to add new filter types |
| **`onChange(of: selectedType)` dispatch** (3f) | Type switch triggers opaque reloads; user may not understand why |
| **`ExploreFilterSheet` side-effect genre load** (3e) | Genres may appear after sheet is already open; jarring |
| **`userRatings` in View not ViewModel** (3g) | Ratings loaded separately in each screen; no cross-screen cache |
| **8 hardcoded MediaRow calls** (3i) | Discover content is not data-driven; adding/modifying rows is a code change |
| **Hero loop using `while !Task.isCancelled`** (3l) | Index wraps without user control; no pause/swipe-back gesture |
| **`activeMoodCard` implicit state machine** (3d) | "New Releases" / "Coming Soon" / genre cards each have subtly different reset/pagination behavior; hard to predict |
| **`SearchFilterDraft` dead code** (3o) | The filter model was refactored but the sheet binding was not updated to match |

---

## 5. Key Structural Metrics

| Metric | Value |
|---|---|
| `SearchView.swift` lines | ~830 (View + ViewModel in same file) |
| `SearchViewModel` methods | ~45 |
| `SearchView` @State vars | 8 (plus 1 @StateObject-equivalent for VM) |
| `DiscoverViewModel` methods | ~20 |
| `DiscoverView` @State vars | 7 |
| `ExploreFilterSheet` bindable vars | 5 |
| Filter state ownership points | 2 (View + ViewModel) |
| Database calls per rating load | 1 (per view) |
| Notification observers in Search | 3 |
| Notification observers in Discover | 4 |

---

## 6. Recommendations (Priority Order)

1. **Move `SearchViewModel` to its own file** — restore single-responsibility; the file mixing is the root of many maintenance problems.

2. **Unify filter state: use `SearchFilterDraft`** — bind `ExploreFilterSheet` to a `SearchFilterDraft` on the ViewModel (or a draft copy). Remove the View's `selectedYear` and `selectedLanguages` state entirely. This eliminates the sync-on-open/sync-on-apply dance.

3. **Move `userRatings` into a shared repository or the ViewModel layer** — both Search and Discover need ratings; load once, cache in a `@Observable` service, inject via `Environment`.

4. **Replace 8 hardcoded `MediaRow` calls with a data-driven approach** — `DiscoverViewModel` exposes `rows: [DiscoverRow]` where `DiscoverRow` has `title`, `symbol`, and `items`. The View renders `ForEach(rows)`. Add a `RefreshableRow` for continue-watching.

5. **Refactor `activeMoodCard` state machine** — replace implicit dispatch via `requery()` with explicit `BrowseMode` enum: `textSearch(String)`, `genreBrowse(Genre)`, `moodCard(ExploreMoodCard)`, `idle`. Each mode has its own pagination closure. Makes transitions explicit and testable.

6. **Batch `filterOutWatchedAndRated` database calls** — consolidate into a single `fetchPersonalizationState()` repository method.

7. **Extract `inlineFilterBar` logic into a `FilterBarViewModel`** — the current 150-line `ViewBuilder` body reads 8+ ViewModel properties; encapsulate filter chip state into a dedicated type.

8. **Rename `EnvironmentPreviewRow.swift`** — it contains `EnvironmentPickerSheet`, not a row component. Wrong name, wrong directory.
