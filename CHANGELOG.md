# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Build Warnings**: Removed nested Task in DownloadManager (fixed retain cycle)
- **Build Warnings**: HeadTracker Swift 6 concurrency safety (captures values before MainActor)
- **DetailViewModel**: Added [weak self] to searchTask
- **DetailViewModel**: Non-optional genres handling
- **SearchViewModel**: Added [weak self] to loadRecentSearches and saveRecentSearches
- **PlayerView**: Fixed coordinateSpace deprecation for visionOS 26+

### Added
- **Tests**: Added BugFixVerificationTests for Fix 11 covering build warnings

## [1.0.0] - 2024-02-28

### Initial Public Release
- First public release of VPStudio
