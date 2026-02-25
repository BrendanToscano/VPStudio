# VPStudio v1.1 Roadmap

This roadmap is a working list of what we should ship next, what needs cleanup, and what we can defer.

## 1) Ratings & Sync Hub (TraktRater-style)

Goal: pull ratings from multiple services into one taste profile, with Trakt as the main sync target.

### High Priority

- [ ] TMDb rating import
  Method: OAuth user auth + `/account/{id}/rated/movies` and `/account/{id}/rated/tv`.
  Notes: We already use TMDb for metadata, so this is an extension of existing work.

- [ ] Letterboxd import (CSV)
  Method: Parse `Date,Name,Year,Letterboxd URI,Rating`.
  Notes: Map 0.5-5.0 stars to 1-10.

- [ ] Unified import screen
  Method: One settings page with:
  - Import from IMDb (CSV)
  - Import from TMDb (connect)
  - Import from Letterboxd (CSV)

### Medium Priority

- [ ] Rating export (CSV/JSON)
  Export local `TasteEvent` ratings back out as CSV or JSON.

- [ ] Trakt live scrobbling wiring
  Connect `startScrobble`, `pauseScrobble`, and `stopScrobble` to real playback events in `PlayerView`.

- [ ] TVDb import
  Account/API integration for users who need it.

### Low Priority (Skip in v1.1 unless requested)

- [ ] Criticker (web scrape)
- [ ] Listal (XML export)
- [ ] Flixster (CSV)
- [ ] iCheckMovies (CSV)
- [ ] MovieLens (CSV)

### Implementation Notes

- Normalize all imports to `TasteEvent(eventType: .rated)`.
- Rating mapping:
  - Letterboxd 0.5-5.0 -> 1-10
  - TMDb 1-10 -> 1-10
  - IMDb 1-10 -> 1-10
- Push ratings through existing `TraktSyncOrchestrator`.
- Deduplicate by IMDb ID.

---

## 2) Gemini AI Provider

Add Google Gemini as a fourth provider (alongside Anthropic, OpenAI, and Ollama).

### Build Tasks

- [ ] Add `.gemini` to `AIProviderKind` (`Models/AIAssistantModels.swift`)
- [ ] Add `GeminiProvider` (`Services/AI/GeminiProvider.swift`)
- [ ] Add Gemini model presets to `AIModelCatalog`
- [ ] Add dynamic model fetch for Gemini models (`AIModelFetcher`)
- [ ] Wire `.gemini` in `AIAssistantManager.configure()`
- [ ] Add Gemini settings UI (`AISettingsView`): API key + model picker
- [ ] Add Gemini to default provider picker
- [ ] Register Gemini in `AppState.configureAIProviders()`
- [ ] Add `GeminiProviderTests`

### API Notes

- Endpoint pattern: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Auth: API key via `?key=` query parameter
- Parse: `candidates[0].content.parts[0].text`
- Usage: `usageMetadata.promptTokenCount` + `usageMetadata.candidatesTokenCount`
- Handle 429 `RESOURCE_EXHAUSTED` as `AIError.rateLimited`
- Default model target: `gemini-2.5-flash`

---

## 3) Stability & Bugs

### Major: Environments / Immersive Space

- [ ] Blank environment when asset backing files are missing
- [ ] Environment switch flicker (brief old frame / black flash)
- [ ] Cold-launch immersive open can fail silently (add retry/backoff)
- [ ] 3D environment previews still use placeholder cards
- [ ] Stabilize cinema screen anchoring to head pose in immersive mode (plane alignment consistency)
- [ ] Prevent `WorldTrackingProvider` simulator crashes with exhaustive anchor/state guards
- [ ] Migrate deprecated APMP display-layer paths to supported visionOS APIs where possible

### Major: Memory / Lifecycle

- [ ] Retain cycle audit across Task closures + observers
- [ ] Add bounded image cache strategy (LRU or image pipeline)
- [ ] Ensure full player resource cleanup on player close
- [ ] Audit background task cancellation lifecycle
- [ ] Release old HDRI textures on environment switch

### Minor Bugs (User-Reported)

- [ ] Search initial over-fetch causes lag
- [ ] Library titles sometimes load late / blank, or require restart
- [ ] Onboarding text-entry lag + TMDb secret save issue
- [ ] Vision Pro onboarding paste buttons are too small
- [ ] Missing paste button for Trakt Client ID
- [ ] Onboarding can show error + blank Discover before wizard starts
- [ ] Remove redundant top-right 3-dot button in player
- [ ] Downloads menu shifts position too often during progress

### Untested Areas (Need Full Pass)

- [ ] Indexer add/edit/remove flow
- [ ] Subtitle settings + OpenSubtitles end-to-end
- [ ] Offline mode playback + fallback behavior

### Build Warnings Backlog

- [ ] `DownloadManager.swift:182` no async work inside `await`
- [ ] `HeadTracker.swift` Swift 6 capture warnings (`self` / `mat`)
- [ ] `DetailViewModel.swift:596` non-optional left side of `??`
- [ ] `PlayerView.swift` deprecated `coordinateSpace` (visionOS 26)
- [ ] FFmpegKit `pkg-config` / `sdl2` warning

---

## 4) Feature Backlog (v1.1)

### Core

- [ ] iCloud sync (CoreData+CloudKit or GRDB custom sync)
- [ ] Auto-load AI curated recommendations on Discover (toggle)
- [ ] AI customization settings:
  - user-specific prompt profile
  - genre interests
  - weighting controls for recommendation behavior
- [ ] Rating scale UI redesign (1-10)
- [ ] Download button state flow polish
- [ ] Organize downloads by folder and series seasons
- [ ] Series episode navigation improvements in detail flow

### Player Reliability & Controls

- [ ] Tune KSPlayer/KSOptions for high-demand streams (4K, AV1, DV/HDR10+, Atmos/TrueHD/DTS-HDMA)
- [ ] Improve stream failover routing quality (`PlayerSessionRouting.sessionStreams`)
- [ ] Tighten player ready timeout/start conditions to reduce blank-screen starts
- [ ] Add advanced transport controls (chapters, audio track switching, playback speed)
- [ ] Improve subtitle render timing accuracy for external and embedded tracks

### Download / Offline Improvements

- [ ] Pause and resume downloads (persist `resumeData`)
- [ ] Queue management with configurable concurrency
- [ ] Offline playback badge + direct local playback route
- [ ] Storage usage dashboard + bulk delete
- [ ] Auto-delete watched downloads (optional)

### Subtitle Improvements

- [ ] Auto-fetch subtitles on playback (preferred language)
- [ ] Multi-language fallback list
- [ ] Subtitle appearance customization
- [ ] Embedded subtitle track picker
- [ ] Manual subtitle sync offset control

### Performance

- [ ] Discover lazy/staggered data loading
- [ ] TMDb response caching with TTL
- [ ] Adaptive search debounce tuning
- [ ] Faster player startup path
- [ ] Add DB composite indexes for hot queries

### UI/UX Polish

- [ ] Discover page UI improvements (clearer hierarchy/scanability)
- [ ] AI curated section redesign: banner + text, not block cards
- [ ] Touch-target spacing pass for easier Vision Pro use:
  - bottom menu bar
  - Library action row (Import/Refresh/History)
- [ ] Library UI improvements for folder hierarchy and sub-folder labels
- [ ] Standardize loading surfaces on `InlineLoadingStatusView` / `LoadingOverlay` across all flows
- [ ] Make error messaging consistently actionable and user-readable (recovery-oriented copy)
- [ ] Fix visionOS list and `NavigationSplitView` edge-case jank
- [ ] Refine sidebar transitions and deep-link routing behavior
- [ ] Add subtle micro-interactions for card selection and sheet transitions
- [ ] Apply consistent spacing rhythm (cards, sections, inter-control gaps) across main screens
- [ ] Ensure text truncation behaves cleanly in compact window sizes
- [ ] Upgrade skeleton/placeholder shimmer behavior for loading states
- [ ] Haptic feedback on key interactions
- [ ] Better empty-state visuals + actions
- [ ] Keyboard shortcuts (macOS)
- [ ] Pull-to-refresh on Discover
- [ ] Detail <-> Player transition polish
- [ ] Onboarding improvements (AI config + optional taste import)
- [ ] Accessibility audit (labels, hints, dynamic type)
