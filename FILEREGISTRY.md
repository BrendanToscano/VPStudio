# File Registry

This document tracks all source files in the project, their purposes, and dependencies.

## Modified Files (this fix)

### VPStudio/Services/Metadata/TMDBService.swift
- **Purpose**: TMDB API client for movie/TV metadata
- **Key Functions**: `searchMovies`, `getMovieDetails`, `fetchEpisode`
- **Dependencies**: `URLSession`, `JSONDecoder`
- **Last Modified**: Branch fix/metadata-concurrency
- **Change**: TMDBError now conforms to Sendable for Swift 6

### VPStudio/Services/Downloads/DownloadManager.swift
- **Purpose**: Manages download queue and progress
- **Key Functions**: `processDownload`, `updateDownloadTaskProgress`
- **Dependencies**: `Database`, `DownloadTask`
- **Last Modified**: Branch fix/metadata-concurrency
- **Change**: Removed nested Task, direct await

### VPStudio/Services/Player/Immersive/HeadTracker.swift
- **Purpose**: Tracks head position for immersive mode
- **Key Functions**: `updateHeadTransform`
- **Dependencies**: `MainActor`, `simd_float4x4`
- **Last Modified**: Branch fix/metadata-concurrency
- **Change**: Captured values before MainActor.run

### VPStudio/ViewModels/Detail/DetailViewModel.swift
- **Purpose**: ViewModel for media detail view
- **Key Functions**: `buildDetailItem`
- **Dependencies**: `MediaItem`, `TMDBService`
- **Last Modified**: Branch fix/metadata-concurrency
- **Change**: Non-optional genres

### VPStudio/Views/Windows/Player/PlayerView.swift
- **Purpose**: Main video player view
- **Key Functions**: `updateWindowGeometry`
- **Dependencies**: `VPPlayerEngine`
- **Last Modified**: Branch fix/metadata-concurrency
- **Change**: coordinateSpace deprecation fix

### VPStudioTests/BugFixVerificationTests.swift
- **Purpose**: Tests verifying bug fixes
- **Key Functions**: Test suites
- **Dependencies**: `TMDBError`
- **Last Modified**: Branch fix/metadata-concurrency
- **Change**: Added Fix 12 test suite
