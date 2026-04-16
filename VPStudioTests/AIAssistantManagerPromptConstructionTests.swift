import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct AIAssistantManagerPromptConstructionTests {
    private actor CapturingProvider: AIProvider {
        let providerKind: AIProviderKind
        var lastSystemPrompt: String?

        init(providerKind: AIProviderKind) {
            self.providerKind = providerKind
        }

        func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
            lastSystemPrompt = system
            return AIProviderResponse(provider: providerKind, content: #"[{"title":"X","type":"movie"}]"#, model: "capture", inputTokens: 1, outputTokens: 1)
        }

        func prompt() async -> String? { lastSystemPrompt }
    }

    private struct TestError: LocalizedError, Sendable {
        var errorDescription: String? { "unexpected provider invocation" }
    }

    private actor StaleLocalProvider: AIProvider {
        let providerKind: AIProviderKind = .local
        let modelID: String = "nonexistent-local-model"

        func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
            throw TestError()
        }
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<8), full: Array(0..<20)))
    func promptIncludesContextFields(index: Int) async throws {
        let manager = try await makeManager()
        defer { try? FileManager.default.removeItem(at: manager.tempDir) }

        let provider = CapturingProvider(providerKind: .openAI)
        await manager.instance.registerProvider(kind: .openAI, provider: provider)

        let context = AssistantContext(
            recentlyWatched: index % 2 == 0 ? ["Dune", "Andor"] : [],
            historyTitles: index % 6 == 0 ? ["Interstellar"] : [],
            favoriteGenres: index % 3 == 0 ? ["Sci-Fi"] : [],
            dislikedGenres: index % 4 == 0 ? ["Horror"] : [],
            currentMood: index % 5 == 0 ? "calm" : nil,
            watchlistTitles: index % 7 == 0 ? ["Severance"] : [],
            favoriteTitles: index % 8 == 0 ? ["The Matrix"] : [],
            feedbackScaleMode: index % 9 == 0 ? .oneToTen : nil,
            likedTitles: index % 10 == 0 ? ["Arrival"] : [],
            dislikedTitles: index % 11 == 0 ? ["Saw"] : [],
            ratedTitles: index % 12 == 0 ? ["Arrival (9/10)"] : []
        )

        _ = try await manager.instance.ask(prompt: "recommend", provider: .openAI, context: context)
        let prompt = await provider.prompt() ?? ""

        #expect(prompt.contains("You are VPStudio AI"))
        if !context.recentlyWatched.isEmpty {
            #expect(prompt.contains("Recently watched:"))
        }
        if !context.favoriteGenres.isEmpty {
            #expect(prompt.contains("Favorite genres:"))
        }
        if !context.dislikedGenres.isEmpty {
            #expect(prompt.contains("Dislikes:"))
        }
        if !context.historyTitles.isEmpty {
            #expect(prompt.contains("History titles:"))
        }
        if !context.watchlistTitles.isEmpty {
            #expect(prompt.contains("Watchlist titles:"))
        }
        if !context.favoriteTitles.isEmpty {
            #expect(prompt.contains("Favorite titles:"))
        }
        if context.feedbackScaleMode != nil {
            #expect(prompt.contains("Rating scale preference:"))
        }
        if !context.likedTitles.isEmpty {
            #expect(prompt.contains("Liked titles:"))
        }
        if !context.dislikedTitles.isEmpty {
            #expect(prompt.contains("Disliked titles:"))
        }
        if !context.ratedTitles.isEmpty {
            #expect(prompt.contains("Recent ratings:"))
        }
        if context.currentMood != nil {
            #expect(prompt.contains("Current mood:"))
        }
    }

    @Test
    func promptAutoloadsWatchlistFavoritesAndHistoryFromDatabase() async throws {
        let manager = try await makeManager()
        defer { try? FileManager.default.removeItem(at: manager.tempDir) }

        let watchlistFolderID = try await manager.database.fetchSystemLibraryFolderID(listType: .watchlist)
        let favoritesFolderID = try await manager.database.fetchSystemLibraryFolderID(listType: .favorites)

        try await manager.database.saveMediaItem(MediaItem(id: "wl-media", type: .movie, title: "Dune"))
        try await manager.database.saveMediaItem(MediaItem(id: "fav-media", type: .movie, title: "Arrival"))

        try await manager.database.addToLibrary(
            UserLibraryEntry(
                id: "wl-entry",
                mediaId: "wl-media",
                folderId: watchlistFolderID,
                listType: .watchlist,
                addedAt: Date()
            )
        )
        try await manager.database.addToLibrary(
            UserLibraryEntry(
                id: "fav-entry",
                mediaId: "fav-media",
                folderId: favoritesFolderID,
                listType: .favorites,
                addedAt: Date()
            )
        )

        try await manager.database.saveWatchHistory(
            WatchHistory(
                id: "history-1",
                mediaId: "history-media",
                episodeId: nil,
                title: "Inception",
                progress: 120,
                duration: 7200,
                quality: "1080p",
                debridService: nil,
                streamURL: nil,
                watchedAt: Date(),
                isCompleted: false
            )
        )

        try await manager.database.setSetting(
            key: SettingsKeys.feedbackScaleMode,
            value: FeedbackScaleMode.oneToTen.rawValue
        )
        try await manager.database.saveTasteEvent(
            TasteEvent(
                id: "rating-1",
                mediaId: "wl-media",
                eventType: .rated,
                signalStrength: 0.9,
                feedbackScale: .oneToTen,
                feedbackValue: 9,
                source: .manual,
                metadata: ["title": "Dune"]
            )
        )
        try await manager.database.saveTasteEvent(
            TasteEvent(
                id: "rating-2",
                mediaId: "fav-media",
                eventType: .rated,
                signalStrength: 0.1,
                feedbackScale: .oneToTen,
                feedbackValue: 2,
                source: .manual,
                metadata: ["title": "Arrival"]
            )
        )

        let provider = CapturingProvider(providerKind: .openAI)
        await manager.instance.registerProvider(kind: .openAI, provider: provider)

        _ = try await manager.instance.ask(prompt: "recommend", provider: .openAI, context: nil)
        let prompt = await provider.prompt() ?? ""

        #expect(prompt.contains("Watchlist titles: Dune"))
        #expect(prompt.contains("Favorite titles: Arrival"))
        #expect(prompt.contains("History titles: Inception"))
        #expect(prompt.contains("Rating scale preference: 1-10"))
        #expect(prompt.contains("Liked titles: Dune"))
        #expect(prompt.contains("Disliked titles: Arrival"))
        #expect(prompt.contains("Recent ratings:"))
    }

    @Test
    func promptBudgetTracksConfiguredModels() async throws {
        let manager = try await makeManager()
        defer { try? FileManager.default.removeItem(at: manager.tempDir) }

        await manager.instance.configure(provider: .openAI, apiKey: "test-key", model: AIModelCatalog.gpt4oMini.id)

        #expect(await manager.instance.promptBudgetTokens(for: .openAI) == AIModelCatalog.gpt4oMini.maxContextTokens / 2)
        #expect(await manager.instance.promptBudgetTokens(for: .local) == AIModelCatalog.localSmolLM2.maxContextTokens / 2)
    }

    @Test
    func promptBudgetTrimsOverflowingParts() {
        let budget = 120
        let parts = [
            "You are VPStudio AI.",
            String(repeating: "long-context ", count: 50),
            "This tail should be trimmed.",
        ]

        let prompt = AssistantPromptBudgetPolicy.composePrompt(from: parts, budgetTokens: budget)

        #expect(AssistantPromptBudgetPolicy.estimatedTokenCount(for: prompt) <= budget)
        #expect(prompt.contains("You are VPStudio AI."))
        #expect(!prompt.contains("This tail should be trimmed."))
    }

    @Test
    func staleLocalProviderFallsBackToAvailableProvider() async throws {
        let manager = try await makeManager()
        defer { try? FileManager.default.removeItem(at: manager.tempDir) }

        let openAIProvider = CapturingProvider(providerKind: .openAI)
        let staleLocalProvider = StaleLocalProvider()

        await manager.instance.registerProvider(kind: .openAI, provider: openAIProvider)
        await manager.instance.registerProvider(kind: .local, provider: staleLocalProvider)

        let response = try await manager.instance.ask(prompt: "recommend", provider: .local, context: nil)
        let prompt = await openAIProvider.prompt() ?? ""

        #expect(response.provider == .openAI)
        #expect(prompt.contains("You are VPStudio AI"))
    }

    private func makeManager() async throws -> (instance: AIAssistantManager, database: DatabaseManager, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseManager(path: tempDir.appendingPathComponent("ai-prompt.sqlite").path)
        try await db.migrate()
        return (AIAssistantManager(database: db), db, tempDir)
    }
}
