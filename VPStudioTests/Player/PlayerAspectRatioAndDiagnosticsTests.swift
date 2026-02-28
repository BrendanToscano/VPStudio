import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import VPStudio

// MARK: - Aspect Ratio Selection Tests

@Suite("AspectRatioSelection")
struct AspectRatioSelectionTests {

    @Test func allCasesAreAvailable() {
        let allCases = AspectRatioSelection.allCases
        #expect(allCases.count == 5)
        #expect(allCases.contains(.auto))
        #expect(allCases.contains(.sixteenByNine))
        #expect(allCases.contains(.twentyOneByNine))
        #expect(allCases.contains(.fourByThree))
        #expect(allCases.contains(.freeform))
    }

    @Test func autoHasCorrectLabel() {
        #expect(AspectRatioSelection.auto.label == "Auto (Native)")
    }

    @Test func fixedPresetsLockWindowRatio() {
        #expect(AspectRatioSelection.auto.locksWindowRatio == true)
        #expect(AspectRatioSelection.sixteenByNine.locksWindowRatio == true)
        #expect(AspectRatioSelection.twentyOneByNine.locksWindowRatio == true)
        #expect(AspectRatioSelection.fourByThree.locksWindowRatio == true)
    }

    @Test func freeformDoesNotLockWindowRatio() {
        #expect(AspectRatioSelection.freeform.locksWindowRatio == false)
    }

    @Test func freeformHasCorrectIcon() {
        #expect(AspectRatioSelection.freeform.icon == "rectangle.dashed")
    }
}

// MARK: - Player Aspect Ratio Policy Tests

@Suite("PlayerAspectRatioPolicy")
struct PlayerAspectRatioPolicyTests {

    @Test func defaultRatioIs16By9() {
        #expect(PlayerAspectRatioPolicy.defaultRatio == 16.0 / 9.0)
    }

    @Test func resolvedRatioAutoWithDetected() {
        let detected: CGFloat = 2.35 // 21:9
        let resolved = PlayerAspectRatioPolicy.resolvedRatio(for: .auto, detectedRatio: detected)
        #expect(resolved == detected)
    }

    @Test func resolvedRatioAutoWithNoDetection() {
        let resolved = PlayerAspectRatioPolicy.resolvedRatio(for: .auto, detectedRatio: nil)
        #expect(resolved == PlayerAspectRatioPolicy.defaultRatio)
    }

    @Test func resolvedRatioFixedPresets() {
        #expect(PlayerAspectRatioPolicy.resolvedRatio(for: .sixteenByNine, detectedRatio: nil) == 16.0 / 9.0)
        #expect(PlayerAspectRatioPolicy.resolvedRatio(for: .twentyOneByNine, detectedRatio: nil) == 21.0 / 9.0)
        #expect(PlayerAspectRatioPolicy.resolvedRatio(for: .fourByThree, detectedRatio: nil) == 4.0 / 3.0)
    }

    @Test func resolvedRatioFreeformReturnsNil() {
        let resolved = PlayerAspectRatioPolicy.resolvedRatio(for: .freeform, detectedRatio: nil)
        #expect(resolved == nil)
    }

    @Test func videoGravityAutoAndFixedPresetsUseAspectFill() {
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .auto) == .resizeAspectFill)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .sixteenByNine) == .resizeAspectFill)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .twentyOneByNine) == .resizeAspectFill)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .fourByThree) == .resizeAspectFill)
    }

    @Test func videoGravityFreeformUsesResizeAspect() {
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .freeform) == .resizeAspect)
    }

    @Test func ratioFromValidSize() {
        let size = CGSize(width: 1920, height: 1080)
        let ratio = PlayerAspectRatioPolicy.ratio(from: size)
        #expect(ratio == 16.0 / 9.0)
    }

    @Test func ratioFromSquareSize() {
        let size = CGSize(width: 1000, height: 1000)
        let ratio = PlayerAspectRatioPolicy.ratio(from: size)
        #expect(ratio == 1.0)
    }

    @Test func ratioFromInvalidSizeReturnsNil() {
        #expect(PlayerAspectRatioPolicy.ratio(from: .zero) == nil)
        #expect(PlayerAspectRatioPolicy.ratio(from: CGSize(width: 0, height: 100)) == nil)
        #expect(PlayerAspectRatioPolicy.ratio(from: CGSize(width: 100, height: 0)) == nil)
    }

    @Test func windowAspectSizeForValidRatio() {
        let ratio: CGFloat = 16.0 / 9.0
        let size = PlayerAspectRatioPolicy.windowAspectSize(for: ratio)
        #expect(size != nil)
        if let size = size {
            #expect(size.width == 16.0)
            #expect(size.height == 9.0)
        }
    }

    @Test func windowAspectSizeForNilReturnsNil() {
        #expect(PlayerAspectRatioPolicy.windowAspectSize(for: nil) == nil)
    }
}

// MARK: - Memory Leak Detector Tests

@Suite("MemoryLeakDetector")
struct MemoryLeakDetectorTests {

    @Test func detectorReturnsFalseWithFewSnapshots() {
        var detector = MemoryLeakDetector(maxSnapshots: 5, leakThresholdMB: 100, growthRateThreshold: 0.1)

        let snapshot1 = RuntimeMemorySnapshot(residentBytes: 100 * 1024 * 1024) // 100 MB
        let snapshot2 = RuntimeMemorySnapshot(residentBytes: 110 * 1024 * 1024) // 110 MB

        #expect(detector.record(snapshot1) == false)
        #expect(detector.record(snapshot2) == false)
    }

    @Test func detectorReturnsTrueOnLeakPattern() {
        var detector = MemoryLeakDetector(maxSnapshots: 5, leakThresholdMB: 50, growthRateThreshold: 0.1)

        // Simulate memory growing from 100MB to 200MB (100% growth)
        let snapshot1 = RuntimeMemorySnapshot(residentBytes: 100 * 1024 * 1024) // 100 MB
        let snapshot2 = RuntimeMemorySnapshot(residentBytes: 130 * 1024 * 1024) // 130 MB
        let snapshot3 = RuntimeMemorySnapshot(residentBytes: 160 * 1024 * 1024) // 160 MB

        #expect(detector.record(snapshot1) == false)
        #expect(detector.record(snapshot2) == false)
        #expect(detector.record(snapshot3) == true) // Growth > 15% threshold
    }

    @Test func detectorResetClearsState() {
        var detector = MemoryLeakDetector(maxSnapshots: 5, leakThresholdMB: 50, growthRateThreshold: 0.1)

        let snapshot1 = RuntimeMemorySnapshot(residentBytes: 100 * 1024 * 1024)
        let snapshot2 = RuntimeMemorySnapshot(residentBytes: 130 * 1024 * 1024)
        let snapshot3 = RuntimeMemorySnapshot(residentBytes: 160 * 1024 * 1024)

        _ = detector.record(snapshot1)
        _ = detector.record(snapshot2)
        _ = detector.record(snapshot3)

        detector.reset()

        // After reset, should not detect leak with next snapshots
        let snapshot4 = RuntimeMemorySnapshot(residentBytes: 170 * 1024 * 1024)
        #expect(detector.record(snapshot4) == false)
    }
}

// MARK: - Runtime Diagnostics Policy Tests

@Suite("RuntimeDiagnosticsPolicy")
struct RuntimeDiagnosticsPolicyTests {

    @Test func normalizedContextTruncatesLongStrings() {
        let longString = String(repeating: "a", count: 200)
        let normalized = RuntimeDiagnosticsPolicy.normalizedContext(longString)
        #expect(normalized.count <= RuntimeDiagnosticsPolicy.maxContextLength)
    }

    @Test func normalizedContextReturnsEmptyForNil() {
        #expect(RuntimeDiagnosticsPolicy.normalizedContext(nil) == "")
    }

    @Test func normalizedContextReturnsTrimmedForWhitespace() {
        let withWhitespace = "   hello world   "
        let normalized = RuntimeDiagnosticsPolicy.normalizedContext(withWhitespace)
        #expect(normalized == "hello world")
    }

    @Test func shouldSnapshotReturnsTrueForFirstCall() {
        #expect(RuntimeDiagnosticsPolicy.shouldSnapshot(lastSnapshotTime: nil) == true)
    }

    @Test func shouldSnapshotReturnsFalseForRecentCall() {
        let recentTime = Date()
        #expect(RuntimeDiagnosticsPolicy.shouldSnapshot(lastSnapshotTime: recentTime) == false)
    }

    @Test func shouldSnapshotReturnsTrueForOldCall() {
        let oldTime = Date().addingTimeInterval(-5)
        #expect(RuntimeDiagnosticsPolicy.shouldSnapshot(lastSnapshotTime: oldTime) == true)
    }
}
