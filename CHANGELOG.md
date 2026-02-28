# Changelog

All notable changes to VPStudio will be documented in this file.

## [Unreleased]

### Added
- **Player Audio Track Selection**: Audio tracks from AVPlayer media selection groups are now properly loaded and displayed in the Audio picker

### Fixed
- **Player Audio Tracks**: Fixed audio track loading to first load asset tracks before accessing media selection groups, ensuring all available audio tracks are discovered. Also added support for loading audio tracks in KSPlayer sessions via AVAsset.

### Tests Added
- Unit tests for audio track loading logic in VPPlayerEngine

## [Previous Versions]
- See git history for previous changes
