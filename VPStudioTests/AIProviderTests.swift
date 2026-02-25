import Testing
import Foundation
@testable import VPStudio

// MARK: - AIProviderKind Tests

@Suite("AIProviderKind")
struct AIProviderKindTests {

    @Test func allProvidersHaveDisplayNames() {
        for kind in AIProviderKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test func idMatchesRawValue() {
        for kind in AIProviderKind.allCases {
            #expect(kind.id == kind.rawValue)
        }
    }

    @Test func displayNamesAreCorrect() {
        #expect(AIProviderKind.openAI.displayName == "OpenAI")
        #expect(AIProviderKind.anthropic.displayName == "Anthropic")
        #expect(AIProviderKind.ollama.displayName == "Ollama")
    }

    @Test func rawValuesAreLowercase() {
        #expect(AIProviderKind.openAI.rawValue == "openai")
        #expect(AIProviderKind.anthropic.rawValue == "anthropic")
        #expect(AIProviderKind.ollama.rawValue == "ollama")
    }
}

// MARK: - AIMovieRecommendation Tests

@Suite("AIMovieRecommendation")
struct AIMovieRecommendationTests {

    @Test func idIsBasedOnTitleAndYear() {
        let rec = AIMovieRecommendation(title: "Dune", year: 2021, type: .movie, reason: "Great sci-fi")
        #expect(rec.id == "dune-2021-movie")
    }

    @Test func idHandlesNilYear() {
        let rec = AIMovieRecommendation(title: "Unknown", year: nil, type: .movie, reason: "")
        #expect(rec.id == "unknown-0-movie")
    }

    @Test func idLowercasesTitle() {
        let rec = AIMovieRecommendation(title: "The Matrix", year: 1999, type: .movie, reason: "")
        #expect(rec.id == "the matrix-1999-movie")
    }

    @Test func idUsesTmdbIdWhenAvailable() {
        let rec = AIMovieRecommendation(title: "Dune", year: 2021, type: .movie, reason: "r", tmdbId: 438631)
        #expect(rec.id == "movie-tmdb-438631")
    }
}

// MARK: - AIAssistantManager Tests

@Suite("AIAssistantManager - Recommendation Parsing")
struct AIAssistantManagerParsingTests {

    private func makeManager() async throws -> (AIAssistantManager, DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("ai-test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        let manager = AIAssistantManager(database: database)
        return (manager, database, tempDir)
    }

    @Test func askThrowsWithNoProvider() async throws {
        let (manager, _, tempDir) = try await makeManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            let _ = try await manager.ask(prompt: "test")
            Issue.record("Expected AIError.noProviderConfigured")
        } catch let error as AIError {
            if case .noProviderConfigured = error { /* OK */ }
            else { Issue.record("Unexpected AIError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}

// MARK: - AIError Tests

@Suite("AIError")
struct AIErrorTests {

    @Test func allErrorsHaveDescriptions() {
        let errors: [AIError] = [
            .noProviderConfigured,
            .invalidResponse,
            .httpError(500, "Server Error"),
            .rateLimited,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - AssistantContext Tests

@Suite("AssistantContext")
struct AssistantContextTests {

    @Test func defaultsAreEmpty() {
        let ctx = AssistantContext()
        #expect(ctx.recentlyWatched.isEmpty)
        #expect(ctx.historyTitles.isEmpty)
        #expect(ctx.favoriteGenres.isEmpty)
        #expect(ctx.dislikedGenres.isEmpty)
        #expect(ctx.currentMood == nil)
        #expect(ctx.watchlistTitles.isEmpty)
        #expect(ctx.favoriteTitles.isEmpty)
        #expect(ctx.feedbackScaleMode == nil)
        #expect(ctx.likedTitles.isEmpty)
        #expect(ctx.dislikedTitles.isEmpty)
        #expect(ctx.ratedTitles.isEmpty)
    }

    @Test func customValuesArePreserved() {
        let ctx = AssistantContext(
            recentlyWatched: ["Dune", "Blade Runner"],
            historyTitles: ["Heat"],
            favoriteGenres: ["Sci-Fi"],
            dislikedGenres: ["Horror"],
            currentMood: "adventurous",
            watchlistTitles: ["Oppenheimer"],
            favoriteTitles: ["Arrival"],
            feedbackScaleMode: .oneToTen,
            likedTitles: ["Arrival"],
            dislikedTitles: ["Saw"],
            ratedTitles: ["Arrival (9/10)"]
        )
        #expect(ctx.recentlyWatched.count == 2)
        #expect(ctx.historyTitles == ["Heat"])
        #expect(ctx.favoriteGenres == ["Sci-Fi"])
        #expect(ctx.currentMood == "adventurous")
        #expect(ctx.watchlistTitles == ["Oppenheimer"])
        #expect(ctx.favoriteTitles == ["Arrival"])
        #expect(ctx.feedbackScaleMode == .oneToTen)
        #expect(ctx.likedTitles == ["Arrival"])
        #expect(ctx.dislikedTitles == ["Saw"])
        #expect(ctx.ratedTitles == ["Arrival (9/10)"])
    }
}

// MARK: - AICompareResult Tests

@Suite("AICompareResult")
struct AICompareResultTests {

    @Test func storesResponsesAndErrors() {
        let response = AIProviderResponse(provider: .openAI, content: "Hello", model: "gpt-4o", inputTokens: 10, outputTokens: 5)
        let result = AICompareResult(
            prompt: "Test prompt",
            responses: [.openAI: response],
            errors: [.anthropic: "Connection timeout"]
        )
        #expect(result.prompt == "Test prompt")
        #expect(result.responses.count == 1)
        #expect(result.errors.count == 1)
        #expect(result.responses[.openAI]?.content == "Hello")
        #expect(result.errors[.anthropic] == "Connection timeout")
    }
}

// MARK: - AI Provider Init Tests

@Suite("AI Provider Initialization")
struct AIProviderInitTests {

    @Test func anthropicDefaultModel() {
        let provider = AnthropicProvider(apiKey: "test-key")
        #expect(provider.providerKind == .anthropic)
    }

    @Test func openAIDefaultModel() {
        let provider = OpenAIProvider(apiKey: "test-key")
        #expect(provider.providerKind == .openAI)
    }

    @Test func ollamaDefaultModel() {
        let provider = OllamaProvider()
        #expect(provider.providerKind == .ollama)
    }
}

// MARK: - AIProviderResponse Tests

@Suite("AIProviderResponse")
struct AIProviderResponseTests {

    @Test func storesAllFields() {
        let r = AIProviderResponse(provider: .anthropic, content: "Test content", model: "claude-sonnet-4-20250514", inputTokens: 100, outputTokens: 200)
        #expect(r.provider == .anthropic)
        #expect(r.content == "Test content")
        #expect(r.model == "claude-sonnet-4-20250514")
        #expect(r.inputTokens == 100)
        #expect(r.outputTokens == 200)
    }
}

// MARK: - AIPersonalizedAnalysis Tests

@Suite("AIPersonalizedAnalysis")
struct AIPersonalizedAnalysisTests {

    @Test func decodesFromJSON() throws {
        let json = """
        {
            "personalizedDescription": "A mind-bending sci-fi thriller that matches your love of cerebral storytelling.",
            "predictedRating": 8.5,
            "verdict": "strong_yes",
            "reasons": ["Matches your sci-fi preference", "Similar to Inception which you loved"]
        }
        """
        let data = json.data(using: .utf8)!
        let analysis = try JSONDecoder().decode(AIPersonalizedAnalysis.self, from: data)
        #expect(analysis.predictedRating == 8.5)
        #expect(analysis.verdict == .strongYes)
        #expect(analysis.reasons.count == 2)
        #expect(analysis.personalizedDescription.contains("mind-bending"))
    }

    @Test func allVerdictsHaveLabels() {
        let verdicts: [AIPersonalizedAnalysis.Verdict] = [.strongYes, .yes, .maybe, .no, .strongNo]
        for verdict in verdicts {
            #expect(!verdict.label.isEmpty)
            #expect(!verdict.systemImage.isEmpty)
            #expect(!verdict.tint.isEmpty)
        }
    }

    @Test func verdictRawValues() {
        #expect(AIPersonalizedAnalysis.Verdict.strongYes.rawValue == "strong_yes")
        #expect(AIPersonalizedAnalysis.Verdict.yes.rawValue == "yes")
        #expect(AIPersonalizedAnalysis.Verdict.maybe.rawValue == "maybe")
        #expect(AIPersonalizedAnalysis.Verdict.no.rawValue == "no")
        #expect(AIPersonalizedAnalysis.Verdict.strongNo.rawValue == "strong_no")
    }

    @Test func equatableConformance() {
        let a = AIPersonalizedAnalysis(
            personalizedDescription: "Great film",
            predictedRating: 9.0,
            verdict: .strongYes,
            reasons: ["Reason 1"]
        )
        let b = AIPersonalizedAnalysis(
            personalizedDescription: "Great film",
            predictedRating: 9.0,
            verdict: .strongYes,
            reasons: ["Reason 1"]
        )
        #expect(a == b)
    }

    @Test func differentVerdictsMeanDifferentAnalyses() {
        let a = AIPersonalizedAnalysis(personalizedDescription: "X", predictedRating: 5, verdict: .yes, reasons: [])
        let b = AIPersonalizedAnalysis(personalizedDescription: "X", predictedRating: 5, verdict: .no, reasons: [])
        #expect(a != b)
    }

    @Test func decodesAllVerdicts() throws {
        let verdicts = ["strong_yes", "yes", "maybe", "no", "strong_no"]
        for raw in verdicts {
            let json = """
            {"personalizedDescription":"d","predictedRating":5,"verdict":"\(raw)","reasons":[]}
            """
            let data = json.data(using: .utf8)!
            let analysis = try JSONDecoder().decode(AIPersonalizedAnalysis.self, from: data)
            #expect(analysis.verdict.rawValue == raw)
        }
    }

    @Test func getPersonalizedAnalysisThrowsWithNoProvider() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("ai-analysis-test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        let manager = AIAssistantManager(database: database)

        do {
            _ = try await manager.getPersonalizedAnalysis(
                title: "Inception",
                year: 2010,
                type: .movie,
                genres: ["Sci-Fi", "Thriller"],
                overview: "A thief enters dreams"
            )
            Issue.record("Expected AIError.noProviderConfigured")
        } catch let error as AIError {
            if case .noProviderConfigured = error { /* OK */ }
            else { Issue.record("Unexpected AIError: \(error)") }
        }
    }

    @Test func hasConfiguredProviderIsFalseByDefault() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("ai-has-provider-test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        let manager = AIAssistantManager(database: database)

        let hasProvider = await manager.hasConfiguredProvider
        #expect(hasProvider == false)
    }

    @Test func hasConfiguredProviderIsTrueAfterConfigure() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dbURL = tempDir.appendingPathComponent("ai-has-provider-true-test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        let manager = AIAssistantManager(database: database)

        await manager.configure(provider: .anthropic, apiKey: "test-key")
        let hasProvider = await manager.hasConfiguredProvider
        #expect(hasProvider == true)
    }
}
