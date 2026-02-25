import Foundation

enum SettingsSectionHeaderPolicy {
    /// Maps existing `SettingsCategory` to an SF Symbol icon name.
    static func icon(for category: SettingsCategory) -> String {
        switch category {
        case .services:
            return "server.rack"
        case .playback:
            return "play.circle"
        case .intelligence:
            return "brain"
        case .sync:
            return "arrow.triangle.2.circlepath"
        }
    }

    /// Generates a summary string like "2/3 configured" for section headers.
    static func summaryText(category: SettingsCategory, configuredCount: Int, totalCount: Int) -> String {
        guard totalCount > 0 else {
            return "No items"
        }
        return "\(configuredCount)/\(totalCount) configured"
    }
}
