# File Registry

This document tracks the purpose and dependencies of key files in VPStudio.

## Views

### Player
| File | Purpose | Dependencies |
|------|---------|--------------|
| `VPStudio/Views/Windows/Player/PlayerView.swift` | Main player view with audio/subtitle track selection | VPPlayerEngine, AVPlayer, KSPlayer |

## Tests

| File | Purpose |
|------|---------|
| `VPStudioTests/Player/PlayerAudioTrackTests.swift` | Tests for audio track loading and selection in VPPlayerEngine |

---

## Recent Changes (Agent 4 - Player Audio Tracks)

### Modified Files
1. `VPStudio/Views/Windows/Player/PlayerView.swift` - Fixed audio track loading to first load asset tracks before accessing media selection groups, added loadTracksFromAsset for KSPlayer support

### Added Files
1. `VPStudioTests/Player/PlayerAudioTrackTests.swift` - Unit tests for audio track loading
2. `CHANGELOG.md` - Change log
3. `FILEREGISTRY.md` - This file
