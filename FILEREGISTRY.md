# File Registry

This document tracks all source files in the project, their purposes, and dependencies.

## Modified Files (this fix)

### VPStudio/Services/Downloads/DownloadManager.swift
- **Purpose**: Manages download queue, progress tracking, and file persistence
- **Key Functions**: `enqueueDownload`, `cancelDownload`, `retryDownload`, `notifyDownloadsChanged`
- **Dependencies**: `Database`, `DownloadTask`
- **Last Modified**: Branch fix/swift-warnings-d1
- **Change**: Added `[weak self]` to Task closure in progress update to prevent retain cycle

### VPStudio/ViewModels/Detail/DetailViewModel.swift
- **Purpose**: ViewModel for media detail view, handles AI analysis and metadata
- **Key Functions**: `analyzeWithAI`, `loadDetails`, `buildDetailItem`
- **Dependencies**: `MediaItem`, `TMDBService`, `SimklService`
- **Last Modified**: Branch fix/swift-warnings-d1
- **Change**: Changed `item.genres ?? []` to `item.genres` (genres now non-optional)

### VPStudio/Views/Windows/Player/PlayerView.swift
- **Purpose**: Main video player view with controls and UI
- **Key Functions**: `makeWindowController`, `updateWindowGeometry`
- **Dependencies**: `VPPlayerEngine`, `PlayerSessionRequest`
- **Last Modified**: Branch fix/swift-warnings-d1
- **Change**: Fixed deprecated `coordinateSpace` usage for visionOS 26+ using `window.frame`

### VPStudioTests/BugFixVerificationTests.swift
- **Purpose**: Tests verifying critical bug fixes
- **Key Functions**: Various test suites for numbered fixes
- **Dependencies**: `DownloadManager`, `DetailViewModel`, `MediaItem`
- **Last Modified**: Branch fix/swift-warnings-d1
- **Change**: Added Fix 9 test suite for Swift warnings cleanup
