import Foundation

enum PlayerCapabilityWarningPolicy {
    static let maxInlineWarnings = 1
    static let maxInlineCharacters = 72

    static func inlineMessage(for warnings: [String]) -> String? {
        guard let first = warnings.first else { return nil }
        return truncated(first)
    }

    static func overflowCount(for warnings: [String]) -> Int {
        max(0, warnings.count - maxInlineWarnings)
    }

    private static func truncated(_ warning: String) -> String {
        guard warning.count > maxInlineCharacters else { return warning }
        let endIndex = warning.index(warning.startIndex, offsetBy: maxInlineCharacters - 1)
        return warning[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
