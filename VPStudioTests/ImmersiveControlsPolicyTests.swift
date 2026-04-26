import Testing
import simd
@testable import VPStudio

@Suite("ImmersiveControlsPolicy -- Constants & Smoothing")
struct ImmersiveControlsPolicyTests {

    // MARK: - Constant Values

    @Test("Fallback controls position Y equals 1.3")
    func fallbackPositionY() {
        #expect(ImmersiveControlsPolicy.fallbackControlsPosition.y == 1.3)
    }

    @Test("Fallback controls position is forward of origin (negative Z)")
    func fallbackPositionForwardOfOrigin() {
        #expect(ImmersiveControlsPolicy.fallbackControlsPosition.z < 0)
    }

    @Test("Fallback controls position X is centered at 0")
    func fallbackPositionCentered() {
        #expect(ImmersiveControlsPolicy.fallbackControlsPosition.x == 0)
    }

    @Test("Auto-dismiss interval equals 10 seconds")
    func autoDismissInterval() {
        #expect(ImmersiveControlsPolicy.autoDismissInterval == .seconds(10))
    }

    @Test("Controls anchor smoothing factor is between 0 and 1 exclusive")
    func smoothingFactorRange() {
        let t = ImmersiveControlsPolicy.controlsAnchorSmoothing
        #expect(t > 0)
        #expect(t < 1)
    }

    @Test("Controls forward offset is positive")
    func controlsForwardOffsetPositive() {
        #expect(ImmersiveControlsPolicy.controlsForwardOffset > 0)
    }

    @Test("Controls vertical offset is negative (below eye line)")
    func controlsVerticalOffsetNegative() {
        #expect(ImmersiveControlsPolicy.controlsVerticalOffset < 0)
    }

    @Test("Fallback eye height is in a plausible range for seated VR")
    func fallbackEyeHeightPlausible() {
        let h = ImmersiveControlsPolicy.fallbackEyeHeight
        #expect(h >= 1.0)
        #expect(h <= 2.0)
    }

    // MARK: - smoothedPosition

    @Test("smoothedPosition returns same position when current equals target")
    func smoothedPositionIdentity() {
        let pos = SIMD3<Float>(2.0, 1.5, -3.0)
        let result = ImmersiveControlsPolicy.smoothedPosition(current: pos, target: pos)
        #expect(result.x == pos.x)
        #expect(result.y == pos.y)
        #expect(result.z == pos.z)
    }

    @Test("smoothedPosition moves toward target by smoothing factor")
    func smoothedPositionMovesTowardTarget() {
        let current = SIMD3<Float>(0, 0, 0)
        let target = SIMD3<Float>(10, 0, 0)
        let result = ImmersiveControlsPolicy.smoothedPosition(current: current, target: target)
        let t = ImmersiveControlsPolicy.controlsAnchorSmoothing

        #expect(abs(result.x - t * 10) < 0.001)
        #expect(result.y == 0)
        #expect(result.z == 0)
    }

    @Test("smoothedPosition converges after many iterations")
    func smoothedPositionConverges() {
        var pos = SIMD3<Float>(0, 0, 0)
        let target = SIMD3<Float>(5, 3, -2)

        for _ in 0..<200 {
            pos = ImmersiveControlsPolicy.smoothedPosition(current: pos, target: target)
        }

        #expect(abs(pos.x - target.x) < 0.01)
        #expect(abs(pos.y - target.y) < 0.01)
        #expect(abs(pos.z - target.z) < 0.01)
    }

    @Test("smoothedPosition is closer to target than current after one step")
    func smoothedPositionIsCloser() {
        let current = SIMD3<Float>(0, 0, 0)
        let target = SIMD3<Float>(10, 5, -8)
        let result = ImmersiveControlsPolicy.smoothedPosition(current: current, target: target)

        let distBefore = simd_length(target - current)
        let distAfter = simd_length(target - result)
        #expect(distAfter < distBefore)
    }

    @Test("smoothedPosition handles negative coordinates")
    func smoothedPositionNegativeCoordinates() {
        let current = SIMD3<Float>(-5, -3, -10)
        let target = SIMD3<Float>(-1, -1, -2)
        let result = ImmersiveControlsPolicy.smoothedPosition(current: current, target: target)

        // Result should be between current and target for each component.
        #expect(result.x > current.x && result.x < target.x)
        #expect(result.y > current.y && result.y < target.y)
        #expect(result.z > current.z && result.z < target.z)
    }
}
