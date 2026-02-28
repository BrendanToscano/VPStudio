import Foundation

/// Multi-provider AI assistant for recommendations and conversation
actor AIAssistantManager {
    private let database: DatabaseManager
    private var providers: [AIProviderKind: any AIProvider] = [:]
    private let contextAssembler = AssistantContextAssembler()

    init(database: DatabaseManager) {
        self.database = database
    }

    var hasConfiguredProvider: Bool {
        !providers.isEmpty
    }

    func registerProvider(kind: AIProviderKind, provider: any AIProvider) {
        providers[kind] = provider
    }

    func clearProviders() {
        providers.removeAll()
    }

    func configure(provider: AIProviderKind, apiKey: String, baseURL: String? = nil, model: String? = nil) {
        let defaultModelID = AIModelCatalog.defaultModel(for: provider)?.id
        switch provider {
        case .anthropic:
            providers[.anthropic] = AnthropicProvider(apiKey: apiKey, model: model ?? defaultModelID ?? "claude-sonnet-4-6")
        case .openAI:
            providers[.openAI] = OpenAIProvider(apiKey: apiKey, model: model ?? defaultModelID ?? "gpt-5.2")
        case .ollama:
            providers[.ollama] = OllamaProvider(baseURL: baseURL ?? "http://localhost:11434", model: model ?? defaultModelID ?? "llama3.1")
        case .gemini:
            providers[.gemini] = GeminiProvider(apiKey: apiKey, model: model ?? defaultModelID ?? "gemini-2.0-flash", baseURL: baseURL ?? "https://generativelanguage.googleapis.com/v1beta")
        }
    }

    /// Ask the AI a question with optional context
    func ask(prompt: String, provider: AIProviderKind? = nil, context: AssistantContext? = nil) async throws -> AIProviderResponse {
        let selectedProvider = provider ?? providers.keys.sorted(by: { $0.rawValue < $1.rawValue }).first
        guard let kind = selectedProvider, let aiProvider = providers[kind] else {
            throw AIError.noProviderConfigured
        }

        let assembledNotes = await assembledContextNotes()
        let resolvedContext = await contextualizedContext(from: context)
        let systemPrompt = buildSystemPrompt(context: resolvedContext, assembledNotes: assembledNotes)
        let response = try await aiProvider.complete(system: systemPrompt, userMessage: prompt)
        logUsage(response: response, requestType: .ask)
        return response
    }

    /// Get movie/show recommendations based on user taste
    func getRecommendations(context: AssistantContext, provider: AIProviderKind? = nil) async throws -> [AIMovieRecommendation] {
        var promptParts = [
            "Based on my viewing history and preferences, recommend 10 movies or TV shows I'd enjoy.",
            "Focus on titles I haven't seen yet.",
            "For each, provide: title, year, type (movie/series), and a brief reason why I'd like it.",
            "Format as JSON array with keys: title, year, type, reason, tmdbId (if known).",
        ]
        if let mood = context.currentMood {
            promptParts.insert("I'm currently in the mood for: \(mood).", at: 1)
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
        let overviewStr = (overview ?? "").isEmpty ? "" : " Synopsis: \(overview!)"

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
        let providersCopy = providers
        var results: [AIProviderKind: AIProviderResponse] = [:]
        var errors: [AIProviderKind: String] = [:]

        let assembledNotes = await assembledContextNotes()
        let resolvedContext = await contextualizedContext(from: context)
        let systemPrompt = buildSystemPrompt(context: resolvedContext, assembledNotes: assembledNotes)

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
            logUsage(response: response, requestType: .compare)
        }

        return AICompareResult(prompt: prompt, responses: results, errors: errors)
    }

    /// Build contextual system prompt, merging assembled context notes with any ad-hoc context.
    private func buildSystemPrompt(context: AssistantContext?, assembledNotes: [String] = []) -> String {
        var parts = [
            "You are VPStudio AI, a knowledgeable movie and TV show assistant.",
            "You help users discover content they'll love based on their preferences.",
            "Provide specific, actionable recommendations with reasoning.",
        ]

        // Inject assembled context notes (from periodic indexing)
        for note in assembledNotes {
            parts.append(note)
        }

        // Overlay any ad-hoc context from the caller
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

        return parts.joined(separator: "\n")
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

    /// Invalidates the assembler's cached snapshot, forcing a rebuild on the next request.
    func invalidateContextCache() async {
        await contextAssembler.invalidateCache()
    }

    // MARK: - Usage Tracking

    private nonisolated func logUsage(response: AIProviderResponse, requestType: AIRequestType) {
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
        let database = self.database
        Task.detached {
            try? await database.saveAIUsageRecord(record)
        }
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
