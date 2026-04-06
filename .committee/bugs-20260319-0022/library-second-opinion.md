# Bug Review: library title cards load slowly

## Finding (root-cause direction)
**Primary culprit: metadata matching/enrichment, not title resolution.**

Library cards build titles locally and synchronously from cache; there is no expensive per-card title lookup on render.

## Pipeline audit

1. **Library list load path**
- `LibraryView.loadSelection()` -> `loadLibraryEntries()` / `loadHistoryEntries()` then `loadMediaItemsIfMissing()` (`Views/Windows/Library/LibraryView.swift:509-580`).
- `loadMediaItemsIfMissing` does a single DB read for missing `mediaId`s; no network call at this stage.

2. **Title resolution path (fast/local)**
- `preview(for:)` returns fields from cached `MediaItem` when present (`LibraryView.swift:594-606`).
- Missing cache fallback is immediate and deterministic:
  - IMDb IDs become `"IMDb: <id>"` if `mediaID.hasPrefix("tt")`, else raw `mediaID` (`LibraryView.swift:607-616`).
- So title display is not gated on metadata fetch latency.

3. **Metadata/poster path (the choke point)**
- `MediaCardView` renders poster via `AsyncImage(url: item.posterURL)` and for `.empty` always shows `ProgressView` (`Views/Components/MediaCardView.swift:15-27`).
- `MediaPreview.posterURL` is nil unless `posterPath` exists (`Models/MediaItem.swift:123-130`).
- Missing `posterPath` on many imported/synced entries therefore produces long-running “loading” UI even when metadata/title is already present.

4. **Where metadata is dropped to stubs**
- Trakt sync inserts stub rows with title but **nil poster/backdrop** and no subsequent metadata hydrate call (`Services/Sync/TraktSyncOrchestrator.swift:697-715`), then only says this is so LibraryView can display “before TMDB metadata is fetched”.
- CSV import also writes bare cache rows (title/year/rating only) and never enriches from TMDB (`Services/Import/LibraryCSVImportService.swift:359-394`).
- `TMDBService.getDetail(...)` exists, but is only used from detail flow, not from library list hydration (`ViewModels/Detail/DetailViewModel.swift` + `Services/Metadata/TMDBService.swift`).

## Why title resolution vs metadata matching
- **Title resolution** is already cheap and local; fallback prevents blocks.
- **Metadata matching/enrichment** is incomplete for library rows from sync/import, which leaves `posterPath` empty and causes cards to remain in placeholder/loading state.

## Recommended fix (minimal + effective)
1. Add a background metadata hydrate pass for library rows with missing `posterPath`/`backdropPath` or stale `lastFetched`, using `tmdbId` or `mediaId` and `MetadataProvider.getDetail(...)`.
2. Persist enriched fields back to `media_cache` and refresh `mediaItems` dictionary on the main actor.
3. In `MediaCardView`, only show `ProgressView` when an URL is present and actually loading; for nil URL use static poster placeholder immediately.
4. Optional perf hardening: add index for `user_library(listType, folderId)` if library load with large datasets remains slow after metadata hydration.
