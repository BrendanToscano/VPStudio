# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Swift Warnings (d1)**: Fixed retain cycle in DownloadManager progress update by using `[weak self]` in Task closure
- **DetailViewModel**: Fixed optional genres handling (now non-optional)
- **PlayerView**: Fixed deprecated `coordinateSpace` usage for visionOS 26+ (now uses `window.frame`)

### Added
- **Tests**: Added BugFixVerificationTests for Fix 9 covering Swift warnings cleanup

## [1.0.0] - 2024-02-28

### Initial Public Release
- First public release of VPStudio
