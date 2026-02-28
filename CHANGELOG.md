# CHANGELOG.md - VPStudio

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- **New Releases section in DiscoverView**: Added dedicated "New Releases" row showing movies released in the last 90 days (up to today). Uses TMDB discover API with date filtering (releaseDateGte: 90 days ago, releaseDateLte: today).
- **Coming Soon / Future Releases section in DiscoverView**: Added dedicated "Coming Soon" row showing upcoming movies (release date > today). Uses TMDB's `/movie/upcoming` category.
- **Unit tests for filter date logic**: Added `SearchFilterDateTests.swift` covering:
  - Date helper functions (`todayString`, `dateString`)
  - Year range presets (recent, twenties, tens, classic)
  - Mood card date boundaries (New Releases, Future Releases)
- **Unit tests for client-side filtering**: Added `SearchViewModelClientSideFilterTests.swift` covering:
  - Client-side sorting (rating, title, release date)
  - Year range preset filtering on search results
  - Pagination with filters applied
  - `hasActiveFilters` and `activeFilterCount` computed properties

### Fixed
- **Search filters not applying to text search**: Fixed `SearchViewModel.search()` to apply client-side sorting and year range preset filtering when filters are active. Previously, only year and language filters were passed to the API.
- **Sort options not applied**: Added client-side sorting in `search()` and `loadMoreSearch()` methods for sort options that the TMDB search API doesn't support (rating sort, title sort, release date sort).
- **Year range preset not applied to search**: Year range presets (recent, twenties, tens, classic) are now applied client-side to filter search results.
- **Pagination with filters**: Fixed `loadMoreSearch()` to apply client-side sorting and year range preset filtering to paginated results.
- **DiscoverFilters query parameter**: Added optional `query` parameter to `DiscoverFilters` struct for discover API calls.

### Changed
- **New Releases definition**: New Releases now explicitly shows content from 90 days ago up to today (inclusive). This matches the mood card behavior in SearchView.
- **Upcoming Movies**: Uses TMDB's `/movie/upcoming` endpoint which returns movies with release dates in the future.

---

## [Previous Versions]

- See git history for version prior to this changelog.
