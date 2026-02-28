# File Registry

This document tracks all source files in the project, their purposes, and dependencies.

## Modified Files (this fix)

### VPStudio/Views/Windows/Settings/Destinations/AISettingsView.swift
- **Purpose**: AI provider settings UI
- **Key Functions**: Gemini API key and model configuration
- **Dependencies**: `AIModelFetcher`, `SettingsManager`
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added Gemini section with API key and model picker

### VPStudio/Services/AI/GeminiProvider.swift
- **Purpose**: Google Gemini API provider implementation
- **Key Functions**: `complete`
- **Dependencies**: `URLSession`
- **Last Modified**: Branch fix/gemini-ui
- **Change**: New file - Gemini API integration

### VPStudio/Core/Database/SettingsManager.swift
- **Purpose**: Settings persistence
- **Key Functions**: Settings key definitions
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added geminiApiKey, geminiModelPreset

### VPStudio/Models/AIAssistantModels.swift
- **Purpose**: AI provider enum
- **Key Functions**: AIProviderKind
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added .gemini case

### VPStudio/Services/AI/AIAssistantManager.swift
- **Purpose**: AI provider management
- **Key Functions**: `configure`
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added Gemini configuration

### VPStudio/Services/AI/AIModelCatalog.swift
- **Purpose**: AI model definitions
- **Key Functions**: `models(for:)`, `allModels`
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added Gemini models

### VPStudio/App/AppState.swift
- **Purpose**: App state management
- **Key Functions**: `configureAIProviders`
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added Gemini to provider config

### VPStudio/Views/Immersive/CustomEnvironmentView.swift
- **Purpose**: Custom environment viewer
- **Key Functions**: Environment loading
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added file validation

### VPStudio/Views/Immersive/HDRISkyboxEnvironment.swift
- **Purpose**: HDRI environment viewer
- **Key Functions**: HDRI loading
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added file validation

### VPStudioTests/BugFixVerificationTests.swift
- **Purpose**: Tests verifying bug fixes
- **Key Functions**: Test suites
- **Dependencies**: Various
- **Last Modified**: Branch fix/gemini-ui
- **Change**: Added Fix 16 test suite
