# FILEREGISTRY.md - VPStudio

This document tracks all source files in the VPStudio project with their purposes, dependencies, and modification history.

## Source Files

### ViewModels

| File | Purpose | Dependencies | Last Modified |
|------|---------|--------------|---------------|
| `VPStudio/ViewModels/Search/SearchViewModel.swift` | Search logic with debouncing, pagination, genre browsing, and AI recommendations | MetadataProvider, DiscoverFilters, MediaPreview | 2026-02-28 |

### Views

| File | Purpose | Dependencies | Last Modified |
|------|---------|--------------|---------------|
| `VPStudio/Views/Windows/Search/SearchView.swift` | Main search UI with search bar, filters, results grid | SearchViewModel, MediaCardView | 2026-02-28 |
| `VPStudio/Views/Components/MediaCardView.swift` | Card component for displaying media previews with poster images | Kingfisher (for image caching) | 2026-02-28 |

### App

| File | Purpose | Dependencies | Last Modified |
|------|---------|--------------|---------------|
| `VPStudio/App/VPStudioApp.swift` | App entry point, scene configuration, Kingfisher cache setup | Kingfisher, AVFoundation | 2026-02-28 |

### Tests

| File | Purpose | Dependencies | Last Modified |
|------|---------|--------------|---------------|
| `VPStudioTests/ViewModels/SearchViewModelTests.swift` | Core search functionality tests | SearchViewModel, Fixtures | 2026-02-28 |
| `VPStudioTests/ViewModels/SearchViewModelPerformanceTests.swift` | Debounce and pagination performance tests | SearchViewModel, Fixtures | 2026-02-28 |
| `VPStudioTests/ViewModels/SearchViewModelDebounceOptimizationTests.swift` | New tests for minimum query length and debounce optimization | SearchViewModel, Fixtures | 2026-02-28 |

---

## Dependencies

### Swift Package Manager

| Package | Version | Purpose |
|---------|---------|---------|
| GRDB.swift | 7.0.0+ | SQLite database wrapper |
| KSPlayer | 2.2.0+ | Video player |
| Kingfisher | 8.0.0+ | Image caching and loading |

---

## Recent Changes (2026-02-28)

### Files Modified
1. `VPStudio/ViewModels/Search/SearchViewModel.swift` - Added minimum query length constant and debounce query tracking
2. `VPStudio/Views/Components/MediaCardView.swift` - Replaced AsyncImage with Kingfisher KFImage
3. `VPStudio/App/VPStudioApp.swift` - Added Kingfisher cache configuration
4. `Package.swift` - Added Kingfisher dependency

### Files Added
1. `VPStudioTests/ViewModels/SearchViewModelDebounceOptimizationTests.swift` - New unit tests
2. `CHANGELOG.md` - Project changelog
3. `FILEREGISTRY.md` - This file
