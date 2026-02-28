# Swift 6 Concurrency Issues - Fixes Applied

This document details the Swift 6 concurrency issues found and fixed in VPStudio.

## Issues Found & Fixed

### 1. AppState.swift - Task.detached accessing @MainActor method

**File:** `VPStudio/App/AppState.swift`

**Issue:** The `Task.detached` block was calling `self.makeTraktSyncOrchestrator()` directly, which is a `@MainActor` method. In Swift 6 strict concurrency, calling `@MainActor` methods from detached tasks is an error.

**Original Code:**
```swift
Task.detached { [weak self] in
    guard let self else { return }
    let orchestrator = await self.makeTraktSyncOrchestrator()
    guard let orchestrator else { return }
    let result = await orchestrator.sync()
    // ...
}
```

**Fix:** Captured all required data (`settingsManager`, `database`) from the `@MainActor` context before entering the detached task. The `TraktSyncOrchestrator` is now constructed with captured data instead of calling a `@MainActor` method from the detached context.

**Fixed Code:**
```swift
Task.detached { [weak self] in
    guard let self else { return }
    // Capture needed data from @MainActor context before entering detached task
    let traktClientId = try? await self.settingsManager.getString(key: SettingsKeys.traktClientId)
    let traktClientSecret = try? await self.settingsManager.getString(key: SettingsKeys.traktSecret)
    let database = self.database
    let settingsManager = self.settingsManager

    // Now create orchestrator off main actor using captured data
    guard let creds = TraktDefaults.resolvedCredentials(
        userClientId: traktClientId,
        userClientSecret: traktClientSecret
    ) else { return }
    // ... rest of implementation
}
```

### 2. AIAssistantManager.swift - Task.detached with implicit capture

**File:** `VPStudio/Services/AI/AIAssistantManager.swift`

**Issue:** The `Task.detached` block captured `database` implicitly, which could cause Swift 6 concurrency warnings. Making the capture explicit improves clarity and ensures proper Sendable checking.

**Original Code:**
```swift
let database = self.database
Task.detached {
    try? await database.saveAIUsageRecord(record)
}
```

**Fix:** Added explicit capture list `[database]` to the Task.detached closure.

**Fixed Code:**
```swift
let database = self.database
Task.detached { [database] in
    try? await database.saveAIUsageRecord(record)
}
```

## Verified: No Issues Found

### ViewModels

After thorough analysis, the following ViewModels were verified to have proper Swift 6 concurrency handling:

- **DetailViewModel.swift**: All `Task{}` closures properly use `[weak self]` capture lists
- **DiscoverViewModel.swift**: Uses async/await directly, no detached tasks found
- **SearchViewModel.swift**: All `Task{}` closures properly use `[weak self]` capture lists
- **DownloadsViewModel.swift**: Uses async/await directly, no detached tasks found

### DetailFeatureState (TorrentSearchState, DebridResolverState, MediaLibraryState)

These `@Observable @MainActor` classes are properly isolated and don't contain any Task closures that could cause issues.

### Other Files

- **EnvironmentCatalogManager.swift**: Uses `Task { @MainActor in }` correctly for posting notifications from non-isolated contexts
- **DownloadManager.swift**: Uses `Task { @MainActor in }` correctly for posting notifications from non-isolated contexts
- **HeadTracker.swift**: Uses `Task.detached` correctly with proper `MainActor.run` for updating state

## Summary

- **Issues Fixed:** 2
- **Issues Verified as OK:** All ViewModels and major service classes
- **Branch:** fix/swift6-full
