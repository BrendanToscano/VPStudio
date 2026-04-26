import Foundation
import Observation

@Observable
@MainActor
final class DiscoverViewModel {
    var continueWatching: [(history: WatchHistory, preview: MediaPreview)] = []
    var trendingMovies: [MediaPreview] = []
    var trendingShows: [MediaPreview] = []
    var popularMovies: [MediaPreview] = []
    var topRatedMovies: [MediaPreview] = []
    var nowPlayingMovies: [MediaPreview] = []
    var featuredBackdrops: [MediaPreview] = []
    var isLoading = true
    var error: AppError?

    // MARK: - AI Curated Recommendations

    var aiRecommendations: [AIMovieRecommendation] = []
    var aiHeroPreview: MediaPreview?
    var isLoadingAIRecommendations = false
    var aiRecommendationsEnabled = false
    var aiAutoGenerate = true
    var hasPerformedInitialLoad = false
    private var aiRecommendationsLoaded = false
    private var aiResolvedPreviews: [String: MediaPreview] = [:]

    private var metadataService: (any MetadataProvider)?
    private var database: DatabaseManager?
    private let metadataServiceFactory: @Sendable (String) -> any MetadataProvider
    private var configuredApiKey: String?
    private var loadGeneration = 0

    private static let minimumUniqueRegeneratedRecommendations = 4
    private static let maximumRegenerationAttempts = 3

    init(
        metadataService: (any MetadataProvider)? = nil,
        database: DatabaseManager? = nil,
        metadataServiceFactory: @escaping @Sendable (String) -> any MetadataProvider = { TMDBService(apiKey: $0) }
    ) {
        self.metadataService = metadataService
        self.database = database
        self.metadataServiceFactory = metadataServiceFactory
    }

    func configure(database: DatabaseManager) {
        let isFirstConfiguration = self.database == nil
        if isFirstConfiguration {
            self.database = database
        }

        guard isFirstConfiguration, hasPerformedInitialLoad else { return }
        Task { [weak self] in
            await self?.refreshLocalPersonalizationState()
        }
    }

    func load(apiKey: String) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedKey.isEmpty {
            if Self.shouldResetRemoteServiceForMissingKey(configuredApiKey: configuredApiKey) {
                metadataService = nil
                configuredApiKey = nil
                clearRemoteDiscoverRows()
                await refreshAIHeroPreview()

                if QARuntimeOptions.traktRefreshFixturePath != nil {
                    await loadContinueWatching()
                    if generation == loadGeneration {
                        isLoading = false
                        error = nil
                    }
                    return
                }

                if generation == loadGeneration {
                    isLoading = false
                    error = .tmdbSetupRequired(feature: "Discover")
                }
                return
            }

            if metadataService == nil {
                await refreshAIHeroPreview()

                if QARuntimeOptions.traktRefreshFixturePath != nil {
                    await loadContinueWatching()
                    if generation == loadGeneration {
                        isLoading = false
                        error = nil
                    }
                    return
                }

                if generation == loadGeneration {
                    isLoading = false
                    error = .tmdbSetupRequired(feature: "Discover")
                }
                return
            }
        } else if metadataService == nil {
            metadataService = metadataServiceFactory(normalizedKey)
            configuredApiKey = normalizedKey
        } else if let configuredApiKey, configuredApiKey != normalizedKey {
            metadataService = metadataServiceFactory(normalizedKey)
            self.configuredApiKey = normalizedKey
        } else if configuredApiKey == nil {
            // Preserve explicitly injected metadata services (tests/previews),
            // but still remember the current key for later refreshes.
            configuredApiKey = normalizedKey
        }

        guard let service = metadataService else {
            if generation == loadGeneration {
                isLoading = false
                error = .tmdbSetupRequired(feature: "Discover")
            }
            return
        }
        isLoading = true
        error = nil

        // Load continue watching from local database (non-blocking for TMDB fetches).
        await loadContinueWatching()
        guard generation == loadGeneration else { return }

        // Fetch all categories concurrently while preserving first domain error.
        async let trendingMoviesResult = fetchResult { try await service.getTrending(type: .movie, timeWindow: .week, page: 1) }
        async let trendingShowsResult = fetchResult { try await service.getTrending(type: .series, timeWindow: .week, page: 1) }
        async let popularResult = fetchResult { try await service.getCategory(.popular, type: .movie, page: 1) }
        async let topRatedResult = fetchResult { try await service.getCategory(.topRated, type: .movie, page: 1) }
        async let nowPlayingResult = fetchResult { try await service.getCategory(.nowPlaying, type: .movie, page: 1) }

        let (moviesResult, showsResult, popularResultValue, topRatedResultValue, nowPlayingResultValue) = await (
            trendingMoviesResult, trendingShowsResult, popularResult, topRatedResult, nowPlayingResult
        )

        let results = [moviesResult, showsResult, popularResultValue, topRatedResultValue, nowPlayingResultValue]
        let firstFailure = results.compactMap { result -> Error? in
            guard case .failure(let error) = result else { return nil }
            return error
        }.first

        guard generation == loadGeneration else { return }

        if case .success(let movies) = moviesResult {
            trendingMovies = movies.items
            featuredBackdrops = Array(movies.items.prefix(5))
        }
        if case .success(let shows) = showsResult { trendingShows = shows.items }
        if case .success(let popular) = popularResultValue { popularMovies = popular.items }
        if case .success(let topRated) = topRatedResultValue { topRatedMovies = topRated.items }
        if case .success(let nowPlaying) = nowPlayingResultValue { nowPlayingMovies = nowPlaying.items }

        if trendingMovies.isEmpty,
           trendingShows.isEmpty,
           popularMovies.isEmpty,
           topRatedMovies.isEmpty,
           nowPlayingMovies.isEmpty,
           let firstFailure {
            error = AppError(firstFailure, fallback: .network(.transport("Failed to load discover content.")))
        }

        isLoading = false

        if !aiRecommendations.isEmpty {
            await refreshAIHeroPreview()
        }
    }

    func refresh() async {
        await load(apiKey: configuredApiKey ?? "")
    }

    func loadContinueWatching() async {
        let generation = loadGeneration
        guard let database else { return }
        do {
            let recentHistory = try await database.fetchWatchHistory(limit: 20)
            let inProgress = Array(recentHistory.filter {
                !$0.isCompleted && $0.progressPercent > 0.02 && $0.progressPercent < 0.95
            }.prefix(10))

            let cachedItems = try await database.fetchMediaItems(ids: inProgress.map(\.mediaId))
            let cachedByID = Dictionary(uniqueKeysWithValues: cachedItems.map { ($0.id, $0) })
            guard generation == loadGeneration else { return }

            continueWatching = inProgress.compactMap { entry in
                guard let cached = cachedByID[entry.mediaId] else { return nil }
                return (entry, MediaPreview(
                    id: cached.id,
                    type: cached.type,
                    title: cached.title,
                    year: cached.year,
                    posterPath: cached.posterPath,
                    backdropPath: cached.backdropPath,
                    imdbRating: cached.imdbRating,
                    tmdbId: cached.tmdbId,
                    episodeId: entry.episodeId
                ))
            }
        } catch {
            // Continue watching is non-critical — don't surface errors.
        }
    }

    func refreshLocalPersonalizationState() async {
        await loadContinueWatching()
        guard !aiRecommendations.isEmpty else {
            aiHeroPreview = nil
            return
        }

        let filtered = await filterOutWatchedAndRated(recommendations: aiRecommendations)
        await updateAIRecommendations(filtered)
    }

    private func fetchResult<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func clearRemoteDiscoverRows() {
        trendingMovies = []
        trendingShows = []
        popularMovies = []
        topRatedMovies = []
        nowPlayingMovies = []
        featuredBackdrops = []
    }

    nonisolated static func shouldResetRemoteServiceForMissingKey(configuredApiKey: String?) -> Bool {
        guard let configuredApiKey else { return false }
        return !configuredApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func shouldKeepRecommendation(
        title: String,
        recommendationMediaID: String,
        recommendationType: MediaType,
        tmdbId: Int?,
        ratedMediaIds: Set<String>,
        libraryMediaIds: Set<String>,
        ratedTitles: Set<String>,
        watchedTitles: Set<String>,
        libraryTitles: Set<String>
    ) -> Bool {
        let titleLower = title.lowercased()

        if ratedMediaIds.contains(recommendationMediaID) { return false }
        if libraryMediaIds.contains(recommendationMediaID) { return false }

        if let tmdbId {
            let compositeTMDBID = "\(recommendationType.rawValue)-tmdb-\(tmdbId)"
            if ratedMediaIds.contains(compositeTMDBID) { return false }
            if libraryMediaIds.contains(compositeTMDBID) { return false }
        }

        if ratedTitles.contains(titleLower) { return false }
        if watchedTitles.contains(titleLower) { return false }
        if libraryTitles.contains(titleLower) { return false }

        return true
    }

    // MARK: - AI Curated Recommendations

    func loadAIRecommendationsIfNeeded(aiManager: AIAssistantManager, settingsManager: SettingsManager) async {
        guard !aiRecommendationsLoaded else { return }
        let enabled = (try? await settingsManager.getBool(key: SettingsKeys.discoverAIRecommendationsEnabled)) ?? false
        aiRecommendationsEnabled = enabled
        guard enabled else { return }

        let autoGen = (try? await settingsManager.getBool(key: SettingsKeys.aiAutoGenerate, default: true)) ?? true
        aiAutoGenerate = autoGen

        if !autoGen {
            // Load cached recommendations instead of fetching new ones
            await loadCachedRecommendations(settingsManager: settingsManager)
            aiRecommendationsLoaded = true
            return
        }

        guard await aiManager.hasConfiguredProvider else {
            clearAIRowState()
            aiRecommendationsLoaded = true
            return
        }

        await fetchAIRecommendations(aiManager: aiManager, settingsManager: settingsManager)
    }

    func reloadAIRecommendationSettings(aiManager: AIAssistantManager, settingsManager: SettingsManager) async {
        let enabled = (try? await settingsManager.getBool(key: SettingsKeys.discoverAIRecommendationsEnabled)) ?? false
        aiRecommendationsEnabled = enabled
        let autoGen = (try? await settingsManager.getBool(key: SettingsKeys.aiAutoGenerate, default: true)) ?? true
        aiAutoGenerate = autoGen
        aiRecommendationsLoaded = false

        guard enabled else {
            aiRecommendations = []
            aiResolvedPreviews = [:]
            aiHeroPreview = nil
            isLoadingAIRecommendations = false
            return
        }

        if !autoGen {
            await loadCachedRecommendations(settingsManager: settingsManager)
            aiRecommendationsLoaded = true
            return
        }

        guard await aiManager.hasConfiguredProvider else {
            clearAIRowState()
            aiRecommendationsLoaded = true
            return
        }

        await fetchAIRecommendations(aiManager: aiManager, settingsManager: settingsManager)
    }

    func refreshAIRecommendations(aiManager: AIAssistantManager) async {
        guard await aiManager.hasConfiguredProvider else {
            clearAIRowState()
            aiRecommendationsLoaded = true
            return
        }
        aiRecommendationsLoaded = false
        await fetchAIRecommendations(aiManager: aiManager, settingsManager: nil)
    }

    func regenerateAIRecommendations(aiManager: AIAssistantManager, settingsManager: SettingsManager) async {
        guard await aiManager.hasConfiguredProvider else {
            clearAIRowState()
            aiRecommendationsLoaded = true
            return
        }
        aiRecommendationsLoaded = false
        await fetchRegeneratedAIRecommendations(
            aiManager: aiManager,
            settingsManager: settingsManager,
            excludingRecommendations: aiRecommendations
        )
    }

    func refreshResolvedAIPreviewsIfNeeded() async {
        guard !aiRecommendations.isEmpty else { return }
        let (sanitizedRecommendations, resolvedPreviews) = await sanitizeAIRecommendations(aiRecommendations)
        await updateAIRecommendations(sanitizedRecommendations, resolvedPreviews: resolvedPreviews)
    }

    @MainActor
    private func clearAIRowState() {
        aiRecommendationsEnabled = false
        aiRecommendations = []
        aiResolvedPreviews = [:]
        aiHeroPreview = nil
        isLoadingAIRecommendations = false
    }

    private func fetchAIRecommendations(aiManager: AIAssistantManager, settingsManager: SettingsManager?) async {
        isLoadingAIRecommendations = true
        do {
            let context = AssistantContext()
            let recommendations = try await aiManager.getRecommendations(context: context)
            let (sanitizedRecommendations, resolvedPreviews) = await sanitizeAIRecommendations(recommendations)
            let filtered = await filterOutWatchedAndRated(recommendations: sanitizedRecommendations)
            await updateAIRecommendations(filtered, resolvedPreviews: resolvedPreviews)
            aiRecommendationsLoaded = true

            // Cache the recommendations for offline / auto-generate-off use
            if let settingsManager {
                await cacheRecommendations(filtered, settingsManager: settingsManager)
            }
        } catch {
            // Non-critical — don't surface errors for AI row
        }
        isLoadingAIRecommendations = false
    }

    private func fetchRegeneratedAIRecommendations(
        aiManager: AIAssistantManager,
        settingsManager: SettingsManager,
        excludingRecommendations: [AIMovieRecommendation]
    ) async {
        isLoadingAIRecommendations = true
        defer { isLoadingAIRecommendations = false }

        let exclusions = excludingRecommendations
        var accumulated: [AIMovieRecommendation] = []
        var accumulatedPreviews: [String: MediaPreview] = [:]

        for _ in 0 ..< Self.maximumRegenerationAttempts {
            do {
                let context = AssistantContext()
                let excludedTitles = Self.exclusionTitles(from: exclusions + accumulated)
                let recommendations = try await aiManager.getRecommendations(
                    context: context,
                    excludingTitles: excludedTitles
                )
                let (sanitizedRecommendations, resolvedPreviews) = await sanitizeAIRecommendations(recommendations)
                let filtered = await filterOutWatchedAndRated(recommendations: sanitizedRecommendations)
                let uniqueRecommendations = Self.uniqueRecommendations(
                    from: filtered,
                    excluding: exclusions + accumulated
                )

                for recommendation in uniqueRecommendations {
                    let key = Self.aiRecommendationLookupKey(for: recommendation)
                    guard accumulatedPreviews[key] == nil else { continue }
                    if let preview = resolvedPreviews[key] {
                        accumulatedPreviews[key] = preview
                    }
                }

                accumulated.append(contentsOf: uniqueRecommendations)

                if accumulated.count >= Self.minimumUniqueRegeneratedRecommendations {
                    break
                }
            } catch {
                if !accumulated.isEmpty {
                    break
                }
                return
            }
        }

        guard !accumulated.isEmpty else {
            aiRecommendationsLoaded = true
            return
        }

        await updateAIRecommendations(accumulated, resolvedPreviews: accumulatedPreviews)
        aiRecommendationsLoaded = true
        await cacheRecommendations(accumulated, settingsManager: settingsManager)
    }

    // MARK: - Recommendation Caching

    private func cacheRecommendations(_ recommendations: [AIMovieRecommendation], settingsManager: SettingsManager) async {
        guard let data = try? JSONEncoder().encode(recommendations),
              let json = String(data: data, encoding: .utf8) else { return }
        try? await settingsManager.setString(key: SettingsKeys.aiCachedRecommendations, value: json)
    }

    private func loadCachedRecommendations(settingsManager: SettingsManager) async {
        guard let json = try? await settingsManager.getString(key: SettingsKeys.aiCachedRecommendations),
              let data = json.data(using: .utf8),
              let cached = try? JSONDecoder().decode([AIMovieRecommendation].self, from: data) else {
            await updateAIRecommendations([], resolvedPreviews: [:])
            return
        }

        let (sanitizedRecommendations, resolvedPreviews) = await sanitizeAIRecommendations(cached)
        await updateAIRecommendations(sanitizedRecommendations, resolvedPreviews: resolvedPreviews)
    }

    private func filterOutWatchedAndRated(recommendations: [AIMovieRecommendation]) async -> [AIMovieRecommendation] {
        guard let database else { return recommendations }
        do {
            let ratedEvents = try await database.fetchTasteEvents(eventType: .rated, limit: 500)
            let history = try await database.fetchWatchHistory(limit: 500)
            let watchlistEntries = try await database.fetchLibraryEntries(listType: .watchlist)
            let favoritesEntries = try await database.fetchLibraryEntries(listType: .favorites)
            let historyEntries = try await database.fetchLibraryEntries(listType: .history)
            let libraryEntries = watchlistEntries + favoritesEntries + historyEntries

            let ratedMediaIds = Set(ratedEvents.compactMap(\.mediaId))
            let ratedTitles = Set(ratedEvents.compactMap { $0.metadata["title"]?.lowercased() })
            let watchedTitles = Set(history.map { $0.title.lowercased() })
            let libraryMediaIds = Set(libraryEntries.map(\.mediaId))

            // Resolve library titles from cached media items for title-based matching
            let cachedLibraryItems = try await database.fetchMediaItems(ids: libraryEntries.map(\.mediaId))
            let libraryTitles = Set(cachedLibraryItems.map { $0.title.lowercased() })

            return recommendations.filter { rec in
                Self.shouldKeepRecommendation(
                    title: rec.title,
                    recommendationMediaID: rec.toMediaPreview().id,
                    recommendationType: rec.type,
                    tmdbId: rec.tmdbId,
                    ratedMediaIds: ratedMediaIds,
                    libraryMediaIds: libraryMediaIds,
                    ratedTitles: ratedTitles,
                    watchedTitles: watchedTitles,
                    libraryTitles: libraryTitles
                )
            }
        } catch {
            return recommendations
        }
    }

    func removeAIRecommendation(matchingMediaId mediaId: String) {
        aiRecommendations.removeAll { $0.toMediaPreview().id == mediaId }
        aiResolvedPreviews = aiResolvedPreviews.filter { key, _ in
            aiRecommendations.contains { Self.aiRecommendationLookupKey(for: $0) == key }
        }
        aiHeroPreview = aiRecommendations.first.flatMap { aiResolvedPreviews[Self.aiRecommendationLookupKey(for: $0)] } ?? aiRecommendations.first?.toMediaPreview()

        Task {
            await refreshAIHeroPreview()
        }
    }

    func removeAIRecommendation(matchingTitle title: String) {
        let lower = title.lowercased()
        aiRecommendations.removeAll { $0.title.lowercased() == lower }
        aiResolvedPreviews = aiResolvedPreviews.filter { key, _ in
            aiRecommendations.contains { Self.aiRecommendationLookupKey(for: $0) == key }
        }
        aiHeroPreview = aiRecommendations.first.flatMap { aiResolvedPreviews[Self.aiRecommendationLookupKey(for: $0)] } ?? aiRecommendations.first?.toMediaPreview()

        Task {
            await refreshAIHeroPreview()
        }
    }

    func updateAIRecommendations(
        _ recommendations: [AIMovieRecommendation],
        resolvedPreviews: [String: MediaPreview] = [:]
    ) async {
        var effectiveRecommendations = recommendations
        var effectiveResolvedPreviews = resolvedPreviews

        if effectiveResolvedPreviews.isEmpty {
            let sanitized = await sanitizeAIRecommendations(recommendations)
            effectiveRecommendations = sanitized.0
            effectiveResolvedPreviews = sanitized.1
        }

        aiRecommendations = effectiveRecommendations
        aiResolvedPreviews = effectiveRecommendations.reduce(into: [String: MediaPreview]()) { partialResult, recommendation in
            let key = Self.aiRecommendationLookupKey(for: recommendation)
            if let preview = effectiveResolvedPreviews[key] {
                partialResult[key] = preview
            }
        }
        await refreshAIHeroPreview()
    }

    func aiPreview(for recommendation: AIMovieRecommendation) -> MediaPreview {
        aiResolvedPreviews[Self.aiRecommendationLookupKey(for: recommendation)] ?? recommendation.toMediaPreview()
    }

    func refreshAIHeroPreview() async {
        guard let firstRecommendation = aiRecommendations.first else {
            aiHeroPreview = nil
            return
        }

        if let cachedPreview = aiResolvedPreviews[Self.aiRecommendationLookupKey(for: firstRecommendation)] {
            aiHeroPreview = cachedPreview
            return
        }

        let fallbackPreview = firstRecommendation.toMediaPreview()
        aiHeroPreview = fallbackPreview

        guard let metadataService else {
            return
        }

        guard let resolvedPreview = await resolveAIPreview(for: firstRecommendation, using: metadataService) else {
            return
        }

        guard aiRecommendations.first?.id == firstRecommendation.id else {
            return
        }

        aiResolvedPreviews[Self.aiRecommendationLookupKey(for: firstRecommendation)] = resolvedPreview
        aiHeroPreview = resolvedPreview
    }

    private func sanitizeAIRecommendations(
        _ recommendations: [AIMovieRecommendation]
    ) async -> ([AIMovieRecommendation], [String: MediaPreview]) {
        guard let metadataService else {
            return (recommendations, [:])
        }

        var sanitized: [AIMovieRecommendation] = []
        var resolvedPreviews: [String: MediaPreview] = [:]

        for recommendation in recommendations {
            let resolvedPreview = await resolveAIPreview(for: recommendation, using: metadataService)
            let sanitizedRecommendation = Self.sanitizedRecommendation(
                recommendation,
                resolvedPreview: resolvedPreview
            )
            let key = Self.aiRecommendationLookupKey(for: sanitizedRecommendation)
            if let resolvedPreview {
                resolvedPreviews[key] = resolvedPreview
            }
            sanitized.append(sanitizedRecommendation)
        }

        return (sanitized, resolvedPreviews)
    }

    private func resolveAIPreview(
        for recommendation: AIMovieRecommendation,
        using metadataService: any MetadataProvider
    ) async -> MediaPreview? {
        if let tmdbId = recommendation.tmdbId,
           let detail = try? await metadataService.getDetail(id: String(tmdbId), type: recommendation.type),
           Self.isMatchingMetadata(
               recommendationTitle: recommendation.title,
               recommendationYear: recommendation.year,
               candidateTitle: detail.title,
               candidateYear: detail.year
           ) {
            return MediaPreview(
                id: "\(recommendation.type.rawValue)-tmdb-\(tmdbId)",
                type: recommendation.type,
                title: detail.title,
                year: detail.year ?? recommendation.year,
                posterPath: detail.posterPath,
                backdropPath: detail.backdropPath,
                imdbRating: detail.imdbRating,
                tmdbId: detail.tmdbId ?? tmdbId
            )
        }

        guard let searchResult = try? await metadataService.search(
            query: recommendation.title,
            type: recommendation.type,
            page: 1,
            year: recommendation.year,
            language: "en-US"
        ) else {
            return nil
        }

        return searchResult.items
            .filter { $0.type == recommendation.type }
            .map { ($0, Self.matchScore(for: recommendation, candidate: $0)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return (lhs.0.year ?? Int.max) < (rhs.0.year ?? Int.max)
                }
                return lhs.1 > rhs.1
            }
            .first?
            .0
    }

    private static func sanitizedRecommendation(
        _ recommendation: AIMovieRecommendation,
        resolvedPreview: MediaPreview?
    ) -> AIMovieRecommendation {
        guard let resolvedPreview else {
            var clearedRecommendation = recommendation
            clearedRecommendation.tmdbId = nil
            return clearedRecommendation
        }

        var sanitizedRecommendation = recommendation
        sanitizedRecommendation.title = resolvedPreview.title
        sanitizedRecommendation.year = resolvedPreview.year ?? recommendation.year
        sanitizedRecommendation.tmdbId = resolvedPreview.tmdbId
        return sanitizedRecommendation
    }

    private static func aiRecommendationLookupKey(for recommendation: AIMovieRecommendation) -> String {
        aiRecommendationLookupKey(
            title: recommendation.title,
            year: recommendation.year,
            type: recommendation.type
        )
    }

    private static func aiRecommendationLookupKey(title: String, year: Int?, type: MediaType) -> String {
        "\(normalizeRecommendationTitle(title))-\(year ?? 0)-\(type.rawValue)"
    }

    private static func normalizeRecommendationTitle(_ title: String) -> String {
        title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func matchScore(for recommendation: AIMovieRecommendation, candidate: MediaPreview) -> Int {
        guard isMatchingMetadata(
            recommendationTitle: recommendation.title,
            recommendationYear: recommendation.year,
            candidateTitle: candidate.title,
            candidateYear: candidate.year
        ) else {
            return 0
        }

        let recommendationTitle = normalizeRecommendationTitle(recommendation.title)
        let candidateTitle = normalizeRecommendationTitle(candidate.title)
        var score = 1

        if recommendationTitle == candidateTitle {
            score += 4
        } else if recommendationTitle.contains(candidateTitle) || candidateTitle.contains(recommendationTitle) {
            score += 2
        }

        if let recommendationYear = recommendation.year,
           let candidateYear = candidate.year,
           recommendationYear == candidateYear {
            score += 2
        }

        if recommendation.tmdbId == candidate.tmdbId {
            score += 1
        }

        return score
    }

    private static func isMatchingMetadata(
        recommendationTitle: String,
        recommendationYear: Int?,
        candidateTitle: String,
        candidateYear: Int?
    ) -> Bool {
        let normalizedRecommendationTitle = normalizeRecommendationTitle(recommendationTitle)
        let normalizedCandidateTitle = normalizeRecommendationTitle(candidateTitle)

        guard !normalizedRecommendationTitle.isEmpty,
              !normalizedCandidateTitle.isEmpty else {
            return false
        }

        let titlesCompatible = normalizedRecommendationTitle == normalizedCandidateTitle
            || normalizedRecommendationTitle.contains(normalizedCandidateTitle)
            || normalizedCandidateTitle.contains(normalizedRecommendationTitle)

        guard titlesCompatible else {
            return false
        }

        guard let recommendationYear, let candidateYear else {
            return true
        }

        return recommendationYear == candidateYear
    }

    private static func exclusionTitles(from recommendations: [AIMovieRecommendation]) -> [String] {
        var seen = Set<String>()
        var titles: [String] = []

        for recommendation in recommendations {
            let key = aiRecommendationLookupKey(for: recommendation)
            guard seen.insert(key).inserted else { continue }
            titles.append(recommendation.title)
        }

        return titles
    }

    private static func uniqueRecommendations(
        from recommendations: [AIMovieRecommendation],
        excluding excludedRecommendations: [AIMovieRecommendation]
    ) -> [AIMovieRecommendation] {
        var seen = Set(excludedRecommendations.map { aiRecommendationLookupKey(for: $0) })
        var unique: [AIMovieRecommendation] = []

        for recommendation in recommendations {
            let key = aiRecommendationLookupKey(for: recommendation)
            guard seen.insert(key).inserted else { continue }
            unique.append(recommendation)
        }

        return unique
    }
}
