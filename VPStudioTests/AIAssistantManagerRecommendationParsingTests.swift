import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct AIAssistantManagerRecommendationParsingTests {
    struct CaseData: Sendable {
        let payload: String
        let shouldSucceed: Bool
        let expectedCount: Int
    }

    private static let cases: [CaseData] = {
        var values: [CaseData] = []
        for index in 0..<120 {
            switch index % 6 {
            case 0:
                values.append(
                    CaseData(
                        payload: #"[{"title":"Dune","year":2021,"type":"movie","reason":"Sci-fi","tmdbId":438631}]"#,
                        shouldSucceed: true,
                        expectedCount: 1
                    )
                )
            case 1:
                values.append(
                    CaseData(
                        payload: "```json\n[{\"title\":\"Andor\",\"year\":2022,\"type\":\"series\",\"reason\":\"tone\",\"tmdbId\":83867}]\n```",
                        shouldSucceed: true,
                        expectedCount: 1
                    )
                )
            case 2:
                values.append(
                    CaseData(
                        payload: "Some intro text [ {\"title\":\"Alien\",\"type\":\"movie\"} ] trailing text",
                        shouldSucceed: true,
                        expectedCount: 1
                    )
                )
            case 3:
                values.append(
                    CaseData(
                        payload: #"[{"title":"A","type":"tv"},{"title":"B","type":"show"}]"#,
                        shouldSucceed: true,
                        expectedCount: 2
                    )
                )
            case 4:
                values.append(
                    CaseData(
                        payload: #"{"not":"an array"}"#,
                        shouldSucceed: false,
                        expectedCount: 0
                    )
                )
            default:
                values.append(
                    CaseData(
                        payload: "no json content \(index)",
                        shouldSucceed: false,
                        expectedCount: 0
                    )
                )
            }
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(30)), full: cases))
    func recommendationsParsingMatrix(data: CaseData) async throws {
        let manager = try await makeManager()
        defer { try? FileManager.default.removeItem(at: manager.tempDir) }

        let response = AIProviderResponse(provider: .openAI, content: data.payload, model: "stub", inputTokens: 1, outputTokens: 1)
        await manager.instance.registerProvider(
            kind: .openAI,
            provider: StubAIProvider(providerKind: .openAI, result: .success(response))
        )

        do {
            let recommendations = try await manager.instance.getRecommendations(context: AssistantContext(), provider: .openAI)
            #expect(data.shouldSucceed)
            #expect(recommendations.count == data.expectedCount)
        } catch {
            #expect(data.shouldSucceed == false)
        }
    }

    private func makeManager() async throws -> (instance: AIAssistantManager, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try DatabaseManager(path: tempDir.appendingPathComponent("ai.sqlite").path)
        try await db.migrate()
        return (AIAssistantManager(database: db), tempDir)
    }
}
