import Foundation

enum DiscoverRefreshReason: String, Sendable, Equatable {
    case tabReselected = "tab_reselected"
    case returnedToDiscover = "returned_to_discover"
    case setupCompleted = "setup_completed"
}

struct TabSelectionEvent: Sendable, Equatable {
    let previousTab: SidebarTab
    let selectedTab: SidebarTab

    var isReselection: Bool {
        previousTab == selectedTab
    }

    var notificationUserInfo: [String: Any] {
        [
            AppNotificationUserInfoKey.previousTab: previousTab.rawValue,
            AppNotificationUserInfoKey.selectedTab: selectedTab.rawValue,
        ]
    }
}

enum DiscoverRefreshTriggerPolicy {
    static func reason(for event: TabSelectionEvent) -> DiscoverRefreshReason? {
        guard event.selectedTab == .discover else { return nil }
        return event.isReselection ? .tabReselected : .returnedToDiscover
    }
}

enum OnboardingPresentationPolicy {
    static func shouldAutoPresentSetup(
        setupRecommendationNeeded: Bool,
        hasCompletedOnboarding: Bool
    ) -> Bool {
        setupRecommendationNeeded && !hasCompletedOnboarding
    }
}

enum AppNotificationUserInfoKey {
    static let previousTab = "previousTab"
    static let selectedTab = "selectedTab"
    static let discoverRefreshReason = "discoverRefreshReason"
    static let setupRecommendationNeeded = "setupRecommendationNeeded"
}

extension DiscoverRefreshReason {
    var notificationUserInfo: [String: Any] {
        [AppNotificationUserInfoKey.discoverRefreshReason: rawValue]
    }
}

extension Notification {
    var tabSelectionEvent: TabSelectionEvent? {
        guard let userInfo,
              let previousRaw = userInfo[AppNotificationUserInfoKey.previousTab] as? String,
              let selectedRaw = userInfo[AppNotificationUserInfoKey.selectedTab] as? String,
              let previousTab = SidebarTab(rawValue: previousRaw),
              let selectedTab = SidebarTab(rawValue: selectedRaw) else {
            return nil
        }
        return TabSelectionEvent(previousTab: previousTab, selectedTab: selectedTab)
    }

    var discoverRefreshReason: DiscoverRefreshReason? {
        guard let userInfo,
              let raw = userInfo[AppNotificationUserInfoKey.discoverRefreshReason] as? String else {
            return nil
        }
        return DiscoverRefreshReason(rawValue: raw)
    }
}
