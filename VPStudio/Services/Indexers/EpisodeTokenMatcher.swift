import Foundation

enum EpisodeTokenMatcher {
    struct Context: Equatable, Sendable {
        let season: Int
        let episode: Int
    }

    private struct Pattern {
        let regex: NSRegularExpression

        init(_ pattern: String) {
            regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }

    private static let seasonEpisodePattern = Pattern(#"s\s*(\d{1,2})\s*e\s*(\d{1,3})"#)
    private static let seasonByEpisodePattern = Pattern(#"(?<!\d)(\d{1,2})\s*x\s*(\d{1,3})(?!\d)"#)
    private static let seasonEpisodeWordsPattern = Pattern(#"season\D*(\d{1,2}).{0,20}episode\D*(\d{1,3})"#)
    private static let allPatterns = [
        seasonEpisodePattern,
        seasonByEpisodePattern,
        seasonEpisodeWordsPattern,
    ]

    nonisolated static func context(fromQuery query: String) -> Context? {
        context(in: query.lowercased())
    }

    nonisolated static func matches(title: String, season: Int, episode: Int) -> Bool {
        guard let context = context(in: title.lowercased()) else { return false }
        return context.season == season && context.episode == episode
    }

    nonisolated static func matchesIfPresent(title: String, season: Int, episode: Int) -> Bool {
        guard let context = context(in: title.lowercased()) else { return true }
        return context.season == season && context.episode == episode
    }

    nonisolated private static func context(in normalizedValue: String) -> Context? {
        for pattern in allPatterns {
            if let match = firstMatch(using: pattern.regex, in: normalizedValue) {
                return Context(season: match.0, episode: match.1)
            }
        }
        return nil
    }

    nonisolated private static func firstMatch(using regex: NSRegularExpression, in value: String) -> (Int, Int)? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              match.numberOfRanges >= 3,
              let firstRange = Range(match.range(at: 1), in: value),
              let secondRange = Range(match.range(at: 2), in: value),
              let first = Int(value[firstRange]),
              let second = Int(value[secondRange]) else {
            return nil
        }
        return (first, second)
    }
}
