import Testing
import Foundation
@testable import VPStudio

// MARK: - GeminiProvider Tests

@Suite("GeminiProvider")
struct GeminiProviderTests {

    private func makeProvider(session: URLSession, model: String = "gemini-2.5-flash") -> GeminiProvider {
        GeminiProvider(apiKey: "test-key", model: model, session: session)
    }

    private func stubSession(
        statusCode: Int = 200,
        json: [String: Any]
    ) -> URLSession {
        URLProtocolHarness.makeSession { _ in
            let data = try JSONSerialization.data(withJSONObject: json)
            let response = HTTPURLResponse(
                url: URL(string: "https://generativelanguage.googleapis.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
    }

    // MARK: - Successful Response

    @Test func successfulResponseParsing() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "Hello from Gemini!"]]
                    ]
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 42,
                "candidatesTokenCount": 15
            ]
        ]

        let session = stubSession(json: responseJSON)
        let provider = makeProvider(session: session)
        let result = try await provider.complete(system: "You are helpful.", userMessage: "Hi")

        #expect(result.provider == .gemini)
        #expect(result.content == "Hello from Gemini!")
        #expect(result.model == "gemini-2.5-flash")
        #expect(result.inputTokens == 42)
        #expect(result.outputTokens == 15)
    }

    // MARK: - HTTP Error Handling

    @Test func httpErrorReturnsStatusAndBody() async throws {
        let errorJSON: [String: Any] = [
            "error": ["message": "Bad request", "code": 400]
        ]

        let session = stubSession(statusCode: 400, json: errorJSON)
        let provider = makeProvider(session: session)

        do {
            _ = try await provider.complete(system: "s", userMessage: "u")
            Issue.record("Expected AIError.httpError")
        } catch let error as AIError {
            if case .httpError(let code, let msg) = error {
                #expect(code == 400)
                #expect(msg.contains("Bad request"))
            } else {
                Issue.record("Unexpected AIError: \(error)")
            }
        }
    }

    // MARK: - Rate Limiting

    @Test func rateLimitedOn429() async throws {
        let session = stubSession(statusCode: 429, json: ["error": "rate limited"])
        let provider = makeProvider(session: session)

        do {
            _ = try await provider.complete(system: "s", userMessage: "u")
            Issue.record("Expected AIError.rateLimited")
        } catch let error as AIError {
            if case .rateLimited = error { /* OK */ }
            else { Issue.record("Expected rateLimited, got \(error)") }
        }
    }

    // MARK: - Invalid Response

    @Test func invalidResponseOnMissingContent() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": ["parts": []]
                ]
            ]
        ]
        let session = stubSession(json: responseJSON)
        let provider = makeProvider(session: session)

        do {
            _ = try await provider.complete(system: "s", userMessage: "u")
            Issue.record("Expected AIError.invalidResponse")
        } catch let error as AIError {
            if case .invalidResponse = error { /* OK */ }
            else { Issue.record("Expected invalidResponse, got \(error)") }
        }
    }

    @Test func invalidResponseOnEmptyText() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": ""]]
                    ]
                ]
            ]
        ]
        let session = stubSession(json: responseJSON)
        let provider = makeProvider(session: session)

        do {
            _ = try await provider.complete(system: "s", userMessage: "u")
            Issue.record("Expected AIError.invalidResponse")
        } catch let error as AIError {
            if case .invalidResponse = error { /* OK */ }
            else { Issue.record("Expected invalidResponse, got \(error)") }
        }
    }

    @Test func missingUsageMetadataDefaultsToZero() async throws {
        let responseJSON: [String: Any] = [
            "candidates": [
                ["content": ["parts": [["text": "response"]]]]
            ]
        ]

        let session = stubSession(json: responseJSON)
        let provider = makeProvider(session: session)
        let result = try await provider.complete(system: "s", userMessage: "u")

        #expect(result.inputTokens == 0)
        #expect(result.outputTokens == 0)
    }
}

// MARK: - AIProviderKind Gemini Tests

@Suite("AIProviderKind - Gemini")
struct AIProviderKindGeminiTests {

    @Test func geminiRawValue() {
        #expect(AIProviderKind.gemini.rawValue == "gemini")
    }

    @Test func geminiDisplayName() {
        #expect(AIProviderKind.gemini.displayName == "Google Gemini")
    }

    @Test func geminiIdMatchesRawValue() {
        #expect(AIProviderKind.gemini.id == "gemini")
    }
}

// MARK: - GeminiProvider Init Tests

@Suite("GeminiProvider Initialization")
struct GeminiProviderInitTests {

    @Test func defaultModel() {
        let provider = GeminiProvider(apiKey: "test-key")
        #expect(provider.providerKind == .gemini)
    }

    @Test func customModel() {
        let provider = GeminiProvider(apiKey: "test-key", model: "gemini-2.5-pro")
        #expect(provider.providerKind == .gemini)
    }
}
