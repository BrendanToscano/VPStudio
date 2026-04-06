import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import VPStudio

@Suite("Player Aspect Ratio Policy")
struct PlayerAspectRatioPolicyTests {

    @Test
    func autoUsesDetectedRatioWhenAvailable() {
        let resolved = PlayerAspectRatioPolicy.resolvedRatio(for: .auto, detectedRatio: 2.39)
        #expect(resolved == 2.39)
    }

    @Test
    func autoFallsBackToDefaultRatio() {
        let resolved = PlayerAspectRatioPolicy.resolvedRatio(for: .auto, detectedRatio: nil)
        #expect(resolved == PlayerAspectRatioPolicy.defaultRatio)
    }

    @Test
    func fixedRatiosResolveToExpectedValues() {
        #expect(PlayerAspectRatioPolicy.resolvedRatio(for: .sixteenByNine, detectedRatio: nil) == (16.0 / 9.0))
        #expect(PlayerAspectRatioPolicy.resolvedRatio(for: .twentyOneByNine, detectedRatio: nil) == (21.0 / 9.0))
        #expect(PlayerAspectRatioPolicy.resolvedRatio(for: .fourByThree, detectedRatio: nil) == (4.0 / 3.0))
    }

    @Test
    func freeformUnlocksRatioAndUsesLetterboxGravity() {
        #expect(PlayerAspectRatioPolicy.resolvedRatio(for: .freeform, detectedRatio: 16.0 / 9.0) == nil)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .freeform) == .resizeAspect)
    }

    @Test
    func lockedPresetsUseAspectFillGravity() {
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .auto) == .resizeAspectFill)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .sixteenByNine) == .resizeAspectFill)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .twentyOneByNine) == .resizeAspectFill)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .fourByThree) == .resizeAspectFill)
    }

    @Test
    func qaValueParsingSupportsUserAndAliasStrings() {
        #expect(AspectRatioSelection(qaValue: "freeflow") == .freeform)
        #expect(AspectRatioSelection(qaValue: "16x9") == .sixteenByNine)
        #expect(AspectRatioSelection(qaValue: "auto") == .auto)
        #expect(AspectRatioSelection(qaValue: "4:3") == .fourByThree)
        #expect(AspectRatioSelection(qaValue: "unknown") == nil)
    }

    @Test
    func windowAspectSizeIsNilWhenUnlocked() {
        #expect(PlayerAspectRatioPolicy.windowAspectSize(for: nil) == nil)
        let size = PlayerAspectRatioPolicy.windowAspectSize(for: 16.0 / 9.0)
        #expect(size?.height == 9)
        #expect(size?.width == 16)
    }
}
