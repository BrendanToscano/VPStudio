import Testing
@testable import VPStudio

struct VPMenuBackgroundIntensityPolicyTests {
    @Test func clampReturnsMinForLowerValues() {
        let clamped = VPMenuBackgroundIntensityPolicy.clamped(-0.5)
        #expect(clamped == VPMenuBackgroundIntensityPolicy.minValue)
    }

    @Test func clampReturnsMaxForHigherValues() {
        let clamped = VPMenuBackgroundIntensityPolicy.clamped(2.0)
        #expect(clamped == VPMenuBackgroundIntensityPolicy.maxValue)
    }

    @Test func clampPassesThroughInRangeValues() {
        let value = 0.42
        let clamped = VPMenuBackgroundIntensityPolicy.clamped(value)
        #expect(clamped == value)
    }

    @Test func percentageLabelUsesClampedValue() {
        #expect(VPMenuBackgroundIntensityPolicy.percentageLabel(for: -1.0) == "0%")
        #expect(VPMenuBackgroundIntensityPolicy.percentageLabel(for: 1.0) == "100%")
        #expect(VPMenuBackgroundIntensityPolicy.percentageLabel(for: 2.0) == "100%")
    }
}
