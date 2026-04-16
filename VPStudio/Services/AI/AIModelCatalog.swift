import Foundation

// MARK: - Model Definition

struct AIModelDefinition: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let displayName: String
    let provider: AIProviderKind
    let inputCostPer1MTokens: Double
    let outputCostPer1MTokens: Double
    let maxContextTokens: Int
    let isDefault: Bool
}

// MARK: - Model Catalog

enum AIModelCatalog {

    // MARK: Anthropic Models

    static let claudeOpus46 = AIModelDefinition(
        id: "claude-opus-4-6",
        displayName: "Claude Opus 4.6",
        provider: .anthropic,
        inputCostPer1MTokens: 15.0,
        outputCostPer1MTokens: 75.0,
        maxContextTokens: 200_000,
        isDefault: false
    )

    static let claudeSonnet46 = AIModelDefinition(
        id: "claude-sonnet-4-6",
        displayName: "Claude Sonnet 4.6",
        provider: .anthropic,
        inputCostPer1MTokens: 3.0,
        outputCostPer1MTokens: 15.0,
        maxContextTokens: 200_000,
        isDefault: true
    )

    static let claudeOpus4 = AIModelDefinition(
        id: "claude-opus-4-20250514",
        displayName: "Claude Opus 4",
        provider: .anthropic,
        inputCostPer1MTokens: 15.0,
        outputCostPer1MTokens: 75.0,
        maxContextTokens: 200_000,
        isDefault: false
    )

    static let claudeSonnet4 = AIModelDefinition(
        id: "claude-sonnet-4-20250514",
        displayName: "Claude Sonnet 4",
        provider: .anthropic,
        inputCostPer1MTokens: 3.0,
        outputCostPer1MTokens: 15.0,
        maxContextTokens: 200_000,
        isDefault: false
    )

    static let claudeHaiku35 = AIModelDefinition(
        id: "claude-3-5-haiku-20241022",
        displayName: "Claude Haiku 3.5",
        provider: .anthropic,
        inputCostPer1MTokens: 0.80,
        outputCostPer1MTokens: 4.0,
        maxContextTokens: 200_000,
        isDefault: false
    )

    // MARK: OpenAI Models

    static let gpt54 = AIModelDefinition(
        id: "gpt-5.4",
        displayName: "GPT-5.4",
        provider: .openAI,
        inputCostPer1MTokens: 2.50,
        outputCostPer1MTokens: 15.0,
        maxContextTokens: 1_050_000,
        isDefault: true
    )

    static let gpt54Mini = AIModelDefinition(
        id: "gpt-5.4-mini",
        displayName: "GPT-5.4 Mini",
        provider: .openAI,
        inputCostPer1MTokens: 0.75,
        outputCostPer1MTokens: 4.50,
        maxContextTokens: 400_000,
        isDefault: false
    )

    static let gpt54Nano = AIModelDefinition(
        id: "gpt-5.4-nano",
        displayName: "GPT-5.4 Nano",
        provider: .openAI,
        inputCostPer1MTokens: 0.20,
        outputCostPer1MTokens: 1.25,
        maxContextTokens: 400_000,
        isDefault: false
    )

    static let gpt5 = AIModelDefinition(
        id: "gpt-5",
        displayName: "GPT-5",
        provider: .openAI,
        inputCostPer1MTokens: 5.0,
        outputCostPer1MTokens: 15.0,
        maxContextTokens: 128_000,
        isDefault: false
    )

    static let gpt4o = AIModelDefinition(
        id: "gpt-4o",
        displayName: "GPT-4o",
        provider: .openAI,
        inputCostPer1MTokens: 2.50,
        outputCostPer1MTokens: 10.0,
        maxContextTokens: 128_000,
        isDefault: false
    )

    static let gpt4oMini = AIModelDefinition(
        id: "gpt-4o-mini",
        displayName: "GPT-4o Mini",
        provider: .openAI,
        inputCostPer1MTokens: 0.15,
        outputCostPer1MTokens: 0.60,
        maxContextTokens: 128_000,
        isDefault: false
    )

    static let o1 = AIModelDefinition(
        id: "o1",
        displayName: "o1",
        provider: .openAI,
        inputCostPer1MTokens: 15.0,
        outputCostPer1MTokens: 60.0,
        maxContextTokens: 200_000,
        isDefault: false
    )

    // MARK: Ollama Models

    static let llama31 = AIModelDefinition(
        id: "llama3.1",
        displayName: "Llama 3.1",
        provider: .ollama,
        inputCostPer1MTokens: 0,
        outputCostPer1MTokens: 0,
        maxContextTokens: 128_000,
        isDefault: true
    )

    static let llama32 = AIModelDefinition(
        id: "llama3.2",
        displayName: "Llama 3.2",
        provider: .ollama,
        inputCostPer1MTokens: 0,
        outputCostPer1MTokens: 0,
        maxContextTokens: 128_000,
        isDefault: false
    )

    static let mistral = AIModelDefinition(
        id: "mistral",
        displayName: "Mistral",
        provider: .ollama,
        inputCostPer1MTokens: 0,
        outputCostPer1MTokens: 0,
        maxContextTokens: 32_000,
        isDefault: false
    )

    // MARK: Gemini Models

    static let gemini25Flash = AIModelDefinition(
        id: "gemini-2.5-flash",
        displayName: "Gemini 2.5 Flash",
        provider: .gemini,
        inputCostPer1MTokens: 0.15,
        outputCostPer1MTokens: 0.60,
        maxContextTokens: 1_000_000,
        isDefault: true
    )

    static let gemini25Pro = AIModelDefinition(
        id: "gemini-2.5-pro",
        displayName: "Gemini 2.5 Pro",
        provider: .gemini,
        inputCostPer1MTokens: 1.25,
        outputCostPer1MTokens: 10.0,
        maxContextTokens: 1_000_000,
        isDefault: false
    )

    // MARK: OpenRouter Models

    static let openRouterGeminiFlashLite = AIModelDefinition(
        id: "openrouter/google/gemini-2.5-flash-lite-preview",
        displayName: "Gemini 2.5 Flash Lite (OpenRouter)",
        provider: .openRouter,
        inputCostPer1MTokens: 0.10,
        outputCostPer1MTokens: 0.40,
        maxContextTokens: 100_000,
        isDefault: true
    )

    static let openRouterClaudeHaiku = AIModelDefinition(
        id: "openrouter/anthropic/claude-3.5-haiku",
        displayName: "Claude 3.5 Haiku (OpenRouter)",
        provider: .openRouter,
        inputCostPer1MTokens: 0.80,
        outputCostPer1MTokens: 4.0,
        maxContextTokens: 200_000,
        isDefault: false
    )

    static let openRouterGPT4oMini = AIModelDefinition(
        id: "openrouter/openai/gpt-4o-mini",
        displayName: "GPT-4o Mini (OpenRouter)",
        provider: .openRouter,
        inputCostPer1MTokens: 0.15,
        outputCostPer1MTokens: 0.60,
        maxContextTokens: 128_000,
        isDefault: false
    )

    static let openRouterLlama3 = AIModelDefinition(
        id: "openrouter/meta-llama/llama-3.1-8b-instruct",
        displayName: "Llama 3.1 8B (OpenRouter)",
        provider: .openRouter,
        inputCostPer1MTokens: 0.04,
        outputCostPer1MTokens: 0.04,
        maxContextTokens: 128_000,
        isDefault: false
    )

    static let openRouterMistralNemo = AIModelDefinition(
        id: "openrouter/mistralai/mistral-nemo",
        displayName: "Mistral Nemo (OpenRouter)",
        provider: .openRouter,
        inputCostPer1MTokens: 0.15,
        outputCostPer1MTokens: 0.15,
        maxContextTokens: 128_000,
        isDefault: false
    )

    static let openRouterQwen = AIModelDefinition(
        id: "openrouter/qwen/qwen-2.5-72b-instruct",
        displayName: "Qwen 2.5 72B (OpenRouter)",
        provider: .openRouter,
        inputCostPer1MTokens: 0.90,
        outputCostPer1MTokens: 0.90,
        maxContextTokens: 32_000,
        isDefault: false
    )

    // MARK: Local (On-Device CoreML) Models

    static let localSmolLM2 = AIModelDefinition(
        id: "apple/SmolLM2-360M-Instruct-CoreML",
        displayName: "SmolLM2 360M (On-Device)",
        provider: .local,
        inputCostPer1MTokens: 0,
        outputCostPer1MTokens: 0,
        maxContextTokens: 2_048,
        isDefault: true
    )

    static let localPhi3Mini = AIModelDefinition(
        id: "apple/Phi-3-mini-128k-instruct-CoreML",
        displayName: "Phi-3 Mini (On-Device)",
        provider: .local,
        inputCostPer1MTokens: 0,
        outputCostPer1MTokens: 0,
        maxContextTokens: 4_096,
        isDefault: false
    )

    static let localOpenELM3B = AIModelDefinition(
        id: "apple/OpenELM-3B-Instruct-CoreML",
        displayName: "OpenELM 3B (On-Device)",
        provider: .local,
        inputCostPer1MTokens: 0,
        outputCostPer1MTokens: 0,
        maxContextTokens: 2_048,
        isDefault: false
    )

    // MARK: All Models

    static let allModels: [AIModelDefinition] = [
        claudeOpus46, claudeSonnet46, claudeOpus4, claudeSonnet4, claudeHaiku35,
        gpt54, gpt54Mini, gpt54Nano, gpt5, gpt4o, gpt4oMini, o1,
        llama31, llama32, mistral,
        gemini25Flash, gemini25Pro,
        openRouterGeminiFlashLite, openRouterClaudeHaiku, openRouterGPT4oMini,
        openRouterLlama3, openRouterMistralNemo, openRouterQwen,
        localSmolLM2, localPhi3Mini, localOpenELM3B,
    ]

    // MARK: Lookup

    /// Returns all catalog models for a given provider.
    static func models(for provider: AIProviderKind) -> [AIModelDefinition] {
        allModels.filter { $0.provider == provider }
    }

    /// Returns the default model for a provider, or the first available model.
    static func defaultModel(for provider: AIProviderKind) -> AIModelDefinition? {
        let providerModels = models(for: provider)
        return providerModels.first(where: \.isDefault) ?? providerModels.first
    }

    /// Looks up a model by its ID across all providers.
    static func model(byID id: String) -> AIModelDefinition? {
        allModels.first { $0.id == id }
    }

    // MARK: Cost Estimation

    /// Calculates the estimated USD cost for a given token usage.
    ///
    /// Returns 0 for unknown model IDs (safe fallback for Ollama custom models).
    static func estimateCost(modelID: String, inputTokens: Int, outputTokens: Int) -> Double {
        guard let model = model(byID: modelID) else { return 0 }
        return estimateCost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    /// Calculates the estimated USD cost for a given model definition and token usage.
    static func estimateCost(model: AIModelDefinition, inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost = Double(inputTokens) * model.inputCostPer1MTokens / 1_000_000.0
        let outputCost = Double(outputTokens) * model.outputCostPer1MTokens / 1_000_000.0
        return inputCost + outputCost
    }
}

// MARK: - Live Model Fetcher

enum AIModelFetcher {

    /// Fetches available models from the OpenAI API.
    static func fetchOpenAIModels(apiKey: String) async -> [AIModelDefinition] {
        guard !apiKey.isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return [] }

        let chatModelPrefixes = ["gpt-5", "gpt-4", "gpt-3.5", "o1", "o3", "o4", "chatgpt"]
        return items.compactMap { item -> AIModelDefinition? in
            guard let id = item["id"] as? String else { return nil }
            let lower = id.lowercased()
            guard chatModelPrefixes.contains(where: { lower.hasPrefix($0) }) else { return nil }
            // Skip snapshots / fine-tunes to keep the list clean
            if lower.contains("realtime") || lower.contains("audio") || lower.contains("search") { return nil }
            let catalogMatch = AIModelCatalog.model(byID: id)
            return AIModelDefinition(
                id: id,
                displayName: catalogMatch?.displayName ?? formatModelID(id),
                provider: .openAI,
                inputCostPer1MTokens: catalogMatch?.inputCostPer1MTokens ?? 0,
                outputCostPer1MTokens: catalogMatch?.outputCostPer1MTokens ?? 0,
                maxContextTokens: catalogMatch?.maxContextTokens ?? 128_000,
                isDefault: catalogMatch?.isDefault ?? false
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Fetches available models from the Anthropic API.
    static func fetchAnthropicModels(apiKey: String) async -> [AIModelDefinition] {
        guard !apiKey.isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=50")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return [] }

        return items.compactMap { item -> AIModelDefinition? in
            guard let id = item["id"] as? String else { return nil }
            let displayName = item["display_name"] as? String
            let catalogMatch = AIModelCatalog.model(byID: id)
            return AIModelDefinition(
                id: id,
                displayName: catalogMatch?.displayName ?? displayName ?? formatModelID(id),
                provider: .anthropic,
                inputCostPer1MTokens: catalogMatch?.inputCostPer1MTokens ?? 0,
                outputCostPer1MTokens: catalogMatch?.outputCostPer1MTokens ?? 0,
                maxContextTokens: catalogMatch?.maxContextTokens ?? 200_000,
                isDefault: catalogMatch?.isDefault ?? false
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Fetches locally installed models from an Ollama instance.
    static func fetchOllamaModels(baseURL: String) async -> [AIModelDefinition] {
        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard AIOllamaEndpointPolicy.isAllowedBaseURL(endpoint) else { return [] }
        guard let url = URL(string: "\(endpoint)/api/tags") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }

        return models.compactMap { item -> AIModelDefinition? in
            guard let name = item["name"] as? String else { return nil }
            // Strip :latest tag for cleaner display
            let cleanID = name.hasSuffix(":latest") ? String(name.dropLast(7)) : name
            let catalogMatch = AIModelCatalog.model(byID: cleanID)
            return AIModelDefinition(
                id: cleanID,
                displayName: catalogMatch?.displayName ?? formatModelID(cleanID),
                provider: .ollama,
                inputCostPer1MTokens: 0,
                outputCostPer1MTokens: 0,
                maxContextTokens: catalogMatch?.maxContextTokens ?? 128_000,
                isDefault: catalogMatch?.isDefault ?? false
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Fetches available models from the OpenRouter API.
    static func fetchOpenRouterModels(
        apiKey: String,
        session: URLSession = .shared
    ) async -> [AIModelDefinition] {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else { return [] }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return [] }

        return items.compactMap { item -> AIModelDefinition? in
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            let catalogMatch = AIModelCatalog.model(byID: id)
            let displayName = (item["name"] as? String)
                ?? catalogMatch?.displayName
                ?? formatModelID(id)
            let pricing = item["pricing"] as? [String: Any]
            let inputCost = catalogMatch?.inputCostPer1MTokens
                ?? scaledOpenRouterPrice(from: pricing?["prompt"])
                ?? 0
            let outputCost = catalogMatch?.outputCostPer1MTokens
                ?? scaledOpenRouterPrice(from: pricing?["completion"])
                ?? 0
            let contextLength = (item["context_length"] as? Int)
                ?? catalogMatch?.maxContextTokens
                ?? 128_000

            return AIModelDefinition(
                id: id,
                displayName: displayName,
                provider: .openRouter,
                inputCostPer1MTokens: inputCost,
                outputCostPer1MTokens: outputCost,
                maxContextTokens: contextLength,
                isDefault: catalogMatch?.isDefault ?? false
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Fetches available models from the Google Gemini API.
    static func fetchGeminiModels(apiKey: String) async -> [AIModelDefinition] {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else { return [] }
        var components = URLComponents(string: "https://generativelanguage.googleapis.com")
        components?.path = "/v1beta/models"
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["models"] as? [[String: Any]] else { return [] }

        return items.compactMap { item -> AIModelDefinition? in
            guard let name = item["name"] as? String else { return nil }
            // name is "models/gemini-2.5-flash" — extract the model ID
            let id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
            guard id.lowercased().contains("gemini") else { return nil }
            let displayName = item["displayName"] as? String
            let catalogMatch = AIModelCatalog.model(byID: id)
            return AIModelDefinition(
                id: id,
                displayName: catalogMatch?.displayName ?? displayName ?? formatModelID(id),
                provider: .gemini,
                inputCostPer1MTokens: catalogMatch?.inputCostPer1MTokens ?? 0,
                outputCostPer1MTokens: catalogMatch?.outputCostPer1MTokens ?? 0,
                maxContextTokens: catalogMatch?.maxContextTokens ?? 1_000_000,
                isDefault: catalogMatch?.isDefault ?? false
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Formats a raw model ID into a human-readable display name.
    private static func formatModelID(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ")
          .replacingOccurrences(of: "_", with: " ")
          .split(separator: " ")
          .map { $0.prefix(1).uppercased() + $0.dropFirst() }
          .joined(separator: " ")
    }

    private static func scaledOpenRouterPrice(from value: Any?) -> Double? {
        if let string = value as? String, let parsed = Double(string) {
            return parsed * 1_000_000
        }
        if let number = value as? NSNumber {
            return number.doubleValue * 1_000_000
        }
        return nil
    }
}
