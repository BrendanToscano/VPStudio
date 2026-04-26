import SwiftUI

enum SettingsRowIndicatorPolicy {
    enum StatusKind: Equatable, Sendable {
        case configured
        case warning
        case unconfigured
        case disabled
    }

    static func indicatorColor(for status: StatusKind) -> Color {
        switch status {
        case .configured:
            return .green
        case .warning:
            return .orange
        case .unconfigured:
            return .gray
        case .disabled:
            return .clear
        }
    }

    static func shouldShowIndicator(for status: StatusKind) -> Bool {
        status != .disabled
    }

    /// Maps from the existing `SettingsStatusKind` used in `SettingsStatusFormatter`
    /// to the new `StatusKind` used for row indicators.
    static func statusKind(from settingsStatusKind: SettingsStatusKind) -> StatusKind {
        switch settingsStatusKind {
        case .positive:
            return .configured
        case .warning:
            return .warning
        case .neutral:
            return .unconfigured
        }
    }
}
