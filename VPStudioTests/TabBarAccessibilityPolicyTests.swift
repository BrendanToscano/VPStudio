import Testing
@testable import VPStudio

@Suite("TabBarAccessibilityPolicy")
struct TabBarAccessibilityPolicyTests {

    // MARK: - Selected Label

    @Test(arguments: SidebarTab.allCases)
    func selectedTabLabelIncludesSelected(tab: SidebarTab) {
        let label = TabBarAccessibilityPolicy.accessibilityLabel(for: tab, isSelected: true)
        #expect(label.contains("Selected"),
                "Selected label for \(tab.rawValue) should contain 'Selected'")
        #expect(label.contains(tab.rawValue),
                "Selected label should contain the tab name")
    }

    // MARK: - Unselected Label

    @Test(arguments: SidebarTab.allCases)
    func unselectedTabLabelIsJustTheTabName(tab: SidebarTab) {
        let label = TabBarAccessibilityPolicy.accessibilityLabel(for: tab, isSelected: false)
        #expect(label == tab.rawValue,
                "Unselected label should be exactly the tab rawValue")
        #expect(!label.contains("Selected"),
                "Unselected label should not contain 'Selected'")
    }

    // MARK: - Hints

    @Test(arguments: SidebarTab.allCases)
    func hintTextIsNonEmptyForAllTabs(tab: SidebarTab) {
        let hint = TabBarAccessibilityPolicy.accessibilityHint(for: tab)
        #expect(!hint.isEmpty,
                "Hint for \(tab.rawValue) must be non-empty")
    }

    @Test
    func hintsAreDistinctPerTab() {
        let hints = SidebarTab.allCases.map { TabBarAccessibilityPolicy.accessibilityHint(for: $0) }
        let uniqueHints = Set(hints)
        #expect(uniqueHints.count == SidebarTab.allCases.count,
                "Each tab should have a unique hint")
    }

    @Test
    func labelFormatIsConsistent() {
        // Verify the selected format is "Name, Selected"
        let label = TabBarAccessibilityPolicy.accessibilityLabel(for: .discover, isSelected: true)
        #expect(label == "Discover, Selected")
    }
}
