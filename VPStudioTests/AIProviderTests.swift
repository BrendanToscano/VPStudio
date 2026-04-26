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

    @Test func askUsesSavedDefaultProviderWhenItIsConfigured() async throws {
        let (manager, database, tempDir) = try await makeManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await database.setSetting(key: SettingsKeys.defaultAIProvider, value: AIProviderKind.openAI.rawValue)

        await manager.registerProvider(
            kind: .anthropic,
            provider: StubAIProvider(
                providerKind: .anthropic,
                result: .success(
                    AIProviderResponse(
                        provider: .anthropic,
                        content: "anthropic",
                        model: "stub",
                        inputTokens: 1,
                        outputTokens: 1
                    )
                )
            )
        )
        await manager.registerProvider(
            kind: .openAI,
            provider: StubAIProvider(
                providerKind: .openAI,
                result: .success(
                    AIProviderResponse(
                        provider: .openAI,
                        content: "openai",
                        model: "stub",
                        inputTokens: 1,
                        outputTokens: 1
                    )
                )
            )
        )

        let response = try await manager.ask(prompt: "test")
        #expect(response.provider == .openAI)
    }

    @Test func askFallsBackDeterministicallyWhenSavedDefaultIsUnavailable() async throws {
        let (manager, database, tempDir) = try await makeManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await database.setSetting(key: SettingsKeys.defaultAIProvider, value: AIProviderKind.ollama.rawValue)

        await manager.registerProvider(
            kind: .openAI,
            provider: StubAIProvider(
                providerKind: .openAI,
                result: .success(
                    AIProviderResponse(
                        provider: .openAI,
                        content: "openai",
                        model: "stub",
                        inputTokens: 1,
                        outputTokens: 1
                    )
                )
            )
        )
        await manager.registerProvider(
            kind: .gemini,
            provider: StubAIProvider(
                providerKind: .gemini,
                result: .success(
                    AIProviderResponse(
                        provider: .gemini,
                        content: "gemini",
                        model: "stub",
                        inputTokens: 1,
                        outputTokens: 1
                    )
                )
            )
        )

        let response = try await manager.ask(prompt: "test")
        #expect(response.provider == .openAI)
    }

    @Test func resolvedModelIDPrefersAnthropicCatalogDefaultWhenPresent() {
        #expect(
            AIAssistantManager.resolvedModelID(
                provider: .anthropic,
                catalogDefault: AIModelCatalog.claudeSonnet46.id,
                configuredModel: nil
            ) == AIModelCatalog.claudeSonnet46.id
        )
        #expect(
            AIAssistantManager.resolvedModelID(
                provider: .anthropic,
                catalogDefault: nil,
                configuredModel: nil
            ) == AIModelCatalog.claudeSonnet46.id
        )
    }

    @Test func resolvedModelIDNormalizesOpenRouterCatalogDefault() {
        #expect(
            AIAssistantManager.resolvedModelID(
                provider: .openRouter,
                catalogDefault: "openrouter/google/gemini-2.5-flash-lite-preview",
                configuredModel: nil
            ) == "google/gemini-2.5-flash-lite-preview"
        )
    }

    @Test func resolvedModelIDNormalizesConfiguredOpenRouterLegacyPrefix() {
        #expect(
            AIAssistantManager.resolvedModelID(
                provider: .openRouter,
                catalogDefault: AIModelCatalog.openRouterGeminiFlashLite.id,
                configuredModel: "  OpenRouter/anthropic/claude-3.5-haiku  "
            ) == "anthropic/claude-3.5-haiku"
        )
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
    private final class RequestBodyCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [Data] = []

        func record(_ request: URLRequest) {
            lock.lock()
            defer { lock.unlock() }
            if let body = bodyData(from: request) {
                bodies.append(body)
            }
        }

        func firstBody() -> Data? {
            lock.lock()
            defer { lock.unlock() }
            return bodies.first
        }

        private func bodyData(from request: URLRequest) -> Data? {
            if let body = request.httpBody {
                return body
            }
            guard let stream = request.httpBodyStream else {
                return nil
            }

            stream.open()
            defer { stream.close() }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count > 0 {
                    data.append(buffer, count: count)
                } else {
                    break
                }
            }
            return data.isEmpty ? nil : data
        }
    }

    private func openRouterSession(capturing capture: RequestBodyCapture) -> URLSession {
        URLProtocolHarness.makeSession { request in
            capture.record(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: [
                "choices": [
                    ["message": ["content": "ok"]]
                ],
                "usage": [
                    "prompt_tokens": 1,
                    "completion_tokens": 1
                ]
            ])
            return (response, data)
        }
    }

    private func capturedModel(from capture: RequestBodyCapture) throws -> String {
        let body = try #require(capture.firstBody())
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try #require(json["model"] as? String)
    }

    @Test func anthropicDefaultModel() {
        let provider = AnthropicProvider(apiKey: "test-key")
        #expect(provider.providerKind == .anthropic)
    }

    @Test func openAIDefaultModel() {
        let provider = OpenAIProvider(apiKey: "test-key")
        #expect(provider.providerKind == .openAI)
    }

    @Test func openRouterResolvesLegacyModelPrefixToProviderNativeID() async throws {
        let capture = RequestBodyCapture()
        let provider = OpenRouterProvider(
            apiKey: "test-key",
            model: "  OpenRouter/openai/gpt-4o-mini  ",
            session: openRouterSession(capturing: capture)
        )

        let response = try await provider.complete(system: "sys", userMessage: "msg")

        #expect(response.model == "openai/gpt-4o-mini")
        #expect(try capturedModel(from: capture) == "openai/gpt-4o-mini")
    }

    @Test func openRouterDefaultModelRequestUsesProviderNativeID() async throws {
        let capture = RequestBodyCapture()
        let provider = OpenRouterProvider(
            apiKey: "test-key",
            session: openRouterSession(capturing: capture)
        )

        let response = try await provider.complete(system: "sys", userMessage: "msg")

        #expect(response.model == "google/gemini-2.5-flash-lite-preview")
        #expect(try capturedModel(from: capture) == "google/gemini-2.5-flash-lite-preview")
    }

    @Test func ollamaDefaultModel() {
        let provider = OllamaProvider()
        #expect(provider.providerKind == .ollama)
    }
}

// MARK: - AIOllamaEndpointPolicy Tests

@Suite("AIOllamaEndpointPolicy")
struct AIOllamaEndpointPolicyTests {

    @Test func allowsLocalhostAndBlocksRemotePlaintext() {
        #expect(AIOllamaEndpointPolicy.warningMessage(for: "http://localhost:11434") == nil)
        #expect(AIOllamaEndpointPolicy.warningMessage(for: "http://127.0.0.1:11434") == nil)
        #expect(AIOllamaEndpointPolicy.warningMessage(for: "http://[::1]:11434") == nil)
        #expect(AIOllamaEndpointPolicy.warningMessage(for: "http://example.com:11434") != nil)
    }
}

// MARK: - AIAssistantManager Ollama Configuration Tests

@Suite("AIAssistantManager - Ollama Configuration")
struct AIAssistantManagerOllamaConfigurationTests {

    private func makeManager() async throws -> (AIAssistantManager, DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("ai-ollama-config-test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        let manager = AIAssistantManager(database: database)
        return (manager, database, tempDir)
    }

    @Test func rejectsInsecurePlainHttpOllamaEndpoint() async throws {
        let (manager, _, tempDir) = try await makeManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.configure(
            provider: .ollama,
            apiKey: "",
            baseURL: "http://example.com:11434",
            model: "llama3.1"
        )

        #expect(await manager.hasConfiguredProvider == false)
    }

    @Test func acceptsLocalhostOllamaEndpoint() async throws {
        let (manager, _, tempDir) = try await makeManager()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await manager.configure(
            provider: .ollama,
            apiKey: "",
            baseURL: "http://localhost:11434",
            model: "llama3.1"
        )

        #expect(await manager.hasConfiguredProvider == true)
    }
}

// MARK: - OllamaProvider Tests

@Suite("OllamaProvider")
struct OllamaProviderTests {

    private func makeProvider(session: URLSession, sleep: @escaping AIHTTPSleep = { _ in }) -> OllamaProvider {
        OllamaProvider(baseURL: "http://localhost:11434", model: "llama3.1", session: session, sleep: sleep)
    }

    @Test func rateLimitedOnRepeated429() async throws {
        let session = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "0"]
            )!
            let data = Data(#"{"error":"rate limited"}"#.utf8)
            return (response, data)
        }
        let provider = makeProvider(session: session)

        do {
            _ = try await provider.complete(system: "s", userMessage: "u")
            Issue.record("Expected AIError.rateLimited")
        } catch let error as AIError {
            if case .rateLimited = error { /* OK */ }
            else { Issue.record("Expected rateLimited, got \(error)") }
        }
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

// MARK: - Provider Transport Hardening Tests

@Suite("AI Provider Transport Hardening")
struct AIProviderTransportHardeningTests {
    private final class ResponseSequence: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [(Int, [String: String]?, Data)]
        private var requestCount = 0

        init(_ responses: [(Int, [String: String]?, Data)]) {
            self.responses = responses
        }

        func next(for request: URLRequest) -> (HTTPURLResponse, Data) {
            lock.lock()
            defer { lock.unlock() }
            requestCount += 1
            let entry = responses.isEmpty ? (500, nil, Data()) : responses.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: entry.0,
                httpVersion: nil,
                headerFields: entry.1
            )!
            return (response, entry.2)
        }

        func totalRequests() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return requestCount
        }
    }

    private final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [TimeInterval] = []

        func record(_ delay: TimeInterval) {
            lock.lock()
            values.append(delay)
            lock.unlock()
        }

        func allValues() -> [TimeInterval] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private func makeSession(sequence: ResponseSequence) -> URLSession {
        URLProtocolHarness.makeSession { request in
            sequence.next(for: request)
        }
    }

    private func openAIResponseJSON(content: String) -> Data {
        let json: [String: Any] = [
            "output_text": content,
            "usage": [
                "input_tokens": 12,
                "output_tokens": 4
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func anthropicResponseJSON(content: String) -> Data {
        let json: [String: Any] = [
            "content": [["text": content]],
            "usage": [
                "input_tokens": 7,
                "output_tokens": 3
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func openRouterResponseJSON(content: String) -> Data {
        let json: [String: Any] = [
            "choices": [
                ["message": ["content": content]]
            ],
            "usage": [
                "prompt_tokens": 9,
                "completion_tokens": 2
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func ollamaResponseJSON(content: String) -> Data {
        let json: [String: Any] = [
            "message": ["content": content]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func openAIRetriesRateLimitUsingRetryAfterHeader() async throws {
        let sequence = ResponseSequence([
            (429, ["Retry-After": "0"], Data("{\"error\":\"slow down\"}".utf8)),
            (200, nil, openAIResponseJSON(content: "ok-openai"))
        ])
        let sleepRecorder = SleepRecorder()
        let provider = OpenAIProvider(
            apiKey: "test-key",
            session: makeSession(sequence: sequence),
            sleep: { delay in sleepRecorder.record(delay) }
        )

        let response = try await provider.complete(system: "sys", userMessage: "msg")

        #expect(response.content == "ok-openai")
        #expect(sequence.totalRequests() == 2)
        #expect(sleepRecorder.allValues() == [0])
    }

    @Test func anthropicRetriesRateLimitBeforeSucceeding() async throws {
        let sequence = ResponseSequence([
            (429, nil, Data("{\"error\":\"rate limited\"}".utf8)),
            (200, nil, anthropicResponseJSON(content: "ok-claude"))
        ])
        let sleepRecorder = SleepRecorder()
        let provider = AnthropicProvider(
            apiKey: "test-key",
            session: makeSession(sequence: sequence),
            sleep: { delay in sleepRecorder.record(delay) }
        )

        let response = try await provider.complete(system: "sys", userMessage: "msg")

        #expect(response.content == "ok-claude")
        #expect(sequence.totalRequests() == 2)
        #expect(sleepRecorder.allValues() == [1])
    }

    @Test func openRouterThrowsDedicatedRateLimitedErrorAfterRetryBudget() async throws {
        let sequence = ResponseSequence([
            (429, nil, Data("{\"error\":\"first limit\"}".utf8)),
            (429, nil, Data("{\"error\":\"second limit\"}".utf8))
        ])
        let sleepRecorder = SleepRecorder()
        let provider = OpenRouterProvider(
            apiKey: "test-key",
            session: makeSession(sequence: sequence),
            sleep: { delay in sleepRecorder.record(delay) }
        )

        do {
            _ = try await provider.complete(system: "sys", userMessage: "msg")
            Issue.record("Expected AIError.rateLimited")
        } catch let error as AIError {
            if case .rateLimited = error {
                #expect(sequence.totalRequests() == 2)
                #expect(sleepRecorder.allValues() == [1])
            } else {
                Issue.record("Unexpected AIError: \(error)")
            }
        }
    }

    @Test func ollamaThrowsDedicatedRateLimitedErrorAfterRetryBudget() async throws {
        let sequence = ResponseSequence([
            (429, ["Retry-After": "0"], Data("{\"error\":\"first limit\"}".utf8)),
            (429, ["Retry-After": "0"], Data("{\"error\":\"second limit\"}".utf8))
        ])
        let sleepRecorder = SleepRecorder()
        let provider = OllamaProvider(
            session: makeSession(sequence: sequence),
            sleep: { delay in sleepRecorder.record(delay) }
        )

        do {
            _ = try await provider.complete(system: "sys", userMessage: "msg")
            Issue.record("Expected AIError.rateLimited")
        } catch let error as AIError {
            if case .rateLimited = error {
                #expect(sequence.totalRequests() == 2)
                #expect(sleepRecorder.allValues() == [0])
            } else {
                Issue.record("Unexpected AIError: \(error)")
            }
        }
    }
}

// MARK: - AI Provider Request/Parsing Tests

@Suite("AI Provider Request and Parsing")
struct AIProviderRequestParsingTests {
    private final class CapturedRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?

        func record(_ request: URLRequest) {
            lock.lock()
            self.request = request
            lock.unlock()
        }

        func header(_ name: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return request?.value(forHTTPHeaderField: name)
        }

        func path() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return request?.url?.path
        }

        func jsonBody() throws -> [String: Any] {
            lock.lock()
            let body = request.flatMap(Self.bodyData(from:))
            lock.unlock()
            let data = try #require(body)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        private static func bodyData(from request: URLRequest) -> Data? {
            if let body = request.httpBody {
                return body
            }
            guard let stream = request.httpBodyStream else {
                return nil
            }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            return data.isEmpty ? nil : data
        }
    }

    @Test func openAIChatCompletionsRequestAndUsageParsing() async throws {
        let capture = CapturedRequest()
        let session = URLProtocolHarness.makeSession { request in
            capture.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"choices":[{"message":{"content":"chat response"}}],"usage":{"prompt_tokens":21,"completion_tokens":8}}
            """
            return (response, Data(body.utf8))
        }
        let provider = OpenAIProvider(
            apiKey: " key ",
            model: " gpt-test ",
            baseURL: "https://api.openai.test/v1/chat/completions",
            session: session,
            sleep: { _ in }
        )

        let response = try await provider.complete(system: "system text", userMessage: "user text")
        let body = try capture.jsonBody()
        let messages = try #require(body["messages"] as? [[String: Any]])

        #expect(capture.path() == "/v1/chat/completions")
        #expect(capture.header("Authorization") == "Bearer key")
        #expect(body["model"] as? String == "gpt-test")
        #expect(body["max_completion_tokens"] as? Int == 4096)
        #expect(messages.count == 2)
        #expect(response.content == "chat response")
        #expect(response.inputTokens == 21)
        #expect(response.outputTokens == 8)
    }

    @Test func openAIResponsesOutputArrayAcceptsLegacyUsageKeys() async throws {
        let session = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"output":[{"type":"message","content":[{"text":"hello "},{"text":"world"}]}],"usage":{"prompt_tokens":11,"completion_tokens":5}}
            """
            return (response, Data(body.utf8))
        }
        let provider = OpenAIProvider(apiKey: "key", model: "gpt-test", session: session, sleep: { _ in })

        let response = try await provider.complete(system: "s", userMessage: "u")

        #expect(response.content == "hello world")
        #expect(response.inputTokens == 11)
        #expect(response.outputTokens == 5)
    }

    @Test func openAIResponsesRequestAndOutputTextParsing() async throws {
        let capture = CapturedRequest()
        let session = URLProtocolHarness.makeSession { request in
            capture.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"output_text":"responses text","usage":{"input_tokens":3,"output_tokens":2}}"#
            return (response, Data(body.utf8))
        }
        let provider = OpenAIProvider(
            apiKey: " key ",
            model: " gpt-responses ",
            baseURL: "https://api.openai.test/v1/responses",
            session: session,
            sleep: { _ in }
        )

        let response = try await provider.complete(system: "sys", userMessage: "msg")
        let body = try capture.jsonBody()
        let input = try #require(body["input"] as? [[String: Any]])
        let firstContent = try #require(input.first?["content"] as? [[String: Any]])

        #expect(capture.path() == "/v1/responses")
        #expect(capture.header("Authorization") == "Bearer key")
        #expect(body["model"] as? String == "gpt-responses")
        #expect(body["instructions"] as? String == "sys")
        #expect(body["max_output_tokens"] as? Int == 4096)
        #expect(firstContent.first?["type"] as? String == "input_text")
        #expect(firstContent.first?["text"] as? String == "msg")
        #expect(response.content == "responses text")
        #expect(response.inputTokens == 3)
        #expect(response.outputTokens == 2)
    }

    @Test func openAIRejectsBlankCredentialsWithoutNetwork() async {
        let provider = OpenAIProvider(
            apiKey: "   ",
            model: "gpt-test",
            session: URLProtocolHarness.makeSession { request in
                Issue.record("Unexpected OpenAI request: \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
        )

        await #expect(throws: AIError.self) {
            _ = try await provider.complete(system: "s", userMessage: "u")
        }
    }

    @Test func openAIRejectsBlankModelInvalidURLHTTPErrorAndEmptyPayload() async {
        let noNetwork = URLProtocolHarness.makeSession { request in
            Issue.record("Unexpected OpenAI request: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let failing = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (response, Data("openai unavailable".utf8))
        }
        let empty = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"output_text":"","usage":{}}"#.utf8))
        }

        let blankModel = OpenAIProvider(apiKey: "key", model: "   ", session: noNetwork)
        let badURL = OpenAIProvider(apiKey: "key", model: "gpt-test", baseURL: "http://[::1", session: noNetwork)
        let httpFailure = OpenAIProvider(apiKey: "key", model: "gpt-test", session: failing, sleep: { _ in })
        let emptyPayload = OpenAIProvider(apiKey: "key", model: "gpt-test", session: empty, sleep: { _ in })

        await #expect(throws: AIError.self) {
            _ = try await blankModel.complete(system: "s", userMessage: "u")
        }
        await #expect(throws: AIError.self) {
            _ = try await badURL.complete(system: "s", userMessage: "u")
        }
        do {
            _ = try await httpFailure.complete(system: "s", userMessage: "u")
            Issue.record("Expected HTTP error")
        } catch AIError.httpError(let status, let message) {
            #expect(status == 502)
            #expect(message == "openai unavailable")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        await #expect(throws: AIError.self) {
            _ = try await emptyPayload.complete(system: "s", userMessage: "u")
        }
    }

    @Test func anthropicSendsRequiredHeadersAndParsesUsage() async throws {
        let capture = CapturedRequest()
        let session = URLProtocolHarness.makeSession { request in
            capture.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"content":[{"type":"text","text":"anthropic response"}],"usage":{"input_tokens":13,"output_tokens":4}}"#
            return (response, Data(body.utf8))
        }
        let provider = AnthropicProvider(
            apiKey: "  claude-key  ",
            model: " claude-test ",
            baseURL: "https://api.anthropic.test/v1/messages",
            session: session,
            sleep: { _ in }
        )

        let response = try await provider.complete(system: "sys", userMessage: "msg")
        let body = try capture.jsonBody()

        #expect(capture.header("x-api-key") == "claude-key")
        #expect(capture.header("anthropic-version") == "2023-06-01")
        #expect(body["model"] as? String == "claude-test")
        #expect(body["max_tokens"] as? Int == 4096)
        #expect(response.content == "anthropic response")
        #expect(response.inputTokens == 13)
        #expect(response.outputTokens == 4)
    }

    @Test func anthropicThrowsInvalidResponseForEmptyContent() async {
        let session = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"content":[{"text":""}],"usage":{}}"#.utf8))
        }
        let provider = AnthropicProvider(apiKey: "key", model: "claude-test", session: session, sleep: { _ in })

        await #expect(throws: AIError.self) {
            _ = try await provider.complete(system: "s", userMessage: "u")
        }
    }

    @Test func anthropicRejectsBlankInputsAndSurfacesHTTPError() async {
        let noNetwork = URLProtocolHarness.makeSession { request in
            Issue.record("Unexpected Anthropic request: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let failing = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data("anthropic down".utf8))
        }

        let blankKey = AnthropicProvider(apiKey: "   ", model: "claude-test", session: noNetwork)
        let blankModel = AnthropicProvider(apiKey: "key", model: "   ", session: noNetwork)
        let badURL = AnthropicProvider(apiKey: "key", model: "claude-test", baseURL: "http://[::1", session: noNetwork)
        let httpFailure = AnthropicProvider(apiKey: "key", model: "claude-test", session: failing, sleep: { _ in })

        await #expect(throws: AIError.self) {
            _ = try await blankKey.complete(system: "s", userMessage: "u")
        }
        await #expect(throws: AIError.self) {
            _ = try await blankModel.complete(system: "s", userMessage: "u")
        }
        await #expect(throws: AIError.self) {
            _ = try await badURL.complete(system: "s", userMessage: "u")
        }
        do {
            _ = try await httpFailure.complete(system: "s", userMessage: "u")
            Issue.record("Expected HTTP error")
        } catch AIError.httpError(let status, let message) {
            #expect(status == 500)
            #expect(message == "anthropic down")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func openRouterBuildsRequestAndParsesUsage() async throws {
        let capture = CapturedRequest()
        let session = URLProtocolHarness.makeSession { request in
            capture.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"choices":[{"message":{"content":"router response"}}],"usage":{"prompt_tokens":17,"completion_tokens":6}}"#
            return (response, Data(body.utf8))
        }
        let provider = OpenRouterProvider(
            apiKey: " router-key ",
            model: " OpenRouter/openai/gpt-4o-mini ",
            baseURL: "https://openrouter.test/api/v1/chat/completions",
            session: session,
            sleep: { _ in }
        )

        let response = try await provider.complete(system: "sys", userMessage: "msg")
        let body = try capture.jsonBody()
        let messages = try #require(body["messages"] as? [[String: Any]])

        #expect(capture.header("Authorization") == "Bearer router-key")
        #expect(capture.header("Content-Type") == "application/json")
        #expect(capture.path() == "/api/v1/chat/completions")
        #expect(body["model"] as? String == "openai/gpt-4o-mini")
        #expect(body["max_completion_tokens"] as? Int == 4096)
        #expect(messages.count == 2)
        #expect(response.provider == .openRouter)
        #expect(response.content == "router response")
        #expect(response.inputTokens == 17)
        #expect(response.outputTokens == 6)
    }

    @Test func openRouterRejectsBlankCredentialsModelAndInvalidURLWithoutNetwork() async {
        let session = URLProtocolHarness.makeSession { request in
            Issue.record("Unexpected OpenRouter request: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let blankKey = OpenRouterProvider(apiKey: "   ", model: "openai/gpt-4o-mini", session: session)
        let blankModel = OpenRouterProvider(apiKey: "key", model: "   ", session: session)
        let badURL = OpenRouterProvider(apiKey: "key", model: "openai/gpt-4o-mini", baseURL: "http://[::1", session: session)

        await #expect(throws: AIError.self) {
            _ = try await blankKey.complete(system: "s", userMessage: "u")
        }
        await #expect(throws: AIError.self) {
            _ = try await blankModel.complete(system: "s", userMessage: "u")
        }
        await #expect(throws: AIError.self) {
            _ = try await badURL.complete(system: "s", userMessage: "u")
        }
    }

    @Test func openRouterThrowsHTTPErrorAndInvalidResponseForBadPayloads() async throws {
        let failingSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data("router unavailable".utf8))
        }
        let invalidSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"choices":[{"message":{"content":""}}],"usage":{}}"#.utf8))
        }

        let failingProvider = OpenRouterProvider(apiKey: "key", model: "openai/gpt-4o-mini", session: failingSession, sleep: { _ in })
        let invalidProvider = OpenRouterProvider(apiKey: "key", model: "openai/gpt-4o-mini", session: invalidSession, sleep: { _ in })

        do {
            _ = try await failingProvider.complete(system: "s", userMessage: "u")
            Issue.record("Expected HTTP error")
        } catch AIError.httpError(let status, let message) {
            #expect(status == 503)
            #expect(message == "router unavailable")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        await #expect(throws: AIError.self) {
            _ = try await invalidProvider.complete(system: "s", userMessage: "u")
        }
    }

    @Test func ollamaBuildsChatRequestAndParsesResponse() async throws {
        let capture = CapturedRequest()
        let session = URLProtocolHarness.makeSession { request in
            capture.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"message":{"content":"local response"}}"#.utf8))
        }
        let provider = OllamaProvider(
            baseURL: " http://localhost:11434 ",
            model: " llama3.2 ",
            session: session,
            sleep: { _ in }
        )

        let response = try await provider.complete(system: "sys", userMessage: "msg")
        let body = try capture.jsonBody()
        let messages = try #require(body["messages"] as? [[String: Any]])

        #expect(capture.path() == "/api/chat")
        #expect(body["model"] as? String == "llama3.2")
        #expect(body["stream"] as? Bool == false)
        #expect(messages.count == 2)
        #expect(response.provider == .ollama)
        #expect(response.content == "local response")
    }

    @Test func ollamaRejectsBlankBaseURLWithoutNetwork() async {
        let provider = OllamaProvider(
            baseURL: "   ",
            model: "llama3.2",
            session: URLProtocolHarness.makeSession { request in
                Issue.record("Unexpected Ollama request: \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
        )

        await #expect(throws: AIError.self) {
            _ = try await provider.complete(system: "s", userMessage: "u")
        }
    }

    @Test func ollamaRejectsBlankModelInvalidURLHTTPErrorAndEmptyContent() async {
        let noNetwork = URLProtocolHarness.makeSession { request in
            Issue.record("Unexpected Ollama request: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let failing = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data("ollama unavailable".utf8))
        }
        let empty = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"message":{"content":""}}"#.utf8))
        }

        let blankModel = OllamaProvider(baseURL: "http://localhost:11434", model: "   ", session: noNetwork)
        let badURL = OllamaProvider(baseURL: "http://[::1", model: "llama3.2", session: noNetwork)
        let httpFailure = OllamaProvider(baseURL: "http://localhost:11434", model: "llama3.2", session: failing, sleep: { _ in })
        let emptyContent = OllamaProvider(baseURL: "http://localhost:11434", model: "llama3.2", session: empty, sleep: { _ in })

        await #expect(throws: AIError.self) {
            _ = try await blankModel.complete(system: "s", userMessage: "u")
        }
        await #expect(throws: AIError.self) {
            _ = try await badURL.complete(system: "s", userMessage: "u")
        }
        do {
            _ = try await httpFailure.complete(system: "s", userMessage: "u")
            Issue.record("Expected HTTP error")
        } catch AIError.httpError(let status, let message) {
            #expect(status == 503)
            #expect(message == "ollama unavailable")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        await #expect(throws: AIError.self) {
            _ = try await emptyContent.complete(system: "s", userMessage: "u")
        }
    }
}

// MARK: - AI Manager Hardening Tests

@Suite("AIAssistantManager Hardening")
struct AIAssistantManagerHardeningTests {
    private func makeTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    @Test func usagePersistenceFailuresAreRecordedWithoutBreakingRequests() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let database = try DatabaseManager(path: tempDir.appendingPathComponent("ai-usage.sqlite").path)
        let manager = AIAssistantManager(database: database)

        await manager.registerProvider(
            kind: .openAI,
            provider: StubAIProvider(
                providerKind: .openAI,
                result: .success(
                    AIProviderResponse(
                        provider: .openAI,
                        content: "ok",
                        model: "gpt-5.4",
                        inputTokens: 10,
                        outputTokens: 5
                    )
                )
            )
        )

        let response = try await manager.ask(prompt: "hello", provider: .openAI)
        let usageError = await manager.lastUsagePersistenceErrorMessage

        #expect(response.content == "ok")
        #expect(usageError?.isEmpty == false)
    }

    @Test func managerRejectsRemotePlaintextOllamaEndpoints() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let database = try DatabaseManager(path: tempDir.appendingPathComponent("ai-manager.sqlite").path)
        try await database.migrate()
        let manager = AIAssistantManager(database: database)

        await manager.configure(provider: .ollama, apiKey: "", baseURL: "http://example.com:11434", model: "llama3.1")

        #expect(await manager.hasConfiguredProvider == false)
        #expect(AIOllamaEndpointPolicy.warningMessage(for: "http://example.com:11434") != nil)
        #expect(AIOllamaEndpointPolicy.warningMessage(for: "http://localhost:11434") == nil)
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
