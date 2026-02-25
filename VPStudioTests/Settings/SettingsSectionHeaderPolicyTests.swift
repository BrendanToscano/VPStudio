import Testing
@testable import VPStudio

@Suite("Settings Section Header Policy")
struct SettingsSectionHeaderPolicyTests {
    @Test
    func eachCategoryHasValidIcon() {
        for category in SettingsCategory.allCases {
            let icon = SettingsSectionHeaderPolicy.icon(for: category)
            #expect(!icon.isEmpty, "Icon for \(category) should not be empty")
        }
    }

    @Test
    func servicesIconIsServerRack() {
        #expect(SettingsSectionHeaderPolicy.icon(for: .services) == "server.rack")
    }

    @Test
    func summaryTextFormatting() {
        let text = SettingsSectionHeaderPolicy.summaryText(
            category: .services,
            configuredCount: 2,
            totalCount: 3
        )
        #expect(text == "2/3 configured")
    }

    @Test
    func summaryTextZeroConfigured() {
        let text = SettingsSectionHeaderPolicy.summaryText(
            category: .playback,
            configuredCount: 0,
            totalCount: 4
        )
        #expect(text == "0/4 configured")
    }

    @Test
    func summaryTextZeroTotalReturnsNoItems() {
        let text = SettingsSectionHeaderPolicy.summaryText(
            category: .sync,
            configuredCount: 0,
            totalCount: 0
        )
        #expect(text == "No items")
    }
}
