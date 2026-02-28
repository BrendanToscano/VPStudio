# CHANGELOG.md - VPStudio

All notable changes to VPStudio will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Image Caching**: Integrated Kingfisher library for efficient LRU image caching with configurable memory (100MB, 150 items) and disk (500MB, 7-day expiration) limits.
- **Search Debounce Optimization**: Added minimum query length check (2 characters) to prevent over-fetching on single keystrokes.
- **Duplicate Debounce Prevention**: Added query tracking to skip unnecessary debounce calls when query hasn't changed.

### Changed
- **MediaCardView**: Replaced native `AsyncImage` with Kingfisher's `KFImage` for proper image caching and memory management.
- **SearchViewModel**: Enhanced `debouncedSearch()` to check minimum query length and prevent duplicate debounce calls.

### Fixed
- Search page now avoids unnecessary network requests for short queries (< 2 characters).
- Image loading now uses LRU cache instead of re-fetching from network on every view appearance.

### Tests Added
- `SearchViewModelDebounceOptimizationTests`: Unit tests for minimum query length and duplicate debounce prevention.

---

## [Previous Versions]

- See git history for versions prior to this changelog.
