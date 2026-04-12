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
- overall_state: DEGRADED_INPUT
- definition_of_done: ALL_LANES_SATURATED_FOR_NOW = all three lanes are SATURATED_FOR_NOW and there are no unresolved high-priority validation disputes remaining
- active_visible_finding_count: 39
- total_recorded_finding_count: 43
- validation_event_count: 35
- last_overall_update: 2026-04-04T23:47:00Z
<!-- OVERALL_STATUS_END -->

## Input integrity
<!-- INPUT_INTEGRITY_START -->
- status: DEGRADED
- malformed_input_record_count: 2
- non_object_input_record_count: 0
- ignored_non_finding_record_count: 24
- notes:
  - `lane-a.jsonl`: malformed=1, non_object=0, ignored_non_finding=24
  - `lane-c.jsonl`: malformed=1, non_object=0, ignored_non_finding=0
<!-- INPUT_INTEGRITY_END -->

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
- last_scan: 2026-04-04T23:47:00Z
- no_new_valid_bug_streak: 1
- saturation_state: ACTIVE
- scan_mode: hot
- finding_count: 35
- notes: |
  2026-04-04 Run 98: Re-scanned Lane A files across App/, Core/Database, Models, and Services (Debrid, Downloads, Import, Indexers, Metadata, Network, Subtitles, Sync). No new high-confidence non-duplicate findings were identified.
- notes: |
  2026-04-04 Run 97: Re-scanned Lane A on-disk files in App/AppState; Core/Database/DatabaseManager; Models (DebridConfig, UserLibraryEntry, WatchHistory); Services/Debrid (DebridManager, RealDebridService, AllDebridService, TorBoxService, PremiumizeService, DebridLinkService, OffcloudService, EasyNewsService); Services/Downloads (DownloadManager); Services/Import (LibraryCSVImportService, LibraryCSVExportService); Services/Indexers (EZTVIndexer, StremioIndexer, ZileanIndexer); Services/Metadata (TMDBService); Services/Network (NetworkMonitor); Services/Subtitles (OpenSubtitlesService); Services/Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). Added LANE-A-2026-04-04-A-005 for pullHistory skipping remote completed plays when any local watch row already exists.
- notes: |
  2026-04-04 Run 96: Re-scanned Lane A on-disk files in App/AppState; Core/Database/DatabaseManager; Models (UserLibraryEntry); Services/Debrid (DebridManager, RealDebridService, AllDebridService, TorBoxService, PremiumizeService, DebridLinkService, OffcloudService, EasyNewsService); Services/Downloads (DownloadManager); Services/Import (LibraryCSVImportService, LibraryCSVExportService); Services/Indexers (EZTVIndexer, StremioIndexer, ZileanIndexer); Services/Metadata (TMDBService); Services/Network (NetworkMonitor); Services/Subtitles (OpenSubtitlesService); Services/Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). No new high-confidence non-duplicate findings were added.
- notes: |
  2026-04-04 Run 95: Re-scanned Lane A on-disk files in App/AppState; Core/Database/DatabaseManager; Models (UserLibraryEntry); Services/Debrid (DebridManager, PremiumizeService, OffcloudService); Services/Downloads (DownloadManager); Services/Import (LibraryCSVImportService, LibraryCSVExportService); Services/Indexers (EZTVIndexer, StremioIndexer); Services/Metadata (TMDBService); Services/Network (NetworkMonitor); Services/Subtitles (OpenSubtitlesService); Services/Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). No new high-confidence non-duplicate findings were added.
- notes: |
  2026-04-04 Run 94: Re-scanned Lane A on-disk files in App/AppState; Core/Database/DatabaseManager; Models (UserLibraryEntry, WatchHistory); Services/Debrid (DebridManager, RealDebridService, AllDebridService, TorBoxService, PremiumizeService, DebridLinkService, OffcloudService, EasyNewsService); Services/Downloads (DownloadManager); Services/Import (LibraryCSVImportService, LibraryCSVExportService); Services/Indexers (EZTVIndexer, StremioIndexer, ZileanIndexer); Services/Metadata (TMDBService); Services/Network (NetworkMonitor); Services/Subtitles (OpenSubtitlesService); Services/Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). No new high-confidence non-duplicate findings were added.
- notes: |
  2026-04-04 Run 93: Re-scanned Lane A on-disk files in App/AppState; Core/Database/DatabaseManager; Models (DebridConfig, UserLibraryEntry, WatchHistory); Services/Debrid (DebridManager, RealDebridService, AllDebridService, TorBoxService, DebridLinkService, OffcloudService, EasyNewsService); Services/Downloads (DownloadManager); Services/Import (LibraryCSVImportService, LibraryCSVExportService); Services/Indexers (EZTVIndexer, StremioIndexer, ZileanIndexer); Services/Metadata (TMDBService); Services/Network (NetworkMonitor); Services/Subtitles (OpenSubtitlesService); Services/Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). No new high-confidence non-duplicate findings were added.
- notes: |
  2026-04-04 Run 92: Re-scanned Lane A on-disk files in App/AppState; Core/Database/DatabaseManager; Models (DebridConfig, UserLibraryEntry, WatchHistory); Services/Debrid (DebridManager, RealDebridService, AllDebridService, TorBoxService, PremiumizeService, DebridLinkService, OffcloudService, EasyNewsService); Services/Downloads (DownloadManager); Services/Import (LibraryCSVImportService, LibraryCSVExportService); Services/Indexers (EZTVIndexer, StremioIndexer, ZileanIndexer); Services/Metadata (TMDBService); Services/Network (NetworkMonitor); Services/Subtitles (OpenSubtitlesService); Services/Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). No new high-confidence non-duplicate findings were added. Older finding A-011 appears stale on current code because EZTVIndexer.searchByQuery now applies parsed episode context filtering.
- notes: |
  2026-04-04 Run 91: Re-scanned Lane A on-disk files in App/AppState; Core/Database/DatabaseManager; Models (DebridConfig, UserLibraryEntry, WatchHistory); Services/Debrid (DebridManager, RealDebridService, AllDebridService, TorBoxService, PremiumizeService, DebridLinkService, OffcloudService); Services/Downloads (DownloadManager); Services/Import (LibraryCSVImportService, LibraryCSVExportService); Services/Indexers (EZTVIndexer, StremioIndexer, ZileanIndexer); Services/Metadata (TMDBService); Services/Network (NetworkMonitor); Services/Subtitles (OpenSubtitlesService); Services/Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). No new high-confidence non-duplicate findings were added.
- notes: |
  2026-04-04 Run 90: Re-scanned Lane A on-disk files in App/AppState; Core/Database/DatabaseManager; Models (UserLibraryEntry, WatchHistory); Services/Debrid (DebridManager, RealDebridService, AllDebridService, TorBoxService, PremiumizeService, DebridLinkService, OffcloudService); Services/Downloads (DownloadManager); Services/Import (LibraryCSVImportService, LibraryCSVExportService); Services/Indexers (EZTVIndexer, StremioIndexer, ZileanIndexer); Services/Metadata (TMDBService); Services/Network (NetworkMonitor); Services/Subtitles (OpenSubtitlesService); Services/Sync (TraktSyncOrchestrator, TraktSyncService, ScrobbleCoordinator, SimklSyncService). Added LANE-A-2026-04-04-A-004 for invalid torrent-id fallback in Premiumize/Offcloud addMagnet when provider ID is missing.
<!-- LANE_A_STATUS_END -->

## Lane B status
<!-- LANE_B_STATUS_START -->
- scope: 
- paths:
- owner_model: minimax
- last_scan: 2026-04-04T15:04:00Z
- no_new_valid_bug_streak: 1
- saturation_state: ACTIVE
- scan_mode: hot
- finding_count: 18
- notes: |
  Scanned Lane B ViewModels and lane-B UI/navigation/component files (ContentView; Detail/Discover/Downloads/Library/Search/Navigation windows; MediaCardView) on commit 38e5a2dfb5c90869199fb7da5f9568c944da441e. No new high-confidence non-duplicate on-disk bugs were found; lane-b.jsonl remains at 18 records. Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
- notes: |
  Scanned Lane B ViewModels and lane-B UI/navigation/component files (ContentView; Detail/Discover/Downloads/Library/Search/Navigation windows; MediaCardView) on commit 38e5a2dfb5c90869199fb7da5f9568c944da441e and appended LANE-B-2026-04-04-B-016 (stream-open failures are hidden because torrent-row error UI only renders while player launch is in progress). Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
- notes: |
  Scanned Lane B ViewModels and lane-B UI/navigation/component files (ContentView; Detail/Discover/Downloads/Library/Search/Navigation windows; Views/Components) on commit 38e5a2dfb5c90869199fb7da5f9568c944da441e. No new high-confidence non-duplicate findings were identified; lane-b.jsonl remains at 17 records. Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
- notes: |
  Scanned Lane B ViewModels (Detail/Discover/Search/Downloads) plus lane-B UI/navigation/component files (ContentView, Discover/Search/Downloads/Library/Detail windows, VPSidebarView/TabBadgePolicy, MediaCardView, DetailTorrentsSection, SeriesDetailLayout) on commit 1f60f8fb8fae994bf3b3f45ff35859332ea46717. No new high-confidence non-duplicate findings were identified; lane-b.jsonl remains unchanged at 17 records. Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
- notes: |
  Scanned Lane B ViewModels (Detail/Discover/Search/Downloads) plus lane-B UI/navigation/component files (ContentView, Discover/Search/Downloads/Library/Detail windows, VPSidebarView/TabBadgePolicy, MediaCardView, DetailTorrentsSection, SeriesDetailLayout) on commit 1f60f8fb8fae994bf3b3f45ff35859332ea46717. No new high-confidence non-duplicate findings were identified; lane-b.jsonl unchanged. Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
- notes: |
  Scanned Lane B ViewModels plus UI/navigation/component files (ContentView, Discover/Search/Downloads/Library/Detail windows, Navigation, MediaCardView, DetailTorrentsSection, SeriesDetailLayout) on commit 1f60f8fb8fae994bf3b3f45ff35859332ea46717. No new high-confidence non-duplicate findings were identified; lane-b.jsonl unchanged. Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
- notes: |
  Scanned Lane B ViewModels plus UI/navigation/component files (ContentView, Discover/Search/Downloads/Library/Detail windows, Navigation, MediaCardView, DetailTorrentsSection, SeriesDetailLayout) on commit cc86863f249b94df3df2accc4789bd566adea9ba. No new high-confidence non-duplicate findings were identified; lane-b.jsonl unchanged. Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
- notes: |
  Scanned Lane B ViewModels plus UI/navigation/component files (ContentView, Discover/Search/Downloads/Library/Detail windows, Navigation, MediaCardView, DetailTorrentsSection, SeriesDetailLayout) on commit 6259d81c370a22836c5b57a033675aac82d0bda2. No new high-confidence non-duplicate findings were identified; lane-b.jsonl unchanged. Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
- notes: |
  Scanned Lane B ViewModels plus UI/navigation/component files (ContentView, Discover/Search/Downloads/Library/Detail windows, Navigation, MediaCardView, DetailTorrentsSection, SeriesDetailLayout) on commit 36d21f405b2cd24a5da4927b2b920f864faae9e1. No new high-confidence non-duplicate findings were identified; lane-b.jsonl unchanged. Validation events on disk still classify B-020, LANE-B-2026-04-03-B-010, and LANE-B-2026-04-03-B-011 as invalid/stale.
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
- last_scan: 2026-04-04T15:37:00Z
- no_new_valid_bug_streak: 1
- saturation_state: ACTIVE
- scan_mode: hot
- finding_count: 16
- notes: |
  2026-04-04 Run 89: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> 29a35e5a8cf0a5d4bb349194ce256c678df3d33c, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler, AnthropicProvider, OpenAIProvider, GeminiProvider), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (APMPInjector, HeadTracker, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, ExternalPlayerRouting, PlayerSessionRouting, PlayerCapabilityEvaluator, PlayerAspectRatioPolicy, SpatialVideoTitleDetector, WatchProgressResumePolicy), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment), Views/Windows/Player (PlayerView), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate findings were appended; findings file remains at 16 records. Validation log still contains prior stale/invalid entries (including C-009, C-014, and LANE-C-2026-04-02-C-007 marked invalid).
- notes: |
  2026-04-04 Run 88: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> 29a35e5a8cf0a5d4bb349194ce256c678df3d33c, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler, AnthropicProvider, OpenAIProvider, GeminiProvider, OllamaProvider, OpenRouterProvider), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (ExternalPlayerRouting, APMPInjector, HeadTracker, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, PlayerEngine, PlayerEngineSelector, PlayerSessionRouting, PlayerCapabilityEvaluator, PlayerAspectRatioPolicy, SpatialVideoTitleDetector, WatchProgressResumePolicy), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, ImmersiveControlsPolicy), Views/Windows/Player (PlayerView, AVPlayerSurfaceView, APMPRendererView, PlayerControlPresentation), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), and Assets.xcassets/Contents.json. Appended 1 new high-confidence, non-duplicate finding: LANE-C-2026-04-04-C-016 (zero-length forward-vector normalization can propagate NaNs into immersive transforms). Validation log still contains prior stale/invalid entries (including C-009, C-014, and LANE-C-2026-04-02-C-007 marked invalid).
- notes: |
  2026-04-04 Run 87: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> 38e5a2dfb5c90869199fb7da5f9568c944da441e, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler, AnthropicProvider, OpenAIProvider, GeminiProvider, OllamaProvider, OpenRouterProvider), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (APMPInjector, HeadTracker, ExternalPlayerRouting, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, PlayerEngineSelector, PlayerSessionRouting, PlayerCapabilityEvaluator, PlayerAspectRatioPolicy, SpatialVideoTitleDetector), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, ImmersiveControlsPolicy), Views/Windows/Player (PlayerView, AVPlayerSurfaceView, APMPRendererView, PlayerControlPresentation), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate findings were appended; findings file remains at 15 records. Validation log still contains prior stale/invalid entries (including C-009, C-014, and LANE-C-2026-04-02-C-007 marked invalid).
- notes: |
  2026-04-04 Run 86: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> 38e5a2dfb5c90869199fb7da5f9568c944da441e, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (APMPInjector, HeadTracker, ExternalPlayerRouting, PlayerEngine, AVPlayerEngine, KSPlayerEngine, PlayerEngineSelector, PlayerSessionRouting, PlayerCapabilityEvaluator, PlayerAspectRatioPolicy, WatchProgressResumePolicy, SpatialVideoTitleDetector, OpenSubtitlesService, Subtitle, SubtitleParser, VPPlayerEngine), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, ImmersiveControlsPolicy), Views/Windows/Player (PlayerView, AVPlayerSurfaceView, APMPRendererView, PlayerControlPresentation), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate findings were appended; findings file remains at 15 records. Validation log still contains prior stale/invalid entries (including C-009, C-014, and LANE-C-2026-04-02-C-007 marked invalid).
- notes: |
  2026-04-04 Run 85: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> 1f60f8fb8fae994bf3b3f45ff35859332ea46717, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (ExternalPlayerRouting, APMPInjector, HeadTracker, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, SpatialVideoTitleDetector, PlayerSessionRouting, PlayerCapabilityEvaluator, PlayerAspectRatioPolicy, WatchProgressResumePolicy, PlayerEngineSelector), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, ImmersiveControlsPolicy), Views/Windows/Player (PlayerView, AVPlayerSurfaceView, APMPRendererView, PlayerControlPresentation), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), App/VPStudioApp, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate findings were appended; findings file remains at 15 records. Validation log still contains prior stale/invalid entries (including C-009, C-014, and LANE-C-2026-04-02-C-007 marked invalid).
- notes: |
  2026-04-04 Run 84: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> 1f60f8fb8fae994bf3b3f45ff35859332ea46717, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (ExternalPlayerRouting, APMPInjector, HeadTracker, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, SpatialVideoTitleDetector, PlayerSessionRouting, PlayerCapabilityEvaluator, PlayerAspectRatioPolicy, WatchProgressResumePolicy, PlayerEngineSelector), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, ImmersiveControlsPolicy), Views/Windows/Player (PlayerView, AVPlayerSurfaceView, APMPRendererView, PlayerControlPresentation), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), App/VPStudioApp, and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate findings were appended; findings file remains at 15 records. Validation log still contains prior stale/invalid entries (including C-009, C-014, and LANE-C-2026-04-02-C-007 marked invalid).
- notes: |
  2026-04-04 Run 83: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> 1f60f8fb8fae994bf3b3f45ff35859332ea46717, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (ExternalPlayerRouting, APMPInjector, HeadTracker, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, PlayerSessionRouting, PlayerCapabilityEvaluator, SpatialVideoTitleDetector, WatchProgressResumePolicy, PlayerAspectRatioPolicy), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, ImmersiveControlsPolicy), Views/Windows/Player (PlayerView, AVPlayerSurfaceView, APMPRendererView, PlayerControlPresentation), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate findings were appended; findings file remains at 15 records. Validation log still contains prior stale/invalid entries (including C-009 and C-014 marked invalid).
- notes: |
  2026-04-04 Run 82: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> cc86863f249b94df3df2accc4789bd566adea9ba, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (ExternalPlayerRouting, APMPInjector, HeadTracker, VPPlayerEngine, AVPlayerEngine, KSPlayerEngine, PlayerSessionRouting, PlayerCapabilityEvaluator, SpatialVideoTitleDetector, WatchProgressResumePolicy, PlayerAspectRatioPolicy), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, ImmersiveControlsPolicy), Views/Windows/Player (PlayerView, AVPlayerSurfaceView, APMPRendererView, PlayerControlPresentation), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate findings were appended; findings file remains at 15 records. Validation log still contains prior stale/invalid entries (including C-014 marked invalid).
- notes: |
  2026-04-04 Run 81: Re-read lane-c state/findings/validation, verified .git/HEAD -> refs/heads/main -> cc86863f249b94df3df2accc4789bd566adea9ba, and re-scanned Lane C sources in Services/AI (AIAssistantManager, AIModelCatalog, AssistantContextAssembler), Services/Environment (EnvironmentCatalogManager, HDRIOrientationAnalyzer), Services/Player (ExternalPlayerRouting, APMPInjector, HeadTracker, VPPlayerEngine, SpatialVideoTitleDetector, AVPlayerEngine, KSPlayerEngine, PlayerSessionRouting, PlayerCapabilityEvaluator), Views/Immersive (ImmersivePlayerControlsView, CustomEnvironmentView, HDRISkyboxEnvironment, ImmersiveControlsPolicy), Views/Windows/Player (PlayerView, AVPlayerSurfaceView, APMPRendererView, PlayerControlPresentation), Core/Diagnostics (RuntimeMemoryDiagnostics), Core/Security (SecretStore), and Assets.xcassets/Contents.json. No new high-confidence, non-duplicate findings were appended; findings file remains at 15 records. Validation log still contains prior stale/invalid items (including C-014 marked invalid).
<!-- LANE_C_STATUS_END -->

## Findings

### Lane A findings
<!-- LANE_A_FINDINGS_START -->
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

- `[LANE-A-2026-04-04-A-001] Trakt custom-list pull can delete local tmdb-* folder entries because push path never mirrors them remotely`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
  - why_it_is_a_bug: For mapped custom folders, `pushFolderItems` only considers local IDs that start with `tt` (`localImdbIds = Set(entries.map(\.mediaId).filter { $0.hasPrefix("tt") })`), so local `tmdb-*` entries are never added to the remote Trakt list. `pullListItems` then treats the remote list as source-of-truth and deletes any local folder entry whose `mediaId` is not in `remoteMediaIds`. This causes local tmdb-only entries to be removed on subsequent (or same-session) syncs.
  - trigger_or_repro: Put a `tmdb-12345` entry into a watchlist folder that is mapped to a Trakt custom list, then run custom-list sync. The push step skips that item because it is not `tt*`; later pull reconciliation loops local entries and executes `removeFromLibrary` for entries absent from `remoteMediaIds`, deleting the local `tmdb-*` row.
  - impact: User-managed custom-folder items with tmdb-only IDs can disappear from local library after sync, causing silent data loss in mapped folders.
  - evidence: In `pushFolderItems`, local set is explicitly `entries.map(\.mediaId).filter { $0.hasPrefix("tt") }`. In `pullListItems`, reconciliation deletes local entries where `!remoteMediaIds.contains(entry.mediaId)` via `database.removeFromLibrary(...)`.

- `[LANE-A-2026-04-04-A-002] TMDB TV search ignores year filter because it sends `year` instead of `first_air_date_year``
  - confidence: high
  - paths: `VPStudio/Services/Metadata/TMDBService.swift`
  - why_it_is_a_bug: TMDBService.search(query:type:page:year:language:) always writes the same `year` query parameter regardless of media type. For `/search/tv`, TMDB expects `first_air_date_year`; `year` is for movie search. As a result, year-constrained TV searches are not filtered by the intended year.
  - trigger_or_repro: Call `TMDBService.search(query:type:.series,page:1,year:2019,language:nil)`. The generated request goes to `/search/tv` with `year=2019` (not `first_air_date_year=2019`), so TMDB does not apply the year constraint for TV results.
  - impact: TV search results can include shows from incorrect years when users apply a year filter, leading to wrong matches and noisier search/discovery results.
  - evidence: In `TMDBService.search(...)`, `params["year"] = String(year)` is set unconditionally after choosing the path, including when `type == .series` and path is `/search/tv`.

- `[LANE-A-2026-04-04-A-003] Mapped Trakt custom-list sync deletes local IMDb additions before push`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`
  - why_it_is_a_bug: syncCustomLists() executes pull for already-mapped lists before push. pullListItems() removes any local folder entry not present on the remote list, so newly added local IMDb entries are deleted before pushFolderItems() runs.
  - trigger_or_repro: With an existing Trakt list mapping, add a new local `tt*` item to that mapped folder and run syncCustomLists(). During pull, pullListItems() computes remoteMediaIds and removes the local item because it is not yet remote. The subsequent push pass then sees no local addition to send, so the item is never pushed and is already deleted locally.
  - impact: Bi-directional custom-list sync is effectively broken for mapped folders: local additions can be silently lost and never propagated to Trakt, causing data loss and inconsistent list state.
  - evidence: In syncCustomLists(), mapped lists call pullListItems(...) in the pull phase before pushFolderItems(...) in the push phase. pullListItems() deletes local entries with `!remoteMediaIds.contains(entry.mediaId)` via database.removeFromLibrary(...).

- `[LANE-A-2026-04-04-A-004] Premiumize/Offcloud magnet add silently substitutes the info-hash as torrent ID when API omits an ID`
  - confidence: high
  - paths: `VPStudio/Services/Debrid/PremiumizeService.swift`, `VPStudio/Services/Debrid/OffcloudService.swift`
  - why_it_is_a_bug: Both addMagnet implementations return the input hash when the provider response lacks a transfer/request ID (`response.id ?? hash` and `decoded.requestId ?? hash`). The returned value is then treated as a provider torrent/request identifier, but downstream status lookups require real provider-issued IDs.
  - trigger_or_repro: Force either provider add-magnet call to return a 2xx payload without `id`/`requestId` (e.g., partial/error payload). `addMagnet` returns the hash string, then `getStreamURL` queries transfer/status APIs using that hash as the torrent ID and fails (not found/not ready) instead of surfacing add-magnet failure.
  - impact: Stream resolution fails with misleading downstream errors, and the original add-magnet failure is masked, making affected downloads/playback attempts silently unrecoverable in normal flow.
  - evidence: PremiumizeService.addMagnet: `return response.id ?? hash`; OffcloudService.addMagnet: `return decoded.requestId ?? hash`. Both services later use that returned value as `torrentId` for `/transfer/list` or `/cloud/status` lookups.

- `[LANE-A-2026-04-04-A-005] Trakt history pull skips remote completed plays whenever any local watch record already exists`
  - confidence: high
  - paths: `VPStudio/Services/Sync/TraktSyncOrchestrator.swift`, `VPStudio/Core/Database/DatabaseManager.swift`
  - why_it_is_a_bug: During pullHistory, the code checks only whether any local WatchHistory row exists for the same media/episode and skips writing if one exists. It does not require the existing row to be completed, nor does it merge/update progress. A partial local row (`isCompleted == false`) therefore blocks importing a completed remote Trakt play for that same item.
  - trigger_or_repro: Create a local in-progress watch_history row for a movie (or episode) with `isCompleted = false`, then ensure Trakt history contains a completed play for that same media/episode and run sync. pullHistory calls `fetchWatchHistory(mediaId:episodeId:)`, receives the existing partial row, and because `existingWatch != nil` it never saves the completed WatchHistory entry from Trakt.
  - impact: Completed plays from Trakt can be silently missing locally for titles that already have partial progress rows, causing stale continue-watching/completion state and inconsistent sync results.
  - evidence: TraktSyncOrchestrator.pullHistory: `let existingWatch = try await database.fetchWatchHistory(mediaId: mediaId, episodeId: episodeId)` followed by `if existingWatch == nil { ... saveWatchHistory(... isCompleted: true) }`. DatabaseManager.fetchWatchHistory returns the most recent row for media/episode without filtering `isCompleted`.
<!-- LANE_A_FINDINGS_END -->

### Lane A validation notes
<!-- LANE_A_VALIDATION_START -->
<!-- append Lane A validation / duplicate / invalidity notes below -->
- **classified_as_stale A-018** _(at 2026-04-02T15:23:00Z)_
- **classified_as_stale A-030** _(at 2026-04-02T15:23:00Z)_
- **invalid A-018**: Revalidated as stale on current code: StremioIndexer no longer loses episode-context filtering in searchByQuery flow. _(at 2026-04-02T15:45:00Z)_
- **invalid A-030**: Revalidated as stale on current code: LibraryCSVExportService now preserves newest rating per mediaId. _(at 2026-04-02T15:45:00Z)_
- **invalid A-012**: No longer reproduces: TorBoxService.selectFiles now persists selectedFileIDsByTorrent and calls selectMatchingEpisodeFile. _(at 2026-04-02T17:44:00Z)_
- **invalid A-024**: No longer reproduces: Debrid providers no longer all use empty no-op selectFiles implementations, so the cross-provider blanket claim is stale. _(at 2026-04-02T17:44:00Z)_
- **invalid A-003**: No longer reproduces: stopPlayback now forwards activeEpisodeId into addToHistory when present. _(at 2026-04-02T17:44:00Z)_
- **invalid A-020**: No longer reproduces: pullHistory now passes episodeId into fetchWatchHistory when syncing history. _(at 2026-04-02T17:44:00Z)_
- **collector_scan lane-A** _(at 2026-04-04T10:34:00Z)_
- **collector_scan lane-A** _(at 2026-04-04T11:41:00Z)_
- **collector_scan lane-A** _(at 2026-04-04T12:35:00Z)_
- **collector_scan lane-A** _(at 2026-04-04T12:56:00Z)_
- **collector_scan lane-A** _(at 2026-04-04T13:56:00Z)_
- **collector_scan lane-A** _(at 2026-04-04T15:17:00Z)_
<!-- LANE_A_VALIDATION_END -->

### Lane B findings
<!-- LANE_B_FINDINGS_START -->
- `[B-021] DownloadsViewModel.playFile uses potentially stale mediaTitle from DownloadTask`
  - confidence: medium
  - paths: (none recorded)

- `[LANE-B-2026-04-02-B-001] LibraryView fallback preview hard-codes unknown items as movies, breaking TV detail routing`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-04-02-B-002] Search silently shows empty results when TMDB is unconfigured instead of surfacing a setup error`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-04-02-B-003] Search year-range presets (2020s/2010s/Classic) apply only a single year`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-04-02-B-004] Search language filter UI allows multi-select but only one language is actually applied`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-04-02-B-005] Search filter sheet Cancel action does not cancel sort/genre changes`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-04-02-B-006] Clearing Search filters leaves stale mood-card context active and traps Explore in results mode`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-04-02-B-007] Detail torrent rows can remain stuck in Downloaded state after the download is removed`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-02-B-008] Detail layout hides the streams section whenever search returns zero results`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-04-02-B-009] Detail download-state badges reset to idle after reopening a title`
  - confidence: high
  - paths: (none recorded)

- `[LANE-B-2026-04-04-B-012] Navigation badges can never appear because ContentView never passes non-zero badge counts`
  - confidence: high
  - paths: `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/ContentView.swift`, `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Navigation/VPSidebarView.swift`, `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Navigation/TabBadgePolicy.swift`
  - why_it_is_a_bug: Badge visibility is entirely driven by activeDownloadCount/settingsWarningCount, but ContentView instantiates both VPBottomTabBar and VPSidebarView without supplying those values, so the default zero values are always used and badge conditions are never met.
  - trigger_or_repro: 1) Start at least one active download or create a settings warning condition. 2) Open either bottom-tab or sidebar navigation. 3) No badge dot appears on Downloads/Settings because counts are still 0 at the navigation components.
  - impact: Users receive no visual navigation alerts for active downloads or settings warnings, weakening status discoverability and delaying corrective action.
  - evidence: ContentView creates VPBottomTabBar/VPSidebarView with only selectedTab/opensEnvironmentPicker/callbacks and omits activeDownloadCount/settingsWarningCount.; VPBottomTabBar and VPSidebarView define activeDownloadCount and settingsWarningCount with default value 0.; TabBadgePolicy.shouldShowBadge returns true only when activeDownloadCount > 0 for Downloads or settingsWarningCount > 0 for Settings.

- `[LANE-B-2026-04-04-B-013] LibraryView can render stale list/folder data after rapid selection changes because cancelled loads still mutate state`
  - confidence: high
  - paths: `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Library/LibraryView.swift`
  - why_it_is_a_bug: scheduleReload() cancels prior load tasks and increments selectionLoadToken, but loadSelection/loadFolders/loadLibraryEntries/loadHistoryEntries still assign entries/folders/mediaItems without verifying token or cancellation. A slower canceled load can finish later and overwrite the UI state for the newest selection.
  - trigger_or_repro: 1) In Library, rapidly switch between Watchlist/Favorites and/or folder chips while storage queries are non-trivial. 2) Newer load starts, but an older canceled task completes afterward. 3) Grid/folder contents can momentarily show the previous selection while selectedList already points to the new one.
  - impact: Users can see mismatched library contents for the active tab/folder, creating confusing navigation and increasing risk of acting on the wrong visible set (move/delete/refresh actions).
  - evidence: scheduleReload() increments selectionLoadToken and cancels prior loadTask, then starts Task { await loadSelection(loadToken:) }.; loadSelection() only uses selectionLoadToken in defer to gate isLoadingSelection, but does not gate writes to entries/historyEntries/folders/mediaItems.; loadFolders(), loadLibraryEntries(), and loadHistoryEntries() perform direct state assignment after awaits with no Task.isCancelled or loadToken check.

- `[LANE-B-2026-04-04-B-014] Left-sidebar navigation drops the Environments tab on non-visionOS, creating layout-dependent tab access`
  - confidence: high
  - paths: `/Users/openclaw/Projects/VPStudio/VPStudio/App/AppState.swift`, `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/ContentView.swift`, `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Navigation/VPSidebarView.swift`
  - why_it_is_a_bug: The bottom-tab layout renders all SidebarTab.mainTabs (including .environments), but the left-sidebar layout hard-codes sidebarMainTabs to exclude .environments and only provides a separate Environments button under #if os(visionOS). On macOS/iOS with left-sidebar layout, users lose direct navigation access to the Environments tab despite it existing as a normal tab elsewhere.
  - trigger_or_repro: 1) Run on a non-visionOS target and set navigation layout to Bottom Tab Bar: Environments appears as a selectable tab. 2) Switch navigation layout to Left Sidebar. 3) Environments is no longer present in the sidebar, so tab availability changes purely by layout.
  - impact: Navigation options become inconsistent across layouts; users can no longer directly reach Environments when using left-sidebar mode on non-visionOS, and persisted tab expectations differ after layout changes.
  - evidence: SidebarTab.mainTabs includes .environments in AppState.swift.; ContentView's VPBottomTabBar iterates SidebarTab.mainTabs, so Environments appears in bottom-tab mode.; VPSidebarView uses SidebarLayoutPolicy.sidebarMainTabs = [.discover, .search, .library, .downloads] and the separate environmentButton is compiled only for visionOS.

- `[LANE-B-2026-04-04-B-015] Rapid season switches can show episodes from the wrong season because stale loadSeason calls still overwrite state`
  - confidence: high
  - paths: `/Users/openclaw/Projects/VPStudio/VPStudio/ViewModels/Detail/DetailViewModel.swift`, `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift`
  - why_it_is_a_bug: Each season tap launches an independent Task that awaits loadSeason, but loadSeason has no request token/cancellation guard before assigning episodes and selectedEpisode. If an earlier season request completes after a later one, stale episodes overwrite the current UI state while selectedSeason may already point to a different season.
  - trigger_or_repro: 1) Open a series with multiple seasons. 2) Tap Season 1 then Season 2 quickly (or any rapid season changes) while episode fetches are still in flight. 3) A slower earlier response can arrive last and replace episodes with the wrong season's list.
  - impact: The episode rail can become inconsistent with the selected season chip, causing wrong-episode selection, incorrect stream searches, and confusing playback/download actions.
  - evidence: SeriesDetailLayout.seasonTab starts Task { await viewModel.loadSeason(...) } for every tap, allowing overlapping season loads.; DetailViewModel.loadSeason sets selectedSeason immediately, then after await service.getEpisodes(...) unconditionally assigns episodes and selectedEpisode with no stale-request guard.; DetailViewModel.cancelInFlightWork only cancels searchTask/cacheEnrichmentTask, not prior loadSeason fetches.

- `[LANE-B-2026-04-04-B-016] Stream-open failures are hidden because torrent-row error UI only renders while player launch is in progress`
  - confidence: high
  - paths: `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Detail/DetailView.swift`, `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Detail/DetailTorrentsSection.swift`
  - why_it_is_a_bug: When stream resolution fails, DetailView stores an error message in playerOpeningError but immediately clears isPlayerOpening in the same task via defer. TorrentResultRow only displays playerOpeningError inside the branch guarded by isPlayerOpening, so the failure message disappears as soon as loading ends.
  - trigger_or_repro: 1) Open a detail page with available torrents. 2) Tap Play on a torrent whose resolve step fails (provider/network failure). 3) The loading state ends and buttons return, but no persistent error message is shown even though playerOpeningError was set.
  - impact: Playback failures become effectively silent, so users get no actionable feedback and may repeatedly tap Play without understanding why launch failed.
  - evidence: DetailView.playTorrent sets isPlayerOpening = true, then on failure sets playerOpeningError, and the task's defer sets isPlayerOpening = false.; TorrentResultRow renders the playerOpeningError message only inside `if isPlayerOpening { ... }`; the non-loading branch shows only action buttons.; No other persistent error surface in SeriesDetailLayout reads playerOpeningError after isPlayerOpening becomes false.
<!-- LANE_B_FINDINGS_END -->

### Lane B validation notes
<!-- LANE_B_VALIDATION_START -->
<!-- append Lane B validation / duplicate / invalidity notes below -->
- **invalid B-020**: No longer reproduces: DetailViewModel.loadDetail loads `mediaLibrary.watchHistory` before resolving initial season, so stale watchHistory is not read during initial selection anymore. _(at 2026-04-02T16:02:00Z)_
- **invalid LANE-B-2026-04-03-B-010**: No longer reproduces: `LibraryCSVExportSheet.swift` now delegates export to `LibraryCSVExportService.exportAll()` with no `encodeCSV(entries:historyEntries:)` call path; this finding references a removed/changed flow. _(at 2026-04-04T03:31:00Z)_
- **invalid LANE-B-2026-04-03-B-011**: No longer reproduces: `DetailTorrentsSection` is present and used by `SeriesDetailLayout.torrentsSection`; the missing-component assertion is stale. _(at 2026-04-04T03:31:00Z)_
- **invalid B-020**: Revalidated as stale on current code: DetailViewModel resolves watch history before or during season initialization safely, so stale watch history is no longer read during initial season resolution. _(at 2026-04-04T03:44:00Z)_
- **invalid LANE-B-2026-04-03-B-010**: No longer reproduces: LibraryCSVExportSheet now uses `LibraryCSVExportService.exportAll()` and no longer calls the prior `encodeCSV(entries:historyEntries:)` crash-prone path. _(at 2026-04-04T03:44:00Z)_
- **invalid LANE-B-2026-04-03-B-011**: No longer reproduces: the component exists and is used by detail layout; the prior missing symbol assertion is stale. _(at 2026-04-04T03:44:00Z)_
- **validator_event LANE-B-2026-04-04-B-013** _(at 2026-04-04T08:24:00Z)_
- **validator_event LANE-B-2026-04-04-B-014** _(at 2026-04-04T10:57:00Z)_
- **collector_scan lane-B** _(at 2026-04-04T10:57:00Z)_
- **collector_scan lane-B** _(at 2026-04-04T12:23:00Z)_
- **collector_scan lane-B** _(at 2026-04-04T12:43:00Z)_
- **collector_scan lane-B** _(at 2026-04-04T13:40:00Z)_
- **collector_scan lane-B** _(at 2026-04-04T14:02:00Z)_
<!-- LANE_B_VALIDATION_END -->

### Lane C findings
<!-- LANE_C_FINDINGS_START -->
- `[LANE-C-2026-03-31-C-001] HDRIOrientationAnalyzer.detectScreenYaw: nil result silently propagates to database, corrupting hdriYawOffset for affected assets`
  - confidence: high
  - paths: `VPStudio/Services/Environment/HDRIOrientationAnalyzer.swift`, `VPStudio/Services/Environment/EnvironmentCatalogManager.swift`
  - why_it_is_a_bug: `detectScreenYaw` can return `nil` when the thumbnail decode fails, the image is too small, or the luminance analysis finds no peak. In `EnvironmentCatalogManager.bootstrapCuratedAssets`, the guard `if let yaw = await HDRIOrientationAnalyzer.detectScreenYaw(at: fileURL)` only saves a yaw when non-nil — but the backfill loop iterates all HDRI assets where `hdriYawOffset == nil`. An asset whose HDRI produces `nil` from the analyzer is silently skipped every bootstrap run with no logging and no fallback. The nil value stays in the database forever.
  - trigger_or_repro: User imports an HDRI that the analyzer cannot process (e.g., corrupt HDR bytes, unusual color temperature, or a panorama whose bright region is not in the +5°–+55° latitude band). On every app launch, `bootstrapCuratedAssets` calls `detectScreenYaw` which returns nil, the guard skips the save, and `hdriYawOffset` remains nil in the database. When `HDRISkyboxEnvironment` renders this asset, it uses `hdriYawOffset = nil` and the cinema screen orientation is unpredictable — likely wrong.
  - impact: Affected HDRI environments always render with an incorrect screen orientation. The user sees the cinema screen facing the wrong direction. No error is surfaced; the problem is invisible until the user manually notices the wrong orientation.
  - evidence: `detectScreenYaw` returns `nil` for: `w <= 1 || h <= 1` (zero-size image), when `CGImageSourceCreateThumbnailAtIndex` fails, or when `smoothed.indices.max` returns nil (no peak found). The backfill loop silently skips nil returns without logging or fallback. `persistImportedAsset` calls `detectScreenYaw` with `hdriYawOffset == nil` path — same silent-skip behavior.

- `[LANE-C-2026-03-31-C-002] AIAssistantManager.configure: hardcoded speculative/future model IDs used as production fallbacks`
  - confidence: high
  - paths: `VPStudio/Services/AI/AIAssistantManager.swift`
  - why_it_is_a_bug: `configure(provider:model:)` uses hardcoded concrete model IDs as defaults when `model` is nil: `"claude-sonnet-4-6"` (does not match any known Anthropic API model ID), `"gpt-5.2"` (GPT-5.2 has never existed as a released model; the current flagship is GPT-4o), `"gemini-2.5-flash"` (real, but pinned to a specific minor version that may drift). If a user has configured an API key but never explicitly set a model, playback starts with the hardcoded fallback — which may be an invalid model ID for that provider, causing every AI request to return a model-not-found error silently.
  - trigger_or_repro: User sets an OpenAI API key in Settings without selecting a specific model. Later, `AIAssistantManager` is asked to make a recommendation. `providers[.openAI]` is configured with `model: "gpt-5.2"` (the hardcoded default). OpenAI API rejects the model ID; the provider throws or returns an error. The user sees no recommendations without understanding why.
  - impact: AI recommendation and analysis features silently fail when users have API keys configured but haven't explicitly picked a model. The hardcoded IDs are plausible but wrong, making diagnosis difficult.
  - evidence: `providers[.openAI] = OpenAIProvider(apiKey: apiKey, model: model ?? defaultModelID ?? "gpt-5.2")` — `"gpt-5.2"` is not a released OpenAI model ID. `providers[.anthropic]` uses `"claude-sonnet-4-6"` which doesn't match Anthropic's actual ID format (`claude-sonnet-4-20250514`). The catalog has the correct canonical IDs (`claude-sonnet-4-20250514`, `gpt-4o`) but the hardcoded fallbacks bypass them.

- `[LANE-C-2026-03-31-C-003] APMPInjector.stereoFormatDescription: CMVideoFormatDescription rebuilt on every frame; width/height cache never invalidates correctly on pixel buffer size changes`
  - confidence: medium
  - paths: `VPStudio/Services/Player/Immersive/APMPInjector.swift`
  - why_it_is_a_bug: `stereoFormatDescription` checks `width == cachedWidth && height == cachedHeight` to decide whether to reuse the cached `CMVideoFormatDescription`. However, the comparison uses the *new* pixel buffer's dimensions each call. If two consecutive frames have different dimensions (e.g., resolution change mid-stream, or an过渡 frame at a different size), the cache is treated as invalid, `CMVideoFormatDescriptionCreate` is called again, and `stereoFormatDesc` is set. But the prior `CMVideoFormatDescription` was created with the old stereo extensions dictionary. More critically: when the dimensions DO change back to a previously cached size (e.g., 1920×1080 → 3840×2160 → back to 1920×1080), the cache fires and returns a format description built for whatever the last size was — but the extensions dictionary used might not match the current frame's actual stereo packing requirements if the mode changed in the interim. Additionally, the cache uses `cachedWidth`/`cachedHeight` which are reset to 0 on any `CMVideoFormatDescriptionCreate` failure — a subsequent frame with a valid buffer but the same failed-size could reuse a partially-initialized format description.
  - trigger_or_repro: A stream switches resolution mid-playback (adaptive bitrate). The pixel buffer size changes from 1920×1080 to 1280×720. The next frame's `stereoFormatDescription` call rebuilds the format description. If this rebuild fails (e.g., `CMVideoFormatDescriptionCreate` returns non-noErr), both caches are reset. The next valid frame at 1920×1080 then creates a format description that may carry stale stereo packing metadata. The display layer receives incorrectly-tagged stereo buffers.
  - impact: Stereo 3D video (side-by-side or over-under) may display incorrectly — wrong eye assignment, wrong packing layout — if resolution changes occur during playback. The bug requires a specific sequence of resolution changes to trigger the bad-cache state.
  - evidence: `if let cached = stereoFormatDesc, width == cachedWidth, height == cachedHeight { return cached }` — cache is keyed by dimensions only, not by `Mode`. If `mode` changes between calls (e.g., user switches SBS→OverUnder), the cached format still has the old mode's packing kind. The extensions dict is static per call but the cache key doesn't include it.

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
  - why_it_is_a_bug: The poll task reads `self?.isIdle` via `await MainActor.run` on every iteration to decide the poll interval. `stop()` sets `isRunning = false`, `isTracking = false`, nil the ARKit session, and cancels the task — but `stop()` can be called from any thread while the `Task.detached` poll loop is running on a background thread. If `stop()` is called between the `await MainActor.run` that reads `isIdle` and the `Task.sleep` at the bottom of the loop, the poll loop still holds a weak reference to `self` and may access `self?.isIdle` after `stop()` has already been called (and potentially after `self` has been deallocated by ARC once the task completes and releases its last strong reference).
  - trigger_or_repro: User exits the immersive space, triggering `HeadTracker.stop()`. `stop()` cancels the poll task and nils `arSession`/`worldTracking`. However, the `Task.detached` closure may have already read `self?.isIdle` and be mid-loop. When it reaches the `Task.sleep`, the task is cancelled and exits — but the `isIdle` read happened on a stale `self`. In practice, the weak reference prevents a true use-after-free, but the `await MainActor.run` call on `self?.isIdle` while `stop()` is concurrently niling the session is a data race.
  - impact: Possible stale head tracking state for one poll cycle after stop is called. The weak reference prevents a true memory safety issue, but the race between `stop()` and the async poll loop creates a window where `isIdle` is read after the tracker has conceptually stopped.
  - evidence: `let currentInterval = await MainActor.run { self?.isIdle == true } ? Self.idlePollInterval : interval` — `self?` is a weak dereference. `stop()` sets `isRunning = false` synchronously but nils the session properties outside the MainActor context. The race is between the MainActor-isolated `self?.isIdle` read and the deinit/nil path.

- `[LANE-C-2026-03-31-C-006] ExternalPlayerRouting.launchURL: URL-encoding the full stream URL before template substitution breaks routing for all external players`
  - confidence: high
  - paths: `VPStudio/Services/Player/Policies/ExternalPlayerRouting.swift`
  - why_it_is_a_bug: `launchURL` encodes the stream URL with `encodeForQueryValue` before substituting it into the template. `encodeForQueryValue` uses `CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))` — this does NOT include `:` or `/`. Consequently, `https://example.com/stream.m3u8` becomes `https:%2F%2Fexample.com%2Fstream.m3u8`. When this encoded string is placed in a URL scheme template (e.g., `infuse://x-callback-url/play?url={url}`), the resulting URL is `infuse://x-callback-url/play?url=https:%2F%2Fexample.com%2Fstream.m3u8`. Many external player apps (Infuse, Skybox, VLC) decode percent-encoded URLs before parsing — but this behavior is app-dependent and not guaranteed. For apps that parse the URL string directly (expecting a literal `://` and `/`), the encoded URL is unparseable and routing silently fails. Additionally, when the template has no placeholder (`!hasPlaceholder`), the code appends the already-encoded URL: `template + encodedURL`, producing a malformed URL with double-encoded segments.
  - trigger_or_repro: User enables Infuse as the external player. They open a stream. `ExternalPlayerRouting.launchURL` is called with an HTTPS stream URL. `encodeForQueryValue` encodes it to `https:%2F%2F...`. The URL scheme template `infuse://x-callback-url/play?url=https:%2F%2F...` is returned. Infuse (or Skybox, VLC, etc.) receives the callback URL and attempts to open it. Because `://` is encoded as `%2F%2F`, the URL parsing fails or the app opens the wrong resource. The user sees no error; playback silently falls back or does nothing.
  - impact: External player routing is broken for all HTTPS/HTTP stream URLs when using any external player (Infuse, Skybox, MoonPlayer, VLC) unless the app happens to URL-decode before using the URL. The feature is silently non-functional for most real-world stream URLs.
  - evidence: `let encodedStreamURL = encodeForQueryValue(streamURL.absoluteString)` — `encodeForQueryValue` only preserves `alphanumerics -._~`. The `:` and `/` in `https://` are encoded to `%2F` and `%2F%2F`. `replacingOccurrences(of: encodedURLPlaceholder, with: encodedStreamURL)` then substitutes this broken string. When `!hasPlaceholder`, `resolved + encodedStreamURL` concatenates the already-encoded URL to a template with no placeholder — the template has no `?` or `&` separator, so the result is `infuse://x-callback-url/playhttps:%2F%2F...` (no separator between path and query).

- `[LANE-C-2026-04-02-C-008] PlayerView refreshes AV subtitle groups in a way that silently overrides active external subtitles`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: `refreshAVMediaOptions(for:)` treats `selectedMediaOption(in: subtitleGroup) == nil` as meaning 'no subtitle is selected' and immediately auto-selects the preferred in-stream subtitle. But this view deliberately sets the AV subtitle selection to `nil` whenever an external subtitle is active, because external subtitles live in `engine.subtitleTracks`, not in AVFoundation. Any later AV media refresh therefore misreads the active external-subtitle state as an empty selection and turns an embedded subtitle back on.
  - trigger_or_repro: Play an AVPlayer-backed stream that exposes an AV legible group, then either let `autoLoadSubtitlesIfEnabled(for:)` download an external subtitle or manually pick one from the subtitle sheet. Both paths call `avPlayer?.currentItem?.select(nil, in: avSubtitleGroup)`, clear `selectedAVSubtitleID`, and activate the external track through `engine.selectSubtitleTrack(0)`. When the scheduled `audioTrackRefreshTask` fires 2 seconds later, or when the user taps `Refresh Track List`, `refreshAVMediaOptions(for:)` sees no selected AV subtitle and auto-selects the preferred in-stream subtitle, overriding the external subtitle the user/app had already chosen.
  - impact: External subtitles can spontaneously stop being the active subtitle source shortly after playback starts or after a track refresh. Users can end up with the wrong subtitle language or with embedded subtitles re-enabled even though they explicitly chose an external subtitle.
  - evidence: In `preparePlayback`, AVPlayer setup schedules `audioTrackRefreshTask = Task { ... await refreshAVMediaOptions(for: player) }` after a 2-second delay. External-subtitle flows (`autoLoadSubtitlesIfEnabled`, `downloadAndSelectSubtitle`, and `selectExternalSubtitle`) all clear the AV subtitle selection with `select(nil, in: avSubtitleGroup)` and then activate the external subtitle via `engine.selectSubtitleTrack(...)`. Inside `refreshAVMediaOptions(for:)`, the subtitle branch does `if let selected = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup) { ... } else { ... if let preferredOption = subtitleGroup.options.first(where: ...) { item.select(preferredOption, in: subtitleGroup) ... } }`, so an active external subtitle is overwritten on the next refresh.

- `[LANE-C-2026-04-02-C-009] Immersive screen-size control posts a notification that PlayerView never handles, so the button does nothing`
  - confidence: high
  - paths: `VPStudio/Views/Immersive/ImmersivePlayerControlsView.swift`, `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: The immersive controls include a dedicated screen-size button (`tv` icon) that posts `.immersiveControlCycleScreenSize`. However, `PlayerView`'s `ImmersiveControlHandlers` modifier does not subscribe to that notification and has no callback parameter for it. With no receiver path, pressing this control cannot trigger any resize behavior.
  - trigger_or_repro: Open immersive playback controls in visionOS and tap the screen-size (`tv`) button in `ImmersivePlayerControlsView.secondaryControlsRow`. The button posts `NotificationCenter.default.post(name: .immersiveControlCycleScreenSize, object: nil)`, but `PlayerView` only handles toggle/play/seek/chapter/rate/subtitles/audio/environment/dismiss notifications. No screen-size event is consumed, so nothing changes.
  - impact: Users see a visible UI control that appears to offer immersive screen resizing, but it is non-functional. This creates a dead control path and prevents in-immersive screen-size adjustments from this surface.
  - evidence: `ImmersivePlayerControlsView` defines: `controlButton(icon: "tv" ...) { NotificationCenter.default.post(name: .immersiveControlCycleScreenSize, object: nil) }`. In `PlayerView`, `ImmersiveControlHandlers` declares callbacks for play/pause, seek, chapters, rate, subtitles, audio, environment switch, and dismiss, and subscribes to matching notifications — but there is no `.immersiveControlCycleScreenSize` subscriber or callback.

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
  - evidence: `CustomEnvironmentView` loads the entity and sets `cinemaScreen = findScreenEntity(in: entity)`. `findScreenEntity(in:)` matches only names containing `screen/display/tv/monitor/cinema/video` and otherwise returns nil after recursive traversal. In `RealityView.update`, video material assignment is guarded by `if let screen = cinemaScreen { ... }` with no fallback branch to create/attach a screen when nil.

- `[LANE-C-2026-04-02-C-013] Custom immersive mode advertises screen-size cycling but routes the control to an explicit no-op`
  - confidence: high
  - paths: `VPStudio/Views/Immersive/ImmersivePlayerControlsView.swift`, `VPStudio/Views/Immersive/CustomEnvironmentView.swift`
  - why_it_is_a_bug: `ImmersivePlayerControlsView` always renders a visible `tv` button labeled "Cycle screen size" and posts `.immersiveControlCycleScreenSize`. In the custom-environment immersive path, `CustomEnvironmentView` subscribes to that notification but intentionally does nothing except reset auto-dismiss timing. There is no resize implementation and no conditional hiding/disablement of the control for custom USDZ spaces.
  - trigger_or_repro: Open any custom immersive environment (`customEnvironment` space), show immersive controls, and tap the `tv` button. `ImmersivePlayerControlsView` posts `.immersiveControlCycleScreenSize`; `CustomEnvironmentView` receives it in `.onReceive` and executes only `scheduleAutoDismiss()` (commented as a no-op). Screen geometry/material never changes.
  - impact: Users in custom immersive scenes get a dead, misleading transport control: repeated taps produce no size change and no feedback. This makes a core playback control appear broken specifically in custom environments.
  - evidence: `ImmersivePlayerControlsView.secondaryControlsRow` defines `controlButton(icon: "tv") { NotificationCenter.default.post(name: .immersiveControlCycleScreenSize, object: nil) }`. `CustomEnvironmentView` handles `.immersiveControlCycleScreenSize` with only `scheduleAutoDismiss()` and an inline comment: `screen cycling is a no-op` because meshes are fixed. No alternative branch updates `cinemaScreen` mesh/transform or hides the control.

- `[LANE-C-2026-04-02-C-014] Subtitle download task can apply an old stream’s subtitle to the newly switched stream`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Player/PlayerView.swift`
  - why_it_is_a_bug: `downloadAndSelectSubtitle(_:streamID:)` validates `streamID == currentStream.id` only once at function entry, then awaits a network download and applies subtitle state unconditionally. `switchToStream(_:)` does not cancel `subtitleDownloadTask`, so a task started on Stream A can finish after the user switches to Stream B and still mutate the active player subtitle state.
  - trigger_or_repro: Open subtitle picker on Stream A and tap a downloadable subtitle. Immediately switch to Stream B before `OpenSubtitlesService.downloadSubtitle(fileId:)` returns. When the old task completes, `downloadAndSelectSubtitle` still runs `avPlayer?.currentItem?.select(nil, in: avSubtitleGroup)`, `engine.loadExternalSubtitles([hydrated])`, and `engine.selectSubtitleTrack(0)` against the current view state, which now belongs to Stream B.
  - impact: After quick stream switches, the active stream can receive subtitles from the previous stream, causing mismatched captions or no usable subtitles until the user manually resets tracks.
  - evidence: `switchToStream(_:)` only changes `currentStream` and schedules catalog refresh; it does not cancel `subtitleDownloadTask`. `scheduleSubtitleDownload` starts `subtitleDownloadTask = Task { await downloadAndSelectSubtitle(subtitle, streamID: streamID) }`. Inside `downloadAndSelectSubtitle`, the stream guard is only before `await service.downloadSubtitle(fileId:)`, and there is no second `guard streamID == currentStream.id` after the await before mutating subtitle selection/state.

- `[LANE-C-2026-04-02-C-015] Player cleanup keeps previous external subtitle state alive, so switched streams can render stale subtitle cues`
  - confidence: high
  - paths: `VPStudio/Views/Windows/Player/PlayerView.swift`, `VPStudio/Services/Player/State/VPPlayerEngine.swift`
  - why_it_is_a_bug: `cleanupPlayback(clearSession:)` tears down AV/KS player objects but never clears `VPPlayerEngine` subtitle state (`subtitleTracks`, `selectedSubtitleTrack`, and parsed external cues). If Stream A had an external subtitle selected, switching to Stream B leaves that state intact. During Stream B playback, periodic time updates still call `engine.updateSubtitleText(at:)`, which reads cues from the old subtitle file and can render Stream A captions over Stream B.
  - trigger_or_repro: Play Stream A, load an external subtitle, and leave it selected. Switch to Stream B where auto subtitle loading is disabled or finds no match. `switchToStream` triggers `preparePlayback`, which calls `cleanupPlayback(clearSession: true)` but does not reset engine subtitle data. Once Stream B starts and `startObservingAVPlayer` updates `engine.currentTime`, `engine.updateSubtitleText(at:)` can emit old cues from Stream A.
  - impact: After stream switches, users can see wrong subtitles from a previous stream and stale subtitle entries in the picker until another subtitle load/off action overwrites state.
  - evidence: `cleanupPlayback(clearSession:)` cancels observers and clears AV-specific groups/options, but does not call `engine.loadExternalSubtitles([])`, does not set `engine.selectedSubtitleTrack = -1`, and does not clear `engine.currentSubtitleText`. `VPPlayerEngine.updateSubtitleText(at:)` renders from `parsedSubtitleCues[selectedSubtitleTrack]` whenever `selectedSubtitleTrack >= 0`, so stale cues remain active across stream teardown/restart.

- `[LANE-C-2026-04-04-C-016] Immersive forward-vector normalization can generate NaNs when head pitch is vertical, breaking control/screen placement`
  - confidence: high
  - paths: `VPStudio/Views/Immersive/CustomEnvironmentView.swift`, `VPStudio/Views/Immersive/HDRISkyboxEnvironment.swift`
  - why_it_is_a_bug: Both immersive views derive a horizontal forward vector with `normalize(SIMD3<Float>(-col2.x, 0, -col2.z))`. When the user looks straight up/down, `col2.x` and `col2.z` can both be ~0, so the vector length is 0. Normalizing a zero vector yields NaN components, which are then written into RealityKit positions/transforms.
  - trigger_or_repro: In immersive playback, tilt head to near-vertical pitch and trigger control-anchor updates (or screen-size cycling in HDRI mode). The code computes `forward = normalize(SIMD3<Float>(-col2.x, 0, -col2.z))` and then uses `target = headPos + forward * ...` (or `screenPos = headPos + forward * dist`). With zero-length input, `forward` becomes NaN and propagates into entity transforms.
  - impact: Controls anchor and/or cinema screen can jump, disappear, or become unstable because RealityKit receives invalid transform values. This is user-visible during extreme but valid head poses.
  - evidence: `CustomEnvironmentView` update block and `HDRISkyboxEnvironment` update/cycleScreenSize paths each call `normalize(SIMD3<Float>(-col2.x, 0, -col2.z))` without a zero-length guard before applying the result to `anchor.position`/screen transforms.
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
