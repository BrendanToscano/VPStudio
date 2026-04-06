# VPStudio UI Remodel Plan

_Last updated: 2026-04-04 09:54 America/Halifax_

## UI Principles

- Prioritize clarity over novelty.
- Make key actions visible without hunting.
- Keep scrolling behavior predictable and stable.
- Prefer graceful loading, empty, and error states over hidden sections.
- Maintain consistent spacing, section rhythm, and interaction feedback.
- Respect visionOS ergonomics: larger touch targets, cleaner hierarchy, less layout jitter.

## Screen Inventory

- Discover
- Search
- Detail (movie)
- Detail (series)
- Player
- Library
- Downloads
- Settings
- Onboarding / setup flow
- Immersive / environments

## Current UI Problems

### Immediate / Active
- Series-detail season switching no longer needs a full-page blocking shell, but the new scoped-loading treatment still needs runtime visual QA on-device/simulator.
- The main remaining cleanup is a final sweep for any Library/Settings outliers after the Settings destination error-surface pass below.

### Known roadmap/UI issues
- Discover hierarchy / scanability needs improvement.
- Refresh-level loading treatment is improved on Discover/Search and Detail, but the new Detail season-switch scoped-loading treatment still needs runtime visual QA.
- Error messaging is more actionable for TMDB setup on Discover/Search, Downloads root failures, Library action failures, and the main Settings destination screens. Remaining gaps are now follow-up outliers, not a broad Settings unknown.
- visionOS list / split-view jank still needs cleanup.
- Sidebar transitions and deep-link routing need polish.
- Compact-window truncation and spacing rhythm need a pass.

## Target Design System / Interaction Rules

- One clear primary action per surface.
- Stable section ordering; avoid content appearing/disappearing in ways that break orientation.
- Loading states should occupy the same structural space as loaded states when possible.
- Scrolling should preserve context and never feel "lost" after an action.
- Empty states should explain what to do next.
- Error states should suggest a recovery path.
- Reusable spacing and card patterns across major screens.

## Phased Implementation Plan

### Phase 1 — User-facing bug killers
1. Fix series detail scrolling regression.
2. Add regression coverage for detail-series interaction flow.
3. Normalize nearby empty/loading states so scrolling targets remain stable.

### Phase 2 — Structural polish
1. Discover hierarchy improvements.
2. Library action-row spacing / sub-folder clarity.
3. Consistent loading and error surface components.

### Phase 3 — Interaction polish
1. Transition polish across detail/player/sidebar flows.
2. Compact-window text and layout cleanup.
3. Accessibility and target-size pass.

## Open Questions

- Should the torrents/results section stay visible for a selected episode even before results arrive, showing loading and guidance in-place? (Current plan: yes.)
- Which surface should be prioritized after series detail: Discover or Library?

## Definition of Done

- Key screens follow one coherent UI plan.
- Major user-facing UI bugs are fixed.
- Important interaction flows are polished.
- Regression coverage exists for changed behavior.
- Remaining deferred items are documented intentionally.

## Run Log

### 2026-04-04 00:05 — Kickoff
- Created the UI remodel plan.
- Set current target to the series-detail scrolling regression.
- Confirmed no active UI-remodel workers are currently running.
- Reusing one completed investigation result as prior context; launching a fresh 3-agent cycle for this run.

### 2026-04-04 00:21 — Series detail scroll regression patched
- Added `ScrollViewReader`-based stream-results scrolling back into `VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift`.
- Added `SeriesDetailScrollPolicy` to keep the scroll/visibility rules unit-testable.
- Kept the torrents/results section mounted for series flows when episode/search context exists, so loading and empty states have a stable destination.
- Removed the duplicate `streamResultsAnchor` from `SeriesDetailLayout` and kept the anchor owned by `DetailTorrentsSection`.
- Fixed the `DetailTorrentsSection` empty-state branch that incorrectly showed `Select an Episode` when an episode was already selected.
- Added regression tests in `VPStudioTests/ViewModels/DetailScrollRegressionTests.swift` covering:
  - scroll policy decisions
  - episode-change re-search freshness reset
  - series load preselection
  - season-change invalidation + re-search context stamping
- A later 15-minute cron tick arrived while this cycle was still active; no duplicate 3-agent cycle was started.

### 2026-04-04 00:24 — Discover hierarchy / scanability pass
- Added `DiscoverHierarchyPolicy` and `DiscoverMediaRowSpec` in `VPStudio/Views/Windows/Discover/DiscoverView.swift`.
- Discover now hides empty catalog rows instead of rendering empty headers/rails.
- Discover catalog row animation delays are now compacted to visible rows, preserving visual rhythm without blank section gaps.
- Added regression tests in `VPStudioTests/ViewModels/DiscoverHierarchyPolicyTests.swift` for:
  - continue-watching visibility policy
  - empty-row suppression
  - canonical section ordering
  - compact delay sequencing
  - section metadata mapping
  - empty-state behavior when no catalog rows are available
- Two of three discover-cycle subagent spawns timed out at gateway level; work continued with direct in-repo implementation and test additions in this cycle.

### 2026-04-04 01:02 — Library header / folder clarity pass
- Split the crowded Library header so the title/count row no longer competes with all utility actions.
- Added `LibraryActionRowPolicy` in `VPStudio/Views/Windows/Library/LibraryView.swift` and moved actions into a dedicated horizontal action row that preserves action order while avoiding tighter title-row compression.
- Added `LibraryFolderLabelPolicy` in `VPStudio/Views/Windows/Library/LibraryView.swift`.
- Renamed the system-root folder chip presentation from raw list names to `Top Level` for clearer meaning.
- Nested folder chips, move destinations, delete labels, and delete confirmation copy now use hierarchy-aware paths like `Parent › Child`.
- Added regression tests in `VPStudioTests/LibraryViewPolicyTests.swift` covering:
  - action row order stability
  - refresh availability / disabled states
  - system-root `Top Level` presentation
  - top-level manual folder naming
  - nested breadcrumb labels
  - duplicate child-name disambiguation
  - missing-parent fallback behavior
- Remaining gap: spacing quality itself still needs runtime visual QA at narrow and wide Library window sizes.

### 2026-04-04 01:48 — Discover AI curated redesign pass
- Reworked the Discover AI curated section from a rail of small text-only cards into a banner-first module in `VPStudio/Views/Windows/Discover/DiscoverView.swift`.
- Added `DiscoverAICuratedSectionPolicy` to make section visibility, loading, empty-state, and lead/supporting recommendation splits testable.
- Added a lead `AICuratedHeroCard` plus supporting text rows, matching the roadmap goal of “banner + text, not block cards.”
- Added explicit section states for:
  - loading with banner/row skeletons
  - empty recommendations with actionable copy
  - disabled regenerate button while refresh is in flight
- Added `aiHeroPreview` plus hero-refresh logic in `VPStudio/ViewModels/Discover/DiscoverViewModel.swift` so the lead AI recommendation can upgrade to TMDB-backed artwork/details when metadata is available while still falling back cleanly when it is not.
- Added regression coverage in `VPStudioTests/ViewModels/DiscoverAITests.swift` for:
  - AI section policy hidden/loading/empty behavior
  - lead/supporting recommendation splitting and cap
  - TMDB-backed hero preview enrichment
  - fallback hero preview behavior without metadata
  - hero-preview advancement after removing the lead recommendation
  - hero-preview upgrade after a TMDB key becomes available
  - hero-preview clearing when recommendations are gone
- Remaining gap: the final visual fidelity of the new banner/text composition still needs manual simulator/device QA because the workspace currently lacks a UI/snapshot harness.

### 2026-04-04 02:33 — Loading-surface consistency pass (Library + Downloads)
- Added `LibraryLoadingSurfacePolicy` in `VPStudio/Views/Windows/Library/LibraryView.swift`.
- Library now shows a shared `LoadingOverlay` while the current list/folder/sort selection is reloading instead of briefly presenting a false empty state.
- Added load-token tracking in `LibraryView` so an older canceled reload cannot clear the current loading surface prematurely.
- Added `DownloadsLoadingSurfacePolicy` in `VPStudio/Views/Windows/Downloads/DownloadsView.swift`.
- Downloads now uses the shared `LoadingOverlay` for root loading instead of raw `ProgressView("Loading Downloads...")` branches.
- Kept Downloads content visible whenever groups already exist, even if a background refresh is running.
- Added regression coverage in `VPStudioTests/LoadingSurfaceContractTests.swift` for:
  - library loading-surface policy behavior
  - downloads loading-surface policy behavior
  - `ContentView` boot loading contract
  - `LibraryView` loading-surface wiring contract
  - `DownloadsView` shared loading-surface adoption contract
- Extended `VPStudioTests/AppStateBootstrapMatrixTests.swift` to assert bootstrap always clears `isBootstrapping` after `AppState.bootstrap()` completes.
- Remaining gap: Discover/Search/Detail still need a follow-up pass to separate initial-load surfaces from refresh/scoped-work loading treatments.

### 2026-04-04 03:21 — Error messaging consistency pass (TMDB setup gate)
- Added `AppError.tmdbSetupRequired(feature:)` plus `requiresTMDBSetupAction` in `VPStudio/Core/Support/AppError.swift` so TMDB-setup failures share one source of truth.
- Discover now uses the shared TMDB setup error helper in `VPStudio/ViewModels/Discover/DiscoverViewModel.swift` instead of feature-local hard-coded strings.
- Search now surfaces missing-TMDB configuration as a real `AppError` in `VPStudio/ViewModels/Search/SearchViewModel.swift` for:
  - direct text search
  - genre browse
  - special mood-card browse
- Search query edits now clear stale setup errors when the user changes away from the previously submitted query, returning the shell to an idle drafting state until the next explicit search.
- Extended `ExploreErrorView` in `VPStudio/Views/Components/AsyncStateViews.swift` with an optional `Open Settings` action for setup-gated failures.
- Wired `VPStudio/Views/Windows/Search/SearchView.swift` to send users directly to Settings from the Search error card.
- Added regression coverage in:
  - `VPStudioTests/ViewModels/DiscoverViewModelTests.swift`
  - `VPStudioTests/ViewModels/SearchViewModelTests.swift`
  - `VPStudioTests/ViewModels/SearchViewModelExplorePhaseTests.swift`
- Coverage now locks down:
  - shared Discover TMDB setup error copy source
  - Search setup-error surfacing for text search / genre browse / mood browse
  - Search explore-phase moving to `.error` instead of fake `.empty` when metadata is unavailable
  - returning to idle after editing away from a failed unconfigured search
- One child regression-strategy run timed out and returned unusable external content, so this cycle’s test plan was authored directly from the local codebase instead.

### 2026-04-04 03:42 — Refresh-level loading treatment pass (Discover/Search + Detail reload retention)
- Added `DiscoverLoadingPresentationPolicy` in `VPStudio/Views/Windows/Discover/DiscoverView.swift`.
- Discover now keeps existing hero/rows visible during refresh when content already exists, and only uses `DiscoverSkeletonView` for true initial/no-content loads.
- Added inline refresh chrome (`InlineLoadingStatusView`) for Discover refresh instead of full-page reset flicker.
- Added `SearchLoadingPresentationPolicy` in `VPStudio/Views/Windows/Search/SearchView.swift`.
- Search now keeps retained results visible while requerying and shows a compact `Updating results…` indicator instead of swapping back to `ExploreSkeletonView` when content is already present.
- Added `DetailRefreshRetentionPolicy` in `VPStudio/ViewModels/Detail/DetailViewModel.swift` so same-preview metadata reloads preserve existing detail content until replacement data arrives.
- Added `DetailRefreshLoadingPresentationPolicy` in `VPStudio/Views/Windows/Detail/DetailView.swift` to distinguish:
  - blocking overlay for first-load detail / season-episode loads
  - non-blocking inline refresh indicator for same-preview detail reloads
- Added regression coverage in `VPStudioTests/ViewModels/RefreshLoadingPolicyTests.swift` for:
  - Discover blocking vs refreshing presentation decisions
  - Search blocking vs retained-results refreshing decisions
  - Detail blocking-overlay vs inline-refresh decisions
  - Detail same-context refresh retention decisions
- Remaining gap: Detail season switching still blocks the whole page shell and needs a dedicated scoped-loading pass if we want fully consistent refresh treatment.

### 2026-04-04 04:35 — In-flight series-detail cycle preserved (no duplicate run)
- Re-read `docs/ROADMAP_v1.1.md` and `docs/UI_REMODEL_PLAN.md` for this scheduled tick.
- Detected that a prior 3-agent series-detail cycle for the scrolling/loading surface was already in flight.
- Did **not** launch a duplicate cycle.
- Kept the active target on the series-detail season-switch scoped-loading / retained-context pass.
- Waiting for the already-started child-agent outputs before landing the next bounded implementation change.

### 2026-04-04 05:56 — Series-detail season-switch scoped-loading pass
- Narrowed `DetailRefreshLoadingPresentationPolicy` in `VPStudio/Views/Windows/Detail/DetailView.swift` so season switching no longer triggers the full-page blocking overlay once detail content already exists.
- Updated `VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift` so the Episodes area stays structurally mounted during season changes with:
  - inline loading status
  - skeleton placeholders
  - season-scoped explanatory copy
- Disabled season-tab and primary Play interaction while a season swap is loading, preventing stale episode/play actions during the handoff.
- Updated `SeriesDetailScrollPolicy` so the streams section stays visible when a series episode is selected, even before a new search starts, matching the intended stable lower-page layout.
- Updated `VPStudio/ViewModels/Detail/DetailViewModel.swift` so `loadSeason` clears stale episode/results context immediately before awaiting new episode data, instead of leaving old season content interactable behind a page-level blocker.
- Added regression coverage in:
  - `VPStudioTests/ViewModels/DetailScrollRegressionTests.swift`
  - `VPStudioTests/ViewModels/RefreshLoadingPolicyTests.swift`
- New coverage locks down:
  - selected-episode stream-section visibility
  - primary-play busy state during season loads
  - non-blocking season reload overlay policy
  - episodes-shell visibility during season loads
  - immediate stale-context clearing before delayed season data returns
- Remaining gap: this turn did not complete simulator/device visual QA, so final feel/spacing verification is still pending.

### 2026-04-04 06:29 — Downloads root error-surface consistency pass
- Promoted Downloads root failures from string-first state to typed `AppError` state in `VPStudio/ViewModels/Downloads/DownloadsViewModel.swift`.
- Kept a compatibility `errorMessage` computed property for lightweight callers/tests while moving the underlying source of truth to `rootError`.
- Added `DownloadsErrorSurfacePolicy` in `VPStudio/Views/Windows/Downloads/DownloadsView.swift`.
- Downloads now distinguishes between:
  - root error surface when the screen is empty and the root load fails
  - inline non-blocking error banner when content already exists and a later failure happens
- Replaced the raw red `Text(error)` root treatment in `DownloadsView` with:
  - a retryable root error card using typed `AppError` description + recovery suggestion
  - an inline banner using `AppErrorInlineView` plus Retry when groups already exist
- Added regression coverage in:
  - `VPStudioTests/ViewModels/DownloadsViewModelTests.swift`
  - `VPStudioTests/DownloadsErrorSurfacePolicyTests.swift`
  - `VPStudioTests/ErrorSurfaceContractTests.swift`
- New coverage locks down:
  - typed `rootError` mapping and clearing behavior
  - retained Downloads content on refresh/mutation failures
  - root-vs-inline error-surface policy decisions
  - removal of raw root `Text(error)` error rendering from `DownloadsView`
- Remaining gap: final visual hierarchy/spacing of the Downloads root error card vs empty state still needs simulator/device QA.

### 2026-04-04 07:29 — Library action error-surface separation pass
- Added `LibraryActionFailurePolicy`, `LibraryFeedbackMessage`, and `LibraryFeedbackPresentationPolicy` in `VPStudio/Views/Windows/Library/LibraryView.swift`.
- Library now separates real action/mutation failures from ordinary status copy instead of funneling both through the same `statusMessage` text path.
- Added typed `actionError` state in `LibraryView` and routed mutation failures through `AppErrorInlineView` for:
  - folder creation
  - move-to-folder
  - remove-from-library
  - duplicate-title refresh
  - folder reorder persistence
  - folder deletion
- Kept success/info updates as lightweight status copy so messages like `Moved to …`, `Deleted …`, and `Refresh complete …` remain calm non-error feedback.
- Added regression coverage in:
  - `VPStudioTests/LibraryViewPolicyTests.swift`
  - `VPStudioTests/ErrorSurfaceContractTests.swift`
- New coverage locks down:
  - error-over-status precedence in Library feedback presentation
  - readable fallback copy for common Library action failures
  - source-level use of `AppErrorInlineView` and typed `actionError` in `LibraryView`
  - removal of direct `statusMessage = error.localizedDescription` assignment in the Library surface
- Remaining gap: root load / empty-state failures in Library still collapse through `try?` fetches and do not yet present a first-class typed error state.

### 2026-04-04 08:03 — Settings error-surface cycle started
- Re-read `docs/ROADMAP_v1.1.md` and `docs/UI_REMODEL_PLAN.md` for this scheduled tick.
- Confirmed no active remodel workers were already running.
- The next bounded target remains the Settings error-surface consistency pass.
- Parent-session shell search for the live Settings surface was denied by policy, so this turn is using the 3-agent cycle to locate the concrete Settings files and return an exact bounded implementation/test plan instead of guessing.
- No repo edits were made yet beyond this trace entry.

### 2026-04-04 08:46 — Settings targeting blocked pending file-path discovery
- Confirmed the prior Settings subagent cycle is no longer active.
- Checked the spawned child sessions and they returned no usable output.
- Parent-session repo search is still denied, so I cannot safely identify the live Settings Swift surface from here without guessing at paths.
- No Settings implementation change was made this tick.
- Next safe move is to get the concrete Settings file path(s) from Brendan or restore repo-search capability for this session.

### 2026-04-04 09:33 — Waiting on concrete Settings file path
- Re-read the roadmap and remodel plan for this scheduled tick.
- Confirmed there are still no active remodel workers in flight.
- The blocker is unchanged: parent-session repo search is denied and prior Settings discovery runs produced no usable file-path output.
- No new implementation change was made this tick.
- Work remains paused on Settings until the concrete Swift file path(s) are provided or repo search becomes available again.

### 2026-04-04 09:37 — Settings destination error-surface consistency pass
- Disabled the recurring GPT UI remodel cron job at the user’s request; manual implementation took over from this point.
- Added shared Settings feedback views in `VPStudio/Views/Windows/Settings/Core/SettingsFeedbackViews.swift`.
- Replaced string-first / alert-based / silent-save error handling across the main Settings destination screens:
  - `VPStudio/Views/Windows/Settings/Destinations/MetadataSettingsView.swift`
  - `VPStudio/Views/Windows/Settings/Destinations/DebridSettingsView.swift`
  - `VPStudio/Views/Windows/Settings/Destinations/IndexerSettingsView.swift`
  - `VPStudio/Views/Windows/Settings/Destinations/SubtitleSettingsView.swift`
- Metadata now surfaces load/save/test failures through typed `AppError` state and uses inline success/warning notices instead of ad-hoc string status.
- Debrid now replaces the old alert-driven root error path with typed inline surface feedback and converts token validation failures to structured inline errors.
- Indexer now replaces save/test string alerts with inline typed error feedback plus separate success/warning notices.
- Subtitle settings no longer silently swallow save/load failures via `try?`; failed reads/writes now surface through typed inline error UI.
- Extended `VPStudioTests/ErrorSurfaceContractTests.swift` with Settings contract coverage so these screens do not regress back to string-first alerts/silent writes.
- Remaining gap: this pass did not add simulator/device QA for Settings layout polish, and any less-used Settings subsections not covered above may still need follow-up review.

### 2026-04-04 09:54 — Discover top-hero fallback regression fix
- Found a Discover regression where the top hero block only rendered when `viewModel.featuredBackdrops` was non-empty, so the entire top section vanished whenever the featured-backdrop feed came back empty.
- Added `DiscoverHeroPresentationPolicy` in `VPStudio/Views/Windows/Discover/DiscoverView.swift`.
- Discover hero now falls back to the first populated source in this order:
  - featured backdrops
  - trending movies
  - trending shows
  - popular
  - top rated
  - now playing
  - continue watching
- Updated the hero `TabView` and auto-rotation logic to use the fallback hero items instead of only `featuredBackdrops`.
- Added regression coverage in `VPStudioTests/ViewModels/DiscoverHierarchyPolicyTests.swift` for:
  - featured-backdrop preference
  - fallback to first populated catalog source
  - fallback to continue-watching when catalog rows are empty

### Next Target
- Runtime QA for the series-detail scoped-loading pass and a final sweep for any remaining Library/Settings outliers.

### Blockers
- No blocking implementation blocker right now; main remaining limitation is lack of shell-based test execution / git commit from this chat session.
