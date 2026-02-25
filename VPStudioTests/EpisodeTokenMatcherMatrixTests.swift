import Foundation
import Testing
@testable import VPStudio

@Suite("Episode Token Matcher Matrix")
struct EpisodeTokenMatcherMatrixTests {
    struct ContextCase: Sendable {
        let query: String
        let expected: EpisodeTokenMatcher.Context?
    }

    struct MatchCase: Sendable {
        let title: String
        let season: Int
        let episode: Int
        let expected: Bool
    }

    private static let contextCases: [ContextCase] = {
        var cases: [ContextCase] = []
        for season in 1...10 {
            for episode in 1...7 {
                cases.append(ContextCase(query: "Show S\(season)E\(episode)", expected: .init(season: season, episode: episode)))
            }
        }
        while cases.count < 70 {
            let idx = cases.count
            let query = idx % 2 == 0 ? "Show \(idx)x\(idx + 1)" : "No episode token \(idx)"
            let expected: EpisodeTokenMatcher.Context? = idx % 2 == 0 ? .init(season: idx, episode: idx + 1) : nil
            cases.append(ContextCase(query: query, expected: expected))
        }
        return Array(cases.prefix(70))
    }()

    private static let matchCases: [MatchCase] = {
        var cases: [MatchCase] = []
        for season in 1...10 {
            for episode in 1...7 {
                cases.append(MatchCase(title: "Series.Name.S\(String(format: "%02d", season))E\(String(format: "%02d", episode)).1080p", season: season, episode: episode, expected: true))
            }
        }
        return Array(cases.prefix(70))
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(contextCases.prefix(20)), full: contextCases))
    func contextExtractionMatrix(data: ContextCase) {
        let context = EpisodeTokenMatcher.context(fromQuery: data.query)
        #expect(context == data.expected)
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(matchCases.prefix(20)), full: matchCases))
    func matchMatrix(data: MatchCase) {
        let result = EpisodeTokenMatcher.matches(
            title: data.title,
            season: data.season,
            episode: data.episode
        )
        #expect(result == data.expected)

        let mismatch = EpisodeTokenMatcher.matches(
            title: data.title,
            season: data.season,
            episode: data.episode + 1
        )
        #expect(mismatch == false)
    }
}
