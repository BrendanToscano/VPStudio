# File Registry

This document tracks all source files in the project, their purposes, and dependencies.

## Modified Files (this fix)

### VPStudio/Views/Immersive/HDRISkyboxEnvironment.swift
- **Purpose**: HDRI skybox environment rendering
- **Key Functions**: `loadHDRImage`
- **Dependencies**: `CGImageSource`, `RealityView`
- **Last Modified**: Branch fix/environment-robustness
- **Change**: Added CGImageSourceGetCount validation

### VPStudio/Views/Windows/Discover/EnvironmentPreviewRow.swift
- **Purpose**: Environment preview cards
- **Key Functions**: `loadHDRThumbnail`
- **Dependencies**: `CGImageSource`
- **Last Modified**: Branch fix/environment-robustness
- **Change**: Added CGImageSourceGetCount validation

### VPStudio/Views/Windows/Player/PlayerView.swift
- **Purpose**: Main video player view
- **Key Functions**: `updateWindowGeometry`
- **Dependencies**: `VPPlayerEngine`
- **Last Modified**: Branch fix/environment-robustness
- **Change**: Fixed coordinateSpace deprecation

### VPStudio/Services/AI/GeminiProvider.swift
- **Purpose**: Google Gemini API provider
- **Key Functions**: `complete`
- **Dependencies**: `URLSession`
- **Last Modified**: Branch fix/environment-robustness
- **Change**: Added Gemini support

### VPStudio/ViewModels/Detail/DetailViewModel.swift
- **Purpose**: Media detail view model
- **Key Functions**: `searchForTorrents`
- **Dependencies**: `MediaItem`
- **Last Modified**: Branch fix/environment-robustness
- **Change**: Added [weak self] to Task

### VPStudio/ViewModels/Search/SearchViewModel.swift
- **Purpose**: Search view model
- **Key Functions**: `loadRecentSearches`, `saveRecentSearches`
- **Dependencies**: `SettingsManager`
- **Last Modified**: Branch fix/environment-robustness
- **Change**: Added [weak self] to Tasks

### VPStudioTests/BugFixVerificationTests.swift
- **Purpose**: Tests verifying bug fixes
- **Key Functions**: Test suites
- **Dependencies**: Various
- **Last Modified**: Branch fix/environment-robustness
- **Change**: Added Fix 15 test suite
