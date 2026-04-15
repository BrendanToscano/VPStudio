import Foundation
import OSLog

/// Multi-provider AI assistant for recommendations and conversation
actor AIAssistantManager {
    private static let logger = Logger(subsystem: "VPStudio", category: "AI")
    private let database: DatabaseManager
    private var providers: [AIProviderKind: any AIProvider] = [:]
    private var configuredModels: [AIProviderKind: String] = [:]
    private let contextAssembler = AssistantContextAssembler()
    private(set) var lastUsagePersistenceErrorMessage: String?

    nonisolated static let defaultProviderResolutionOrder: [AIProviderKind] = [
        .anthropic,
        .openAI,
        .gemini,
        .openRouter,
        .ollama,
        .local,
    ]

    init(database: DatabaseManager) {
        self.database = database
    }

    var hasConfiguredProvider: Bool {
        !usableProviders().isEmpty
    }

    func registerProvider(kind: AIProviderKind, provider: any AIProvider) {
        providers[kind] = provider
        configuredModels[kind] = Self.inferredModelID(from: provider) ?? AIModelCatalog.defaultModel(for: kind)?.id
    }

    func clearProviders() {
        providers.removeAll()
        configuredModels.removeAll()
    }

    nonisolated static func resolvedDefaultProvider(
        preferredProvider: AIProviderKind?,
        availableProviders: [AIProviderKind]
    ) -> AIProviderKind? {
        let availableSet = Set(availableProviders)
        guard !availableSet.isEmpty else { return nil }

        if let preferredProvider, availableSet.contains(preferredProvider) {
            return preferredProvider
        }

        for candidate in defaultProviderResolutionOrder where availableSet.contains(candidate) {
            return candidate
        }

        return availableProviders.sorted { $0.rawValue < $1.rawValue }.first
    }

    func configure(provider: AIProviderKind, apiKey: String, baseURL: String? = nil, model: String? = nil) {
        let configuredModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalogDefaultModelID = AIModelCatalog.defaultModel(for: provider)?.id
        let resolvedModel = Self.resolvedModelID(
            provider: provider,
            catalogDefault: catalogDefaultModelID,
            configuredModel: configuredModel
        )

        switch provider {
        case .anthropic:
            providers[.anthropic] = AnthropicProvider(apiKey: apiKey, model: resolvedModel)
        case .openAI:
            providers[.openAI] = OpenAIProvider(apiKey: apiKey, model: resolvedModel)
        case .ollama:
            let resolvedBaseURL = (baseURL ?? "http://localhost:11434")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !resolvedBaseURL.isEmpty else {
                providers.removeValue(forKey: .ollama)
                configuredModels.removeValue(forKey: .ollama)
                Self.logger.info("Skipped Ollama configuration because the endpoint was empty.")
                return
            }

            if let warning = AIOllamaEndpointPolicy.warningMessage(for: resolvedBaseURL) {
                providers.removeValue(forKey: .ollama)
                configuredModels.removeValue(forKey: .ollama)
                if warning.contains("Plain HTTP is only allowed") {
                    Self.logger.error(
                        "Rejected insecure Ollama endpoint: \(resolvedBaseURL, privacy: .public)"
                    )
                } else {
                    Self.logger.info(
                        "Skipped Ollama configuration because the endpoint was invalid."
                    )
                }
                return
            }

            providers[.ollama] = OllamaProvider(
                baseURL: resolvedBaseURL,
                model: resolvedModel
            )
        case .gemini:
            providers[.gemini] = GeminiProvider(apiKey: apiKey, model: resolvedModel)
        case .openRouter:
            providers[.openRouter] = OpenRouterProvider(
                apiKey: apiKey,
                model: resolvedModel
            )
        case .local:
            break // Local provider is registered directly via registerProvider in AppState
        }

        configuredModels[provider] = resolvedModel
    }

    /// Ask the AI a question with optional context
    func ask(prompt: String, provider: AIProviderKind? = nil, context: AssistantContext? = nil) async throws -> AIProviderResponse {
        let selectedProvider = await resolvedProvider(for: provider)
        guard let kind = selectedProvider, let aiProvider = providers[kind] else {
            throw AIError.noProviderConfigured
        }

        let assembledNotes = await assembledContextNotes()
        let resolvedContext = await contextualizedContext(from: context)
        let systemPrompt = buildSystemPrompt(
            context: resolvedContext,
            assembledNotes: assembledNotes,
            budgetTokens: promptBudgetTokens(for: kind)
        )
        let response = try await aiProvider.complete(system: systemPrompt, userMessage: prompt)
        await logUsage(response: response, requestType: .ask)
        return response
    }

    private func resolvedProvider(for requestedProvider: AIProviderKind?) async -> AIProviderKind? {
        let availableProviders = usableProviders()
        guard !availableProviders.isEmpty else { return nil }

        if let requestedProvider {
            return Self.resolvedDefaultProvider(
                preferredProvider: requestedProvider,
                availableProviders: Array(availableProviders.keys)
            )
        }

        let preferredProvider = await preferredDefaultProvider()
        return Self.resolvedDefaultProvider(
            preferredProvider: preferredProvider,
            availableProviders: Array(availableProviders.keys)
        )
    }

    private func preferredDefaultProvider() async -> AIProviderKind? {
        guard let rawValue = try? await database.getSetting(key: SettingsKeys.defaultAIProvider) else {
            return nil
        }
        return AIProviderKind(rawValue: rawValue)
    }

    /// Get movie/show recommendations based on user taste
    func getRecommendations(
        context: AssistantContext,
        provider: AIProviderKind? = nil,
        excludingTitles: [String] = []
    ) async throws -> [AIMovieRecommendation] {
        var promptParts = [
            "Based on my viewing history and preferences, recommend 10 movies or TV shows I'd enjoy.",
            "Focus on titles I haven't seen yet.",
            "For each, provide: title, year, type (movie/series), and a brief reason why I'd like it.",
            "Format as JSON array with keys: title, year, type, reason, tmdbId.",
            "Only include tmdbId when you are highly confident it is correct. Otherwise use null.",
        ]
        if let mood = context.currentMood {
            promptParts.insert("I'm currently in the mood for: \(mood).", at: 1)
        }
        if !excludingTitles.isEmpty {
            let exclusions = excludingTitles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(12)
                .joined(separator: ", ")
            if !exclusions.isEmpty {
                promptParts.append("Do not recommend any of these titles again: \(exclusions).")
                promptParts.append("Return a meaningfully different list from those excluded titles.")
            }
        }
        let prompt = promptParts.joined(separator: " ")

        let response = try await ask(prompt: prompt, provider: provider, context: context)

        return try parseRecommendations(from: response.content)
    }

    /// Personalized analysis of a specific movie/show for the user
    func getPersonalizedAnalysis(
        title: String,
        year: Int?,
        type: MediaType,
        genres: [String],
        overview: String?
    ) async throws -> AIPersonalizedAnalysis {
        let yearStr = year.map { " (\($0))" } ?? ""
        let genreStr = genres.isEmpty ? "" : " Genres: \(genres.joined(separator: ", "))."
        let overviewStr = overview.flatMap { $0.isEmpty ? nil : " Synopsis: \($0)" } ?? ""

        let prompt = """
        Analyze this \(type == .movie ? "movie" : "TV show") for me personally based on my taste profile:

        Title: \(title)\(yearStr)
        Type: \(type == .movie ? "Movie" : "TV Series")\(genreStr)\(overviewStr)

        Respond with ONLY a JSON object (no markdown, no explanation) with these exact keys:
        - "personalizedDescription": A 2-3 sentence description tailored to what I'd specifically appreciate or dislike about it based on my preferences.
        - "predictedRating": A number 1-10 predicting how I'd rate it.
        - "verdict": One of "strong_yes", "yes", "maybe", "no", "strong_no".
        - "reasons": An array of 2-4 short bullet points explaining why.
        """

        let response = try await ask(prompt: prompt, context: AssistantContext())
        return try parsePersonalizedAnalysis(from: response.content)
    }

    nonisolated static func resolvedModelID(
        provider: AIProviderKind,
        catalogDefault: String?,
        configuredModel: String?
    ) -> String {
        if let configuredModel, !configuredModel.isEmpty {
            return configuredModel
        }

        return catalogDefault ?? fallbackModelID(for: provider)
    }

    nonisolated static func fallbackModelID(for provider: AIProviderKind) -> String {
        if let catalogDefault = AIModelCatalog.defaultModel(for: provider)?.id {
            return catalogDefault
        }

        switch provider {
        case .anthropic:
            return AIModelCatalog.claudeSonnet4.id
        case .openAI:
            return AIModelCatalog.gpt54.id
        case .gemini:
            return AIModelCatalog.gemini25Flash.id
        case .ollama:
            return AIModelCatalog.llama31.id
        case .openRouter:
            return AIModelCatalog.openRouterGeminiFlashLite.id
        case .local:
            return AIModelCatalog.localSmolLM2.id
        }
    }

    nonisolated static func availableDefaultProviders(
        configuredCloudProviders: [AIProviderKind],
        hasOllamaEndpoint: Bool,
        hasUsableLocalProvider: Bool
    ) -> [AIProviderKind] {
        var available = configuredCloudProviders
        if hasOllamaEndpoint {
            available.append(.ollama)
        }
        if hasUsableLocalProvider {
            available.append(.local)
        }

        var seen = Set<AIProviderKind>()
        return defaultProviderResolutionOrder.filter { provider in
            guard available.contains(provider), !seen.contains(provider) else { return false }
            seen.insert(provider)
            return true
        }
    }

    private func parsePersonalizedAnalysis(from content: String) throws -> AIPersonalizedAnalysis {
        let candidates = [content] + fencedCodeBlockCandidates(from: content)

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let analysis = try? JSONDecoder().decode(AIPersonalizedAnalysis.self, from: data) {
                return analysis
            }
        }

        // Try extracting JSON object from braces
        if let firstBrace = content.firstIndex(of: "{"),
           let lastBrace = content.lastIndex(of: "}"),
           firstBrace < lastBrace {
            let slice = String(content[firstBrace...lastBrace])
            if let data = slice.data(using: .utf8),
               let analysis = try? JSONDecoder().decode(AIPersonalizedAnalysis.self, from: data) {
                return analysis
            }
        }

        throw AIError.invalidResponse
    }

    /// Compare recommendations across providers
    func compareProviders(prompt: String, context: AssistantContext?) async throws -> AICompareResult {
        let providersCopy = usableProviders()
        var results: [AIProviderKind: AIProviderResponse] = [:]
        var errors: [AIProviderKind: String] = [:]

        let assembledNotes = await assembledContextNotes()
        let resolvedContext = await contextualizedContext(from: context)
        let systemPrompt = buildSystemPrompt(
            context: resolvedContext,
            assembledNotes: assembledNotes,
            budgetTokens: promptBudgetTokens(for: Array(providersCopy.keys))
        )

        await withTaskGroup(of: (AIProviderKind, Result<AIProviderResponse, Error>).self) { group in
            for (kind, provider) in providersCopy {
                group.addTask {
                    do {
                        let response = try await provider.complete(system: systemPrompt, userMessage: prompt)
                        return (kind, .success(response))
                    } catch {
                        return (kind, .failure(error))
                    }
                }
            }
            for await (kind, result) in group {
                switch result {
                case .success(let response):
                    results[kind] = response
                case .failure(let error):
                    errors[kind] = error.localizedDescription
                }
            }
        }

        for (_, response) in results {
            await logUsage(response: response, requestType: .compare)
        }

        return AICompareResult(prompt: prompt, responses: results, errors: errors)
    }

    /// Build contextual system prompt, merging assembled context notes with any ad-hoc context.
    private func buildSystemPrompt(
        context: AssistantContext?,
        assembledNotes: [String] = [],
        budgetTokens: Int
    ) -> String {
        var parts = [
            "You are VPStudio AI, a knowledgeable movie and TV show assistant.",
            "You help users discover content they'll love based on their preferences.",
            "Provide specific, actionable recommendations with reasoning.",
        ]

        // Overlay any ad-hoc context from the caller first so request-scoped data is
        // preserved when the prompt needs to be trimmed to a model-specific budget.
        if let ctx = context {
            if !ctx.recentlyWatched.isEmpty {
                parts.append("Recently watched: \(ctx.recentlyWatched.joined(separator: ", "))")
            }
            if !ctx.historyTitles.isEmpty {
                parts.append("History titles: \(ctx.historyTitles.joined(separator: ", "))")
            }
            if !ctx.favoriteGenres.isEmpty {
                parts.append("Favorite genres: \(ctx.favoriteGenres.joined(separator: ", "))")
            }
            if !ctx.dislikedGenres.isEmpty {
                parts.append("Dislikes: \(ctx.dislikedGenres.joined(separator: ", "))")
            }
            if !ctx.watchlistTitles.isEmpty {
                parts.append("Watchlist titles: \(ctx.watchlistTitles.joined(separator: ", "))")
            }
            if !ctx.favoriteTitles.isEmpty {
                parts.append("Favorite titles: \(ctx.favoriteTitles.joined(separator: ", "))")
            }
            if let feedbackScaleMode = ctx.feedbackScaleMode {
                parts.append("Rating scale preference: \(feedbackScaleMode.displayName)")
            }
            if !ctx.likedTitles.isEmpty {
                parts.append("Liked titles: \(ctx.likedTitles.joined(separator: ", "))")
            }
            if !ctx.dislikedTitles.isEmpty {
                parts.append("Disliked titles: \(ctx.dislikedTitles.joined(separator: ", "))")
            }
            if !ctx.ratedTitles.isEmpty {
                parts.append("Recent ratings: \(ctx.ratedTitles.joined(separator: ", "))")
            }
            if let mood = ctx.currentMood {
                parts.append("Current mood: \(mood)")
            }
        }

        // Inject assembled context notes (from periodic indexing) after caller-supplied data.
        for note in assembledNotes {
            parts.append(note)
        }

        return AssistantPromptBudgetPolicy.composePrompt(from: parts, budgetTokens: budgetTokens)
    }

    private func parseRecommendations(from content: String) throws -> [AIMovieRecommendation] {
        guard let data = recommendationData(from: content) else {
            throw AIError.invalidResponse
        }

        struct RawRec: Decodable {
            let title: String
            let year: Int?
            let type: String?
            let reason: String?
            let tmdbId: Int?
        }

        let raws = try JSONDecoder().decode([RawRec].self, from: data)

        return raws.map {
            let normalizedType = ($0.type ?? "").lowercased()
            return AIMovieRecommendation(
                title: $0.title,
                year: $0.year,
                type: normalizedType == "series" || normalizedType == "show" || normalizedType == "tv" ? .series : .movie,
                reason: $0.reason ?? "",
                tmdbId: $0.tmdbId
            )
        }
    }

    private func recommendationData(from content: String) -> Data? {
        let candidates = [content] + fencedCodeBlockCandidates(from: content) + bracketedJSONArrayCandidates(from: content)

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }

        return nil
    }

    private func fencedCodeBlockCandidates(from content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "```(?:json)?\\s*([\\s\\S]*?)```", options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        return matches.compactMap { match in
            guard let blockRange = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[blockRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func bracketedJSONArrayCandidates(from content: String) -> [String] {
        guard let lastBracket = content.lastIndex(of: "]") else { return [] }
        var results: [String] = []
        for (index, char) in content.enumerated() where char == "[" {
            let start = content.index(content.startIndex, offsetBy: index)
            guard start <= lastBracket else { break }
            let slice = String(content[start...lastBracket]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !slice.isEmpty {
                results.append(slice)
            }
        }
        return results
    }

    private func contextualizedContext(from context: AssistantContext?) async -> AssistantContext {
        var merged = context ?? AssistantContext()

        do {
            let watchlistEntries = try await database.fetchLibraryEntries(listType: .watchlist)
            let favoriteEntries = try await database.fetchLibraryEntries(listType: .favorites)
            let historyEntries = try await database.fetchWatchHistory(limit: 120)
            let ratingEvents = try await database.fetchTasteEvents(eventType: .rated, limit: 300)
            let feedbackScaleRaw = try await database.getSetting(key: SettingsKeys.feedbackScaleMode)
            let configuredFeedbackScale = FeedbackScaleMode.fromStoredValue(feedbackScaleRaw)
            let database = self.database

            let ratingMediaIDs = ratingEvents.compactMap(\.mediaId)
            let allMediaIDs = Set(watchlistEntries.map(\.mediaId) + favoriteEntries.map(\.mediaId) + ratingMediaIDs)
            var titleByMediaID: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { group in
                for mediaID in allMediaIDs {
                    group.addTask {
                        let title = try? await database.fetchMediaItem(id: mediaID)?.title
                        return (mediaID, title)
                    }
                }
                for await (mediaID, title) in group {
                    if let title, !title.isEmpty {
                        titleByMediaID[mediaID] = title
                    }
                }
            }

            let watchlistTitles = watchlistEntries.compactMap { titleByMediaID[$0.mediaId] }
            let favoriteTitles = favoriteEntries.compactMap { titleByMediaID[$0.mediaId] }
            let historyTitles = historyEntries.map(\.title)
            let feedbackSummary = summarizedFeedback(
                events: ratingEvents,
                titleByMediaID: titleByMediaID,
                defaultScale: configuredFeedbackScale
            )

            merged.watchlistTitles = mergeUnique(current: merged.watchlistTitles, incoming: watchlistTitles)
            merged.favoriteTitles = mergeUnique(current: merged.favoriteTitles, incoming: favoriteTitles)
            merged.historyTitles = mergeUnique(current: merged.historyTitles, incoming: historyTitles)
            merged.recentlyWatched = mergeUnique(current: merged.recentlyWatched, incoming: Array(historyTitles.prefix(20)))
            if merged.feedbackScaleMode == nil {
                merged.feedbackScaleMode = configuredFeedbackScale
            }
            merged.likedTitles = mergeUnique(current: merged.likedTitles, incoming: feedbackSummary.likedTitles)
            merged.dislikedTitles = mergeUnique(current: merged.dislikedTitles, incoming: feedbackSummary.dislikedTitles)
            merged.ratedTitles = mergeUnique(current: merged.ratedTitles, incoming: feedbackSummary.ratedTitles)
        } catch {
            return merged
        }

        return merged
    }

    private func mergeUnique(current: [String], incoming: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for title in current + incoming {
            let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized.lowercased()).inserted {
                merged.append(normalized)
            }
        }

        return merged
    }

    private func summarizedFeedback(
        events: [TasteEvent],
        titleByMediaID: [String: String],
        defaultScale: FeedbackScaleMode
    ) -> (likedTitles: [String], dislikedTitles: [String], ratedTitles: [String]) {
        var likedTitles: [String] = []
        var dislikedTitles: [String] = []
        var ratedTitles: [String] = []

        var likedSeen = Set<String>()
        var dislikedSeen = Set<String>()
        var ratedSeen = Set<String>()

        for event in events {
            guard let value = event.feedbackValue else { continue }
            let scale = (event.feedbackScale ?? defaultScale).canonicalMode
            let title = feedbackTitle(for: event, titleByMediaID: titleByMediaID)
            guard !title.isEmpty else { continue }

            switch scale.sentiment(for: value) {
            case .liked:
                let key = title.lowercased()
                if likedSeen.insert(key).inserted {
                    likedTitles.append(title)
                }
            case .disliked:
                let key = title.lowercased()
                if dislikedSeen.insert(key).inserted {
                    dislikedTitles.append(title)
                }
            case .neutral:
                break
            }

            let rating = "\(title) (\(scale.format(value)))"
            let ratingKey = rating.lowercased()
            if ratedTitles.count < 40, ratedSeen.insert(ratingKey).inserted {
                ratedTitles.append(rating)
            }
        }

        return (likedTitles, dislikedTitles, ratedTitles)
    }

    private func feedbackTitle(
        for event: TasteEvent,
        titleByMediaID: [String: String]
    ) -> String {
        if let metadataTitle = event.metadata["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !metadataTitle.isEmpty {
            return metadataTitle
        }
        if let mediaID = event.mediaId,
           let mediaTitle = titleByMediaID[mediaID] {
            return mediaTitle
        }
        return event.mediaId ?? ""
    }

    // MARK: - Context Assembly

    /// Fetches assembled context notes from the `AssistantContextAssembler`.
    /// Returns an empty array on failure to avoid blocking the request.
    private func assembledContextNotes() async -> [String] {
        do {
            let snapshot = try await contextAssembler.cachedOrAssemble(from: database)
            return snapshot.contextNotes
        } catch {
            return []
        }
    }

    private func usableProviders() -> [AIProviderKind: any AIProvider] {
        Dictionary(uniqueKeysWithValues: providers.filter { kind, provider in
            providerIsUsable(kind: kind, provider: provider)
        })
    }

    private func providerIsUsable(kind: AIProviderKind, provider: any AIProvider) -> Bool {
        guard kind == .local else { return true }

        guard let modelID = Self.inferredModelID(from: provider), !modelID.isEmpty else {
            return false
        }

        return Self.localModelArtifactsExist(modelID: modelID)
    }

    func promptBudgetTokens(for provider: AIProviderKind) -> Int {
        let configuredModelID = configuredModels[provider] ?? AIModelCatalog.defaultModel(for: provider)?.id
        let maxContextTokens = configuredModelID.flatMap { AIModelCatalog.model(byID: $0)?.maxContextTokens }
            ?? AIModelCatalog.defaultModel(for: provider)?.maxContextTokens
            ?? 4096

        return max(512, maxContextTokens / 2)
    }

    func promptBudgetTokens(for providers: [AIProviderKind]) -> Int {
        let budgets = providers.map { promptBudgetTokens(for: $0) }
        return budgets.min() ?? 4096
    }

    private nonisolated static func inferredModelID(from provider: any AIProvider) -> String? {
        let mirror = Mirror(reflecting: provider)
        for child in mirror.children {
            if child.label == "modelID", let modelID = child.value as? String, !modelID.isEmpty {
                return modelID
            }
        }
        return nil
    }

    private nonisolated static func localModelArtifactsExist(modelID: String) -> Bool {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let sanitizedDirectoryName = modelID.replacingOccurrences(of: "/", with: "_")
        let sanitizedCacheName = modelID.replacingOccurrences(of: "/", with: "--")

        let candidateURLs = [
            appSupport?.appendingPathComponent("VPStudio/Models", isDirectory: true)
                .appendingPathComponent(sanitizedDirectoryName, isDirectory: true),
            caches?.appendingPathComponent("huggingface/hub", isDirectory: true)
                .appendingPathComponent("models--\(sanitizedCacheName)", isDirectory: true),
        ].compactMap { $0 }

        return candidateURLs.contains(where: { fileManager.fileExists(atPath: $0.path) })
    }

    /// Invalidates the assembler's cached snapshot, forcing a rebuild on the next request.
    func invalidateContextCache() async {
        await contextAssembler.invalidateCache()
    }

    // MARK: - Usage Tracking

    private func logUsage(response: AIProviderResponse, requestType: AIRequestType) async {
        let cost = AIModelCatalog.estimateCost(
            modelID: response.model,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens
        )
        let record = AIUsageRecord(
            provider: response.provider,
            model: response.model,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            estimatedCostUSD: cost,
            requestType: requestType
        )
        do {
            try await database.saveAIUsageRecord(record)
            lastUsagePersistenceErrorMessage = nil
        } catch {
            lastUsagePersistenceErrorMessage = error.localizedDescription
            Self.logger.error(
                "Failed to persist AI usage record: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

typealias AIHTTPSleep = @Sendable (TimeInterval) async throws -> Void

enum AIHTTPTransport {
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    static let defaultSleep: AIHTTPSleep = { delay in
        let boundedDelay = max(delay, 0)
        let nanoseconds = UInt64((boundedDelay * 1_000_000_000).rounded())
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    static func perform(
        _ request: URLRequest,
        using session: URLSession,
        maxRateLimitRetries: Int = 1,
        sleep: AIHTTPSleep = defaultSleep
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0

        while true {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }

            guard http.statusCode == 429 else {
                return (data, http)
            }

            guard attempt < maxRateLimitRetries else {
                throw AIError.rateLimited
            }

            attempt += 1
            try await sleep(retryDelay(from: http, attempt: attempt))
        }
    }

    static func retryDelay(from response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let retryAfter = retryAfterInterval(from: response.value(forHTTPHeaderField: "Retry-After")) {
            return min(max(retryAfter, 0), 30)
        }

        let backoff = pow(2.0, Double(max(attempt - 1, 0)))
        return min(max(backoff, 0.25), 8)
    }

    static func retryAfterInterval(from headerValue: String?) -> TimeInterval? {
        guard let trimmedHeader = headerValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedHeader.isEmpty else {
            return nil
        }

        if let seconds = Double(trimmedHeader) {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        guard let retryDate = formatter.date(from: trimmedHeader) else {
            return nil
        }

        return retryDate.timeIntervalSinceNow
    }
}

enum AIOllamaEndpointPolicy {
    static func isAllowedBaseURL(_ baseURL: String) -> Bool {
        warningMessage(for: baseURL) == nil
    }

    static func warningMessage(for baseURL: String) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return "Enter a valid Ollama server URL."
        }

        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" else { return nil }
        guard !isLocalHost(host) else { return nil }

        return "Remote Ollama endpoints must use HTTPS. Plain HTTP is only allowed for localhost and loopback addresses."
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host == "[::1]"
    }
}

// MARK: - AI Provider Protocol

protocol AIProvider: Sendable {
    var providerKind: AIProviderKind { get }
    func complete(system: String, userMessage: String) async throws -> AIProviderResponse
}

// MARK: - Context

struct AssistantContext: Sendable {
    var recentlyWatched: [String] = []
    var historyTitles: [String] = []
    var favoriteGenres: [String] = []
    var dislikedGenres: [String] = []
    var currentMood: String?
    var watchlistTitles: [String] = []
    var favoriteTitles: [String] = []
    var feedbackScaleMode: FeedbackScaleMode?
    var likedTitles: [String] = []
    var dislikedTitles: [String] = []
    var ratedTitles: [String] = []
}

// MARK: - Errors

enum AIError: LocalizedError {
    case noProviderConfigured
    case invalidResponse
    case httpError(Int, String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured: return "No AI provider configured"
        case .invalidResponse: return "Invalid AI response"
        case .httpError(let code, let msg): return "AI API error HTTP \(code): \(msg)"
        case .rateLimited: return "AI rate limited, try again shortly"
        }
    }
}
