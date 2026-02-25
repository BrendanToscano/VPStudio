import Foundation

enum SettingsHealthPolicy {
    static func configurationProgress(configured: Int, total: Int) -> Double {
        guard total > 0 else { return 0.0 }
        return Double(configured) / Double(total)
    }

    static func warningCount(statuses: [SettingsRowIndicatorPolicy.StatusKind]) -> Int {
        statuses.filter { $0 == .warning }.count
    }

    static func progressLabel(configured: Int, total: Int) -> String {
        "\(configured)/\(total) configured"
    }

    static func shouldShowWarningBadge(warningCount: Int) -> Bool {
        warningCount > 0
    }

    /// Returns the number of essential destinations that have a `.positive` status.
    static func essentialConfiguredCount(
        statuses: [SettingsDestination: SettingsDestinationStatus]
    ) -> Int {
        SettingsNavigationCatalog.essentialDestinations
            .filter { statuses[$0]?.kind == .positive }
            .count
    }

    /// Returns the total number of essential destinations (the denominator for health).
    static var essentialTotal: Int {
        SettingsNavigationCatalog.essentialDestinations.count
    }
}
