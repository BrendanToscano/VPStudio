# File Registry

This document tracks the purpose and dependencies of key files in VPStudio.

## Views

### Library
| File | Purpose | Dependencies |
|------|---------|--------------|
| `VPStudio/Views/Windows/Library/LibraryView.swift` | Main library view displaying user's watchlist, favorites, and history | DatabaseManager, SettingsManager, TMDBService |

### Discover
| File | Purpose | Dependencies |
|------|---------|--------------|
| `VPStudio/Views/Windows/Discover/DiscoverView.swift` | Home/Discover view with Continue Watching, Trending, Curated sections | DiscoverViewModel |

### Components
| File | Purpose | Dependencies |
|------|---------|--------------|
| `VPStudio/Views/Components/MediaCardView.swift` | Card component for displaying media posters and metadata | MediaPreview |

## ViewModels

| File | Purpose | Dependencies |
|------|---------|--------------|
| `VPStudio/ViewModels/Discover/DiscoverViewModel.swift` | Manages Discover/Home page data including Continue Watching | DatabaseManager, MetadataProvider |

## Models

| File | Purpose | Dependencies |
|------|---------|--------------|
| `VPStudio/Models/MediaItem.swift` | Media item model with poster/backdrop URL construction | None (pure model) |
| `VPStudio/Models/WatchHistory.swift` | Watch history tracking with progress percentage | None (pure model) |

## Tests

| File | Purpose |
|------|---------|
| `VPStudioTests/ViewModels/DiscoverContinueWatchingTests.swift` | Tests for Continue Watching functionality |
| `VPStudioTests/ModelTests/MediaItemImageURLTests.swift` | Tests for image URL construction |

---

## Recent Changes (Agent 6 - Library Images + Continue Watching)

### Modified Files
1. `VPStudio/Views/Windows/Library/LibraryView.swift` - Added `fetchMissingMetadata` function
2. `VPStudio/ViewModels/Discover/DiscoverViewModel.swift` - Changed threshold from 2% to 5%

### Added Files
1. `VPStudioTests/ModelTests/MediaItemImageURLTests.swift` - Image URL tests
2. `CHANGELOG.md` - Change log
3. `FILEREGISTRY.md` - This file
