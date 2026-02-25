import CoreGraphics
import Testing
@testable import VPStudio

// MARK: - NavigationLayout Enum

@Suite("NavigationLayout - Enum Contract")
struct NavigationLayoutEnumTests {

    @Test func bottomTabBarRawValue() {
        #expect(NavigationLayout.bottomTabBar.rawValue == "bottom")
    }

    @Test func leftSidebarRawValue() {
        #expect(NavigationLayout.leftSidebar.rawValue == "sidebar")
    }

    @Test func allCasesCountIsTwo() {
        #expect(NavigationLayout.allCases.count == 2)
    }

    @Test func initFromRawValueBottom() {
        #expect(NavigationLayout(rawValue: "bottom") == .bottomTabBar)
    }

    @Test func initFromRawValueSidebar() {
        #expect(NavigationLayout(rawValue: "sidebar") == .leftSidebar)
    }

    @Test func initFromInvalidRawValueReturnsNil() {
        #expect(NavigationLayout(rawValue: "top") == nil)
        #expect(NavigationLayout(rawValue: "") == nil)
        #expect(NavigationLayout(rawValue: "BOTTOM") == nil)
    }

    @Test func displayNameBottomTabBar() {
        #expect(NavigationLayout.bottomTabBar.displayName == "Bottom Tab Bar")
    }

    @Test func displayNameLeftSidebar() {
        #expect(NavigationLayout.leftSidebar.displayName == "Left Sidebar")
    }

    @Test func isSendable() {
        let layout: NavigationLayout = .bottomTabBar
        let _: any Sendable = layout
    }
}

// MARK: - NavigationChromePolicy

@Suite("NavigationChromePolicy - Layout Routing")
struct NavigationChromePolicyTests {

    @Test func bottomLayoutUsesBottomTabBar() {
        #expect(NavigationChromePolicy.usesBottomTabBar(for: .bottomTabBar) == true)
    }

    @Test func bottomLayoutDoesNotUseSidebar() {
        #expect(NavigationChromePolicy.usesSidebar(for: .bottomTabBar) == false)
    }

    @Test func sidebarLayoutUsesSidebar() {
        #expect(NavigationChromePolicy.usesSidebar(for: .leftSidebar) == true)
    }

    @Test func sidebarLayoutDoesNotUseBottomTabBar() {
        #expect(NavigationChromePolicy.usesBottomTabBar(for: .leftSidebar) == false)
    }

    @Test(arguments: NavigationLayout.allCases)
    func layoutsAreMutuallyExclusive(layout: NavigationLayout) {
        let usesBottom = NavigationChromePolicy.usesBottomTabBar(for: layout)
        let usesSidebar = NavigationChromePolicy.usesSidebar(for: layout)
        #expect(usesBottom != usesSidebar, "Bottom and sidebar should be mutually exclusive")
    }
}

// MARK: - AppState Default

@Suite("NavigationLayout - AppState Defaults")
struct NavigationLayoutAppStateTests {

    @Test @MainActor func defaultLayoutIsBottomTabBar() {
        let state = AppState(testHooks: .init())
        #expect(state.navigationLayout == .bottomTabBar)
    }

    @Test @MainActor func layoutCanBeSetToSidebar() {
        let state = AppState(testHooks: .init())
        state.navigationLayout = .leftSidebar
        #expect(state.navigationLayout == .leftSidebar)
    }

    @Test @MainActor func layoutCanBeToggledBack() {
        let state = AppState(testHooks: .init())
        state.navigationLayout = .leftSidebar
        state.navigationLayout = .bottomTabBar
        #expect(state.navigationLayout == .bottomTabBar)
    }
}

// MARK: - Settings Key

@Suite("NavigationLayout - Settings Key")
struct NavigationLayoutSettingsKeyTests {

    @Test func settingsKeyExists() {
        #expect(SettingsKeys.navigationLayout == "navigation_layout")
    }

    @Test func settingsKeyIsNotEmpty() {
        #expect(!SettingsKeys.navigationLayout.isEmpty)
    }
}

// MARK: - Sidebar Layout Policy

@Suite("SidebarLayoutPolicy")
struct SidebarLayoutPolicyTests {

    @Test func collapsedWidthIsPositive() {
        #expect(SidebarLayoutPolicy.collapsedWidth > 0)
        #expect(SidebarLayoutPolicy.collapsedWidth == 52)
    }

    @Test func expandedWidthIsGreaterThanCollapsed() {
        #expect(SidebarLayoutPolicy.expandedWidth > SidebarLayoutPolicy.collapsedWidth)
    }

    @Test func cornerRadiusIsPositive() {
        #expect(SidebarLayoutPolicy.cornerRadius > 0)
    }

    @Test func sidebarMainTabsExcludesEnvironments() {
        #expect(!SidebarLayoutPolicy.sidebarMainTabs.contains(.environments))
    }

    @Test func sidebarMainTabsExcludesSettings() {
        #expect(!SidebarLayoutPolicy.sidebarMainTabs.contains(.settings))
    }

    @Test func sidebarMainTabsContainsCoreNavTabs() {
        #expect(SidebarLayoutPolicy.sidebarMainTabs.contains(.discover))
        #expect(SidebarLayoutPolicy.sidebarMainTabs.contains(.search))
        #expect(SidebarLayoutPolicy.sidebarMainTabs.contains(.library))
        #expect(SidebarLayoutPolicy.sidebarMainTabs.contains(.downloads))
    }

    @Test func sidebarMainTabsCountIsFour() {
        #expect(SidebarLayoutPolicy.sidebarMainTabs.count == 4)
    }
}

// MARK: - BottomTabRoutingPolicy Compatibility

@Suite("NavigationLayout - BottomTabRoutingPolicy Compatibility")
struct NavigationLayoutRoutingCompatibilityTests {

    @Test(arguments: SidebarTab.allCases)
    func routingPolicyWorksWithBothLayouts(tab: SidebarTab) {
        // BottomTabRoutingPolicy is layout-agnostic — it should work for both layouts
        let withPicker = BottomTabRoutingPolicy.action(for: tab, opensEnvironmentPicker: true)
        let withoutPicker = BottomTabRoutingPolicy.action(for: tab, opensEnvironmentPicker: false)

        if tab == .environments {
            #expect(withPicker == .openEnvironmentPicker)
            #expect(withoutPicker == .select(.environments))
        } else {
            #expect(withPicker == .select(tab))
            #expect(withoutPicker == .select(tab))
        }
    }
}
