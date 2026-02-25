import Testing
import SwiftUI
@testable import VPStudio

@Suite("TabBadgePolicy")
struct TabBadgePolicyTests {

    // MARK: - Downloads Badge

    @Test
    func downloadsTabShowsBadgeWhenActiveDownloadsExist() {
        let result = TabBadgePolicy.shouldShowBadge(
            for: .downloads,
            activeDownloadCount: 3,
            settingsWarningCount: 0
        )
        #expect(result == true)
    }

    @Test
    func downloadsTabHidesBadgeWhenNoActiveDownloads() {
        let result = TabBadgePolicy.shouldShowBadge(
            for: .downloads,
            activeDownloadCount: 0,
            settingsWarningCount: 0
        )
        #expect(result == false)
    }

    // MARK: - Settings Badge

    @Test
    func settingsTabShowsBadgeWhenWarningsExist() {
        let result = TabBadgePolicy.shouldShowBadge(
            for: .settings,
            activeDownloadCount: 0,
            settingsWarningCount: 2
        )
        #expect(result == true)
    }

    @Test
    func settingsTabHidesBadgeWhenNoWarnings() {
        let result = TabBadgePolicy.shouldShowBadge(
            for: .settings,
            activeDownloadCount: 0,
            settingsWarningCount: 0
        )
        #expect(result == false)
    }

    // MARK: - Other Tabs

    @Test(arguments: [SidebarTab.discover, .search, .library, .environments])
    func otherTabsNeverShowBadge(tab: SidebarTab) {
        let result = TabBadgePolicy.shouldShowBadge(
            for: tab,
            activeDownloadCount: 10,
            settingsWarningCount: 10
        )
        #expect(result == false, "Tab \(tab.rawValue) should never show a badge")
    }

    // MARK: - Badge Colors

    @Test
    func badgeColorsAreCorrectForAllTabs() {
        #expect(TabBadgePolicy.badgeColor(for: .downloads) == .red)
        #expect(TabBadgePolicy.badgeColor(for: .settings) == .orange)
        #expect(TabBadgePolicy.badgeColor(for: .discover) == .clear)
        #expect(TabBadgePolicy.badgeColor(for: .search) == .clear)
        #expect(TabBadgePolicy.badgeColor(for: .library) == .clear)
        #expect(TabBadgePolicy.badgeColor(for: .environments) == .clear)
    }
}
