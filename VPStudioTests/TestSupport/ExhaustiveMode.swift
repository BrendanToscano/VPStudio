import Foundation

enum ExhaustiveMode {
    private static let keys = ["VPSTUDIO_EXHAUSTIVE", "CI_EXHAUSTIVE", "EXHAUSTIVE"]

    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return keys.contains { key in
            guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return false
            }
            return value == "1" || value == "true" || value == "yes" || value == "on"
        }
    }

    static func choose<T>(fast: [T], full: [T]) -> [T] {
        isEnabled ? full : fast
    }

    static func repeatCount(fast: Int, full: Int) -> Int {
        isEnabled ? full : fast
    }
}
