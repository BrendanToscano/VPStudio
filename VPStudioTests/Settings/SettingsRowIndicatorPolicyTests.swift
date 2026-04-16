import SwiftUI
import Testing
@testable import VPStudio

@Suite("Settings Row Indicator Policy")
struct SettingsRowIndicatorPolicyTests {
    @Test
    func configuredStatusReturnsGreen() {
        let color = SettingsRowIndicatorPolicy.indicatorColor(for: .configured)
        #expect(color == .green)
    }

    @Test
    func warningStatusReturnsOrange() {
        let color = SettingsRowIndicatorPolicy.indicatorColor(for: .warning)
        #expect(color == .orange)
    }

    @Test
    func unconfiguredStatusReturnsGray() {
        let color = SettingsRowIndicatorPolicy.indicatorColor(for: .unconfigured)
        #expect(color == .gray)
    }

    @Test
    func disabledStatusReturnsClear() {
        let color = SettingsRowIndicatorPolicy.indicatorColor(for: .disabled)
        #expect(color == .clear)
    }

    @Test
    func shouldShowIndicatorTrueForVisibleStatuses() {
        #expect(SettingsRowIndicatorPolicy.shouldShowIndicator(for: .configured) == true)
        #expect(SettingsRowIndicatorPolicy.shouldShowIndicator(for: .warning) == true)
        #expect(SettingsRowIndicatorPolicy.shouldShowIndicator(for: .unconfigured) == true)
    }

    @Test
    func shouldShowIndicatorFalseForDisabled() {
        #expect(SettingsRowIndicatorPolicy.shouldShowIndicator(for: .disabled) == false)
    }
}
