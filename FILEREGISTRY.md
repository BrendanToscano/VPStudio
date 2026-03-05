# File Registry

This document tracks all source files in the project, their purposes, and dependencies.

## Modified Files (this fix)

### VPStudio/Services/Debrid/RealDebridService.swift
- **Purpose**: Real-Debrid API client for torrent caching
- **Key Functions**: `checkCache`, `isValidHexHash`
- **Dependencies**: `NSRegularExpression`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Lazy regex pattern to avoid force unwrap

### VPStudio/Services/Metadata/MetadataProvider.swift
- **Purpose**: Provides metadata filtering and discovery
- **Key Functions**: `dateString`, `DiscoverFilters`
- **Dependencies**: `Calendar`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Guard against nil date

### VPStudio/Services/Player/Immersive/APMPInjector.swift
- **Purpose**: Injects APM (Audio Processing Module) for immersive audio
- **Key Functions**: `start`, `stop`
- **Dependencies**: `CADisplayLink`, `AVPlayer`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Strong reference to displayLinkTarget

### VPStudio/Services/Player/Policies/PlayerLoadingTips.swift
- **Purpose**: Rotates loading tips during player startup
- **Key Functions**: `startRotation`, `advance`
- **Dependencies**: `Task`, `MainActor`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Interval capture for Swift 6

### VPStudio/Views/Windows/ContentView.swift
- **Purpose**: Main content view with tabs
- **Key Functions**: `scheduleEnvironmentLoad`
- **Dependencies**: `NotificationCenter`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Added [weak self] to onReceive

### VPStudio/Views/Windows/Detail/DetailView.swift
- **Purpose**: Media detail view
- **Key Functions**: `reloadDetailForLatestTMDBKey`, `reloadLibraryState`
- **Dependencies**: `NotificationCenter`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Added [weak self] to multiple onReceive

### VPStudio/Views/Windows/Library/LibraryView.swift
- **Purpose**: Library grid view
- **Key Functions**: `scheduleReload`, `loadUserRatings`
- **Dependencies**: `NotificationCenter`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Added [weak self] to onReceive

### VPStudio/Views/Windows/Search/SearchView.swift
- **Purpose**: Search interface
- **Key Functions**: `loadUserRatings`, `reloadTMDBConfigurationAndSearch`
- **Dependencies**: `NotificationCenter`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Added [weak self] to onReceive

### VPStudio/Views/Windows/Settings/Destinations/AISettingsView.swift
- **Purpose**: AI provider settings
- **Key Functions**: `loadFeedbackState`
- **Dependencies**: `NotificationCenter`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Added [weak self] to onReceive

### VPStudio/Views/Windows/Settings/Destinations/EnvironmentSettingsView.swift
- **Purpose**: Environment settings
- **Key Functions**: `scheduleAssetLoad`
- **Dependencies**: `NotificationCenter`
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Added [weak self] to onReceive

### VPStudioTests/BugFixVerificationTests.swift
- **Purpose**: Tests verifying bug fixes
- **Key Functions**: Test suites
- **Dependencies**: Various services
- **Last Modified**: Branch fix/player-cleanup-issues
- **Change**: Added Fix 13 test suite
