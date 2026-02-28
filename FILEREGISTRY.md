# FILEREGISTRY.md

This file tracks all source files modified or added in this release, their purposes, and dependencies.

---

## Modified Files

### VPStudio/Views/Windows/Player/PlayerView.swift

**Purpose**: Main player view with video playback, controls, and aspect ratio handling.

**Functions Modified**:
- `startObservingAVPlayer()`: Added `[weak self]` to time observer closure to prevent retain cycles
- Menu: Added "Aspect Ratio" section with selection for Auto, 16:9, 21:9, 4:3, Freeform
- `.onReceive` handlers: Added `[weak self]` to notification observers

**Dependencies**: AVKit, KSPlayer, VPPlayerEngine, PlayerAspectRatioPolicy

**Last Modified**: 2026-02-28

---

### VPStudio/Core/Diagnostics/RuntimeMemoryDiagnostics.swift

**Purpose**: Runtime memory diagnostics and leak detection for the player and app.

**Functions Added**:
- `MemoryLeakDetector` struct: Tracks memory snapshots to detect potential leaks
- `RuntimeMemorySnapshot` enhanced with timestamp
- `RuntimeDiagnosticsPolicy` added leak detection constants

**Dependencies**: Foundation, Darwin (macOS only)

**Last Modified**: 2026-02-28

---

## Added Files

### VPStudioTests/Player/PlayerAspectRatioAndDiagnosticsTests.swift

**Purpose**: Unit tests for aspect ratio selection, policy logic, and memory leak detection.

**Test Suites**:
- `AspectRatioSelectionTests`: Tests for aspect ratio enum cases and properties
- `PlayerAspectRatioPolicyTests`: Tests for aspect ratio resolution and video gravity
- `MemoryLeakDetectorTests`: Tests for leak detection logic
- `RuntimeDiagnosticsPolicyTests`: Tests for diagnostics policy functions

**Dependencies**: VPStudio (testable), CoreGraphics, AVFoundation

**Last Modified**: 2026-02-28

---

### CHANGELOG.md

**Purpose**: Release notes documenting all changes in this release.

**Last Modified**: 2026-02-28

---

## Unchanged Files (Referenced but not modified)

- `VPStudio/Services/Player/Policies/PlayerAspectRatioPolicy.swift` - Already had correct implementation
- `VPStudio/Services/Player/State/VPPlayerEngine.swift` - No changes needed
- `VPStudio/Views/Windows/Player/PlayerCinematicVisualPolicy.swift` - No changes needed
- `VPStudio/Views/Windows/Player/PlayerScrubPolicy.swift` - No changes needed
