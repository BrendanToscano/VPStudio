# File Registry

This document tracks the purpose and structure of key files in the VPStudio codebase.

## Immersive Environment Views

### VPStudio/Views/Immersive/HDRISkyboxEnvironment.swift
- **Purpose**: Renders a 360° HDRI skybox environment with a cinema screen for video playback in Apple Vision Pro immersive mode.
- **Key Components**:
  - `ScreenSizePreset`: Enum for Personal/Cinema/IMAX screen sizes
  - `HDRISkyboxEnvironment`: Main SwiftUI View using RealityView
  - Head tracking for screen anchoring
  - VideoMaterial application for cinema screen
- **Dependencies**: RealityKit, AVFoundation, ImageIO
- **Modified**: Added strong references for AVPlayer/VideoRenderer to fix video handoff

### VPStudio/Views/Immersive/CustomEnvironmentView.swift
- **Purpose**: Renders custom USDZ/Reality environments with a detected cinema screen mesh.
- **Key Components**:
  - `CustomEnvironmentView`: Main SwiftUI View using RealityView
  - `findScreenEntity()`: Recursively searches for screen mesh in USDZ hierarchy
- **Dependencies**: RealityKit, AVFoundation
- **Modified**: Added strong references for AVPlayer/VideoRenderer to fix video handoff

### VPStudio/Views/Immersive/ImmersivePlayerControlsView.swift
- **Purpose**: Transport controls overlay for immersive video playback
- **Dependencies**: SwiftUI

### VPStudio/Services/Player/Immersive/HeadTracker.swift
- **Purpose**: Tracks user's head position for screen anchoring
- **Dependencies**: RealityKit, ARKit

## Environment Management

### VPStudio/Services/Environment/EnvironmentCatalogManager.swift
- **Purpose**: Manages environment asset lifecycle - import, download, delete, persistence
- **Key Methods**:
  - `fetchAssets()`: Get all environment assets
  - `importEnvironment()`: Import local environment file
  - `importCuratedPreset()`: Download and import from Poly Haven
  - `importEnvironment(fromRemote:)`: Download from URL
  - `notifyEnvironmentsChanged()`: Post notification after changes
- **Dependencies**: DatabaseManager, FileManager
- **Note**: Uses weak references in AppState for player sharing

### VPStudio/Views/Windows/Settings/Destinations/EnvironmentSettingsView.swift
- **Purpose**: Settings UI for managing environment assets
- **Key Sections**:
  - Built-in Environments
  - Online Presets (Poly Haven HDRI)
  - Imported Environments
- **Modified**: Fixed section header and placeholder text

### VPStudio/Views/Windows/Settings/Root/SettingsRootView.swift
- **Purpose**: Main settings view with status indicators
- **Key Methods**:
  - `refreshStatuses()`: Updates status indicators
  - `captureStatusSnapshot()`: Captures current state for status display
- **Modified**: Added listener for `.environmentsDidChange` notification

## Player Integration

### VPStudio/App/AppState.swift
- **Purpose**: Global app state singleton
- **Key Properties for Immersive**:
  - `activeAVPlayer`: Weak reference to current AVPlayer
  - `activeVideoRenderer`: Weak reference to video renderer
  - `selectedEnvironmentAsset`: Currently selected environment
  - `isImmersiveSpaceOpen`: Immersive mode state
- **Note**: Weak references can become nil when PlayerView is recreated

### VPStudio/Views/Windows/Player/PlayerView.swift
- **Purpose**: Main video player view
- **Key Behavior**: Sets `appState.activeAVPlayer` when playback starts
- **Modified**: N/A (no changes needed)

## Tests

### VPStudioTests/EnvironmentCatalogTests.swift
- **Purpose**: Unit tests for EnvironmentCatalogManager
- **Modified**: Added tests for asset count and notification behavior
- **New Tests**:
  - `environmentAssetCountReflectsImportedAssets`
  - `importingCuratedPresetNotifiesEnvironmentsChanged`

## Documentation

### docs/CHANGELOG.md
- **Purpose**: Release notes and change documentation
- **Created**: Agent 7 fix for cinema screen anchoring

### docs/FILEREGISTRY.md
- **Purpose**: This file - tracks key files and their purposes
- **Created**: Agent 7 fix for cinema screen anchoring
