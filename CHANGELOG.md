# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Debrid Force Unwraps**: RealDebridService nil username handling
- **Debrid Force Unwraps**: RealDebridService lazy regex pattern
- **Debrid Force Unwraps**: RealDebridService nil response IDs
- **Debrid Force Unwraps**: RealDebridService nil download URL
- **Environment**: EnvironmentCatalogManager validateAsset function
- **Views**: CustomEnvironmentView loading/error state handling
- **Views**: HDRISkyboxEnvironment file validation

### Added
- **Gemini Support**: Added GeminiProvider for Google Gemini API
- **Gemini Support**: Added Gemini models to AIModelCatalog
- **Gemini Support**: Added geminiApiKey and geminiModelPreset to SettingsKeys
- **Gemini Support**: AISettingsView Gemini configuration UI

### Changed
- **Trakt Sync**: Refactored to capture data before detached Task

### Added
- **Tests**: Added BugFixVerificationTests for Fix 14 covering debrid fixes

## [1.0.0] - 2024-02-28

### Initial Public Release
- First public release of VPStudio
