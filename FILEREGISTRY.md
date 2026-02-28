# File Registry

This document tracks all source files in the project, their purposes, and dependencies.

## Modified Files (this fix)

### VPStudio/Services/Debrid/RealDebridService.swift
- **Purpose**: Real-Debrid API client
- **Key Functions**: `addMagnet`, `unrestrict`, `accountInfo`
- **Dependencies**: `URLSession`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Fixed force unwraps for username, id, download URL

### VPStudio/Services/AI/GeminiProvider.swift
- **Purpose**: Google Gemini API provider
- **Key Functions**: `complete`
- **Dependencies**: `URLSession`, `AIProvider`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: New file - Gemini API integration

### VPStudio/Services/AI/AIAssistantManager.swift
- **Purpose**: AI provider management
- **Key Functions**: `configure`
- **Dependencies**: `AIProvider`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Added Gemini provider configuration

### VPStudio/Services/AI/AIModelCatalog.swift
- **Purpose**: AI model definitions
- **Key Functions**: `allModels`, `model`
- **Dependencies**: `AIModelDefinition`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Added Gemini models

### VPStudio/Core/Database/SettingsManager.swift
- **Purpose**: App settings persistence
- **Key Functions**: `getString`, `setString`
- **Dependencies**: `Database`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Added geminiApiKey, geminiModelPreset

### VPStudio/Models/AIAssistantModels.swift
- **Purpose**: AI provider enum
- **Key Functions**: AIProviderKind cases
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Added .gemini case

### VPStudio/App/AppState.swift
- **Purpose**: App-wide state management
- **Key Functions**: `bootstrap`, `configureAIProviders`
- **Dependencies**: `TraktSyncService`, `AIAssistantManager`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Trakt sync refactoring, Gemini support

### VPStudio/Services/Environment/EnvironmentCatalogManager.swift
- **Purpose**: Environment asset catalog
- **Key Functions**: `validateAsset`
- **Dependencies**: `EnvironmentAsset`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Added validateAsset function

### VPStudio/Views/Immersive/CustomEnvironmentView.swift
- **Purpose**: Custom environment viewer
- **Key Functions**: Loading state handling
- **Dependencies**: `RealityView`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Added loading/error state

### VPStudio/Views/Immersive/HDRISkyboxEnvironment.swift
- **Purpose**: HDRI skybox environment
- **Key Functions**: HDRI loading
- **Dependencies**: `Entity`
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Added file validation

### VPStudioTests/BugFixVerificationTests.swift
- **Purpose**: Tests verifying bug fixes
- **Key Functions**: Test suites
- **Dependencies**: Various
- **Last Modified**: Branch fix/debrid-force-unwraps
- **Change**: Added Fix 14 test suite
