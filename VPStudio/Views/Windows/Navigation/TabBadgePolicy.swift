import SwiftUI

/// Pure-logic policy determining when tab badge indicators should appear and their colors.
///
/// Each badge is a small dot overlaid on the tab icon to draw attention to actionable state:
/// - **Downloads**: red badge when active downloads are in progress.
/// - **Settings**: orange badge when configuration warnings require attention.
enum TabBadgePolicy {

    /// Returns `true` when a badge dot should be visible on the given tab.
    static func shouldShowBadge(
        for tab: SidebarTab,
        activeDownloadCount: Int,
        settingsWarningCount: Int
    ) -> Bool {
        switch tab {
        case .downloads:
            return activeDownloadCount > 0
        case .settings:
            return settingsWarningCount > 0
        default:
            return false
        }
    }

    /// The accent color of the badge dot for a given tab.
    static func badgeColor(for tab: SidebarTab) -> Color {
        switch tab {
        case .downloads: return .red
        case .settings: return .orange
        default: return .clear
        }
    }
}
