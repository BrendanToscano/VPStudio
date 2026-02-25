import Testing
@testable import VPStudio

@Suite("Settings Search Policy")
struct SettingsSearchPolicyTests {
    @Test
    func suggestionsEmptyForEmptyQuery() {
        let suggestions = SettingsSearchPolicy.suggestions(for: "")
        #expect(suggestions.isEmpty)
    }

    @Test
    func suggestionsPartialMatchReturnsCandidates() {
        let suggestions = SettingsSearchPolicy.suggestions(for: "deb")
        #expect(suggestions.contains("debrid"))
    }

    @Test
    func resultsSummarySingularFormatting() {
        let summary = SettingsSearchPolicy.resultsSummary(count: 1, query: "tmdb")
        #expect(summary == "1 result for \"tmdb\"")
    }

    @Test
    func resultsSummaryPluralFormatting() {
        let summary = SettingsSearchPolicy.resultsSummary(count: 3, query: "play")
        #expect(summary == "3 results for \"play\"")
    }

    @Test
    func emptyStateVisibleWhenNoResultsAndQueryPresent() {
        #expect(SettingsSearchPolicy.shouldShowEmptyState(resultCount: 0, query: "xyz") == true)
        #expect(SettingsSearchPolicy.shouldShowEmptyState(resultCount: 0, query: "") == false)
        #expect(SettingsSearchPolicy.shouldShowEmptyState(resultCount: 1, query: "xyz") == false)
    }
}
