import Foundation

enum EpisodeTokenMatcher {
    struct Context: Equatable, Sendable {
        let season: Int
        let episode: Int
    }

    nonisolated static func context(fromQuery query: String) -> Context? {
        let normalized = query.lowercased()

        if let match = firstMatch(
            pattern: #"s\s*(\d{1,2})\s*e\s*(\d{1,3})"#,
            in: normalized
        ) {
            return Context(season: match.0, episode: match.1)
        }

        if let match = firstMatch(
            pattern: #"(\d{1,2})\s*x\s*(\d{1,3})"#,
            in: normalized
        ) {
            return Context(season: match.0, episode: match.1)
        }

        return nil
    }

    nonisolated static func matches(title: String, season: Int, episode: Int) -> Bool {
        let normalized = title.lowercased()

        if let match = firstMatch(
            pattern: #"s\s*(\d{1,2})\s*e\s*(\d{1,3})"#,
            in: normalized
        ) {
            return match.0 == season && match.1 == episode
        }

        if let match = firstMatch(
            pattern: #"(\d{1,2})\s*x\s*(\d{1,3})"#,
            in: normalized
        ) {
            return match.0 == season && match.1 == episode
        }

        if let match = firstMatch(
            pattern: #"season\D*(\d{1,2}).{0,20}episode\D*(\d{1,3})"#,
            in: normalized
        ) {
            return match.0 == season && match.1 == episode
        }

        return false
    }

    nonisolated private static func firstMatch(pattern: String, in value: String) -> (Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
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
