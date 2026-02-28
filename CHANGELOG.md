# Changelog

All notable changes to VPStudio will be documented in this file.

## [Unreleased]

### Added
- **Continue Watching Threshold**: Changed from 2% to 5% threshold for Continue Watching section in Discover view
- **Library Image Loading**: Added automatic metadata fetching for library items with missing poster paths

### Fixed
- **Library Posters**: Fixed issue where library poster images wouldn't load when posterPath was missing from database
- **Continue Watching**: Fixed threshold to match specification (5% instead of 2%)

### Tests Added
- Unit tests for MediaPreview and MediaItem image URL construction
- Unit tests for Continue Watching 5% threshold

## [Previous Versions]
- See git history for previous changes
