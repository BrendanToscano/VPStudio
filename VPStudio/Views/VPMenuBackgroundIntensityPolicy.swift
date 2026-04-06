import Foundation

enum VPMenuBackgroundIntensityPolicy {
    static let appStorageKey = "settings.menu_background_intensity"
    static let defaultValue = 1.0
    static let minValue = 0.0
    static let maxValue = 1.0
    static let range = minValue...maxValue

    static func clamped(_ value: Double) -> Double {
        min(max(value, minValue), maxValue)
    }

    static func percentageLabel(for value: Double) -> String {
        "\(Int((clamped(value) * 100).rounded()))%"
    }
}
