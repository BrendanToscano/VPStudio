# File Registry

This document tracks all source files in the project, their purposes, and dependencies.

## Modified Files (this fix)

### VPStudio/Services/Downloads/DownloadManager.swift
- **Purpose**: Manages download queue, progress tracking, and file persistence
- **Key Functions**: `startJob`, `processDownload`, `notifyDownloadsChanged`
- **Dependencies**: `Database`, `DownloadTask`
- **Last Modified**: Branch fix/build-warnings
- **Change**: Removed nested Task, added [weak self] to startJob

### VPStudio/Services/Player/Immersive/HeadTracker.swift
- **Purpose**: Tracks head position for immersive mode
- **Key Functions**: `updateHeadTransform`, `startTracking`
- **Dependencies**: `simd_float4x4`, `MainActor`
- **Last Modified**: Branch fix/build-warnings
- **Change**: Captured values before MainActor.run for Swift 6 safety

### VPStudio/ViewModels/Detail/DetailViewModel.swift
- **Purpose**: ViewModel for media detail view
- **Key Functions**: `searchForTorrents`, `buildDetailItem`
- **Dependencies**: `MediaItem`, `TMDBService`, `IndexerManager`
- **Last Modified**: Branch fix/build-warnings
- **Change**: Added [weak self] to searchTask, non-optional genres

### VPStudio/ViewModels/Search/SearchViewModel.swift
- **Purpose**: ViewModel for search functionality
- **Key Functions**: `loadRecentSearches`, `saveRecentSearches`
- **Dependencies**: `SettingsManager`, `IndexerManager`
- **Last Modified**: Branch fix/build-warnings
- **Change**: Added [weak self] to both Task closures

### VPStudio/Views/Windows/Player/PlayerView.swift
- **Purpose**: Main video player view
- **Key Functions**: `updateWindowGeometry`
- **Dependencies**: `VPPlayerEngine`, `windowScene`
- **Last Modified**: Branch fix/build-warnings
- **Change**: Fixed coordinateSpace deprecation using window.frame

### VPStudioTests/BugFixVerificationTests.swift
- **Purpose**: Tests verifying critical bug fixes
- **Key Functions**: Various test suites
- **Dependencies**: `SearchViewModel`, `HeadTracker`, `MediaItem`
- **Last Modified**: Branch fix/build-warnings
- **Change**: Added Fix 11 test suite
