import Foundation
import Testing
@testable import VPStudio

// MARK: - Model Catalog Tests

@Suite("AIModelCatalog")
struct AIModelCatalogTests {

    // MARK: - Cost Calculation Accuracy

    @Test func costCalculationForClaudeSonnet4() {
        // 1000 input tokens at $3/1M = $0.003
        // 500 output tokens at $15/1M = $0.0075
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-sonnet-4-20250514",
            inputTokens: 1000,
            outputTokens: 500
        )
        #expect(abs(cost - 0.0105) < 0.000001)
    }

    @Test func costCalculationForClaudeOpus4() {
        // 1000 input at $15/1M = $0.015
        // 1000 output at $75/1M = $0.075
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-opus-4-20250514",
            inputTokens: 1000,
            outputTokens: 1000
        )
        #expect(abs(cost - 0.09) < 0.000001)
    }

    @Test func costCalculationForClaudeHaiku35() {
        // 10000 input at $0.80/1M = $0.008
        // 5000 output at $4/1M = $0.02
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-3-5-haiku-20241022",
            inputTokens: 10_000,
            outputTokens: 5_000
        )
        #expect(abs(cost - 0.028) < 0.000001)
    }

    @Test func costCalculationForGPT4o() {
        // 2000 input at $2.50/1M = $0.005
        // 1000 output at $10/1M = $0.01
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-4o",
            inputTokens: 2_000,
            outputTokens: 1_000
        )
        #expect(abs(cost - 0.015) < 0.000001)
    }

    @Test func costCalculationForGPT4oMini() {
        // 10000 input at $0.15/1M = $0.0015
        // 5000 output at $0.60/1M = $0.003
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-4o-mini",
            inputTokens: 10_000,
            outputTokens: 5_000
        )
        #expect(abs(cost - 0.0045) < 0.000001)
    }

    @Test func costCalculationForO1() {
        // 1000 input at $15/1M = $0.015
        // 1000 output at $60/1M = $0.06
        let cost = AIModelCatalog.estimateCost(
            modelID: "o1",
            inputTokens: 1_000,
            outputTokens: 1_000
        )
        #expect(abs(cost - 0.075) < 0.000001)
    }

    @Test func costCalculationForClaudeOpus46() {
        // 1000 input at $15/1M = $0.015
        // 1000 output at $75/1M = $0.075
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-opus-4-6",
            inputTokens: 1000,
            outputTokens: 1000
        )
        #expect(abs(cost - 0.09) < 0.000001)
    }

    @Test func costCalculationForClaudeSonnet46() {
        // 1000 input at $3/1M = $0.003
        // 500 output at $15/1M = $0.0075
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-sonnet-4-6",
            inputTokens: 1000,
            outputTokens: 500
        )
        #expect(abs(cost - 0.0105) < 0.000001)
    }

    @Test func costCalculationForGPT5() {
        // 2000 input at $5/1M = $0.01
        // 1000 output at $15/1M = $0.015
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-5",
            inputTokens: 2_000,
            outputTokens: 1_000
        )
        #expect(abs(cost - 0.025) < 0.000001)
    }

    @Test func costCalculationForGPT54() {
        // 2000 input at $2.50/1M = $0.005
        // 1000 output at $15/1M = $0.015
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-5.4",
            inputTokens: 2_000,
            outputTokens: 1_000
        )
        #expect(abs(cost - 0.02) < 0.000001)
    }

    @Test func costCalculationForGPT54Mini() {
        // 4000 input at $0.75/1M = $0.003
        // 2000 output at $4.50/1M = $0.009
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-5.4-mini",
            inputTokens: 4_000,
            outputTokens: 2_000
        )
        #expect(abs(cost - 0.012) < 0.000001)
    }

    @Test func costCalculationForGPT54Nano() {
        // 5000 input at $0.20/1M = $0.001
        // 2000 output at $1.25/1M = $0.0025
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-5.4-nano",
            inputTokens: 5_000,
            outputTokens: 2_000
        )
        #expect(abs(cost - 0.0035) < 0.000001)
    }

    @Test func costCalculationForOllamaIsZero() {
        let cost = AIModelCatalog.estimateCost(
            modelID: "llama3.1",
            inputTokens: 100_000,
            outputTokens: 50_000
        )
        #expect(cost == 0)
    }

    @Test func costCalculationForAllOllamaModelsIsZero() {
        for model in AIModelCatalog.models(for: .ollama) {
            let cost = AIModelCatalog.estimateCost(
                model: model,
                inputTokens: 1_000_000,
                outputTokens: 1_000_000
            )
            #expect(cost == 0, "Expected zero cost for Ollama model \(model.id)")
        }
    }

    @Test func costCalculationForZeroTokens() {
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-sonnet-4-20250514",
            inputTokens: 0,
            outputTokens: 0
        )
        #expect(cost == 0)
    }

    @Test func costCalculationForUnknownModelReturnsZero() {
        let cost = AIModelCatalog.estimateCost(
            modelID: "nonexistent-model-v99",
            inputTokens: 10_000,
            outputTokens: 5_000
        )
        #expect(cost == 0)
    }

    @Test func costCalculationViaModelDefinition() {
        let model = AIModelCatalog.claudeSonnet4
        let cost = AIModelCatalog.estimateCost(
            model: model,
            inputTokens: 1_000_000,
            outputTokens: 1_000_000
        )
        // $3 input + $15 output = $18
        #expect(abs(cost - 18.0) < 0.000001)
    }

    // MARK: - Model Lookup by Provider

    @Test func anthropicModelsReturnCorrectCount() {
        let models = AIModelCatalog.models(for: .anthropic)
        #expect(models.count == 5)
    }

    @Test func openAIModelsReturnCorrectCount() {
        let models = AIModelCatalog.models(for: .openAI)
        #expect(models.count == 7)
    }

    @Test func ollamaModelsReturnCorrectCount() {
        let models = AIModelCatalog.models(for: .ollama)
        #expect(models.count == 3)
    }

    @Test func allModelsHaveCorrectProvider() {
        for model in AIModelCatalog.allModels {
            let providerModels = AIModelCatalog.models(for: model.provider)
            #expect(providerModels.contains(where: { $0.id == model.id }))
        }
    }

    @Test func allModelsHaveNonEmptyDisplayNames() {
        for model in AIModelCatalog.allModels {
            #expect(!model.displayName.isEmpty, "Model \(model.id) has empty displayName")
        }
    }

    @Test func allModelsHavePositiveContextWindow() {
        for model in AIModelCatalog.allModels {
            #expect(model.maxContextTokens > 0, "Model \(model.id) has non-positive context window")
        }
    }

    @Test func allModelIDsAreUnique() {
        let ids = AIModelCatalog.allModels.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    // MARK: - Default Model Selection

    @Test func defaultAnthropicModelIsSonnet46() {
        let def = AIModelCatalog.defaultModel(for: .anthropic)
        #expect(def?.id == "claude-sonnet-4-6")
    }

    @Test func defaultOpenAIModelIsGPT54() {
        let def = AIModelCatalog.defaultModel(for: .openAI)
        #expect(def?.id == "gpt-5.4")
    }

    @Test func defaultOllamaModelIsLlama31() {
        let def = AIModelCatalog.defaultModel(for: .ollama)
        #expect(def?.id == "llama3.1")
    }

    @Test func defaultOpenRouterModelUsesProviderNativeID() {
        let def = AIModelCatalog.defaultModel(for: .openRouter)
        #expect(def?.id == "google/gemini-2.5-flash-lite-preview")
        #expect(def?.id.hasPrefix("openrouter/") == false)
    }

    @Test func bundledOpenRouterModelsUseProviderNativeIDs() {
        for model in AIModelCatalog.models(for: .openRouter) {
            #expect(model.id.hasPrefix("openrouter/") == false)
            #expect(model.id.contains("/"))
        }
    }

    @Test func legacyOpenRouterModelIDLookupStillResolves() {
        let model = AIModelCatalog.model(byID: "openrouter/openai/gpt-4o-mini")
        #expect(model?.id == "openai/gpt-4o-mini")
        #expect(model?.provider == .openRouter)
    }

    @Test func openRouterProviderNativeIDNormalizationHandlesWhitespaceAndCase() {
        #expect(
            AIModelCatalog.providerNativeOpenRouterModelID("  OpenRouter/openai/gpt-4o-mini  ")
            == "openai/gpt-4o-mini"
        )
        #expect(
            AIModelCatalog.providerNativeOpenRouterModelID("OPENROUTER/anthropic/claude-3.5-haiku")
            == "anthropic/claude-3.5-haiku"
        )
    }

    @Test func openRouterProviderNativeIDNormalizationLeavesNativeIDsUntouched() {
        #expect(
            AIModelCatalog.providerNativeOpenRouterModelID("google/gemini-2.5-flash-lite-preview")
            == "google/gemini-2.5-flash-lite-preview"
        )
    }

    @Test func eachProviderHasExactlyOneDefault() {
        for provider in AIProviderKind.allCases {
            let providerModels = AIModelCatalog.models(for: provider)
            let defaults = providerModels.filter(\.isDefault)
            #expect(defaults.count == 1, "Provider \(provider.rawValue) should have exactly 1 default, found \(defaults.count)")
        }
    }

    // MARK: - Model Lookup by ID

    @Test func lookupKnownModelByID() {
        let model = AIModelCatalog.model(byID: "gpt-4o")
        #expect(model != nil)
        #expect(model?.provider == .openAI)
        #expect(model?.displayName == "GPT-4o")
    }

    @Test func lookupUnknownModelByIDReturnsNil() {
        let model = AIModelCatalog.model(byID: "nonexistent-model")
        #expect(model == nil)
    }

    // MARK: - Pricing Sanity Checks

    @Test func remotePaidModelsCostMoreThanZero() {
        for model in AIModelCatalog.allModels where model.provider != .ollama && model.provider != .local {
            #expect(model.inputCostPer1MTokens > 0, "\(model.id) should have positive input cost")
            #expect(model.outputCostPer1MTokens > 0, "\(model.id) should have positive output cost")
        }
    }

    @Test func outputCostsAreNotLowerThanInputCosts() {
        for model in AIModelCatalog.allModels where model.provider != .ollama && model.provider != .local {
            #expect(
                model.outputCostPer1MTokens >= model.inputCostPer1MTokens,
                "\(model.id): output cost should not be lower than input cost"
            )
        }
    }

    // MARK: - AIModelDefinition Equatable & Identifiable

    @Test func modelDefinitionEquatable() {
        let a = AIModelCatalog.claudeSonnet4
        let b = AIModelCatalog.claudeSonnet4
        #expect(a == b)
    }

    @Test func modelDefinitionIdentifiable() {
        let model = AIModelCatalog.gpt4o
        #expect(model.id == "gpt-4o")
    }
}

@Suite("AIModelFetcher - OpenRouter")
struct OpenRouterModelFetcherTests {
    @Test func fetchOpenRouterModelsReturnsEmptyForBlankAPIKeyWithoutNetwork() async {
        let session = URLProtocolHarness.makeSession { _ in
            Issue.record("Blank API key should not issue a request")
            let response = HTTPURLResponse(
                url: URL(string: "https://openrouter.ai/api/v1/models")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let models = await AIModelFetcher.fetchOpenRouterModels(apiKey: "   ", session: session)

        #expect(models.isEmpty)
    }

    @Test func fetchOpenRouterModelsReturnsEmptyForHTTPFailureAndMalformedPayload() async {
        let failingSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("unavailable".utf8))
        }
        let malformedSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"unexpected\":true}".utf8))
        }

        #expect(await AIModelFetcher.fetchOpenRouterModels(apiKey: "test-key", session: failingSession).isEmpty)
        #expect(await AIModelFetcher.fetchOpenRouterModels(apiKey: "test-key", session: malformedSession).isEmpty)
    }

    @Test func fetchOpenRouterModelsReturnsLiveModels() async {
        let session = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: [
                "data": [
                    [
                        "id": "openai/gpt-4o-mini",
                        "name": "GPT-4o Mini",
                        "context_length": 128000,
                        "pricing": [
                            "prompt": "0.00000015",
                            "completion": "0.00000060"
                        ]
                    ]
                ]
            ])
            return (response, data)
        }

        let models = await AIModelFetcher.fetchOpenRouterModels(apiKey: "test-key", session: session)

        #expect(models.count == 1)
        #expect(models.first?.id == "openai/gpt-4o-mini")
        #expect(models.first?.provider == .openRouter)
        #expect(models.first?.maxContextTokens == 128000)
    }

    @Test func fetchOpenRouterModelsUsesCatalogFallbacksAndNumericPricing() async {
        let session = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: [
                "data": [
                    [
                        "id": "mystery-provider/custom_model-v2",
                        "pricing": [
                            "prompt": NSNumber(value: 0.00000025),
                            "completion": NSNumber(value: 0.00000075),
                        ],
                    ],
                    [
                        "id": "google/gemini-2.5-flash-lite-preview",
                    ],
                    [
                        "id": "",
                    ],
                    [
                        "name": "Missing ID",
                    ],
                ],
            ])
            return (response, data)
        }

        let models = await AIModelFetcher.fetchOpenRouterModels(apiKey: "test-key", session: session)

        #expect(models.map(\.id) == ["google/gemini-2.5-flash-lite-preview", "mystery-provider/custom_model-v2"])

        if let catalog = models.first(where: { $0.id == "google/gemini-2.5-flash-lite-preview" }) {
            #expect(catalog.displayName == "Gemini 2.5 Flash Lite (OpenRouter)")
            #expect(catalog.inputCostPer1MTokens == AIModelCatalog.openRouterGeminiFlashLite.inputCostPer1MTokens)
            #expect(catalog.maxContextTokens == AIModelCatalog.openRouterGeminiFlashLite.maxContextTokens)
            #expect(catalog.isDefault == true)
        } else {
            Issue.record("Expected catalog OpenRouter model")
        }

        if let custom = models.first(where: { $0.id == "mystery-provider/custom_model-v2" }) {
            #expect(custom.displayName == "Mystery Provider/custom Model V2")
            #expect(custom.inputCostPer1MTokens == 0.25)
            #expect(custom.outputCostPer1MTokens == 0.75)
            #expect(custom.maxContextTokens == 128_000)
            #expect(custom.isDefault == false)
        } else {
            Issue.record("Expected custom OpenRouter model")
        }
    }

    @Test func fetchOpenRouterModelsNormalizesLegacyPrefixedIDs() async {
        let session = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: [
                "data": [
                    [
                        "id": "openrouter/openai/gpt-4o-mini",
                        "name": "GPT-4o Mini",
                        "context_length": 128000,
                    ]
                ]
            ])
            return (response, data)
        }

        let models = await AIModelFetcher.fetchOpenRouterModels(apiKey: "test-key", session: session)

        #expect(models.count == 1)
        #expect(models.first?.id == "openai/gpt-4o-mini")
        #expect(models.first?.displayName == "GPT-4o Mini")
    }
}

@Suite("AIModelFetcher - Guard Paths")
struct AIModelFetcherGuardPathTests {
    @Test func fetchOpenAIModelsReturnsEmptyForBlankAPIKey() async {
        #expect(await AIModelFetcher.fetchOpenAIModels(apiKey: "").isEmpty)
    }

    @Test func fetchAnthropicModelsReturnsEmptyForBlankAPIKey() async {
        #expect(await AIModelFetcher.fetchAnthropicModels(apiKey: "").isEmpty)
    }

    @Test func fetchGeminiModelsReturnsEmptyForBlankAPIKey() async {
        #expect(await AIModelFetcher.fetchGeminiModels(apiKey: "").isEmpty)
        #expect(await AIModelFetcher.fetchGeminiModels(apiKey: "   ").isEmpty)
    }

    @Test func fetchOllamaModelsRejectsDisallowedBaseURLs() async {
        #expect(await AIModelFetcher.fetchOllamaModels(baseURL: "").isEmpty)
        #expect(await AIModelFetcher.fetchOllamaModels(baseURL: "https://example.com").isEmpty)
    }
}

@Suite("AIModelFetcher - OpenAI")
struct OpenAIModelFetcherTests {
    @Test func fetchOpenAIModelsParsesSupportedChatModelsAndFiltersUnsupportedIDs() async {
        let session = URLProtocolHarness.makeSession { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-key")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = try JSONSerialization.data(withJSONObject: [
                "data": [
                    ["id": "gpt-5.4"],
                    ["id": "chatgpt-custom_model"],
                    ["id": "gpt-4o-realtime-preview"],
                    ["id": "text-embedding-3-large"],
                    ["name": "missing id"],
                ],
            ])
            return (response, data)
        }

        let models = await AIModelFetcher.fetchOpenAIModels(apiKey: "openai-key", session: session)

        #expect(models.map(\.id) == ["chatgpt-custom_model", "gpt-5.4"])
        #expect(models.first(where: { $0.id == "gpt-5.4" })?.displayName == "GPT-5.4")
        #expect(models.first(where: { $0.id == "chatgpt-custom_model" })?.displayName == "Chatgpt Custom Model")
    }

    @Test func fetchOpenAIModelsReturnsEmptyForHTTPFailureAndMalformedPayload() async {
        let failingSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let malformedSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"data\":\"not-array\"}".utf8))
        }

        #expect(await AIModelFetcher.fetchOpenAIModels(apiKey: "key", session: failingSession).isEmpty)
        #expect(await AIModelFetcher.fetchOpenAIModels(apiKey: "key", session: malformedSession).isEmpty)
    }
}

@Suite("AIModelFetcher - Anthropic")
struct AnthropicModelFetcherTests {
    @Test func fetchAnthropicModelsParsesDisplayNamesAndCatalogFallbacks() async {
        let session = URLProtocolHarness.makeSession { request in
            #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=50")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "anthropic-key")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "data": [
                    ["id": "custom-haiku", "display_name": "Custom Haiku"],
                    ["id": "claude-sonnet-4-6", "display_name": "Stale Live Name"],
                    ["display_name": "Missing ID"],
                ],
            ])
            return (response, data)
        }

        let models = await AIModelFetcher.fetchAnthropicModels(apiKey: "anthropic-key", session: session)

        #expect(models.map(\.id) == ["claude-sonnet-4-6", "custom-haiku"])
        #expect(models.first(where: { $0.id == "claude-sonnet-4-6" })?.displayName == "Claude Sonnet 4.6")
        #expect(models.first(where: { $0.id == "custom-haiku" })?.displayName == "Custom Haiku")
    }

    @Test func fetchAnthropicModelsReturnsEmptyForHTTPFailureAndMalformedPayload() async {
        let failingSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let malformedSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"data\":{}}".utf8))
        }

        #expect(await AIModelFetcher.fetchAnthropicModels(apiKey: "key", session: failingSession).isEmpty)
        #expect(await AIModelFetcher.fetchAnthropicModels(apiKey: "key", session: malformedSession).isEmpty)
    }
}

@Suite("AIModelFetcher - Ollama")
struct OllamaModelFetcherTests {
    @Test func fetchOllamaModelsParsesTagsAndStripsLatestSuffix() async {
        let session = URLProtocolHarness.makeSession { request in
            #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/tags")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "models": [
                    ["name": "llama3.1:latest"],
                    ["name": "zeta_model:Q4_K_M"],
                    ["size": 123],
                ],
            ])
            return (response, data)
        }

        let models = await AIModelFetcher.fetchOllamaModels(baseURL: "http://127.0.0.1:11434/", session: session)

        #expect(models.map(\.id) == ["llama3.1", "zeta_model:Q4_K_M"])
        #expect(models.first?.displayName == "Llama 3.1")
        #expect(models.last?.displayName == "Zeta Model:Q4 K M")
    }

    @Test func fetchOllamaModelsReturnsEmptyForHTTPFailureAndMalformedPayload() async {
        let failingSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let malformedSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"models\":\"not-array\"}".utf8))
        }

        #expect(await AIModelFetcher.fetchOllamaModels(baseURL: "http://localhost:11434", session: failingSession).isEmpty)
        #expect(await AIModelFetcher.fetchOllamaModels(baseURL: "http://localhost:11434", session: malformedSession).isEmpty)
    }
}

@Suite("AIModelFetcher - Gemini")
struct GeminiModelFetcherTests {
    @Test func fetchGeminiModelsParsesModelNamesAndFiltersNonGeminiEntries() async {
        let session = URLProtocolHarness.makeSession { request in
            #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(withJSONObject: [
                "models": [
                    ["name": "models/gemini-2.5-flash", "displayName": "Stale Flash Name"],
                    ["name": "publishers/google/models/gemini-custom_model", "displayName": "Gemini Custom"],
                    ["name": "models/text-embedding-004", "displayName": "Embedding"],
                    ["displayName": "Missing Name"],
                ],
            ])
            return (response, data)
        }

        let models = await AIModelFetcher.fetchGeminiModels(apiKey: " gemini-key ", session: session)

        #expect(models.map(\.id) == ["gemini-2.5-flash", "publishers/google/models/gemini-custom_model"])
        #expect(models.first?.displayName == "Gemini 2.5 Flash")
        #expect(models.last?.displayName == "Gemini Custom")
    }

    @Test func fetchGeminiModelsReturnsEmptyForHTTPFailureAndMalformedPayload() async {
        let failingSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let malformedSession = URLProtocolHarness.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"models\":false}".utf8))
        }

        #expect(await AIModelFetcher.fetchGeminiModels(apiKey: "key", session: failingSession).isEmpty)
        #expect(await AIModelFetcher.fetchGeminiModels(apiKey: "key", session: malformedSession).isEmpty)
    }
}
