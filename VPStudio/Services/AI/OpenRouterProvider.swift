import Foundation

/// OpenRouter provider — OpenAI-compatible API at openrouter.ai
struct OpenRouterProvider: AIProvider, Sendable {
    let providerKind: AIProviderKind = .openRouter
    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let session: URLSession
    private let sleep: AIHTTPSleep

    init(
        apiKey: String,
        model: String = "google/gemini-2.5-flash-lite-preview",
        baseURL: String = "https://openrouter.ai/api/v1/chat/completions",
        session: URLSession = AIHTTPTransport.defaultSession,
        sleep: @escaping AIHTTPSleep = AIHTTPTransport.defaultSleep
    ) {
        self.apiKey = apiKey
        self.model = AIModelCatalog.providerNativeOpenRouterModelID(model)
        self.baseURL = baseURL
        self.session = session
        self.sleep = sleep
    }

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty, !trimmedModel.isEmpty else {
            throw AIError.invalidResponse
        }

        let body: [String: Any] = [
            "model": trimmedModel,
            "max_completion_tokens": 4096,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]

        guard let url = URL(string: baseURL) else {
            throw AIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await AIHTTPTransport.perform(request, using: session, sleep: sleep)

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, msg)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        guard let content = (choices?.first?["message"] as? [String: Any])?["content"] as? String, !content.isEmpty else {
            throw AIError.invalidResponse
        }
        let usage = json?["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        return AIProviderResponse(
            provider: .openRouter,
            content: content,
            model: trimmedModel,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}

// MARK: - OpenRouter Model Catalog

extension OpenRouterProvider {
    /// Known popular OpenRouter models. Fetch the full list from:
    /// GET https://openrouter.ai/api/v1/models
    static let knownModels: [AIModelDefinition] = [
        AIModelDefinition(
            id: "google/gemini-2.5-flash-lite-preview",
            displayName: "Gemini 2.5 Flash Lite (OpenRouter)",
            provider: .openRouter,
            inputCostPer1MTokens: 0.10,
            outputCostPer1MTokens: 0.40,
            maxContextTokens: 100_000,
            isDefault: true
        ),
        AIModelDefinition(
            id: "anthropic/claude-3.5-haiku",
            displayName: "Claude 3.5 Haiku (OpenRouter)",
            provider: .openRouter,
            inputCostPer1MTokens: 0.80,
            outputCostPer1MTokens: 4.0,
            maxContextTokens: 200_000,
            isDefault: false
        ),
        AIModelDefinition(
            id: "openai/gpt-4o-mini",
            displayName: "GPT-4o Mini (OpenRouter)",
            provider: .openRouter,
            inputCostPer1MTokens: 0.15,
            outputCostPer1MTokens: 0.60,
            maxContextTokens: 128_000,
            isDefault: false
        ),
        AIModelDefinition(
            id: "meta-llama/llama-3.1-8b-instruct",
            displayName: "Llama 3.1 8B (OpenRouter)",
            provider: .openRouter,
            inputCostPer1MTokens: 0.04,
            outputCostPer1MTokens: 0.04,
            maxContextTokens: 128_000,
            isDefault: false
        ),
        AIModelDefinition(
            id: "mistralai/mistral-nemo",
            displayName: "Mistral Nemo (OpenRouter)",
            provider: .openRouter,
            inputCostPer1MTokens: 0.15,
            outputCostPer1MTokens: 0.15,
            maxContextTokens: 128_000,
            isDefault: false
        ),
        AIModelDefinition(
            id: "qwen/qwen-2.5-72b-instruct",
            displayName: "Qwen 2.5 72B (OpenRouter)",
            provider: .openRouter,
            inputCostPer1MTokens: 0.90,
            outputCostPer1MTokens: 0.90,
            maxContextTokens: 32_000,
            isDefault: false
        ),
    ]
}
