import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SearchViewModelAITests {

    // MARK: - Helpers

    /// Polls until the condition is true or the timeout expires.
    @MainActor
    private static func waitUntil(
        timeout: Duration = .milliseconds(5000),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("waitUntil timed out after \(timeout)")
                return
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Builds a stub AI provider that returns a canned JSON recommendation array.
    private static func makeStubProvider() -> StubAIProvider {
        let jsonResponse = """
        [{"title":"AI Pick","year":2025,"type":"movie","reason":"Tailored","tmdbId":999}]
        """
        return StubAIProvider(
            providerKind: .anthropic,
            result: .success(AIProviderResponse(
                provider: .anthropic,
                content: jsonResponse,
                model: "test",
                inputTokens: 0,
                outputTokens: 0
            ))
        )
    }

    /// Creates an `AIAssistantManager` backed by an in-memory database.
    private static func makeAIManager() async throws -> AIAssistantManager {
        let db = try DatabaseManager(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-ai-\(UUID().uuidString).sqlite").path)
        try await db.migrate()
        return AIAssistantManager(database: db)
    }

    // MARK: - Test 1: Empty query sets isLoadingAI true initially

    @Test
    @MainActor
    func fetchWithEmptyQuerySetsIsLoadingAITrue() async throws {
        let aiManager = try await Self.makeAIManager()
        let stubProvider = Self.makeStubProvider()
        await aiManager.registerProvider(kind: .anthropic, provider: stubProvider)

        let viewModel = SearchViewModel()
        viewModel.query = ""

        viewModel.fetchAIRecommendations(aiManager: aiManager)

        // Synchronous check — isLoadingAI should be true immediately after calling fetch.
        #expect(viewModel.isLoadingAI == true)

        // Wait for the async task to finish so we don't leak.
        try await Self.waitUntil { !viewModel.isLoadingAI }
    }

    // MARK: - Test 2: Query passes mood hint and loads recommendations

    @Test
    @MainActor
    func fetchWithQueryPassesMoodHintAndLoadsRecommendations() async throws {
        let aiManager = try await Self.makeAIManager()
        let stubProvider = Self.makeStubProvider()
        await aiManager.registerProvider(kind: .anthropic, provider: stubProvider)

        let viewModel = SearchViewModel()
        viewModel.query = "dark thriller"

        viewModel.fetchAIRecommendations(aiManager: aiManager)

        try await Self.waitUntil { !viewModel.aiRecommendations.isEmpty }
        #expect(viewModel.aiRecommendations.count == 1)
        #expect(viewModel.aiRecommendations[0].title == "AI Pick")
        #expect(viewModel.aiRecommendations[0].tmdbId == 999)
        #expect(viewModel.isLoadingAI == false)
        #expect(viewModel.aiError == nil)
    }

    // MARK: - Test 3: No provider registered sets aiError

    @Test
    @MainActor
    func fetchWithNoProviderSetsAIError() async throws {
        let aiManager = try await Self.makeAIManager()
        // No provider registered — should trigger AIError.noProviderConfigured

        let viewModel = SearchViewModel()
        viewModel.query = "anything"
        viewModel.fetchAIRecommendations(aiManager: aiManager)

        try await Self.waitUntil { viewModel.aiError != nil }
        #expect(viewModel.aiError == "No AI provider configured. Set one up in Settings \u{2192} AI Assistant.")
        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.isLoadingAI == false)
    }

    // MARK: - Test 4: explorePhase returns .results when isLoadingAI is true

    @Test
    @MainActor
    func explorePhaseIsResultsWhenLoadingAI() {
        let viewModel = SearchViewModel()
        // No query, no results, no genre — only isLoadingAI is true.
        viewModel.isLoadingAI = true

        #expect(viewModel.explorePhase == .results)
    }

    // MARK: - Test 5: explorePhase returns .idle by default

    @Test
    @MainActor
    func explorePhaseIsIdleByDefault() {
        let viewModel = SearchViewModel()

        #expect(viewModel.explorePhase == .idle)
        #expect(viewModel.query.isEmpty)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.isLoadingAI == false)
    }

    // MARK: - Test 6: clearAIRecommendations resets all AI state

    @Test
    @MainActor
    func clearAIRecommendationsResetsAllAIState() {
        let viewModel = SearchViewModel()

        // Simulate populated AI state.
        viewModel.aiRecommendations = [
            AIMovieRecommendation(title: "Rec1", year: 2025, type: .movie, reason: "Good", tmdbId: 1),
            AIMovieRecommendation(title: "Rec2", year: 2024, type: .series, reason: "Great", tmdbId: 2),
        ]
        viewModel.aiError = "some error"
        viewModel.isLoadingAI = true

        viewModel.clearAIRecommendations()

        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.aiError == nil)
        #expect(viewModel.isLoadingAI == false)
    }

    // MARK: - Test 7: Empty query still produces recommendations

    @Test
    @MainActor
    func fetchWithEmptyQueryStillProducesRecommendations() async throws {
        let aiManager = try await Self.makeAIManager()
        let stubProvider = Self.makeStubProvider()
        await aiManager.registerProvider(kind: .anthropic, provider: stubProvider)

        let viewModel = SearchViewModel()
        viewModel.query = "   " // whitespace-only, trimmed to empty

        viewModel.fetchAIRecommendations(aiManager: aiManager)

        // The key behavior change: empty/whitespace query does NOT short-circuit.
        // It proceeds to fetch recommendations (with nil moodHint).
        try await Self.waitUntil { !viewModel.aiRecommendations.isEmpty }
        #expect(viewModel.aiRecommendations.count == 1)
        #expect(viewModel.aiRecommendations[0].title == "AI Pick")
        #expect(viewModel.aiRecommendations[0].year == 2025)
        #expect(viewModel.aiRecommendations[0].type == .movie)
        #expect(viewModel.aiRecommendations[0].reason == "Tailored")
        #expect(viewModel.isLoadingAI == false)
        #expect(viewModel.aiError == nil)
    }
}
