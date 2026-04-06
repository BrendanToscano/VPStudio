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
    func connectIconIsLink() {
        #expect(SettingsSectionHeaderPolicy.icon(for: .connect) == "link")
    }

    @Test
    func summaryTextFormatting() {
        let text = SettingsSectionHeaderPolicy.summaryText(
            category: .connect,
            configuredCount: 2,
            totalCount: 3
        )
        #expect(text == "2/3 configured")
    }

    @Test
    func summaryTextZeroConfigured() {
        let text = SettingsSectionHeaderPolicy.summaryText(
            category: .watch,
            configuredCount: 0,
            totalCount: 4
        )
        #expect(text == "0/4 configured")
    }

    @Test
    func summaryTextZeroTotalReturnsNoItems() {
        let text = SettingsSectionHeaderPolicy.summaryText(
            category: .about,
            configuredCount: 0,
            totalCount: 0
        )
        #expect(text == "No items")
    }
}
