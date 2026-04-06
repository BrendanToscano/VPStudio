# VPStudio Bug Audit: Library title cards load slowly

## Scope
- **Issue:** Investigate library title card loading latency and whether cards fail to find title/metadata.
- **Target path:** `VPStudio/Views/Windows/Library/LibraryView.swift` and supporting services/models.
- **Constraint:** Read-only investigation; no code edits.

## Pipeline audit (DB → title → metadata → poster/art → async tasks → cache → render)

### 1) DB fetch and list load
- `LibraryView` triggers load via:
  - `.task`/`onAppear`
  - `onChange` on `selectedList`, `selectedFolderID`, `sortOption`
  - `libraryDidChange` notification
  - Explicit call paths after import/move/remove operations.
- `scheduleReload()` cancels prior `loadTask` and starts `loadSelection()`.
- `loadSelection()` sets diagnostics start/finish (`.libraryLoadStarted/.libraryLoadFinished`) then:
  - history path -> `loadHistoryEntries()`
  - watchlist/favorites path -> `loadFolders()` + `loadLibraryEntries()`.
- `loadLibraryEntries()` reads entries with `database.fetchLibraryEntries(listType:folderId:sortOption:)`.
- `fetchLibraryEntries` routes title/year sorts through SQL `LEFT JOIN media_cache m ON m.id = ul.mediaId` and `ORDER BY m.title...` when title sort is selected.
- `loadHistoryEntries()` reads watch_history and calls `loadMediaItemsIfMissing(ids: displayedHistoryMediaIDs)`.
- `loadMediaItemsIfMissing(ids:)` only loads missing IDs in one query: `database.fetchMediaItems(ids:)` and writes them into local `@State var mediaItems: [String: MediaItem]`.

### 2) Title matching / title fallback
- `preview(for:)` performs exact lookup by media ID key:
  - if `mediaItems[mediaID]` exists -> builds preview from that `MediaItem`.
  - else fallback `MediaPreview(id: mediaID, title: mediaID.hasPrefix("tt") ? "IMDb: \(mediaID)" : mediaID, posterPath: nil)`.
- `historyPreview(for:)` also uses fallback title from watch_history only when media item absent.
- **No title-based search/match is performed in this pipeline.** Titles are not resolved by fuzzy matching at render time.

### 3) Metadata lookup path
- In list flow, there is no live metadata lookup. It only reads `media_cache` and shows fallback if missing.
- `TraktSyncOrchestrator` intentionally inserts/ensures a **stub** `MediaItem` before any TMDB fetch with:
  - title/year/media type and `posterPath=nil`.
- `LibraryCSVImportService` upserts `MediaItem` from CSV with title/year/imdb rating only and does **not** fetch TMDB metadata.
- Metadata fetch is only used in detail flow (`DetailViewModel.loadDetail -> getDetail(id:type:)`).

### 4) Poster/art loading
- `MediaCardView` renders poster with `AsyncImage(url: item.posterURL)`.
- `MediaItem.posterURL` builds URL only when `posterPath != nil`.
- For `.empty` phase, `MediaCardView` currently shows `posterPlaceholder.overlay(ProgressView())`.
- A missing `posterPath` therefore keeps the card in a loading visual state even though no network fetch is in flight for that card.

### 5) Async task scheduling
- Library load tasks are serial per view via one mutable `loadTask` and cancellation before relaunch.
- There is **no background metadata hydration queue** tied to library rendering; only on-demand in detail view.
- Detail flow has its own scheduling (`tmdbReloadTask`, `libraryReloadTask`, etc.) but does not re-key metadata from entry ID mismatches (see root-cause below).

### 6) Caching behavior
- In-memory cache: `mediaItems: [String: MediaItem]` survives while view is alive and only grows via explicit fetches.
- DB cache: `media_cache.id` is PK and includes `lastFetched`, but there is no TTL-based refresh enforced by this pipeline.
- `fetchMediaItems(ids:)` uses exact ID set match and does not try alternate keys.

## Likely root cause (single issue)
### Metadata key canonicalization mismatch prevents rows from resolving to the same entry card

Evidence chain:
- Trakt extraction stores ids as IMDb if present, otherwise `tmdb-<id>` (`extractMediaId` / list pulls).
- Stub items are created with that same id (`ensureMediaItem(from:mediaId:)`) and `id=mediaId` in DB.
- On detail open, `DetailViewModel.loadDetail` requests detail with `preview.tmdbId ?? preview.id` and then saves result from `TMDBService.getDetail(...)`.
- `TMDBDetailResponse.toMediaItem` writes `item.id` as IMDb ID when available (`externalIds.imdbId`) or `tmdb-<id>` fallback.
- Therefore a detail fetch for a `tmdb-...` entry commonly saves the enriched metadata under a **different key** (`tt...`) than the library entry key.
- The list pipeline only indexes by exact mediaId; if it expects `tmdb-...` and only enriched key is `tt...`, `preview(for:)` continues to fall back to raw ID + nil poster, which matches the observed “title card loading/placeholder” behavior.

### Why this matches your symptom hypothesis
- The code confirms cards are not doing title matching, and fallback is id-based.
- Missing metadata (especially poster path) yields a spinner-like empty-state card.
- So yes: cards are effectively failing to find usable metadata for some entries, and that is very likely the primary long-load condition.

## Best fix strategy
1. **Unify media identifier model for cache lookups**
   - Keep one canonical key for library/card lookup (or keep aliases).
   - When detail returns `tt...` for a requested `tmdb-...` entry, persist a stable mapping or write a secondary alias row so `preview(for:)` can resolve either key.
2. **Hydrate library metadata after ingest/sync (not only in detail view)**
   - Add a small background pass for rows with nil poster/backdrop or stale data.
   - Use `tmdbId` first, then imdb fallback, then search fallback.
3. **Keep UI honest for missing art**
   - In `MediaCardView`, avoid indefinite `ProgressView` when `posterURL == nil` (URL absent means no poster load is even happening).
   - Show static placeholder immediately and optionally a separate small “No artwork” state.

## Relevant files
- `VPStudio/Views/Windows/Library/LibraryView.swift`
- `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
- `VPStudio/Services/Import/LibraryCSVImportService.swift`
- `VPStudio/ViewModels/Detail/DetailViewModel.swift`
- `VPStudio/Services/Metadata/TMDBService.swift`
- `VPStudio/Models/MediaItem.swift`
- `VPStudio/Views/Components/MediaCardView.swift`
- `VPStudio/Core/Database/DatabaseManager.swift`
