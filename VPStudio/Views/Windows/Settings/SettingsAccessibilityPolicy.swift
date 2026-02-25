import Foundation

/// Pure-logic policy for VoiceOver labels and hints on settings rows and sections.
///
/// Constructs composite accessibility strings so VoiceOver reads meaningful
/// context without requiring the user to explore each element individually.
enum SettingsAccessibilityPolicy {

    /// Accessibility label for a settings row, optionally including status text.
    ///
    /// - Returns: e.g. `"Real-Debrid, Connected"` or `"TMDB API Key"`.
    static func rowLabel(title: String, status: String?) -> String {
        if let status, !status.isEmpty {
            return "\(title), \(status)"
        }
        return title
    }

    /// Accessibility hint for a settings row, indicating whether it needs attention.
    static func rowHint(hasWarning: Bool) -> String {
        if hasWarning {
            return "Needs attention"
        }
        return "Tap to configure"
    }

    /// Accessibility label for a settings section header, summarizing configuration progress.
    ///
    /// - Returns: e.g. `"Indexers, 3 of 5 configured"`.
    static func sectionLabel(title: String, configuredCount: Int, totalCount: Int) -> String {
        "\(title), \(configuredCount) of \(totalCount) configured"
    }
}
