# VPStudio User Manual

This manual explains the day-to-day use of VPStudio on Vision Pro.

## 0) Before You Launch

If you have not downloaded and built the app yet, complete the Setup section in the project README first:

- `README.md` -> `Setup`

Minimum requirements:

- Apple Silicon Mac
- Xcode 26.1+ with visionOS simulator runtime
- Internet connection for first package resolution

Quick install summary:

1. Download ZIP from GitHub and unzip.
2. Open `VPStudio.xcodeproj` in Xcode.
3. Select `VPStudio` scheme and `Apple Vision Pro Simulator`.
4. Press `Cmd+R`.

## 1) Quick Start (First 5 Minutes)

1. Launch VPStudio.
2. In the first-run prompt, choose:
   - `Explore Now` for immediate use, or
   - `Run Setup` to configure services now.
3. Open `Discover` or `Search`.
4. Add an item to your Library, Watchlist, or Favorites.
5. Open an item and start playback.

Optional setup for full streaming features:

1. Open `Settings` -> `Quick Actions` -> `Run Setup Wizard`.
2. Add TMDB and Debrid credentials.
3. Configure optional Trakt/Simkl/AI/Subtitles integrations.

## 2) Main Navigation

VPStudio is organized into these main areas:

- `Discover`: trending content and curated recommendations.
- `Search`: title search and browsing results.
- `Library`: your saved content and imports.
- `Downloads`: downloaded items and progress state.
- `Environments` (visionOS): immersive environment controls.
- `Settings`: integrations, sync, playback, and app configuration.

## 3) Importing Content

1. Go to `Library`.
2. Select the import action.
3. Choose your file or folder source (for example CSV export files).
4. Confirm import target/folder behavior if prompted.
5. Wait for completion, then refresh the view if needed.

If expected items do not appear:

1. Check file format and column structure.
2. Re-run import on a small sample file first.
3. Use refresh/reconciliation actions in Library to normalize titles.

## 4) Library Management

Use Library to organize and maintain your media:

- Create and manage folders/subfolders.
- Sort and filter content.
- Open item details.
- Remove items you no longer need.

Tip: keep folder names short and consistent so imports map cleanly.

## 5) Watchlist, Favorites, and History

- `Watchlist`: items you plan to watch later.
- `Favorites`: quick-access list for priority titles.
- `History`: recently played items and resume points.

Recommended flow:

1. Save from Discover/Search to Watchlist.
2. Promote important titles to Favorites.
3. Use History to continue playback from where you left off.

## 6) Search

1. Open `Search`.
2. Enter title keywords.
3. Review matches.
4. Add results directly to Library/Watchlist/Favorites.

If search feels slow, refine keywords and avoid very broad single-word queries.

## 7) Player Basics

During playback you can:

- Play/pause
- Seek forward/back
- Adjust volume
- Select subtitles/audio when available
- Resume from saved progress

If playback fails on a stream:

1. Back out and re-open the item.
2. Try an alternate source/stream option.
3. Check provider credentials in Settings.

## 8) Settings and Integrations

Common configuration areas:

- TMDB metadata key
- Debrid provider tokens
- Trakt/Simkl sync
- AI provider preferences (optional)
- Subtitle provider setup
- Playback behavior

If onboarding needs to be repeated, use:

- `Settings` -> `Quick Actions` -> `Run Setup Wizard`

## 9) Sync

When sync is configured:

- Watch progress and list changes can be mirrored across services.
- Token/auth expiration can stop sync until reconnected.

If sync appears stale:

1. Re-check account connection status.
2. Re-authenticate affected service.
3. Trigger a manual sync/refresh action.

## 10) Troubleshooting

### Import completed but nothing appears

1. Confirm the target folder/view is correct.
2. Run refresh/reconciliation in Library.
3. Re-import a known-good sample file to isolate format issues.

### Metadata missing

1. Verify TMDB key.
2. Confirm network access.
3. Re-open the affected title.

### App performance drops

1. Reduce simultaneous imports/downloads.
2. Restart VPStudio.
3. Re-test with a smaller content set.

### Setup loop or blank startup states

1. Use `Explore Now` to bypass setup and confirm the app opens normally.
2. Re-run setup later from Settings.
3. If needed, relaunch app.

## 11) FAQ

### Do I need all integrations to use VPStudio?
No. You can explore the app without any integrations and connect services later.

### Can I change settings after onboarding?
Yes. Everything can be updated in `Settings`.

### Does import overwrite my existing library?
Import behavior depends on matching and dedupe rules; review Library after import and run refresh/reconciliation when needed.
