# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Retain Cycles (d2)**: Added [weak self] to DetailViewModel searchTask Task closure
- **Retain Cycles (d2)**: Added [weak self] to SearchViewModel loadRecentSearches Task closure
- **DetailViewModel**: Added guard against nil self after await in searchTask

### Added
- **Tests**: Added BugFixVerificationTests for Fix 10 covering retain cycle fixes

## [1.0.0] - 2024-02-28

### Initial Public Release
- First public release of VPStudio
