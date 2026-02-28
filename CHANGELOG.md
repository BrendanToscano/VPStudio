# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Environment Robustness**: HDRISkyboxEnvironment validates CGImageSource count
- **Environment Robustness**: EnvironmentPreviewRow validates CGImageSource count
- **Player View**: coordinateSpace deprecation fix for visionOS 26+
- **ViewModels**: [weak self] in Task closures

### Added
- **Gemini Support**: Added GeminiProvider for Google Gemini API
- **Tests**: Added BugFixVerificationTests for Fix 15 covering environment robustness

## [1.0.0] - 2024-02-28

### Initial Public Release
- First public release of VPStudio
