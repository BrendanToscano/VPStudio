# FILEREGISTRY.md - VPStudio

This file documents the purpose and structure of key files in the VPStudio project.

---

## ViewModels

### VPStudio/ViewModels/Search/SearchViewModel.swift
- **Purpose**: Main view model for the Explore/Search functionality
- **Key Functions**:
  - `search()` - Executes text search with client-side filtering
  - `performFilteredSearch()` - Applies sorting and year preset filtering client-side
  - `applySorting()` - Client-side sorting by rating, title, or release date
  - `selectMoodCard()` - Handles New Releases and Future Releases mood cards
  - `browseGenre()` - Genre browsing with date limiting
  - `loadMoreSearch()` - Now applies client-side filtering to paginated results
- **Dependencies**: MetadataProvider, DiscoverFilters
- **Modified**: 2026-02-28 - Added client-side filtering for search results

### VPStudio/ViewModels/Discover/DiscoverViewModel.swift
- **Purpose**: View model for the Discover/Home screen
- **Key Properties**:
  - `trendingMovies`, `trendingShows` - Trending content
  - `popularMovies`, `topRatedMovies`, `nowPlayingMovies` - Category content
  - `newReleaseMovies` - Movies from last 90 days (NEW)
  - `upcomingMovies` - Movies with future release dates (NEW)
- **Dependencies**: MetadataProvider, DatabaseManager, DiscoverFilters
- **Modified**: 2026-02-28 - Added New Releases and Coming Soon sections

---

## Views

### VPStudio/Views/Windows/Discover/DiscoverView.swift
- **Purpose**: Main Discover/Home screen UI
- **Key Sections**:
  - Hero carousel with featured backdrops
  - Continue Watching
  - AI Curated recommendations
  - Trending Movies/TV Shows
  - Popular, Top Rated, Now Playing
  - **New**: New Releases (flame.fill icon) - last 90 days up to today
  - **New**: Coming Soon (calendar.badge.clock icon) - future releases
- **Modified**: 2026-02-28 - Added New Releases and Coming Soon rows

### VPStudio/Views/Windows/Search/SearchView.swift
- **Purpose**: Explore/Search screen with genre grid and results
- **Key Components**:
  - Search bar with debounced input
  - Type filter (All/Movies/TV)
  - Inline filter bar (year presets, languages, genre, sort)
  - Explore genre grid with mood cards
  - Results grid with pagination
- **Modified**: 2026-02-28 - Filter bar now shows active filters correctly

### VPStudio/Views/Windows/Search/ExploreFilterSheet.swift
- **Purpose**: Modal sheet for advanced filter configuration
- **Filters**: Genre, Sort, Year, Languages (multi-select)
- **Dependencies**: SearchViewModel, DiscoverFilters.SortOption

---

## Models

### VPStudio/Models/ExploreGenreCatalog.swift
- **Purpose**: Catalog of mood cards for genre browsing
- **Key Types**:
  - `ExploreMoodCard` - Genre/mood card model
  - Special cards: `isNewReleases` (id: -1), `isFutureReleases` (id: -2)
- **Modified**: 2026-02-28 - No changes (existing structure supports New/Future releases)

---

## Services

### VPStudio/Services/Metadata/MetadataProvider.swift
- **Purpose**: Protocol defining metadata service capabilities
- **Key Types**:
  - `DiscoverFilters` - Filter configuration for discover API
  - `SortOption` - Sorting options (popularity, rating, release date, title)
  - Date helpers: `todayString()`, `dateString(daysFromNow:)`
- **Modified**: 2026-02-28 - Added `query` parameter to DiscoverFilters

### VPStudio/Services/Metadata/TMDBService.swift
- **Purpose**: TMDB API implementation
- **Endpoints Used**:
  - `/search/movie`, `/search/tv` - Text search
  - `/discover/movie`, `/discover/tv` - Filtered discovery
  - `/movie/upcoming` - Upcoming movies
  - `/trending/*`, `/movie/*`, `/tv/*` - Various categories

---

## Tests

### VPStudioTests/ViewModels/SearchFilterDateTests.swift (NEW)
- **Purpose**: Unit tests for date and filter boundary logic
- **Coverage**:
  - Date formatting functions
  - Year range preset containment
  - Mood card date range verification
  - DiscoverFilters parameter tests

### VPStudioTests/ViewModels/SearchViewModelClientSideFilterTests.swift (NEW)
- **Purpose**: Unit tests for client-side filtering in SearchViewModel
- **Coverage**:
  - Client-side sorting (rating, title, release date)
  - Year range preset filtering on search
  - Pagination with filters applied
  - hasActiveFilters computed property

### VPStudioTests/ViewModels/SearchViewModelFilterTests.swift
- **Purpose**: Existing filter tests
- **Coverage**: Genre loading, selection, sorting, year filtering

---

## Dependencies

- **TMDB API**: Used for movie/TV metadata, search, discover, and categories
- **Swift Testing**: Built-in testing framework for unit tests
- **Observation**: SwiftUI observation framework for view models

---

## Date Boundary Logic

### New Releases (Mood Card & Discover Section)
- **Date Range**: 90 days ago to today (inclusive)
- **API Parameters**: `releaseDateGte = today - 90 days`, `releaseDateLte = today`
- **Purpose**: Shows recently released content

### Coming Soon / Future Releases (Mood Card & Discover Section)
- **Date Range**: Tomorrow to 1 year from now
- **API Parameters**: `releaseDateGte = tomorrow`, `releaseDateLte = today + 365 days`
- **Purpose**: Shows upcoming releases

### Regular Genre Browse
- **Date Range**: All time up to today
- **API Parameters**: `releaseDateLte = today`
- **Purpose**: Excludes unreleased/unannounced content from genre browsing

---

## Last Updated

- 2026-02-28 - Agent 2 (Search Filters & New/Future Releases)
