# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Metadata Concurrency**: TMDBError now conforms to Sendable for Swift 6
- **DownloadManager**: Removed nested Task, direct await for progress
- **HeadTracker**: Swift 6 concurrency safety with value capture
- **DetailViewModel**: Non-optional genres handling
- **PlayerView**: coordinateSpace deprecation fix for visionOS 26+

### Added
- **Tests**: Added BugFixVerificationTests for Fix 12 covering metadata concurrency

## [1.0.0] - 2024-02-28

### Initial Public Release
- First public release of VPStudio
