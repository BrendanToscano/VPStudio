# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Player Cleanup**: RealDebridService lazy regex to avoid force unwrap
- **Player Cleanup**: MetadataProvider dateString guard against nil
- **Player Cleanup**: APMPInjector strong reference to displayLinkTarget
- **Player Cleanup**: PlayerLoadingTipRotator interval capture for Swift 6
- **Views**: Added [weak self] to onReceive closures in multiple views

### Added
- **Tests**: Added BugFixVerificationTests for Fix 13 covering player cleanup

## [1.0.0] - 2024-02-28

### Initial Public Release
- First public release of VPStudio
