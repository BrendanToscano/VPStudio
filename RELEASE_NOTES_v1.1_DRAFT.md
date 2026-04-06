# VPStudio v1.1 Draft Release Notes

> Drafted from the current repository / working tree state on `main`.
> This is a planning and documentation draft, not a declaration that the release is ready yet.

## Current app version in Xcode

From `VPStudio.xcodeproj/project.pbxproj`:
- **Marketing version:** `1.0`
- **Build number:** `1`

## Release recommendation

**Recommendation: ship this as `v1.1`, not `v2.0`.**

### Why this looks like 1.1 instead of 2.0
The current work is substantial and meaningful, but it is still best described as:
- major bug fixing
- UX / performance polish
- playback hardening
- settings / navigation cleanup
- sync / cache correctness improvements
- partial UI refresh work

That is a strong **minor release** profile.

### What would make this feel more like 2.0
A `2.0` label would make more sense if VPStudio had most of the following completed and verified together:
- a clearly redesigned Explore / Search experience end-to-end
- the art-backed UI refresh finished across key surfaces
- the remaining sync/import/provider work completed (Trakt polish, IMDb sync, CSV robustness, OpenRouter model UX, etc.)
- the player/menu/resize edge cases fully closed
- a cleaner repo / release state instead of a broad active working tree

Right now, the app looks like a **serious 1.1** rather than a clean `2.0` reset.

## Proposed versioning when ready

When the tracked work is actually complete and verified:
- **Marketing version:** `1.1`
- **Build number:** bump from `1` to at least `2` (or whatever the next release build should be in your release process)

## Headline changes currently present in the working tree

### Playback and player reliability
- Hardened playback startup recovery for stale/expired direct links
- Added same-stream direct-link refresh before giving up
- Added early recovery for obvious startup `401/403/404` failures
- Improved stream identity handling so refreshed links do not collide incorrectly
- Added QA fixture coverage for the debrid-backed playback path

### Search / Explore responsiveness work
- Removed root explore-phase crossfade churn
- Removed results-count animation churn
- Reduced spring animation noise in search/filter interactions
- Reduced visionOS hover-effect stacking
- Changed filters to a draft/apply flow instead of live-firing repeated re-queries
- Isolated parts of the Search results feed to reduce broad invalidation
- Improved on-demand genre loading behavior and deduped duplicate in-flight genre requests

### Library card loading and metadata quality
- Added alias-aware cache resolution for library items
- Added background metadata hydration for stub entries missing artwork
- Removed misleading “infinite loading” behavior when no poster URL exists

### Vision Pro and player UI work
- Increased Vision Pro bottom-bar and sidebar control sizing
- Added aspect-ratio quick actions and a Freeflow Resize mode
- Continued alignment work toward the older player resize behavior

### Settings and sync improvements
- Reorganized Settings IA into user-aligned categories: Connect, Watch, Discover, Library, About
- Added Library and Downloads as explicit settings destinations (previously required separate navigation)
- Improved Trakt sync so local library/history/personalization state refreshes properly after sync

### Indexer and parsing fixes
- Added Stremio / Torrentio-style hash extraction fallback when `infoHash` is only present in URLs

## User-visible changes you are most likely to notice
- Library cards populate more reliably
- Vision Pro side/bottom controls are larger and easier to hit
- Search filter interactions should feel significantly calmer and snappier (animation storm reduced)
- Freeflow resize / aspect controls now exist in the player
- Trakt sync should reflect locally more reliably after completion
- Settings is now organized into Connect, Watch, Discover, Library, and About — should feel more intuitive

## Important remaining work before calling 1.1 “done"

These are still active blockers or should at least be reviewed before a release label bump:
- Search bar first-focus / first-input lag (separate from the animation lag addressed in #3)
- Player resize still does not fully match the old VPStudio behavior
- Top-right player stream/aspect menu glitches during playback
- Genre/mood cards still do not have the intended image-generated UI treatment
- Embedded torrent audio/subtitle default-selection work is still open
- Trakt Client ID paste affordance is still open
- OpenRouter model-provider integration work is still open
- IMDb sync is still open
- CSV import robustness / AI header matching is still open

## Current tracker state snapshot

### Fixed
- `#1` Playback startup network-error recovery
- `#2` Indexer URL-hash fallback
- `#4` Library card loading / metadata hydration
- `#6` Vision Pro side and bottom bar sizing
- `#8` Freeflow resize / aspect toggle
- `#11` Settings IA reorganization
- `#12` Trakt sync local refresh

### In progress
- `#5` Player resize parity with the old VPStudio behavior
- `#9` Art-backed search/menu imagery
- Detail view redesigned: episodes now shown as a horizontal scrollable row of thumbnail cards (still frames from TMDB), with watch-state overlay (checkmark for completed, progress bar for in-progress), episode info chip on each card. Season tabs redesigned with episode count labels. Hero section updated with top-right utility cluster (Share, List, Cast), compact metadata row (year, runtime, IMDb rating), inline favorite heart icon, and compact synopsis.

### Fixed pending QA
- `#10` On-demand genre/mood loading
- `#3` Explore/Search lag — animation storm reduced (pending real-use validation)
- `#7` Torrent embedded audio/subtitle tracks — auto-select user preferred languages; added delayed retry (2s) for late-loading track detection; added refresh button and toolbar to audio picker sheet
- `#13` Trakt Client ID paste button
- `#14` OpenRouter AI provider added with 6 known models
- `#15` IMDb CSV import as a first-class Settings destination (Connect category)
- `#16` CSV import now shows a preview before committing; AI-assisted header analysis available

### Open
- `#7`, `#13`, `#14`, `#15`, `#16`, `#17`, `#18`

## Bottom line

If the currently landed work stabilizes and the remaining blockers are closed with QA evidence, this should be released as:
- **VPStudio 1.1**

My recommendation right now is:
- **Do not call this 2.0 yet.**
- Keep `2.0` in reserve for a bigger, cleaner, more visibly transformed release.
