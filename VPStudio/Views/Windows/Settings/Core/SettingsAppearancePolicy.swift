import Foundation

enum SettingsAppearancePolicy {
    static func normalizedMenuBackgroundIntensity(_ rawValue: Double) -> Double {
        VPMenuBackgroundIntensityPolicy.clamped(rawValue)
    }

    static func menuBackgroundIntensityLabel(for rawValue: Double) -> String {
        VPMenuBackgroundIntensityPolicy.percentageLabel(for: normalizedMenuBackgroundIntensity(rawValue))
    }
}
