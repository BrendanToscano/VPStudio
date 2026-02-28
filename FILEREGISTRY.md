# File Registry

This document tracks all source files in the project, their purposes, and dependencies.

## Modified Files (this fix)

### VPStudio/ViewModels/Detail/DetailViewModel.swift
- **Purpose**: ViewModel for media detail view, handles AI analysis and metadata
- **Key Functions**: `searchForTorrents`, `buildDetailItem`, `startCacheEnrichment`
- **Dependencies**: `MediaItem`, `TMDBService`, `IndexerManager`, `TorrentSearch`
- **Last Modified**: Branch fix/retain-cycles-d2
- **Change**: Added [weak self] to searchTask Task closure, added guard against nil

### VPStudio/ViewModels/Search/SearchViewModel.swift
- **Purpose**: ViewModel for search functionality
- **Key Functions**: `loadRecentSearches`, `performSearch`
- **Dependencies**: `SettingsManager`, `IndexerManager`, `Database`
- **Last Modified**: Branch fix/retain-cycles-d2
- **Change**: Added [weak self] to loadRecentSearches Task closure

### VPStudioTests/BugFixVerificationTests.swift
- **Purpose**: Tests verifying critical bug fixes
- **Key Functions**: Various test suites for numbered fixes
- **Dependencies**: `DetailViewModel`, `SearchViewModel`
- **Last Modified**: Branch fix/retain-cycles-d2
- **Change**: Added Fix 10 test suite for retain cycles cleanup
