# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- **Cinema screen video anchoring**: Video now correctly appears on the cinema screen in immersive environments (Pretville Cinema, Cinema Hall) instead of showing as a separate floating window or black screen.
  - Added strong local references (`immersivePlayer`, `immersiveVideoRenderer`) in `HDRISkyboxEnvironment.swift` and `CustomEnvironmentView.swift` to prevent the AVPlayer/VideoRenderer from being deallocated when PlayerView's weak references are cleared.
  - Updated the RealityView update loop to sync from AppState's weak references to local strong references.
  - Added logging to help diagnose video material application issues.

- **Environment settings persistence**: Settings no longer shows "No environments added" after downloading HDRI environments.
  - Added listener for `.environmentsDidChange` notification in `SettingsRootView.swift` to automatically refresh the environment count when environments are imported.

- **Environment settings UI**: Fixed garbled/confusing text in the Environments settings panel.
  - Renamed "Curated Environments" section to "Built-in Environments" with clearer placeholder text.
  - Improved the description for Online Presets section.

### Added
- Unit tests for environment asset state:
  - `environmentAssetCountReflectsImportedAssets`: Verifies the asset count updates correctly after imports.
  - `importingCuratedPresetNotifiesEnvironmentsChanged`: Verifies notifications are sent after importing presets.

## [Previous Versions]
- See git history for previous changelog entries
