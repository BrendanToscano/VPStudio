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

    static let gpt52 = AIModelDefinition(
        id: "gpt-5.2",
        displayName: "GPT-5.2",
        provider: .openAI,
        inputCostPer1MTokens: 2.0,
        outputCostPer1MTokens: 8.0,
        maxContextTokens: 128_000,
        isDefault: true
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

    // MARK: All Models

    static let allModels: [AIModelDefinition] = [
        claudeOpus46, claudeSonnet46, claudeOpus4, claudeSonnet4, claudeHaiku35,
        gpt52, gpt5, gpt4o, gpt4oMini, o1,
        llama31, llama32, mistral,
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

    /// Formats a raw model ID into a human-readable display name.
    private static func formatModelID(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ")
          .replacingOccurrences(of: "_", with: " ")
          .split(separator: " ")
          .map { $0.prefix(1).uppercased() + $0.dropFirst() }
          .joined(separator: " ")
    }
}
