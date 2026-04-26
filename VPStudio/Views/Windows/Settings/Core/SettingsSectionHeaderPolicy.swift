import Foundation

enum SettingsSectionHeaderPolicy {
    /// Maps existing `SettingsCategory` to an SF Symbol icon name.
    static func icon(for category: SettingsCategory) -> String {
        switch category {
        case .connect:
            return "link"
        case .watch:
            return "play.circle"
        case .discover:
            return "sparkles"
        case .library:
            return "books.vertical"
        case .about:
            return "info.circle"
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
