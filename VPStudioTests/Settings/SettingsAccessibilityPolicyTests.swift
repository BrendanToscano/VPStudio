import Testing
@testable import VPStudio

@Suite("SettingsAccessibilityPolicy")
struct SettingsAccessibilityPolicyTests {

    // MARK: - Row Label

    @Test
    func rowLabelWithStatusIncludesBoth() {
        let label = SettingsAccessibilityPolicy.rowLabel(title: "Real-Debrid", status: "Connected")
        #expect(label == "Real-Debrid, Connected")
    }

    @Test
    func rowLabelWithoutStatusIsJustTitle() {
        let label = SettingsAccessibilityPolicy.rowLabel(title: "TMDB API Key", status: nil)
        #expect(label == "TMDB API Key")
    }

    @Test
    func rowLabelWithEmptyStatusIsJustTitle() {
        let label = SettingsAccessibilityPolicy.rowLabel(title: "Indexers", status: "")
        #expect(label == "Indexers")
    }

    // MARK: - Row Hint

    @Test
    func rowHintWithWarningIndicatesAttention() {
        let hint = SettingsAccessibilityPolicy.rowHint(hasWarning: true)
        #expect(hint == "Needs attention")
    }

    @Test
    func rowHintWithoutWarningIndicatesTapToConfigure() {
        let hint = SettingsAccessibilityPolicy.rowHint(hasWarning: false)
        #expect(hint == "Tap to configure")
    }

    // MARK: - Section Label

    @Test
    func sectionLabelFormatsCorrectly() {
        let label = SettingsAccessibilityPolicy.sectionLabel(
            title: "Indexers",
            configuredCount: 3,
            totalCount: 5
        )
        #expect(label == "Indexers, 3 of 5 configured")
    }
}
