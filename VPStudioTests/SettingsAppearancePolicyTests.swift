import Testing
@testable import VPStudio

struct SettingsAppearancePolicyTests {
    @Test
    func normalizedMenuBackgroundIntensityClampsLowValues() {
        #expect(SettingsAppearancePolicy.normalizedMenuBackgroundIntensity(-1.0) == 0.0)
    }

    @Test
    func normalizedMenuBackgroundIntensityClampsHighValues() {
        #expect(SettingsAppearancePolicy.normalizedMenuBackgroundIntensity(2.0) == 1.0)
    }

    @Test
    func menuBackgroundIntensityLabelUsesClampedValue() {
        #expect(SettingsAppearancePolicy.menuBackgroundIntensityLabel(for: -0.25) == "0%")
        #expect(SettingsAppearancePolicy.menuBackgroundIntensityLabel(for: 0.5) == "50%")
        #expect(SettingsAppearancePolicy.menuBackgroundIntensityLabel(for: 1.8) == "100%")
    }
}
