import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct AIAssistantManagerCompareProvidersTests {
    private actor CapturingProvider: AIProvider {
        let providerKind: AIProviderKind
        var lastSystemPrompt: String?

        init(providerKind: AIProviderKind) {
            self.providerKind = providerKind
        }

        func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
            lastSystemPrompt = system
            return AIProviderResponse(provider: providerKind, content: "ok", model: "capture", inputTokens: 1, outputTokens: 1)
        }

        func prompt() async -> String? { lastSystemPrompt }
    }

    struct CaseData: Sendable {
        let failOpenAI: Bool
        let failAnthropic: Bool
        let failOllama: Bool
    }

    private static let cases: [CaseData] = {
        var values: [CaseData] = []
        for index in 0..<30 {
            values.append(
                CaseData(
                    failOpenAI: (index & 1) != 0,
                    failAnthropic: (index & 2) != 0,
                    failOllama: (index & 4) != 0
                )
            )
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(10)), full: cases))
    func compareProvidersMatrix(data: CaseData) async throws {
        struct ProviderError: Error, LocalizedError {
            var errorDescription: String? { "provider-failure" }
        }

        let manager = try await makeManager()
        defer { try? FileManager.default.removeItem(at: manager.tempDir) }

        let successOpenAI = AIProviderResponse(provider: .openAI, content: "ok-openai", model: "stub", inputTokens: 1, outputTokens: 1)
        let successAnthropic = AIProviderResponse(provider: .anthropic, content: "ok-anthropic", model: "stub", inputTokens: 1, outputTokens: 1)
        let successOllama = AIProviderResponse(provider: .ollama, content: "ok-ollama", model: "stub", inputTokens: 1, outputTokens: 1)

        await manager.instance.registerProvider(
            kind: .openAI,
            provider: StubAIProvider(providerKind: .openAI, result: data.failOpenAI ? .failure(ProviderError()) : .success(successOpenAI))
        )
        await manager.instance.registerProvider(
            kind: .anthropic,
            provider: StubAIProvider(providerKind: .anthropic, result: data.failAnthropic ? .failure(ProviderError()) : .success(successAnthropic))
        )
        await manager.instance.registerProvider(
            kind: .ollama,
            provider: StubAIProvider(providerKind: .ollama, result: data.failOllama ? .failure(ProviderError()) : .success(successOllama))
        )

        let result = try await manager.instance.compareProviders(prompt: "test", context: AssistantContext())

        #expect(result.responses.count + result.errors.count == 3)
        #expect((result.responses[.openAI] == nil) == data.failOpenAI)
        #expect((result.responses[.anthropic] == nil) == data.failAnthropic)
        #expect((result.responses[.ollama] == nil) == data.failOllama)
    }

    @Test
    func compareProvidersAutoloadsWatchlistContextWhenContextIsNil() async throws {
        let manager = try await makeManager()
        defer { try? FileManager.default.removeItem(at: manager.tempDir) }

        let folderID = try await manager.database.fetchSystemLibraryFolderID(listType: .watchlist)
        try await manager.database.saveMediaItem(MediaItem(id: "movie-1", type: .movie, title: "Dune"))
        try await manager.database.addToLibrary(
            UserLibraryEntry(
                id: "entry-1",
                mediaId: "movie-1",
                folderId: folderID,
                listType: .watchlist,
                addedAt: Date()
            )
        )
        try await manager.database.setSetting(
            key: SettingsKeys.feedbackScaleMode,
            value: FeedbackScaleMode.oneToTen.rawValue
        )
        try await manager.database.saveTasteEvent(
            TasteEvent(
                id: "rating-openai",
                mediaId: "movie-1",
                eventType: .rated,
                signalStrength: 0.95,
                feedbackScale: .oneToTen,
                feedbackValue: 9,
                source: .manual,
                metadata: ["title": "Dune"]
            )
        )

        let provider = CapturingProvider(providerKind: .openAI)
        await manager.instance.registerProvider(kind: .openAI, provider: provider)

        let result = try await manager.instance.compareProviders(prompt: "test", context: nil)
        let prompt = await provider.prompt() ?? ""

        #expect(result.responses.count == 1)
        #expect(prompt.contains("Watchlist titles: Dune"))
        #expect(prompt.contains("Rating scale preference: 1-10"))
        #expect(prompt.contains("Liked titles: Dune"))
    }

    private func makeManager() async throws -> (instance: AIAssistantManager, database: DatabaseManager, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseManager(path: tempDir.appendingPathComponent("ai-compare.sqlite").path)
        try await db.migrate()
        return (AIAssistantManager(database: db), db, tempDir)
    }
}
