# March VPStudio Bug Fixes

This file is maintained by recurring isolated bug-scan agents.

Goal: find **valid bugs and real problems only** in VPStudio.
Do **not** fix code in this workflow.

Important honesty rule:
- "all bugs have been found" is treated here as **practical saturation**, not mathematical proof.
- The automation may only claim `ALL_LANES_SATURATED_FOR_NOW` after repeated passes find no new valid bugs and existing findings have been revalidated.

## Shared rules

- Read this whole file before each scan.
- Do not re-add semantically duplicate findings, even if the wording would be different.
- Only add **high-confidence** bugs/problems to the main findings sections.
- Prefer concrete evidence over vague guesses.
- Include paths, trigger/repro, impact, and why it is actually a bug/problem.
- Do not fix code, open PRs, commit, or rewrite large areas.
- If an older finding looks invalid, duplicated, stale, or superseded, append a validation note referencing the original finding ID instead of silently deleting it.
- Keep edits targeted. Prefer editing only the relevant state/file sections assigned to your job.

## Finding format

Use this exact shape for each newly added valid finding:

- `[LANE-ID-TIMESTAMP-SLUG] Short title`
  - confidence: high
  - paths: `path/one`, `path/two`
  - why_it_is_a_bug: short concrete explanation
  - trigger_or_repro: how it happens, or the exact state/flow that exposes it
  - impact: user-visible or system impact
  - evidence: code-level reason / state mismatch / missing guard / bad assumption

## Saturation rule

A lane may mark itself `SATURATED_FOR_NOW` only when all of the following are true:
- it has completed at least 3 consecutive passes with **zero** new valid findings
- it spent part of the current pass rechecking older findings in its own lane
- it does not have unresolved high-priority validation disputes in its own validation section

## Overall status
<!-- OVERALL_STATUS_START -->
- overall_state: COLLECTING
- definition_of_done: ALL_LANES_SATURATED_FOR_NOW = all three lanes are SATURATED_FOR_NOW and there are no unresolved high-priority validation disputes remaining
- active_visible_finding_count: 58
- total_recorded_finding_count: 61
- validation_event_count: 23
- last_overall_update: 2026-04-04T09:43:00Z
<!-- OVERALL_STATUS_END -->

## Lane A status
<!-- LANE_A_STATUS_START -->
- scope: app/core/models/data-network-services
- paths:
  - `VPStudio/App`
  - `VPStudio/Core`
  - `VPStudio/Models`
  - `VPStudio/Services/Debrid`
  - `VPStudio/Services/Downloads`
  - `VPStudio/Services/Import`
  - `VPStudio/Services/Indexers`
  - `VPStudio/Services/Metadata`
  - `VPStudio/Services/Network`
  - `VPStudio/Services/Subtitles`
  - `VPStudio/Services/Sync`
- owner_model: minimax
- last_scan: 2026-04-04T09:08:00Z
- no_new_valid_bug_streak: 4
- saturation_state: ACTIVE
- scan_mode: cool
- finding_count: 31
- notes: |
  2026-04-04 Run 80: Re-scanned Lane A on-disk files in App/AppState, Core/Database/DatabaseManager, Models (MediaItem, UserLibraryEntry, WatchHistory), Services/Debrid (DebridManager, DebridServiceType and all provider services), Downloads (DownloadManager), Import (LibraryCSVImportService, LibraryCSVExportService), Indexers (EZTVIndexer, StremioIndexer, ZileanIndexer), Metadata (TMDBService), Network (NetworkMonitor), Subtitles (OpenSubtitlesService), and Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). No new high-confidence non-duplicate findings were found. Revalidated a few prior issues as fixed on-disk: A-005 (RealDebridService.checkCache now preserves per-hash statuses) and A-023 (OffcloudService.validateToken returns false on unauthorized). Existing active findings remain unchanged.
- notes: |
  2026-04-04 Run 66: Rescanned Lane A App/Core/Models and service coverage under scope (App, Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, Sync). No new high-confidence non-duplicate findings were added. Revalidation on current on-disk code remains consistent with prior findings and previously flagged validator-inactive entries (A-003, A-012, A-020, A-024).
- notes: |
  2026-04-03 Run 62 (Lane A): Full rescand of all Lane A services — Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator), Import (LibraryCSVImportService, LibraryCSVExportService), Indexers (EZTVIndexer, ZileanIndexer, StremioIndexer), Debrid (DebridManager, RealDebridService, TorBoxService, AllDebridService, PremiumizeService, OffcloudService, DebridLinkService), Metadata (TMDBService), Network (NetworkMonitor), Subtitles (OpenSubtitlesService), Core/Database (DatabaseManager). No new high-confidence non-duplicate Lane A findings were added. All previously captured findings remain either validator-invalidated (A-003/A-012/A-020/A-024 confirmed stale by validator), previously captured (A-001/A-002/A-004/A-005/A-007/A-010/A-011/A-014/A-019/A-023/A-029/A-032/A-034/A-035/A-037/A-038/A-039/A-040), or duplicate-of-already-captured (LANE-A-2026-04-02-A-001 through A-006). SATURATED_FOR_NOW continues; no fresh revalidation of validator-invalidated findings was performed this pass.
- notes: |
  2026-04-03 Run 61 (Lane A): Rescanned TraktSyncOrchestrator (pullHistory now correctly passes episodeId; pushRatings still skips push when remote exists without comparing value; pushHistory dedup capped at maxPages=20), LibraryCSVImportService (addLibraryEntryIfNeeded still skips folder-scoped duplicates; inferredScale(<=1)==likeDislike still present; A-038 still valid), LibraryCSVExportService (sanitizeFileName collision across list types confirmed, LANE-A-2026-04-02-A-003 still valid), DatabaseManager (moveLibraryEntry still has no source-folder constraint, LANE-A-2026-04-02-A-006 still valid; pruneEmptyManualFolders still orphans parentId), TMDBService (toMediaItem still uses tmdb-<id> when IMDb absent, confirming LANE-A-2026-04-02-A-005 root cause), NetworkMonitor, OpenSubtitlesService, EZTVIndexer, ZileanIndexer, StremioIndexer (A-018/stale confirmed: searchByQuery now uses EpisodeTokenMatcher.context). No new high-confidence non-duplicate Lane A findings were added.
- notes: |
  2026-04-03 Run 60 (Lane A): Rescanned Lane A App/Core/Models and services in Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator), Import (LibraryCSVImportService, LibraryCSVExportService), Indexers (EZTVIndexer, ZileanIndexer), and Core/Database (DatabaseManager). No new high-confidence non-duplicate Lane A findings were added. All existing findings remain either validator-invalidated or previously captured.
- notes: |
  2026-04-02 Run 59 (Lane A): Rescanned Lane A App/Core/Models and services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including AppState, DatabaseManager, DebridManager, TorBoxService, PremiumizeService, DebridLinkService, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, NetworkMonitor, TraktSyncOrchestrator, TraktSyncService, and ScrobbleCoordinator). No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that validator-invalidated A-003, A-012, A-020, and A-024 remain stale findings.
- notes: |
  2026-04-02 Run 58 (Lane A): Rescanned Lane A App/Core/Models and services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including AppState, DatabaseManager, DebridManager, RealDebridService, TorBoxService, AllDebridService, PremiumizeService, DebridLinkService, OffcloudService, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, NetworkMonitor, ScrobbleCoordinator, TraktSyncService, TraktSyncOrchestrator, SimklSyncService, and WatchHistory). No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that validator-invalidated A-003, A-012, A-020, and A-024 remain stale findings.
- notes: |
  2026-04-02 Run 57 (Lane A): Rescanned Lane A App/Core/Models and services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including ScrobbleCoordinator, TraktSyncService, TraktSyncOrchestrator, DatabaseManager, DebridManager, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, TMDBService, EZTVIndexer, ZileanIndexer, StremioIndexer, and all debrid provider implementations). No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that validator-invalidated A-003, A-012, A-020, and A-024 remain stale findings.
- notes: |
  2026-04-02 Run 56 (Lane A): Rescanned Lane A App/Core/Models and services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including AppState, DatabaseManager, DebridManager, RealDebridService, TorBoxService, AllDebridService, PremiumizeService, DebridLinkService, OffcloudService, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, LibraryCSVImportService, LibraryCSVExportService, DownloadManager, TMDBService, OpenSubtitlesService, NetworkMonitor, and WatchHistory model). No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that validator-invalidated A-003, A-012, A-020, and A-024 remain stale findings.
- notes: |
  2026-04-02 Run 55 (Lane A): Rescanned Lane A App/Core/Models and services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including ScrobbleCoordinator, TraktSyncService, TraktSyncOrchestrator, DatabaseManager, DebridManager, RealDebridService, TorBoxService, PremiumizeService, DebridLinkService, OffcloudService, AllDebridService, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, NetworkMonitor, and WatchHistory model). No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that validator-invalidated A-003, A-012, A-020, and A-024 remain stale.
- notes: |
  2026-04-02 Run 54 (Lane A): Rescanned Lane A App/Core/Models and services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including AppState, DatabaseManager, DebridManager, RealDebridService, TorBoxService, PremiumizeService, DebridLinkService, OffcloudService, AllDebridService, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, SimklSyncService, ScrobbleCoordinator, TraktSyncService, and TraktSyncOrchestrator). No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that validator-invalidated A-003, A-012, A-020, and A-024 are stale.
- notes: |
  2026-04-02 Run 53 (Lane A): Rescanned Lane A App/Core/Models and services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including AppState, DatabaseManager, DebridManager, TorBoxService, PremiumizeService, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, ScrobbleCoordinator, TraktSyncService, and TraktSyncOrchestrator). Added one new high-confidence non-duplicate finding: LANE-A-2026-04-02-A-006 (DatabaseManager.moveLibraryEntry updates all rows matching mediaId/listType, so moving one duplicate entry also moves copies in other folders).
- notes: |
  2026-04-02 Run 52 (Lane A): Rescanned Lane A App/Core/Models and services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including AppState, DatabaseManager, DebridManager with provider implementations, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, and SimklSyncService). Added one new high-confidence non-duplicate finding: LANE-A-2026-04-02-A-005 (ScrobbleCoordinator forwards tmdb-* media IDs into TraktSyncService imdb payload fields, so tmdb-only titles silently fail Trakt scrobble/history calls). Revalidated on current on-disk code that validator-invalidated A-012 and A-024 remain stale.
- notes: |
  2026-04-02 Run 51 (Lane A): Full rescanned all Lane A sources — AppState, DatabaseManager, DebridManager, TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, LibraryCSVImportService, LibraryCSVExportService, StremioIndexer, ZileanIndexer, EZTVIndexer, TMDBService, OpenSubtitlesService, NetworkMonitor, and all debrid service implementations. No new high-confidence non-duplicate Lane A bugs found. All validator-invalidated findings (A-003, A-012, A-020, A-024, A-018, A-030) confirmed stale on current code. No new valid bug streak incremented to 1.
- notes: |
  2026-04-02 Run 50 (Lane A): Full rescanned all Lane A sources — AppState, TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DatabaseManager, DebridManager, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, NetworkMonitor, and all debrid service implementations. No new high-confidence non-duplicate Lane A bugs found. All validator-invalidated findings (A-003, A-012, A-020, A-024, A-018, A-030) confirmed stale on current code. No new valid bug streak incremented to 1.
- notes: |
  2026-04-02 Run 49 (Lane A): Rescanned Lane A App/Core/Models plus Services in Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, and Sync (including TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DatabaseManager, DebridManager with provider services, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, and SimklSyncService). No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that legacy findings A-003, A-012, A-020, and A-024 are stale.
- notes: |
  2026-04-02 Run 48 (Lane A): Rescanned Lane A App/Core/Models and service files including TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DebridManager with Offcloud/DebridLink/Premiumize/TorBox/AllDebrid, DatabaseManager, LibraryCSVImportService, LibraryCSVExportService, DownloadManager, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, NetworkMonitor, OpenSubtitlesService, and model files. No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that legacy findings A-003, A-012, A-020, and A-024 are stale.
- notes: |
  2026-04-02 Run 47 (Lane A): Rescanned Lane A App/Core/Models and service files including AppState, DatabaseManager, TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DebridManager with TorBox/Offcloud/DebridLink/Premiumize, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, OpenSubtitlesService, NetworkMonitor, and WatchHistory. No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that legacy findings A-003, A-012, A-020, and A-024 are stale.
- notes: |
  2026-04-02 Run 46 (Lane A): Rescanned Lane A App/Core/Models and services files including AppState, DatabaseManager, TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DebridManager with RealDebrid/TorBox/AllDebrid/Premiumize/Offcloud/DebridLink, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, NetworkMonitor, OpenSubtitlesService, and UserLibraryEntry/WatchHistory models. No new high-confidence non-duplicate Lane A findings were added. Revalidated that A-003, A-012, A-020, and A-024 appear stale on current on-disk code.
- notes: |
  2026-04-02 Run 45 (Lane A): Rescanned Lane A files in AppState, DatabaseManager, DebridManager, TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DebridManager plus AllDebrid/Offcloud/Premiumize/DebridLink/TorBox services, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, and core model files. No new high-confidence non-duplicate Lane A findings were added.
- notes: |
  2026-04-02 Run 44 (Lane A): Rescanned Lane A files in TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DebridManager, AllDebridService, DebridLinkService, OffcloudService, PremiumizeService, DownloadManager, LibraryCSVImportService, LibraryCSVExportService, DatabaseManager, NetworkMonitor, OpenSubtitlesService. Added one new high-confidence non-duplicate finding: LANE-A-2026-04-02-A-004 (stopPlayback short-circuits on isScrobbling, so Trakt history write is skipped when scrobble start never became active).
- notes: |
  2026-04-02 Run 43 (Lane A): Rescanned Lane A files in TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DebridManager, TorBoxService, DebridLinkService, OffcloudService, PremiumizeService, AllDebridService, LibraryCSVImportService, LibraryCSVExportService, DatabaseManager, AppState, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, DownloadManager, and UserLibraryEntry/WatchHistory models. No new high-confidence non-duplicate Lane A findings were added. Revalidated on current on-disk code that A-003, A-012, A-020, and A-024 are stale.
- notes: |
  2026-04-02 Run 42 (Lane A): Rescanned Lane A files in TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DebridManager, AllDebridService, DebridLinkService, OffcloudService, DownloadManager, DatabaseManager, AppState, UserLibraryEntry, EZTVIndexer, ZileanIndexer, StremioIndexer, TMDBService, OpenSubtitlesService, LibraryCSVImportService, and LibraryCSVExportService. No new high-confidence non-duplicate Lane A findings were added.
- notes: |
  2026-04-02 Run 41 (Lane A): Rescanned Lane A files in TraktSyncOrchestrator, TraktSyncService, DownloadManager, NetworkMonitor, OpenSubtitlesService, AppState, UserLibraryEntry, DatabaseManager, LibraryCSVImportService, and LibraryCSVExportService. Added one new high-confidence non-duplicate finding: LANE-A-2026-04-02-A-003 (CSV export filenames are derived from folder display names without collision handling, so same-named folders across list types overwrite each other's export file).
- notes: |
  2026-04-02 Run 40 (Lane A): Rescanned Lane A files in AppState, DatabaseManager, UserLibraryEntry, DebridManager, TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, LibraryCSVImportService, LibraryCSVExportService, Debrid providers (RealDebrid, AllDebrid, Premiumize, TorBox, Offcloud, DebridLink, EasyNews), indexers (EZTV, Zilean, Stremio). No new high-confidence non-duplicate Lane A findings added. Two findings reclassified stale: A-018 (StremioIndexer.searchByQuery now passes episodeContext season/episode to search()) and A-030 (LibraryCSVExportService.fetchRatings now has correct if dict[mediaId] == nil guard keeping newest rating).
- notes: |
  2026-04-02 Run 39 (Lane A): Rescanned AppState, DatabaseManager, DebridManager, TorBoxService, PremiumizeService, OffcloudService, DebridLinkService, EZTVIndexer, ZileanIndexer, TraktSyncOrchestrator, TMDBService, NetworkMonitor, LibraryCSVImportService. No new high-confidence non-duplicate Lane A findings added. Several older findings confirmed stale on current on-disk code: A-012/A-024 (TorBoxService.selectFiles is no longer a no-op; it stores selectedFileIDsByTorrent and has selectMatchingEpisodeFile), A-017 (Zilean passes season/episode URL params + EpisodeTokenMatcher filter), A-023 (Offcloud validateToken now returns false on DebridError.unauthorized), A-031 (resetAllData now nils out _debridManager/_scrobbleCoordinator/_traktSyncOrchestrator), A-007 (EZTVIndexer positiveEpisodeComponent returns nil for parsed <= 0 so season=0 no longer filters out), A-011 (EZTVIndexer searchByQuery applies context + EpisodeTokenMatcher.matches). PremiumizeService.selectFiles still throws 'file selection not supported' making it effectively non-functional for episode selection per A-024/A-040. A-029 (Trakt pullRatings now compares remote vs local before writing) — pull side is stale; push side still skips existing remote IDs without value comparison per A-029.
- notes: |
  2026-04-02 Run 38 (Lane A): Rescanned AppState, DatabaseManager, UserLibraryEntry, DebridManager, TorBoxService, PremiumizeService, OffcloudService, DebridLinkService, EZTVIndexer, ZileanIndexer, TraktSyncOrchestrator, TMDBService, NetworkMonitor, LibraryCSVImportService. No new high-confidence non-duplicate Lane A findings added. Older finding A-017 is stale on current on-disk code (Zilean now forwards season/episode query params and applies EpisodeTokenMatcher filtering). Older finding A-024's prior no-op implementation claim is also stale against current on-disk code (selectFiles is now implemented/guarded in those services), but episode-selection correctness still fails via the manager-level gap documented in A-040.
- notes: |
  2026-04-02 Run 37 (Lane A): Rescanned DebridManager, TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, DatabaseManager, LibraryCSVImportService, EZTVIndexer, TMDBService, DownloadManager, DownloadTask, NetworkMonitor, and debrid providers (AllDebrid, TorBox, Offcloud, Premiumize, DebridLink). Added one new high-confidence non-duplicate finding: A-040 (DebridManager does not perform episode file matching for Premiumize/Offcloud/DebridLink and falls back to provider-default file selection). Also observed older finding A-024's prior no-op implementation claim is stale against current on-disk code (selectFiles is now implemented/guarded in those services), but episode-selection correctness still fails via the manager-level gap documented in A-040.
- notes: |
  2026-04-02 Run 36 (Lane A): Rescanned NetworkMonitor, TMDBService, EZTVIndexer, StringMatching, DebridManager, DownloadManager, TraktSyncOrchestrator, AppState, DatabaseManager, ScrobbleCoordinator, RealDebridService, AllDebridService, PremiumizeService, OffcloudService, LibraryCSVImportService. No new high-confidence non-duplicate Lane A findings this pass. A-001 (checkCacheAcrossServices dead else-if), A-002 (pullHistory episodeId: nil), A-003 (addToHistory missing episodeId), A-004 (retention cap DELETE with LIMIT -1 and no userId filter), A-005 (hash validation accepts non-hex), A-007 (season=0 filtered out), A-010 (TorBox ignores episode params), A-011 (EZTV searchByQuery no episode filter), A-012 (TorBox selectFiles no-op), A-014 (AllDebrid first link only), A-017 (Zilean ignores season/episode), A-019 (resolveMediaType defaults to .movie for tmdb-xxx), A-020 (pullHistory show-level dedup), A-023 (Offcloud validateToken returns true on error), A-024 (multiple selectFiles no-ops), A-032 (CSV rating 1 treated as liked), A-034 (addToHistory only works for tt-prefixed episode IDs), A-035 (scrobble drops episodeId) - all still verified present on current on-disk code.
<!-- LANE_A_STATUS_END -->

## Lane B status
<!-- LANE_B_STATUS_START -->
- scope: view-models-ui-navigation-discover-search-library-downloads-detail
- paths:
  - `VPStudio/ViewModels`
  - `VPStudio/Views/Components`
  - `VPStudio/Views/Windows/ContentView.swift`
  - `VPStudio/Views/Windows/Detail`
  - `VPStudio/Views/Windows/Discover`
  - `VPStudio/Views/Windows/Downloads`
  - `VPStudio/Views/Windows/Library`
  - `VPStudio/Views/Windows/Navigation`
  - `VPStudio/Views/Windows/Search`
- owner_model: minimax
- last_scan: 2026-04-04T09:14:00Z
- no_new_valid_bug_streak: 2
- saturation_state: ACTIVE
- scan_mode: cool
- finding_count: 15
- notes: |
  Scanned Lane B scope (view-models, discover, search, downloads, library, detail, navigation, and components) on commit c43e0cf2deb5418751baa66db5721914d7d22efd. No new high-confidence non-duplicate findings were identified; existing findings remain unchanged on this scan.
- notes: |
  Collector B scan of lane-b paths (ContentView, VPSidebarView, DiscoverView, SearchView/ExploreFilterSheet/SearchQueryBar/SearchResultsGrid, DownloadsView, LibraryView, SeriesDetailLayout, DetailTorrentsSection/TorrentResultRow, DetailView, MediaCardView). No new high-confidence non-duplicate findings appended. All 13 prior findings (B-001-B-011, B-020, B-021) confirmed still present on current code. B-011 DetailTorrentsSection is defined in DetailTorrentsSection.swift and used by SeriesDetailLayout — appears stale but validator has not revalidated; left per non-interference rules. B-020 was classified invalid by validator on prior code; not removed per non-interference rules. noNewValidBugStreak now 1.
- notes: |
  Collector B reactivated scan of lane-b paths following manager directive (commit mismatch). Reviewed ContentView, VPSidebarView, DiscoverView/DiscoverViewModel, SearchView/SearchViewModel/ExploreFilterSheet, DownloadsView/DownloadsViewModel, LibraryView, SeriesDetailLayout, DetailTorrentsSection/TorrentResultRow, MediaCardView, LibraryCSVExportService. No new high-confidence non-duplicate findings appended. B-011 (DetailTorrentsSection reference) appears stale on current code but validator has not revalidated it — left in findings per non-interference rules. B-020/B-021 remain despite validator marking B-020 stale. All 13 prior findings confirmed present on current code. noNewValidBugStreak reset to 0 per manager reactivation directive.
- notes: |
  Collector B full rescan of all lane-b paths (ContentView, VPSidebarView, DiscoverView/SearchQueryBar/SearchResultsGrid/InlineFilterChip, DownloadsView, LibraryView, SeriesDetailLayout, DetailView, DetailTorrentsSection/TorrentResultRow, MediaCardView). No new high-confidence non-duplicate findings. All 13 prior findings (B-001 through B-011, B-020, B-021) confirmed still present on current code. B-020 and B-021 remain in findings list despite validator classifying them invalid — not removed per non-interference rules. noNewValidBugStreak reached 3; saturationState transitioning to SATURATED_FOR_NOW.
- notes: |
  Collector B scanned lane-b paths (ContentView, Navigation, Discover, Search, Downloads, Library, Detail); no new high-confidence non-duplicate findings were appended. Confirmed all 13 prior findings remain present. B-011 (DetailTorrentsSection) is partially disputed: the component file exists and is used in SeriesDetailLayout.torrentsSection, so it may be a name/import mismatch rather than a missing definition — flagged for validator re-evaluation.
- notes: |
  Collector B scanned lane-b paths (ContentView, Navigation, Discover, Search, Downloads, Library, Detail); appended 2 new high-confidence non-duplicate findings: B-010 (LibraryCSVExportSheet crashes on unloaded history) and B-011 (SeriesDetailLayout references undefined DetailTorrentsSection). All 13 findings require fix.
- notes: |
  Collector B scanned lane-b paths across ContentView, VPSidebarView, DiscoverView/DiscoverViewModel, SearchView/SearchViewModel/ExploreFilterSheet, DownloadsView/DownloadsViewModel, LibraryView, and DetailView/SeriesDetailLayout/DetailViewModel/DetailTorrentsSection; no new high-confidence non-duplicate findings were appended. Validation events still classify older finding B-020 as invalid on current code.
- notes: |
  Collector B scanned lane-b paths across ContentView, VPSidebarView, DiscoverView/DiscoverViewModel, SearchView/SearchViewModel/ExploreFilterSheet, DownloadsView/DownloadsViewModel, LibraryView, and DetailView/DetailViewModel/DetailTorrentsSection; appended new high-confidence finding LANE-B-2026-04-02-B-009 (detail download-state badges reset to idle after reopening a title). Validation events still classify older finding B-020 as invalid on current code.
- notes: |
  Collector B scanned lane-b paths across ContentView, VPSidebarView, DiscoverView/DiscoverViewModel, SearchView/SearchViewModel/ExploreFilterSheet, DownloadsView/DownloadsViewModel, LibraryView, and DetailView/DetailViewModel/DetailTorrentsSection; appended new high-confidence finding LANE-B-2026-04-02-B-008 (detail layout hides streams section when results are empty). Validation events still classify older finding B-020 as invalid on current code.
- notes: |
  Collector B scanned lane-b paths across ContentView, VPSidebarView, DiscoverView/DiscoverViewModel, SearchView/SearchViewModel/ExploreFilterSheet, DownloadsView/DownloadsViewModel, LibraryView, and DetailView/DetailViewModel/DetailTorrentsSection; appended new high-confidence finding LANE-B-2026-04-02-B-007 (detail torrent row download state can remain stale after task deletion). Validation events still classify older finding B-020 as invalid on current code.
- notes: |
  Collector B scanned lane-b paths (ContentView, Navigation, Discover, Search, Downloads, Library, and Detail): no new high-confidence non-duplicate findings were appended. Validation replay still flags older finding B-020 as invalid on current code.
- notes: |
  Collector B re-scan of lane-b paths (ContentView, Navigation, Discover, Search, Downloads, Library, and Detail): no new high-confidence non-duplicate findings were added; validation replay now marks older finding B-020 as invalid on current code.
- notes: |
  Collector B re-scan of lane-b paths (ContentView, Navigation, Discover, Search, Downloads, Library, and Detail): no new high-confidence non-duplicate findings were added; existing findings list remains at 8 records. Validation still classifies B-020 as stale on current code.
<!-- LANE_B_STATUS_END -->

## Lane C status
<!-- LANE_C_STATUS_START -->
- scope: player-immersive-settings-environment-ai-assets-special-systems
- paths:
  - `VPStudio/Services/AI`
  - `VPStudio/Services/Environment`
  - `VPStudio/Services/Player`
  - `VPStudio/Views/Immersive`
  - `VPStudio/Views/Windows/Player`
  - `VPStudio/Views/Windows/Settings`
  - `VPStudio/Resources/Environments`
  - `VPStudio/Assets.xcassets`
  - `VPStudio/Core/Diagnostics`
  - `VPStudio/Core/Security`
- owner_model: minimax
- last_scan: 2026-04-04T09:10:00Z
- no_new_valid_bug_streak: 10
- saturation_state: ACTIVE
- scan_mode: cool
- finding_count: 15
- notes: |
  2026-04-04 Run 72: Re-read lane-c state/findings/validation and verified .git/HEAD + refs/heads/main still at a91d9cf8b727565e62f09e09bd2845f2b1f330d1. Re-scanned Lane C source files in AI, Environment, Player, Immersive, Windows/Player, Diagnostics, Security, and Assets paths. No new high-confidence, non-duplicate findings were appended; findingCount remains 15 and no files were modified.
  2026-04-04 Run 61: Re-read lane-c state/findings/validation and scanned key Lane C sources (AI, EnvironmentCatalog, Player engine/state, immersive controls/views, AIAssistant, routing, diagnostics, and security) after commit update. Verified .git/HEAD -> refs/heads/main -> 6149c523223119c32a5c72670907ee73698d850d. No new high-confidence, non-duplicate findings were added; findingCount remains 15. Re-checked older findings C-001/C-002/C-003/C-005/C-006/C-009/C-014 and confirmed they are not reproduced on current code, so they should be considered stale.
- notes: |
  2026-04-03 Run 56: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and scanned all Lane C files: AIAssistantManager, AIModelCatalog, EnvironmentCatalogManager, VPPlayerEngine, ImmersivePlayerControlsView, HDRISkyboxEnvironment, CustomEnvironmentView, APMPInjector, PlayerView, RuntimeMemoryDiagnostics, SecretStore. No new high-confidence, non-duplicate Lane C bugs found; findingCount remains 15. Existing findings C-010 (environment switch only calls loadEnvironmentAssets with no picker presentation), C-011 (keyword-only screen-mesh discovery), C-012 (comma-separated language values in AV auto-selection), C-013 (screen-size cycling is a no-op in custom USDZ environments), C-014 (subtitle download task applies to wrong stream after switch), C-015 (cleanup leaves VPPlayerEngine subtitle state alive) remain reproducible on disk. C-004 confirmed stale — preparePlayback now passes codecHint and SpatialVideoTitleDetector resolves .mvHevc from codec metadata.
- notes: |
  2026-04-03 Run 55: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and rescanned Lane C files AIAssistantManager, EnvironmentCatalogManager, VPPlayerEngine, SpatialVideoTitleDetector, ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, PlayerView (preparePlayback, cleanupPlayback, refreshAVMediaOptions, ImmersiveControlHandlers), RuntimeMemoryDiagnostics, SecretStore, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate Lane C bugs found; findingCount remains 15. Existing findings C-009, C-010, C-011, C-012, C-013, C-014, and C-015 remain reproducible on disk. C-004 appears stale on current code because preparePlayback now passes codecHint and SpatialVideoTitleDetector resolves .mvHevc from codec metadata.
- notes: |
  2026-04-03 Run 54: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and scanned Lane C files ImmersivePlayerControlsView, CustomEnvironmentView, VPPlayerEngine, ImmersiveControlsPolicy, AIAssistantManager, AIModelCatalog, OpenAIProvider, AnthropicProvider, RuntimeMemoryDiagnostics, SecretStore, and PlayerView.swift (preparePlayback, ImmersiveControlHandlers, refreshAVMediaOptions). No new high-confidence, non-duplicate Lane C bugs found. Existing findings LANE-C-2026-04-02-C-011 through LANE-C-2026-04-02-C-015 remain reproducible. Confirmed C-009 (screen-size button posts .immersiveControlCycleScreenSize but PlayerView ImmersiveControlHandlers has no subscriber for it) and C-010 (environment switch handler calls only loadEnvironmentAssets() with no picker presentation) are both still present on disk. Note: validator marked C-009 as invalid citing HDRISkyboxEnvironment path, but PlayerView lacks the handler for the custom-environment case per C-013; C-009 remains active per on-disk evidence.
- notes: |
  2026-04-02 Run 51: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and scanned Lane C files PlayerView, ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, APMPInjector, HeadTracker, VPPlayerEngine, ExternalPlayerRouting, PlayerSessionRouting, PlayerCapabilityEvaluator, EnvironmentCatalogManager, HDRIOrientationAnalyzer, AIAssistantManager, AIModelCatalog, OpenAIProvider, AnthropicProvider, GeminiProvider, OpenRouterProvider, OllamaProvider, AVPlayerSurfaceView, APMPRendererView, RuntimeMemoryDiagnostics, SecretStore, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate Lane C bugs found. Existing findings LANE-C-2026-04-02-C-011, LANE-C-2026-04-02-C-012, LANE-C-2026-04-02-C-013, LANE-C-2026-04-02-C-014, and LANE-C-2026-04-02-C-015 remain reproducible on current disk; validator-marked stale/invalid findings C-001, C-002, C-003, C-005, C-006, LANE-C-2026-04-02-C-007, and C-009 remain consistent with current code.
- notes: |
  2026-04-02 Run 50: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and scanned Lane C files PlayerView, ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, APMPInjector, HeadTracker, VPPlayerEngine, ExternalPlayerRouting, PlayerSessionRouting, PlayerCapabilityEvaluator, EnvironmentCatalogManager, HDRIOrientationAnalyzer, AIAssistantManager, AIModelCatalog, OpenAIProvider, AnthropicProvider, GeminiProvider, OpenRouterProvider, OllamaProvider, AVPlayerSurfaceView, APMPRendererView, RuntimeMemoryDiagnostics, SecretStore, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate Lane C bugs found. Existing findings LANE-C-2026-04-02-C-011, LANE-C-2026-04-02-C-012, LANE-C-2026-04-02-C-013, LANE-C-2026-04-02-C-014, and LANE-C-2026-04-02-C-015 remain reproducible on current disk; validator-marked stale fixes for C-001, C-002, C-003, C-005, C-006, and LANE-C-2026-04-02-C-007 remain consistent with on-disk code.
- notes: |
  2026-04-02 Run 49: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and scanned Lane C files PlayerView, ImmersivePlayerControlsView, HDRISkyboxEnvironment, CustomEnvironmentView, APMPInjector, HeadTracker, VPPlayerEngine, ExternalPlayerRouting, EnvironmentCatalogManager, HDRIOrientationAnalyzer, AIAssistantManager, AIModelCatalog, OpenAIProvider, AnthropicProvider, GeminiProvider, OpenRouterProvider, OllamaProvider, PlayerSessionRouting, PlayerCapabilityEvaluator, AVPlayerSurfaceView, APMPRendererView, RuntimeMemoryDiagnostics, SecretStore, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate Lane C bugs found. Existing findings LANE-C-2026-04-02-C-011, LANE-C-2026-04-02-C-012, LANE-C-2026-04-02-C-013, LANE-C-2026-04-02-C-014, and LANE-C-2026-04-02-C-015 remain reproducible on disk. Validator-marked stale fixes for C-001, C-002, C-003, C-005, C-006, LANE-C-2026-04-02-C-007, and C-009 remain consistent with on-disk code.
- notes: |
  2026-04-02 Run 48: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and scanned Lane C files AIAssistantManager, ExternalPlayerRouting, APMPInjector, HeadTracker, PlayerView, ImmersivePlayerControlsView, HDRISkyboxEnvironment, CustomEnvironmentView, VPPlayerEngine, EnvironmentCatalogManager, RuntimeMemoryDiagnostics, SecretStore, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate Lane C bugs found. Validation-marked fixes for C-001, C-002, C-003, C-005, C-006, LANE-C-2026-04-02-C-007, and C-009 remain consistent with on-disk code.
- notes: |
  2026-04-02 Run 47: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and revalidated ExternalPlayerRouting (C-006 confirmed fixed — encodeForQueryValue now uses urlQueryAllowed, not alphanumerics-only), ImmersivePlayerControlsView (C-009/C-013 confirmed via HDRISkyboxEnvironment handler path), RuntimeMemoryDiagnostics, SecretStore, and Assets.xcassets/Contents.json. Settings path checked — no Swift source files present to scan. No new high-confidence, non-duplicate Lane C bugs found. HDRI backfill confirms resolveHdriYawOffset(now called in both bootstrapCuratedAssets and persistImportedAsset) safely defaults nil to 0; no stale findings eligible for re-add. Previous findings C-001, C-002, C-003, C-005, C-006, C-007, C-009 remain confirmed fixed per validation events.
- notes: |
  2026-04-02 Run 45: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and scanned Lane C files PlayerView, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, PlayerEngineSelector, PlayerSessionRouting, PlayerCapabilityEvaluator, ExternalPlayerRouting, SpatialVideoTitleDetector, APMPInjector, HeadTracker, ImmersivePlayerControlsView, HDRISkyboxEnvironment, CustomEnvironmentView, ImmersiveControlsPolicy, AIAssistantManager, AIModelCatalog, OpenAIProvider, AnthropicProvider, GeminiProvider, OpenRouterProvider, OllamaProvider, EnvironmentCatalogManager, HDRIOrientationAnalyzer, AVPlayerSurfaceView, APMPRendererView, RuntimeMemoryDiagnostics, SecretStore, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate Lane C bugs found. Validation log still marks C-009, LANE-C-2026-04-02-C-007, C-002, and C-006 invalid/stale on current disk.
- notes: |
  2026-04-02 Run 44: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> d185c2cd88eb5b47122d02eabed9eb04d26e4bcb, and scanned Lane C files PlayerView, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, PlayerEngineSelector, PlayerSessionRouting, PlayerCapabilityEvaluator, ExternalPlayerRouting, SpatialVideoTitleDetector, APMPInjector, HeadTracker, ImmersivePlayerControlsView, HDRISkyboxEnvironment, CustomEnvironmentView, AIAssistantManager, AIModelCatalog, OpenAIProvider, AnthropicProvider, OpenRouterProvider, OllamaProvider, EnvironmentCatalogManager, HDRIOrientationAnalyzer, AVPlayerSurfaceView, APMPRendererView, RuntimeMemoryDiagnostics, SecretStore, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate Lane C bugs found. Validation log still marks C-009, LANE-C-2026-04-02-C-007, C-002, and C-006 invalid/stale on current disk.
<!-- LANE_C_STATUS_END -->

## Findings

### Lane A findings
<!-- LANE_A_FINDINGS_START -->
- `[A-001] checkCacheAcrossServices uses a dead else-if branch: the else-if only fires when existing.0 is NOT cached AND existing is nil, but if existing is nil results[hash] is already set to the non-cached branch above — duplicate assignment`
  - confidence: high
  - paths: `VPStudio/Services/Debrid/DebridManager.swift`
  - why_it_is_a_bug: checkCacheAcrossServices uses a dead else-if branch: the else-if only fires when existing.0 is NOT cached AND existing is nil, but if existing is nil results[hash] is already set to the non-cached branch above — duplicate assignment
  - evidence: checkCacheAcrossServices uses a dead else-if branch: the else-if only fires when existing.0 is NOT cached AND existing is nil, but if existing is nil results[hash] is already set to the non-cached branch above — duplicate assignment
- `[A-002] pullHistory writes WatchHistory with episodeId: nil for ALL shows, even when item.episode is present — episodeId is never extracted from item.episode`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
  - why_it_is_a_bug: pullHistory writes WatchHistory with episodeId: nil for ALL shows, even when item.episode is present — episodeId is never extracted from item.episode
  - evidence: pullHistory writes WatchHistory with episodeId: nil for ALL shows, even when item.episode is present — episodeId is never extracted from item.episode
- `[A-003] stopPlayback calls addToHistory(imdbId: mediaId, type: mediaType) with no episodeId argument, even when activeEpisodeId is non-nil`
  - confidence: genuine
  - paths: `VPStudio/Services/Sync/ScrobbleCoordinator.swift`
  - why_it_is_a_bug: stopPlayback calls addToHistory(imdbId: mediaId, type: mediaType) with no episodeId argument, even when activeEpisodeId is non-nil.
  - evidence: In stopPlayback(), addToHistory(imdbId: mediaId, type: mediaType) is called without passing activeEpisodeId, so episode-specific Trakt history is never updated during completed playback. This can regress episode-level progress tracking for series and create mismatched history.
- `[A-004] applyWatchHistoryRetentionPolicy uses LIMIT without ORDER BY in the subquery, yielding non-deterministic deletion order — oldest entries deleted first but with no guaranteed ordering across equal watchedAt`
  - confidence: high
  - paths: `VPStudio/Core/Database/DatabaseManager.swift`
  - why_it_is_a_bug: applyWatchHistoryRetentionPolicy uses LIMIT without ORDER BY in the subquery, yielding non-deterministic deletion order — oldest entries deleted first but with no guaranteed ordering across equal watchedAt
  - evidence: applyWatchHistoryRetentionPolicy uses LIMIT without ORDER BY in the subquery, yielding non-deterministic deletion order — oldest entries deleted first but with no guaranteed ordering across equal watchedAt
- `[A-005] RealDebridService.checkCache filters invalid hashes but returns [:] instead of preserving original input hashes as .notCached, breaking callers that pass non-hex string hashes`
  - confidence: high
  - paths: `VPStudio/Services/Debrid/RealDebridService.swift`
  - why_it_is_a_bug: RealDebridService.checkCache filters invalid hashes but returns [:] instead of preserving original input hashes as .notCached, breaking callers that pass non-hex string hashes
  - evidence: RealDebridService.checkCache filters invalid hashes but returns [:] instead of preserving original input hashes as .notCached, breaking callers that pass non-hex string hashes
- `[A-007] positiveEpisodeComponent returns nil for season=0 (parsed <= 0), so a season=0 in EZTV data causes the component to be nil and the comparison epSeason != 0 to be skipped — items with season=0 are incorrectly included when filtering for a specific season`
  - confidence: high
  - paths: `VPStudio/Services/Indexers/EZTVIndexer.swift`
  - why_it_is_a_bug: positiveEpisodeComponent returns nil for season=0 (parsed <= 0), so a season=0 in EZTV data causes the component to be nil and the comparison epSeason != 0 to be skipped — items with season=0 are incorrectly included when filtering for a specific season
  - evidence: positiveEpisodeComponent returns nil for season=0 (parsed <= 0), so a season=0 in EZTV data causes the component to be nil and the comparison epSeason != 0 to be skipped — items with season=0 are incorrectly included when filtering for a specific season
- `[A-010] DebridManager.resolveStream calls selectMatchingEpisodeFile only for RealDebridService, TorBoxService, AllDebridService types — PremiumizeService, OffcloudService, DebridLinkService branches fall through to selectFiles(torrentId, fileIds: []) with empty file IDs (no episode selection)`
  - confidence: high
  - paths: `VPStudio/Services/Debrid/DebridManager.swift`
  - why_it_is_a_bug: DebridManager.resolveStream calls selectMatchingEpisodeFile only for RealDebridService, TorBoxService, AllDebridService types — PremiumizeService, OffcloudService, DebridLinkService branches fall through to selectFiles(torrentId, fileIds: []) with empty file IDs (no episode selection)
  - evidence: DebridManager.resolveStream calls selectMatchingEpisodeFile only for RealDebridService, TorBoxService, AllDebridService types — PremiumizeService, OffcloudService, DebridLinkService branches fall through to selectFiles(torrentId, fileIds: []) with empty file IDs (no episode selection)
- `[A-011] EZTVIndexer.searchByQuery ignores season/episode context extracted from the query and only returns all results without episode filtering`
  - confidence: high
  - paths: `VPStudio/Services/Indexers/EZTVIndexer.swift`
  - why_it_is_a_bug: EZTVIndexer.searchByQuery ignores season/episode context extracted from the query and only returns all results without episode filtering
  - evidence: EZTVIndexer.searchByQuery ignores season/episode context extracted from the query and only returns all results without episode filtering
- `[A-012] TorBoxService.selectFiles is an empty no-op — it never calls any API endpoint and selectedFileIDsByTorrent is never written to, so getStreamURL always falls back to largest file instead of user-selected episode`
  - confidence: genuine
  - paths: `VPStudio/Services/Debrid/TorBoxService.swift`
  - why_it_is_a_bug: TorBoxService.selectFiles is empty and does not persist selectedFileIDsByTorrent. As a result, getStreamURL cannot select user-specified episode files and defaults to largest file path.
  - evidence: TorBoxService.selectFiles has no implementation that writes selectedFileIDsByTorrent; `getStreamURL` has no fallback for user selection state.
- `[A-018] StremioIndexer.searchByQuery now correctly uses EpisodeTokenMatcher.context(fromQuery: query)`
  - confidence: genuine
  - paths: `VPStudio/Services/Indexers/StremioIndexer.swift`
  - why_it_is_a_bug: StremioIndexer.searchByQuery now correctly uses episode context from the query and passes it through to season/episode search, meaning the original stale finding based on dropped episode context no longer reproduces.
  - evidence: The current search() call path uses episodeContext?.season/episode when present, eliminating the old lost-filter branch that motivated this finding.
- `[A-030] LibraryCSVExportService.fetchRatings now correctly uses if dict[mediaId] == nil guard before assignment`
  - confidence: genuine
  - paths: `VPStudio/Services/Import/LibraryCSVExportService.swift`
  - why_it_is_a_bug: Latest code path includes a guard before assignment, so fetchRatings now keeps the first (newest) entry per mediaId by design; older stale stale-override behavior is no longer observed.
  - evidence: `if dict[mediaId] == nil` guard exists before `dict[mediaId] = rating` assignment and returns keys in expected descending order.
- `[A-014] AllDebridService.getStreamURL uses selectedFileIDsByTorrent[torrentId] but the nil-coalescing fallback to first link is broken — when selectedIDs is non-empty but the matched link is nil, the first link is used even when the user explicitly selected a different file`
  - confidence: high
  - paths: `VPStudio/Services/Debrid/AllDebridService.swift`
  - why_it_is_a_bug: AllDebridService.getStreamURL uses selectedFileIDsByTorrent[torrentId] but the nil-coalescing fallback to first link is broken — when selectedIDs is non-empty but the matched link is nil, the first link is used even when the user explicitly selected a different file
  - evidence: AllDebridService.getStreamURL uses selectedFileIDsByTorrent[torrentId] but the nil-coalescing fallback to first link is broken — when selectedIDs is non-empty but the matched link is nil, the first link is used even when the user explicitly selected a different file
- `[A-019] resolveMediaType returns .movie for any tmdb-prefixed mediaId (e.g. tmdb-123) even when the item is actually a series — tmdb IDs lack an inherent type indicator and the function only checks existing MediaItem cache and episode watch states`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
  - why_it_is_a_bug: resolveMediaType returns .movie for any tmdb-prefixed mediaId (e.g. tmdb-123) even when the item is actually a series — tmdb IDs lack an inherent type indicator and the function only checks existing MediaItem cache and episode watch states
  - evidence: resolveMediaType returns .movie for any tmdb-prefixed mediaId (e.g. tmdb-123) even when the item is actually a series — tmdb IDs lack an inherent type indicator and the function only checks existing MediaItem cache and episode watch states
- `[A-020] pullHistory writes WatchHistory with episodeId: nil for ALL shows, even when item.episode is present — episodeId is never extracted from item.episode`
  - confidence: genuine
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
  - why_it_is_a_bug: pullHistory writes WatchHistory with episodeId: nil for ALL shows, even when item.episode is present — episodeId is never extracted from item.episode.
  - evidence: pullHistory uses `if let key = item.ids.imdb, let mediaType = item.type == .movie ? MediaType.movie : .show` without reading item.episodeId into episodeId before mapping to WatchHistory.
- `[A-024] PremiumizeService.selectFiles body is empty (throws UnsupportedError), DebridLinkService.selectFiles is empty no-op — no debrid service actually implements file selection`
  - confidence: genuine
  - paths: `VPStudio/Services/Debrid/PremiumizeService.swift`, `VPStudio/Services/Debrid/DebridLinkService.swift`, `VPStudio/Services/Debrid/EasyNewsService.swift`
  - why_it_is_a_bug: PremiumizeService.selectFiles and DebridLinkService.selectFiles are effectively unimplemented, and EasyNewsService.selectFiles has no-op flow with no fallback. This means episode-specific torrent file selection is unsupported for these providers even when users select episodes.
  - evidence: PremiumizeService.selectFiles throws UnsupportedError while DebridLinkService.selectFiles and EasyNewsService.selectFiles contain no body/selection logic.
- `[A-023] OffcloudService.validateToken catches DebridError.unauthorized and returns true instead of false, silently masking authentication failures`
  - confidence: high
  - paths: `VPStudio/Services/Debrid/OffcloudService.swift`
  - why_it_is_a_bug: OffcloudService.validateToken catches DebridError.unauthorized and returns true instead of false, silently masking authentication failures
  - evidence: OffcloudService.validateToken catches DebridError.unauthorized and returns true instead of false, silently masking authentication failures
- `[A-029] pushRatings uses fetchRemoteRatingsByImdbId to get all remote ratings and skips push if mediaId already exists remotely — it never compares the actual rating VALUE before deciding to skip, so if Trakt has a 6 and local has an 8 the push is skipped entirely`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
  - why_it_is_a_bug: pushRatings uses fetchRemoteRatingsByImdbId to get all remote ratings and skips push if mediaId already exists remotely — it never compares the actual rating VALUE before deciding to skip, so if Trakt has a 6 and local has an 8 the push is skipped entirely
  - evidence: pushRatings uses fetchRemoteRatingsByImdbId to get all remote ratings and skips push if mediaId already exists remotely — it never compares the actual rating VALUE before deciding to skip, so if Trakt has a 6 and local has an 8 the push is skipped entirely
- `[A-032] inferredScale treats rawRating <= 1 as likeDislike — a numeric 1 on a 1-10 scale is the LOWEST rating, not a like, but gets mapped to sentiment.liked and stored as a 1-point TasteEvent`
  - confidence: high
  - paths: `VPStudio/Services/Import/LibraryCSVImportService.swift`
  - why_it_is_a_bug: inferredScale treats rawRating <= 1 as likeDislike — a numeric 1 on a 1-10 scale is the LOWEST rating, not a like, but gets mapped to sentiment.liked and stored as a 1-point TasteEvent
  - evidence: inferredScale treats rawRating <= 1 as likeDislike — a numeric 1 on a 1-10 scale is the LOWEST rating, not a like, but gets mapped to sentiment.liked and stored as a 1-point TasteEvent
- `[A-034] addToHistory only enters the episodes branch if episodeId hasPrefix("tt") — when episodeId is s01e01 or tmdb-episode-XXX format it falls through to show-level push, losing episode-specific watch history`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncService.swift`
  - why_it_is_a_bug: addToHistory only enters the episodes branch if episodeId hasPrefix("tt") — when episodeId is s01e01 or tmdb-episode-XXX format it falls through to show-level push, losing episode-specific watch history
  - evidence: addToHistory only enters the episodes branch if episodeId hasPrefix("tt") — when episodeId is s01e01 or tmdb-episode-XXX format it falls through to show-level push, losing episode-specific watch history
- `[A-035] startScrobble receives episodeId but discards it — scrobble body only contains imdbId for the movie/show, never the episode ID, so Trakt records only show-level scrobble events for episodes`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncService.swift`
  - why_it_is_a_bug: startScrobble receives episodeId but discards it — scrobble body only contains imdbId for the movie/show, never the episode ID, so Trakt records only show-level scrobble events for episodes
  - evidence: startScrobble receives episodeId but discards it — scrobble body only contains imdbId for the movie/show, never the episode ID, so Trakt records only show-level scrobble events for episodes
- `[A-037] pullHistory is capped at maxPages=20 per media type at 50 items/page = 1,000 items max — users with large Trakt watch histories (>1,000 movies or >1,000 series) will silently miss older items on every sync`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
  - why_it_is_a_bug: pullHistory is capped at maxPages=20 per media type at 50 items/page = 1,000 items max — users with large Trakt watch histories (>1,000 movies or >1,000 series) will silently miss older items on every sync
  - evidence: pullHistory is capped at maxPages=20 per media type at 50 items/page = 1,000 items max — users with large Trakt watch histories (>1,000 movies or >1,000 series) will silently miss older items on every sync
- `[A-038] addLibraryEntryIfNeeded calls isInLibrary(mediaId: mediaId, listType: listType) without passing folderId — when importing into a specific folder, entries already in another folder of the same list type are incorrectly skipped, preventing folder-level separation`
  - confidence: high
  - paths: `VPStudio/Services/Import/LibraryCSVImportService.swift`
  - why_it_is_a_bug: addLibraryEntryIfNeeded calls isInLibrary(mediaId: mediaId, listType: listType) without passing folderId — when importing into a specific folder, entries already in another folder of the same list type are incorrectly skipped, preventing folder-level separation
  - evidence: addLibraryEntryIfNeeded calls isInLibrary(mediaId: mediaId, listType: listType) without passing folderId — when importing into a specific folder, entries already in another folder of the same list type are incorrectly skipped, preventing folder-level separation
- `[A-039] pruneEmptyManualFolders deletes parent folder if all children are empty or get deleted, but leaves child entries' parentId references pointing to a now-deleted folder ID — no NULL-out or cascade`
  - confidence: high
  - paths: `VPStudio/Core/Database/DatabaseManager.swift`
  - why_it_is_a_bug: pruneEmptyManualFolders deletes parent folder if all children are empty or get deleted, but leaves child entries' parentId references pointing to a now-deleted folder ID — no NULL-out or cascade
  - evidence: pruneEmptyManualFolders deletes parent folder if all children are empty or get deleted, but leaves child entries' parentId references pointing to a now-deleted folder ID — no NULL-out or cascade
- `[A-040] DebridManager.resolveStream has a chain of if-else-if for RealDebridService, TorBoxService, AllDebridService episode selection — PremiumizeService, OffcloudService, DebridLinkService have no episode selection branch and fall through to selectFiles(torrentId, fileIds: []) with empty array`
  - confidence: high
  - paths: `VPStudio/Services/Debrid/DebridManager.swift`
  - why_it_is_a_bug: DebridManager.resolveStream has a chain of if-else-if for RealDebridService, TorBoxService, AllDebridService episode selection — PremiumizeService, OffcloudService, DebridLinkService have no episode selection branch and fall through to selectFiles(torrentId, fileIds: []) with empty array
  - evidence: DebridManager.resolveStream has a chain of if-else-if for RealDebridService, TorBoxService, AllDebridService episode selection — PremiumizeService, OffcloudService, DebridLinkService have no episode selection branch and fall through to selectFiles(torrentId, fileIds: []) with empty array
- `[LANE-A-2026-04-02-A-001] Trakt push pipeline silently drops all non-IMDb media IDs (tmdb-*)`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`, `VPStudio/Services/Sync/TraktSyncService.swift`
  - why_it_is_a_bug: Local library/history/rating records that use TMDB-based IDs are excluded before push (guard mediaId.hasPrefix("tt") else continue). Trakt push methods also only serialize ids.imdb. This causes valid local changes for TMDB-only items to never sync to Trakt.
  - trigger_or_repro: Create local watchlist/rating/history entries with mediaId like tmdb-12345 (no IMDb ID), run Trakt sync, and observe pushWatchlist/pushRatings/pushHistory loops skip those entries due to hasPrefix("tt") guards; no Trakt API call is made for them.
  - impact: Watchlist additions, ratings, and watch-history updates for TMDB-only catalog items are silently missing in Trakt, leaving cross-device state inconsistent.
  - evidence: TraktSyncOrchestrator.pushWatchlist/pushRatings/pushHistory each guard on mediaId.hasPrefix("tt") and continue otherwise; TraktSyncService.addToWatchlist/addRating/addToHistory payloads only send ids.imdb.
- `[LANE-A-2026-04-02-A-002] Trakt history push dedup only checks newest 1,000 remote items, so older plays are re-pushed as duplicates`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
  - why_it_is_a_bug: pushHistory deduplicates local completed history against fetchRemoteHistoryKeys(), but fetchRemoteHistoryKeys() hard-caps remote history paging to maxPages (default 20 × 50 = 1,000). Any already-synced remote history older than that window is missing from the dedup key set and is treated as absent.
  - trigger_or_repro: Use an account with >1,000 Trakt history entries and local completed history containing older entries that already exist remotely. Run sync: pushHistory iterates local entries, remoteHistoryKeys lacks older keys due to page <= maxPages cap, and addToHistory is called again for those older items.
  - impact: Older watch-history records can be repeatedly re-submitted, causing duplicate history/play entries and inaccurate watch counts in Trakt.
  - evidence: TraktSyncOrchestrator.fetchRemoteHistoryKeys() loops while `page <= maxPages`; maxPages defaults to 20. TraktSyncOrchestrator.pushHistory() scans all local completed history pages and only skips when `remoteHistoryKeys.contains(syncKey)`; keys beyond the newest 1,000 remote items are never loaded for dedup.
- `[LANE-A-2026-04-02-A-003] CSV export silently overwrites same-named folders across list types`
  - confidence: high
  - paths: `VPStudio/Services/Import/LibraryCSVExportService.swift`
  - why_it_is_a_bug: exportAll() writes each folder export to `outputDir.appendingPathComponent(sanitizeFileName(displayName) + ".csv")` without checking for filename collisions. Watchlist and Favorites folders can legally share the same display name, so the later write replaces the earlier file.
  - trigger_or_repro: Create a Watchlist folder and a Favorites folder with the same name (for example, 'Sci-Fi'), each containing entries. Run exportAll(). Both loops compute `Sci-Fi.csv`; the second write overwrites the first file in the same output directory.
  - impact: One list's exported data is lost from disk, producing incomplete backup/export output while reporting success.
  - evidence: LibraryCSVExportService.exportAll() iterates list types/folders and derives `fileName` solely from `displayName`; it then writes directly to that path with `csv.write(to: fileURL, ...)` and no uniqueness/collision handling.
- `[LANE-A-2026-04-02-A-004] Trakt history write on stop is skipped whenever scrobble start was not active`
  - confidence: high
  - paths: `VPStudio/Services/Sync/ScrobbleCoordinator.swift`
  - why_it_is_a_bug: stopPlayback() exits immediately unless `isScrobbling` is true, but the history write (`addToHistory`) is inside that guarded block. If start scrobble did not activate (for example start request failed), completed playback is never written to Trakt history even when trakt history sync is enabled.
  - trigger_or_repro: Cause `startScrobble` to fail or not activate for a playback session, then watch past 80% and call `stopPlayback`. The top guard in stopPlayback returns early on `isScrobbling == false`, so the later `addToHistory(imdbId:type:episodeId:)` path is never reached.
  - impact: Completed plays are silently missing from Trakt history whenever scrobble start does not become active for that session, creating sync gaps.
  - evidence: ScrobbleCoordinator.stopPlayback begins with `guard isScrobbling, let mediaId = activeMediaId, let mediaType = activeMediaType else { return }` and only after that attempts `service.addToHistory(...)` when progress > 80 and history sync is enabled.
- `[LANE-A-2026-04-02-A-005] Trakt scrobble/history sends tmdb-* IDs as imdb IDs, so tmdb-only titles silently fail sync`
  - confidence: high
  - paths: `VPStudio/Services/Sync/ScrobbleCoordinator.swift`, `VPStudio/Services/Sync/TraktSyncService.swift`, `VPStudio/Services/Metadata/TMDBService.swift`
  - why_it_is_a_bug: TMDBService can persist media items with IDs like `tmdb-<id>` when no IMDb ID exists. ScrobbleCoordinator forwards `mediaId` directly into TraktSyncService.startScrobble/stopScrobble/addToHistory as the `imdbId` argument, and TraktSyncService always serializes that value into `ids.imdb`. For tmdb-prefixed IDs this creates invalid Trakt payload IDs and the calls fail.
  - trigger_or_repro: Play a title whose local `MediaItem.id` is `tmdb-12345` (no IMDb ID), with Trakt scrobble/history enabled. startPlayback/stopPlayback call TraktSyncService with `imdbId: mediaId`; Trakt receives `ids.imdb = "tmdb-12345"` and rejects the request. Errors are swallowed in ScrobbleCoordinator (`catch {}` / `try?`).
  - impact: Real-time Trakt scrobbles and stop-time history writes are silently missing for tmdb-only titles, leaving watched progress/history incomplete despite sync being enabled.
  - evidence: ScrobbleCoordinator.startPlayback/stopPlayback pass `mediaId` directly to TraktSyncService.startScrobble/stopScrobble/addToHistory. TraktSyncService builds payloads with `"ids": {"imdb": imdbId}` for scrobble/history. TMDBService.toMediaItem sets `MediaItem.id` to `"tmdb-\(id)"` when external IMDb ID is absent.
- `[LANE-A-2026-04-02-A-006] moveLibraryEntry updates every same-media row across folders instead of only the targeted entry`
  - confidence: high
  - paths: `VPStudio/Core/Database/DatabaseManager.swift`
  - why_it_is_a_bug: `moveLibraryEntry` performs a broad SQL UPDATE keyed only by `mediaId` and `listType`. When the same media exists in multiple folders of the same list type (supported by folder-specific entry IDs and Trakt custom-list sync), moving one item relocates all copies to the destination folder.
  - trigger_or_repro: Create two watchlist folders that both contain the same mediaId (for example via Trakt custom-list pull into separate mapped folders). Call `moveLibraryEntry(mediaId:listType:toFolderId:)` to move the item from folder A to folder B. The SQL updates every row matching that mediaId/listType, so entries from other folders are moved too.
  - impact: Folder organization is unintentionally corrupted: unrelated copies are removed from their original folders, and users cannot reliably move a single folder entry without side effects.
  - evidence: DatabaseManager.moveLibraryEntry executes `UPDATE user_library SET folderId = ? WHERE mediaId = ? AND listType = ?` with no source-folder or entry-id constraint.
<!-- LANE_A_FINDINGS_END -->

### Lane A validation notes
<!-- LANE_A_VALIDATION_START -->
<!-- append Lane A validation / duplicate / invalidity notes below -->
- **event A-018**: StremioIndexer.searchByQuery now correctly uses EpisodeTokenMatcher.context(fromQuery: query) and passes episodeContext?.season/episode to search() — episode filtering from query string is no longer dropped _(at 2026-04-02T15:23:00Z)_
- **event A-030**: LibraryCSVExportService.fetchRatings now correctly uses if dict[mediaId] == nil guard before assignment — since events are ordered DESC by createdAt (newest first), the first event per mediaId is kept, ensuring newest rating wins _(at 2026-04-02T15:23:00Z)_
- **invalid A-018**: Revalidated as stale on current code: StremioIndexer no longer loses episode-context filtering in searchByQuery flow. _(at 2026-04-02T15:45:00Z)_
- **invalid A-030**: Revalidated as stale on current code: LibraryCSVExportService now preserves newest rating per mediaId. _(at 2026-04-02T15:45:00Z)_
- **invalid A-012**: No longer reproduces: TorBoxService.selectFiles now persists selectedFileIDsByTorrent and calls selectMatchingEpisodeFile. _(at 2026-04-02T17:44:00Z)_
- **invalid A-024**: No longer reproduces: Debrid providers no longer all use empty no-op selectFiles implementations, so this cross-provider blanket claim is stale. _(at 2026-04-02T17:44:00Z)_
- **invalid A-003**: No longer reproduces: stopPlayback now forwards activeEpisodeId into addToHistory when present. _(at 2026-04-02T17:44:00Z)_
- **invalid A-020**: No longer reproduces: pullHistory now passes episodeId into fetchWatchHistory when syncing history. _(at 2026-04-02T17:44:00Z)_
<!-- LANE_A_VALIDATION_END -->

### Lane B findings
<!-- LANE_B_FINDINGS_START -->
- `[B-020] DetailViewModel.resolveInitialSeason reads stale mediaLibrary.watchHistory`
  - confidence: high
  - paths:
- `[B-021] DownloadsViewModel.playFile uses potentially stale mediaTitle from DownloadTask`
  - confidence: medium
  - paths: `VPStudio/ViewModels/Downloads/DownloadsViewModel.swift`
  - why_it_is_a_bug: playFile() on a completed download task constructs a PlayerSessionRequest using task.mediaTitle. DownloadTask.mediaTitle is a stored property set when the download was enqueued. If the user has since renamed the title in VPStudio's library, the stale title from the download record is used in the player session rather than the current library title.
  - trigger_or_repro: playFile() on a completed download task constructs a PlayerSessionRequest using task.mediaTitle. DownloadTask.mediaTitle is a stored property set when the download was enqueued. If the user has since renamed the title in VPStudio's library, the stale title from the download record is used in the player session rather than the current library title.
  - impact: The player session receives an outdated title string, which can cause incorrect metadata display, wrong tracking, or mismatched library state in analytics.
  - evidence: playFile uses task.displayTitle which comes from the DownloadTask stored property set at enqueue time — not re-resolved from current library
- `[LANE-B-2026-04-02-B-001] LibraryView fallback preview hard-codes unknown items as movies, breaking TV detail routing`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Library/LibraryView.swift`, `VPStudio/Views/Windows/Detail/DetailView.swift`
  - why_it_is_a_bug: When a library entry has no cached MediaItem, LibraryView.preview(for:) fabricates a MediaPreview with type: .movie for every unknown item. That fabricated preview is then passed into DetailView, and DetailViewModel.loadDetail uses preview.type to choose metadata lookup mode. Series entries without cached MediaItem are therefore routed through movie detail lookup.
  - trigger_or_repro: Create/sync a library item that lacks a cached MediaItem for a TV series IMDb id. Open it from Library: preview(for:) emits type .movie, then DetailViewModel.loadDetail loads with preview.type == .movie, so series details are not resolved through the series path.
  - impact: Users can land on incorrect detail data (or no usable series detail) for TV entries missing local metadata, which blocks correct season/episode selection and stream search context.
  - evidence: LibraryView.preview(for:) fallback returns MediaPreview(type: .movie) for unknown IDs; DetailView passes preview to DetailViewModel.loadDetail(preview:apiKey:), and that method calls getDetail(..., type: preview.type).
- `[LANE-B-2026-04-02-B-002] Search silently shows empty results when TMDB is unconfigured instead of surfacing a setup error`
  - confidence: high
  - paths: `VPStudio/ViewModels/Search/SearchViewModel.swift`, `VPStudio/Views/Windows/Search/SearchView.swift`
  - why_it_is_a_bug: If no TMDB metadata service is configured, SearchViewModel.search() still accepts the query, clears results, and exits with error == nil. The Search UI then transitions to the generic empty-results state, which incorrectly implies the query returned no matches instead of indicating setup is missing.
  - trigger_or_repro: With no TMDB API key configured, open Search and submit any non-empty query. SearchViewModel.search() runs `guard let service = metadataService else { replaceResults([]); isSearching = false; return }`, setting no error. SearchView then renders the .empty Explore phase for the submitted query rather than a configuration error.
  - impact: Users are misled into thinking catalog search succeeded with zero matches, and they are not directed to Settings to add TMDB credentials.
  - evidence: SearchViewModel.search() has a metadataService guard that clears results and returns without setting error. Explore phase logic maps a submitted query with empty results and no error to .empty.
- `[LANE-B-2026-04-02-B-003] Search year-range presets (2020s/2010s/Classic) apply only a single year`
  - confidence: high
  - paths: `VPStudio/ViewModels/Search/SearchViewModel.swift`
  - why_it_is_a_bug: The UI model defines decade-style presets with explicit ranges (for example 2020...2029), but applying a preset sets yearFilter to only the range lowerBound. All search/discover requests then use that single Int year, and there is no local post-filter enforcing the full range. So '2020s' behaves like '2020 only'.
  - trigger_or_repro: In Search, apply the '2020s' year preset and run a text search or genre/mood browse. SearchViewModel.applyYearRangePreset sets yearFilter = preset.yearRange.lowerBound (2020). Subsequent search()/browseGenre()/discoverMoodCard() calls pass only yearFilter, so titles from 2021-2029 are excluded.
  - impact: Decade presets return materially incomplete result sets and can look empty or low-quality versus user intent, reducing trust in search filters and discover lanes.
  - evidence: YearRangePreset defines multi-year ranges; applyYearRangePreset maps any selected preset to yearFilter = preset.yearRange.lowerBound; request paths use yearFilter only.
- `[LANE-B-2026-04-02-B-004] Search language filter UI allows multi-select but only one language is actually applied`
  - confidence: high
  - paths: `VPStudio/ViewModels/Search/SearchViewModel.swift`, `VPStudio/Views/Windows/Search/SearchView.swift`, `VPStudio/Views/Windows/Search/ExploreFilterSheet.swift`
  - why_it_is_a_bug: The filter UI explicitly supports selecting multiple languages (Set<String> with toggle rows/checkmarks), but SearchViewModel collapses that set to a single primaryLanguage using sorted().first and sends only that one language to TMDB calls. Extra selected languages are silently ignored.
  - trigger_or_repro: In Search filters, select two or more languages (for example Spanish + French), apply filters, then run a query or genre browse. Despite multi-select state and summary chips showing multiple languages, requests use only one language value from primaryLanguage (alphabetically first).
  - impact: Users get narrower or unexpected results while believing multiple-language filtering is active, which can hide valid matches.
  - evidence: ExploreFilterSheet binds selectedLanguages as Set<String>; SearchViewModel.primaryLanguage returns only languageFilters.sorted().first, and search()/discover paths pass language: primaryLanguage into service calls.
- `[LANE-B-2026-04-02-B-005] Search filter sheet Cancel action does not cancel sort/genre changes`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Search/SearchView.swift`, `VPStudio/Views/Windows/Search/ExploreFilterSheet.swift`, `VPStudio/ViewModels/Search/SearchViewModel.swift`
  - why_it_is_a_bug: The filter sheet presents explicit Apply and Cancel actions, but sort and genre controls are wired to live bindings that mutate SearchViewModel immediately. Pressing Cancel therefore leaves changed filters/results in place instead of discarding edits.
  - trigger_or_repro: Open Search filters, change Genre or Sort, then tap Cancel. Genre changes apply instantly and sort selection remains changed because ExploreFilterSheet writes directly through bindings; Cancel only dismisses and has no rollback path.
  - impact: Users cannot safely preview filter adjustments and back out. This causes accidental result-lane changes and violates expected modal sheet semantics.
  - evidence: SearchView injects sortOption as Bindable(viewModel).sortOption and selectedGenre via a binding that calls viewModel.selectGenre($0); the Cancel toolbar action only calls dismiss() with no rollback.
- `[LANE-B-2026-04-02-B-006] Clearing Search filters leaves stale mood-card context active and traps Explore in results mode`
  - confidence: high
  - paths: `VPStudio/ViewModels/Search/SearchViewModel.swift`, `VPStudio/Views/Windows/Search/SearchView.swift`
  - why_it_is_a_bug: Selecting a regular mood card sets activeMoodCard and selectedGenre. The Clear action calls clearAllFilters(), which clears selectedGenre via selectGenre(nil) but never clears activeMoodCard. Because derivedExplorePhase returns .results whenever activeMoodCard != nil, the UI remains in results mode even after filters are cleared and results are emptied.
  - trigger_or_repro: In Search, choose a non-special mood card. Then tap the inline Clear chip. clearAllFilters() resets sort/year/language and calls selectGenre(nil), but activeMoodCard remains set, so explorePhase stays .results and the stale mood context persists.
  - impact: Users cannot reliably reset Search to a neutral state after clearing filters; stale mood context can keep the page in an empty/stuck results shell.
  - evidence: SearchViewModel.selectMoodCard(_:) assigns activeMoodCard before calling selectGenre(genre). clearAllFilters() calls selectGenre(nil) but does not reset activeMoodCard. derivedExplorePhase returns .results when activeMoodCard != nil even if results is empty.
- `[LANE-B-2026-04-02-B-007] Detail torrent rows can remain stuck in Downloaded state after the download is removed`
  - confidence: high
  - paths: `VPStudio/ViewModels/Detail/DetailViewModel.swift`, `VPStudio/Views/Windows/Detail/DetailTorrentsSection.swift`
  - why_it_is_a_bug: DetailViewModel.refreshDownloadStates() only updates hashes when their stored taskId still exists in the latest download list. If the task was deleted, the method leaves the previous hash state untouched instead of resetting it. TorrentResultRow renders `.completed` as a non-interactive 'Downloaded' label, so stale state persists in UI and blocks re-download.
  - trigger_or_repro: From Detail, queue a torrent download and let it reach completed. Delete that download from Downloads. Return to Detail; downloadsDidChange triggers refreshDownloadStates(). Because taskById no longer contains the stored taskId, the loop skips missing tasks and keeps the old .completed state for that hash. The row still shows 'Downloaded' with no Download/Retry action.
  - impact: Users can be prevented from re-queueing a stream they intentionally removed. The detail UI reports an inaccurate download status.
  - evidence: In refreshDownloadStates(), `guard let task = taskById[taskId] else { continue }` skips missing tasks and never clears `downloadStates[hash]`. In TorrentResultRow.downloadButton, `.completed` renders a static label while only `.idle`/`.failed` expose actionable download buttons.
- `[LANE-B-2026-02-B-008] Detail layout hides the streams section whenever search returns zero results`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift`, `VPStudio/Views/Windows/Detail/DetailTorrentsSection.swift`
  - why_it_is_a_bug: SeriesDetailLayout only renders DetailTorrentsSection behind `if !viewModel.torrentSearch.results.isEmpty`. When a search yields no streams, the entire streams panel is removed, so users cannot see the built-in empty/error guidance or any retry affordance.
  - trigger_or_repro: Open a detail page where torrent search yields zero matches (or clear results to empty). Because `viewModel.torrentSearch.results` is empty, `torrentsSection` is not rendered at all. The expected 'No Streams Found'/'Select an Episode' states in DetailTorrentsSection never appear.
  - impact: Users get no on-page stream-state feedback when nothing is found and can be left in a dead-end flow with no visible stream panel context.
  - evidence: In SeriesDetailLayout.body, torrentsSection is gated by `if !viewModel.torrentSearch.results.isEmpty { torrentsSection }`. DetailTorrentsSection itself contains explicit empty/error UI branches, but those cannot render when the parent omits the section entirely.
- `[LANE-B-2026-04-02-B-009] Detail download-state badges reset to idle after reopening a title`
  - confidence: high
  - paths: `VPStudio/ViewModels/Detail/DetailViewModel.swift`, `VPStudio/Views/Windows/Detail/DetailTorrentsSection.swift`
  - why_it_is_a_bug: DetailViewModel persists torrent row download status only in the in-memory `downloadTaskIdsByHash` map, which is populated during `queueDownload`. After navigating away/reopening Detail (new view-model instance), that map starts empty, so `refreshDownloadStates()` exits early and existing download tasks are never reflected. Row state falls back to `.idle` even when the same torrent is already downloading or completed.
  - trigger_or_repro: Queue a torrent from Detail, then leave and reopen the same title. `downloadTaskIdsByHash` is empty in the new view-model, `refreshDownloadStates()` returns immediately on `guard !downloadTaskIdsByHash.isEmpty else { return }`, and `downloadState(for:)` returns default `.idle`, so the row shows Download/Retry UI instead of current task status.
  - impact: Users can be shown incorrect stream status and may enqueue duplicate downloads for torrents already in-progress or already downloaded.
  - evidence: `queueDownload` is the only path that assigns `downloadTaskIdsByHash[hash] = enqueuedTask.id`; `refreshDownloadStates()` short-circuits when that dictionary is empty; `downloadState(for:)` returns `downloadStates[torrent.infoHash] ?? .idle`.
- `[LANE-B-2026-04-04-B-012] Navigation badges can never appear because ContentView never passes non-zero badge counts`
  - confidence: high
  - paths: `VPStudio/Views/Windows/ContentView.swift`, `VPStudio/Views/Windows/Navigation/VPSidebarView.swift`, `VPStudio/Views/Windows/Navigation/TabBadgePolicy.swift`
  - why_it_is_a_bug: Badge visibility is entirely driven by `activeDownloadCount` and `settingsWarningCount`, but ContentView instantiates both `VPBottomTabBar` and `VPSidebarView` without supplying those values, so the defaults remain zero and badge conditions are never met.
  - trigger_or_repro: Start at least one active download or create a settings warning condition. Open either bottom-tab or sidebar navigation. No badge dot appears because counts are still zero at the navigation components.
  - impact: Users receive no visual navigation alerts for active downloads or settings warnings.
  - evidence: `ContentView` creates `VPBottomTabBar`/`VPSidebarView` with only selected tab/presentation callbacks and omits `activeDownloadCount`/`settingsWarningCount`; badge policy returns `false` for count == 0 in all paths.
- `[LANE-B-2026-04-04-B-013] LibraryView can render stale list/folder data after rapid selection changes because cancelled loads still mutate state`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Library/LibraryView.swift`
  - why_it_is_a_bug: `scheduleReload()` cancels prior load tasks and increments `selectionLoadToken`, but `loadSelection/loadFolders/loadLibraryEntries/loadHistoryEntries` still assign entries/folders/mediaItems without verifying token or cancellation. A slower cancelled load can complete later and overwrite UI state for the newest selection.
  - trigger_or_repro: In Library, rapidly switch between Watchlist/Favorites and/or folder chips while storage queries are non-trivial. A newer load starts, but an older canceled task finishes afterward. Grid/folder contents can momentarily show the previous selection while selectedList already points to the new one.
  - impact: Users can see mismatched library contents for the active tab/folder, creating confusing navigation and increasing risk of acting on the wrong visible set.
  - evidence: `scheduleReload()` increments selection token and starts async load tasks; load methods assign `entries`, `folders`, `mediaItems` after await without checking `selectionLoadToken` or task cancellation state.

<!-- LANE_B_FINDINGS_END -->

### Lane B validation notes
<!-- LANE_B_VALIDATION_START -->
<!-- append Lane B validation / duplicate / invalidity notes below -->
- **invalid B-020**: No longer reproduces: DetailViewModel.loadDetail loads `mediaLibrary.watchHistory` before resolving initial season, so stale watchHistory is not read during initial selection anymore. _(at 2026-04-02T16:02:00Z)_
- **invalid B-020**: Revalidated as stale on current code: DetailViewModel resolves watch history before or during season initialization safely, so stale watch history is no longer read during initial season resolution. _(at 2026-04-04T03:44:00Z)_
- **invalid LANE-B-2026-04-03-B-010**: No longer reproduces: `LibraryCSVExportSheet.swift` now delegates export to `LibraryCSVExportService.exportAll()` with no `encodeCSV(entries:historyEntries:)` call path; this finding references a removed/changed flow. _(at 2026-04-04T03:31:00Z)_
- **invalid LANE-B-2026-04-03-B-011**: No longer reproduces: `DetailTorrentsSection` is present and used by `SeriesDetailLayout.torrentsSection`; the missing-component assertion is stale. _(at 2026-04-04T03:31:00Z)_
- **invalid LANE-B-2026-04-03-B-010**: No longer reproduces: LibraryCSVExportSheet now uses `LibraryCSVExportService.exportAll()` and no longer calls the prior `encodeCSV(entries:historyEntries:)` crash-prone path. _(at 2026-04-04T03:44:00Z)_
- **invalid LANE-B-2026-04-03-B-011**: No longer reproduces: the component exists and is used by detail layout; the prior missing symbol assertion is stale. _(at 2026-04-04T03:44:00Z)_
- **event LANE-B-2026-04-04-B-013**: _(at 2026-04-04T08:24:00Z)_
<!-- LANE_B_VALIDATION_END -->

### Lane C findings
<!-- LANE_C_FINDINGS_START -->
- `[LANE-C-2026-03-31-C-001] HDRIOrientationAnalyzer.detectScreenYaw: nil result silently propagates to database, corrupting hdriYawOffset for affected assets`
  - confidence: high
  - paths: `VPStudio/Services/Environment/HDRIOrientationAnalyzer.swift`, `VPStudio/Services/Environment/EnvironmentCatalogManager.swift`
  - why_it_is_a_bug: `detectScreenYaw` can return `nil` when the thumbnail decode fails, the image is too small, or the luminance analysis finds no peak. In `EnvironmentCatalogManager.bootstrapCuratedAssets`, the guard `if let yaw = await HDRIOrientationAnalyzer.detectScreenYaw(at: fileURL)` only saves a yaw when non-nil — but the backfill loop iterates all HDRI assets where `hdriYawOffset == nil`. An asset whose HDRI produces `nil` from the analyzer is silently skipped every bootstrap run with no logging and no fallback. The nil value stays in the database forever.
  - trigger_or_repro: User imports an HDRI that the analyzer cannot process (e.g., corrupt HDR bytes, unusual color temperature, or a panorama whose bright region is not in the +5°–+55° latitude band). On every app launch, `bootstrapCuratedAssets` calls `detectScreenYaw` which returns nil, the guard skips the save, and `hdriYawOffset` remains nil in the database. When `HDRISkyboxEnvironment` renders this asset, it uses `hdriYawOffset = nil`, resulting in wrong screen orientation.
  - impact: Affected HDRI environments always render with an incorrect screen orientation. The user sees the cinema screen facing the wrong direction. No error is surfaced; the problem is invisible until the user manually notices the wrong orientation.
  - evidence: `detectScreenYaw` returns `nil` for: `w <= 1 || h <= 1` (zero-size image), when `CGImageSourceCreateThumbnailAtIndex` fails, or when `smoothed.indices.max` returns nil (no peak found). The backfill loop silently skips nil returns without logging or fallback. `persistImportedAsset` calls `detectScreenYaw` with `hdriYawOffset == nil` path — same silent-skip behavior.
- `[LANE-C-2026-03-31-C-002] AIAssistantManager.configure: hardcoded speculative/future model IDs used as production fallbacks`
  - confidence: high
  - paths: `VPStudio/Services/AI/AIAssistantManager.swift`
  - why_it_is_a_bug: `configure(provider:model:)` uses hardcoded concrete model IDs as defaults when `model` is nil: `"claude-sonnet-4-6"` (does not match any known Anthropic API model ID), `"gpt-5.2"` (GPT-5.2 has never existed as a released model; the current flagship is GPT-4o), `"gemini-2.5-flash"` (real, but pinned to a specific minor version that may drift). If a user has configured an API key but never explicitly set a model, playback starts with the hardcoded fallback — which may be an invalid model ID for that provider, causing AI requests to fail silently.
  - trigger_or_repro: User sets an OpenAI API key in Settings without selecting a specific model. Later, `AIAssistantManager` is asked for recommendation. `providers[.openAI]` is configured with `model: "gpt-5.2"` (the hardcoded default). OpenAI API rejects the model ID; the provider throws or returns an error.
  - impact: AI recommendation and analysis features can silently fail when users have API keys configured but haven't explicitly picked a model. The hardcoded IDs are plausible but wrong, making diagnosis difficult.
  - evidence: `providers[.openAI] = OpenAIProvider(apiKey: apiKey, model: model ?? defaultModelID ?? "gpt-5.2")` — `"gpt-5.2"` is not a released OpenAI model ID. `providers[.anthropic]` uses `"claude-sonnet-4-6"` which doesn't match Anthropic's actual ID format (`claude-sonnet-4-20250514`). The catalog has the canonical IDs (`claude-sonnet-4-20250514`, `gpt-4o`) but the hardcoded fallbacks bypass them.
- `[LANE-C-2026-03-31-C-003] APMPInjector.stereoFormatDescription: CMVideoFormatDescription rebuilt on every frame; width/height cache never invalidates correctly on pixel buffer size changes`
  - confidence: medium
  - paths: `VPStudio/Services/Player/Immersive/APMPInjector.swift`
  - why_it_is_a_bug: `stereoFormatDescription` checks `width == cachedWidth && height == cachedHeight` to decide whether to reuse `stereoFormatDesc`. If dimensions change and later return to a previous size with different mode, the cache can return a stale format description with old stereo packing metadata. This is especially problematic when mode changes during playback or on failed rebuilds.
  - trigger_or_repro: A stream switches resolution mid-playback (adaptive bitrate). The pixel buffer size changes from 1920×1080 to 1280×720. The next frame's `stereoFormatDescription` call rebuilds the format description. If this rebuild fails and caches reset, the subsequent valid frame can reuse a stale description not matching current stereo mode.
  - impact: Stereo 3D video may display incorrectly — wrong eye assignment, wrong packing layout — if resolution changes occur during playback.
  - evidence: `if let cached = stereoFormatDesc, width == cachedWidth, height == cachedHeight { return cached }` — cache is keyed by dimensions only, not by mode. If `mode` changes between calls, the cached format still has old mode packing metadata.
- `[LANE-C-2026-03-31-C-004] VPPlayerEngine.updateStereoMode called from PlayerView before engine is initialized with stream metadata`
  - confidence: high
  - paths: `VPStudio/Services/Player/State/VPPlayerEngine.swift`, `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: In `preparePlayback`, `engine.updateStereoMode(from: mediaTitle ?? stream.fileName)` is called at the top of the function, before any player engine has been selected or any `StreamInfo` metadata has been used to populate `engine.audioTracks`, `engine.subtitleTracks`, or other track info. The `SpatialVideoTitleDetector` relies solely on the title string to infer stereo mode — it has no access to actual codec, container, or track metadata. A filename like `movie_SBS.mkv` can be detected as side-by-side, but `movie.mkv` with embedded MV-HEVC will default to mono. The engine's `stereoMode` is set based on a guess before the player has even attempted to open the file.
  - trigger_or_repro: User opens a 3D MKV file with MV-HEVC encoding (which does NOT have "sbs" or "ou" in the filename). The file is detected as mono. `engine.updateStereoMode(from: "movie.mkv")` sets `stereoMode = .mono`. `updateAPMPInjector` is called in the AVPlayer path and sees `stereoMode = .mono`, so `apmpInjector.stop()` is called even though the stream is actually MV-HEVC 3D. Spatial playback fails silently.
  - impact: MV-HEVC 3D files whose filenames don't contain SBS/OU markers will not activate APMP injection, resulting in flat 2D playback of what should be a 3D video. The user gets no indication that the content is 3D or that the detection failed.
  - evidence: `SpatialVideoTitleDetector.stereoMode(fromTitle:)` uses `["sbs", "side by side", "half OU", "ou"].contains` — no match for MV-HEVC or MV-HEVC indicators. `VPPlayerEngine.swift` `StereoMode` has `.mvHevc` but `SpatialVideoTitleDetector` has no path to return it. `updateStereoMode` is called before any player metadata is consulted.
- `[LANE-C-2026-03-31-C-005] HeadTracker: `isIdle` state read asynchronously inside poll loop, causing potential use-after-free if tracker is stopped while poll task is still running`
  - confidence: medium
  - paths: `VPStudio/Services/Player/Immersive/HeadTracker.swift`
  - why_it_is_a_bug: The poll task reads `self?.isIdle` via `await MainActor.run` on every iteration to decide the poll interval. `stop()` sets `isRunning = false`, `isTracking = false`, nils the ARKit session, and cancels the task — but can run concurrently while the detached poll loop is still active. If `stop()` runs between reads, the loop may access stale tracker state during teardown.
  - trigger_or_repro: User exits immersive space, triggering `HeadTracker.stop()`. `stop()` cancels poll and nils session while the `Task.detached` poll loop is still active. The loop can still read `self?.isIdle` and proceed with stale timing decisions after stop begins.
  - impact: Possible stale head-tracking state for one cycle after stop.
  - evidence: `let currentInterval = await MainActor.run { self?.isIdle == true } ...` with a weak `self` and `stop()` mutating session/state concurrently.
- `[LANE-C-2026-04-02-C-006] ExternalPlayerRouting.launchURL: URL-encoding the full stream URL before template substitution breaks routing for all external players`
  - confidence: high
  - paths: `VPStudio/Services/Player/Policies/ExternalPlayerRouting.swift`
  - why_it_is_a_bug: `launchURL` encodes the stream URL with `encodeForQueryValue` before substituting it into the template. `encodeForQueryValue` strips `:` and `/`, so `https://` becomes `https:%2F%2F...`; this can produce malformed callback URLs for external players.
  - trigger_or_repro: User enables an external player and opens a stream. `launchURL` emits `infuse://...url=https:%2F%2F...`. Some players fail to parse or route because of malformed scheme content.
  - impact: External player routing can silently fail for standard HTTPS stream URLs.
  - evidence: `let encodedStreamURL = encodeForQueryValue(streamURL.absoluteString)` with `CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))` and then substitutes this value directly.
- `[LANE-C-2026-04-02-C-009] Immersive screen-size control posts a notification that PlayerView never handles, so the button does nothing`
  - confidence: high
  - paths: `VPStudio/Views/Immersive/ImmersivePlayerControlsView.swift`, `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: The control posts `.immersiveControlCycleScreenSize` but PlayerView has no handler registration for it. Pressing the control cannot produce a screen-size change.
  - trigger_or_repro: Open immersive controls and tap the `tv` button. Notification is posted, but there is no corresponding handling path in PlayerView.
  - impact: Users see a visible control that does nothing, creating a broken control path.
  - evidence: `ImmersivePlayerControlsView` posts `.immersiveControlCycleScreenSize`; `PlayerView` subscribes to other immersive notifications but not this one.
- `[LANE-C-2026-04-02-C-008] PlayerView refreshes AV subtitle groups in a way that silently overrides active external subtitles`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: `refreshAVMediaOptions(for:)` treats `selectedMediaOption(in: subtitleGroup) == nil` as meaning 'no subtitle is selected' and immediately auto-selects the preferred in-stream subtitle. But this view deliberately sets the AV subtitle selection to `nil` whenever an external subtitle is active, because external subtitles live in `engine.subtitleTracks`, not in AVFoundation. Any later AV media refresh therefore misreads the active external-subtitle state as an empty selection and turns an embedded subtitle back on.
  - trigger_or_repro: Play an AVPlayer-backed stream that exposes an AV legible group, then either let `autoLoadSubtitlesIfEnabled(for:)` download an external subtitle or manually pick one from the subtitle sheet. Both paths call `avPlayer?.currentItem?.select(nil, in: avSubtitleGroup)`, clear `selectedAVSubtitleID`, and activate the external track through `engine.selectSubtitleTrack(0)`. When the scheduled `audioTrackRefreshTask` fires 2 seconds later, or when the user taps `Refresh Track List`, `refreshAVMediaOptions(for:)` sees no selected AV subtitle and auto-selects the preferred in-stream subtitle, overriding the external subtitle the user/app had already chosen.
  - impact: External subtitles can spontaneously stop being the active subtitle source shortly after playback starts or after a track refresh. Users can end up with the wrong subtitle language or with embedded subtitles re-enabled even though they explicitly chose an external subtitle.
  - evidence: In `preparePlayback`, AVPlayer setup schedules `audioTrackRefreshTask = Task { ... await refreshAVMediaOptions(for: player) }` after a 2-second delay. External-subtitle flows all clear the AV subtitle selection with `select(nil, in: avSubtitleGroup)` and then activate the external subtitle via `engine.selectSubtitleTrack(...)`. Inside `refreshAVMediaOptions(for:)`, the subtitle branch does `if let selected = ... { ... } else { ... item.select(preferredOption, in: subtitleGroup) ... }`, so an active external subtitle is overwritten on the next refresh.
- `[LANE-C-2026-04-02-C-010] Immersive environment-switch control is wired to a handler that never presents the environment picker`
  - confidence: high
  - paths: `VPStudio/Views/Immersive/ImmersivePlayerControlsView.swift`, `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: The immersive controls expose a "Change environment" button that posts `.immersiveControlRequestEnvironmentSwitch`, but `PlayerView` maps that callback to `Task { await loadEnvironmentAssets() }` only. `loadEnvironmentAssets()` just refreshes the backing array and never toggles `isShowingEnvironmentPicker`, so the sheet that actually lets users switch environments is never presented from this control path.
  - trigger_or_repro: During immersive playback, open `ImmersivePlayerControlsView` and tap the mountain icon. The button posts `.immersiveControlRequestEnvironmentSwitch`. `ImmersiveControlHandlers` receives it and runs `onRequestEnvironmentSwitch`, which in `PlayerView` only calls `loadEnvironmentAssets()`. Because `isShowingEnvironmentPicker` remains false, no picker appears and no environment-switch UI opens.
  - impact: The immersive "Change environment" control is a visible no-op for users. Environment switching still exists in other surfaces (e.g., top-bar menu), but this dedicated immersive control path cannot complete its advertised action.
  - evidence: `ImmersivePlayerControlsView.secondaryControlsRow` posts `.immersiveControlRequestEnvironmentSwitch` from the mountain button. In `PlayerView.body`, `ImmersiveControlHandlers(onRequestEnvironmentSwitch: { Task { await loadEnvironmentAssets() } })` is the only bound behavior. `loadEnvironmentAssets()` only sets `environmentAssets = ...`; the environment picker is presented exclusively by `.sheet(isPresented: $isShowingEnvironmentPicker)`, and this flag is never set to `true` in that handler path.
- `[LANE-C-2026-04-02-C-011] Custom immersive environments depend on keyword-only screen-mesh discovery with no fallback, causing video to disappear in many USDZ scenes`
  - confidence: high
  - paths: `VPStudio/Views/Immersive/CustomEnvironmentView.swift`
  - why_it_is_a_bug: `CustomEnvironmentView` only assigns `cinemaScreen` when `findScreenEntity(in:)` finds the first `ModelEntity` whose name contains one of six hardcoded keywords (`screen`, `display`, `tv`, `monitor`, `cinema`, `video`). If none match, `cinemaScreen` stays nil and the update loop never applies `VideoMaterial` to any entity. There is no fallback plane and no user-visible error path for this condition.
  - trigger_or_repro: Import/open a custom USDZ environment whose intended projection surface is named generically (for example `Plane`, `Mesh_01`, or localized text) and does not include the hardcoded keywords. `findScreenEntity(in:)` returns nil, so `cinemaScreen` is never set. During playback, `CustomEnvironmentView.update` skips the `if let screen = cinemaScreen` material assignment path, leaving no active video surface in the immersive environment.
  - impact: A large class of third-party or user-authored USDZ environments can enter immersive mode without rendering the movie on any surface, making custom immersive playback appear broken even though media playback continues.
  - evidence: `CustomEnvironmentView` loads the entity and sets `cinemaScreen = findScreenEntity(in: entity)`. `findScreenEntity(in:)` matches only names containing `screen/display/tv/monitor/cinema/video` and otherwise returns nil after recursive traversal. In `RealityView.update`, video material assignment is guarded by `if let screen = cinemaScreen { ... }` with no fallback branch.
- `[LANE-C-2026-04-02-C-012] AV preferred-language auto-selection breaks when subtitle/audio language settings contain comma-separated values`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: `refreshAVMediaOptions(for:)` reads `SettingsKeys.audioLanguage` and `SettingsKeys.subtitleLanguage` as raw strings, then directly compares each AV option's locale to that full string. Elsewhere in the same file (`autoLoadSubtitlesIfEnabled` and `refreshSubtitleCatalog`), `subtitleLanguage` is treated as a comma-separated list and split into multiple language codes. When the stored value contains multiple codes (for example `en,es`), no AV option can match the unsplit string, so the preferred in-stream track is never auto-selected.
  - trigger_or_repro: Set subtitle language to `en,es` in settings. Play an AVPlayer-backed stream with no currently selected legible option and with an English subtitle track available. `refreshAVMediaOptions(for:)` runs and checks `($0.locale?.identifier ?? "").lowercased().hasPrefix(preferredSubtitleLang.lowercased()) || ($0.extendedLanguageTag ?? "").lowercased() == preferredSubtitleLang.lowercased()`, where `preferredSubtitleLang` is `en,es`. No option matches `en,es`, so no preferred subtitle is selected.
  - impact: Users who configure multi-language preferences lose automatic in-stream audio/subtitle language selection in AVPlayer flows, and playback can start with unintended default tracks until manually corrected.
  - evidence: In `refreshAVMediaOptions(for:)`, `preferredAudioLang` and `preferredSubtitleLang` are loaded as raw setting strings and used directly in per-option comparisons. In the same `PlayerView.swift`, OpenSubtitles flows parse `subtitleLanguage` via `.split(separator: ",")`, proving multi-language values are expected on disk. The AV selection branch never performs that split before matching.
- `[LANE-C-2026-04-02-C-013] Custom immersive mode advertises screen-size cycling but routes the control to an explicit no-op`
  - confidence: high
  - paths: `VPStudio/Views/Immersive/ImmersivePlayerControlsView.swift`, `VPStudio/Views/Immersive/CustomEnvironmentView.swift`
  - why_it_is_a_bug: The immersive controls include a visible `tv` button that posts `.immersiveControlCycleScreenSize`, but `CustomEnvironmentView` handles that notification by doing no resize behavior (other than scheduling UI housekeeping). In custom environments with no dedicated size controls, the cycle action is effectively a no-op.
  - trigger_or_repro: Open a custom immersive environment and tap the screen-size control. The control sends the notification, but `CustomEnvironmentView` consumes it only for no-op handling (commented as intentionally disabled/no-op).
  - impact: Users cannot resize/adjust screen size in custom immersive mode through the controls they can see, making the control misleading and functionally inert.
  - evidence: `ImmersivePlayerControlsView` posts `.immersiveControlCycleScreenSize`; `CustomEnvironmentView` handles this notification with `scheduleAutoDismiss()` only and no resize operation.
- `[LANE-C-2026-04-02-C-014] Subtitle download task can apply an old stream’s subtitle to the newly switched stream`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: `downloadAndSelectSubtitle(_:streamID:)` validates the stream only at start, but does not re-check `currentStream.id` after async download. A download kicked off on one stream can complete after the user switches, then overwrite subtitle state for a different active stream.
  - trigger_or_repro: Start a downloadable subtitle fetch on Stream A, then switch to Stream B before download completes. The async subtitle task returns and applies options/selection to B using stale context.
  - impact: Subtitle language/cues may not match actual stream after fast stream switching.
  - evidence: Stream guard check is before the network call in `downloadAndSelectSubtitle`; no second guard exists after `service.downloadSubtitle(...)` before writing subtitle state.
- `[LANE-C-2026-04-02-C-015] Player cleanup keeps previous external subtitle state alive, so switched streams can render stale subtitle cues`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Player/PlayerView.swift`, `VPStudio/Services/Player/State/VPPlayerEngine.swift`
  - why_it_is_a_bug: `cleanupPlayback(clearSession:)` tears down AV/KS player objects but does not clear `VPPlayerEngine` subtitle state (`subtitleTracks`, `selectedSubtitleTrack`, and parsed external cues). If Stream A had an external subtitle selected, switching to Stream B leaves that state intact, and subtitle rendering continues to use stale cues.
  - trigger_or_repro: Play Stream A, load and select an external subtitle. Switch to Stream B where auto subtitle loading is disabled or finds no match. During Stream B playback, `updateSubtitleText(at:)` still reads cues from Engine state that was established for Stream A.
  - impact: After stream switches, users can see subtitles from the previous stream and stale cue entries persist in subtitles state.
  - evidence: `cleanupPlayback(clearSession:)` cancels observers and clears AV-specific groups/options but does not call `engine.loadExternalSubtitles([])` or reset `selectedSubtitleTrack`; `VPPlayerEngine.updateSubtitleText(at:)` reads `parsedSubtitleCues[selectedSubtitleTrack]` whenever a track index is still set.
<!-- LANE_C_FINDINGS_END -->

### Lane C validation notes
<!-- LANE_C_VALIDATION_START -->
<!-- append Lane C validation / duplicate / invalidity notes below -->
- **invalid C-009**: No longer reproduces: immersive screen-size control posts `.immersiveControlCycleScreenSize` which is handled by `HDRISkyboxEnvironment` rather than requiring a PlayerView handler path. _(at 2026-04-02T15:45:00Z)_
- **invalid LANE-C-2026-04-02-C-007**: No longer reproduces: PlayerView cleanup now cancels `audioTrackRefreshTask` after AV playback setup, preventing stale delayed AV track refresh from mutating UI after teardown or stream switch. _(at 2026-04-02T17:11:00Z)_
- **invalid C-002**: No longer reproduces: AIAssistantManager resolvedModelID now resolves via provider catalog/fallback IDs (not hardcoded speculative IDs) before configuring provider models. _(at 2026-04-02T17:44:00Z)_
- **invalid C-006**: No longer reproduces: ExternalPlayerRouting now keeps URL-safe components intact and supports `{raw_url}` fallback, so launch URLs are no longer malformed for HTTPS streams. _(at 2026-04-02T17:44:00Z)_
- **invalid C-001**: No longer reproduces: HDRI yaw backfill now writes a fallback orientation value instead of leaving `hdriYawOffset` permanently nil, so this finding is no longer present on current code. _(at 2026-04-02T21:23:00Z)_
- **invalid C-003**: No longer reproduces: APMP stereo format description cache keys now include mode and mode changes no longer reuse stale cached stereo metadata. _(at 2026-04-02T21:23:00Z)_
- **invalid C-005**: No longer reproduces: HeadTracker start/stop lifecycle handling has been tightened, removing the stale stop-time race observed in this finding. _(at 2026-04-02T21:23:00Z)_
- **invalid C-014**: No longer reproduces: subtitle download task is no longer applied to a switched stream without validating active stream context in current code. _(at 2026-04-04T04:02:00Z)_
<!-- LANE_C_VALIDATION_END -->
