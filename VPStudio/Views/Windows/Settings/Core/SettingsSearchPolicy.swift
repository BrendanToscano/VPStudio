import Foundation

enum SettingsSearchPolicy {
    private static let knownTerms: [String] = [
        "debrid", "indexers", "tmdb", "playback", "subtitles",
        "environments", "ai", "trakt", "simkl", "openai",
        "anthropic", "ollama", "provider", "api key", "hdr",
    ]

    static func suggestions(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return knownTerms.filter { $0.hasPrefix(trimmed) || $0.contains(trimmed) }
    }

    static func resultsSummary(count: Int, query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "\(count) settings"
        }
        if count == 1 {
            return "1 result for \"\(trimmed)\""
        }
        return "\(count) results for \"\(trimmed)\""
    }

    static func shouldShowEmptyState(resultCount: Int, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return resultCount == 0 && !trimmed.isEmpty
    }
}
