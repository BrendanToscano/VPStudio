import Foundation

/// Pure-logic policy for VoiceOver labels and hints on tab bar buttons.
///
/// Ensures every tab has a descriptive label (including selection state)
/// and a brief hint explaining what activating the tab will do.
enum TabBarAccessibilityPolicy {

    /// Accessibility label for a tab button, incorporating selection state.
    ///
    /// - Returns: e.g. `"Discover, Selected"` or `"Settings"`.
    static func accessibilityLabel(for tab: SidebarTab, isSelected: Bool) -> String {
        if isSelected {
            return "\(tab.rawValue), Selected"
        }
        return tab.rawValue
    }

    /// Accessibility hint describing what will happen when the tab is activated.
    static func accessibilityHint(for tab: SidebarTab) -> String {
        switch tab {
        case .discover:
            return "Browse featured and trending content"
        case .search:
            return "Search for movies and TV shows"
        case .library:
            return "View your saved media library"
        case .downloads:
            return "View and manage active downloads"
        case .environments:
            return "Choose an immersive environment"
        case .settings:
            return "Configure app preferences and accounts"
        }
    }
}
