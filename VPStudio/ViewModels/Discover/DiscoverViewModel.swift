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

    private var metadataService: (any MetadataProvider)?
    private var database: DatabaseManager?
    private let metadataServiceFactory: @Sendable (String) -> any MetadataProvider
    private var configuredApiKey: String?

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
        if self.database == nil {
            self.database = database
        }
    }

    func load(apiKey: String) async {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedKey.isEmpty {
            if Self.shouldResetRemoteServiceForMissingKey(configuredApiKey: configuredApiKey) {
                metadataService = nil
                configuredApiKey = nil
                clearRemoteDiscoverRows()
                await refreshAIHeroPreview()

                if QARuntimeOptions.traktRefreshFixturePath != nil {
                    await loadContinueWatching()
                    isLoading = false
                    error = nil
                    return
                }

                isLoading = false
                error = .tmdbSetupRequired(feature: "Discover")
                return
            }

            if metadataService == nil {
                await refreshAIHeroPreview()

                if QARuntimeOptions.traktRefreshFixturePath != nil {
                    await loadContinueWatching()
                    isLoading = false
                    error = nil
                    return
                }

                isLoading = false
                error = .tmdbSetupRequired(feature: "Discover")
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
            isLoading = false
            error = .tmdbSetupRequired(feature: "Discover")
            return
        }
        isLoading = true
        error = nil

        // Load continue watching from local database (non-blocking for TMDB fetches).
        await loadContinueWatching()

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
        guard let database else { return }
        do {
            let recentHistory = try await database.fetchWatchHistory(limit: 20)
            let inProgress = Array(recentHistory.filter {
                !$0.isCompleted && $0.progressPercent > 0.02 && $0.progressPercent < 0.95
            }.prefix(10))

            let cachedItems = try await database.fetchMediaItems(ids: inProgress.map(\.mediaId))
            let cachedByID = Dictionary(uniqueKeysWithValues: cachedItems.map { ($0.id, $0) })

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
        await fetchAIRecommendations(aiManager: aiManager, settingsManager: settingsManager)
    }

    func refreshAIRecommendations(aiManager: AIAssistantManager) async {
        aiRecommendationsLoaded = false
        await fetchAIRecommendations(aiManager: aiManager, settingsManager: nil)
    }

    func regenerateAIRecommendations(aiManager: AIAssistantManager, settingsManager: SettingsManager) async {
        aiRecommendationsLoaded = false
        await fetchAIRecommendations(aiManager: aiManager, settingsManager: settingsManager)
    }

    private func fetchAIRecommendations(aiManager: AIAssistantManager, settingsManager: SettingsManager?) async {
        isLoadingAIRecommendations = true
        do {
            let context = AssistantContext()
            let recommendations = try await aiManager.getRecommendations(context: context)
            let filtered = await filterOutWatchedAndRated(recommendations: recommendations)
            await updateAIRecommendations(filtered)
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
            await updateAIRecommendations([])
            return
        }

        await updateAIRecommendations(cached)
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
        aiHeroPreview = aiRecommendations.first?.toMediaPreview()

        Task {
            await refreshAIHeroPreview()
        }
    }

    func removeAIRecommendation(matchingTitle title: String) {
        let lower = title.lowercased()
        aiRecommendations.removeAll { $0.title.lowercased() == lower }
        aiHeroPreview = aiRecommendations.first?.toMediaPreview()

        Task {
            await refreshAIHeroPreview()
        }
    }

    func updateAIRecommendations(_ recommendations: [AIMovieRecommendation]) async {
        aiRecommendations = recommendations
        await refreshAIHeroPreview()
    }

    func refreshAIHeroPreview() async {
        guard let firstRecommendation = aiRecommendations.first else {
            aiHeroPreview = nil
            return
        }

        let fallbackPreview = firstRecommendation.toMediaPreview()
        aiHeroPreview = fallbackPreview

        guard let tmdbId = firstRecommendation.tmdbId,
              let metadataService else {
            return
        }

        guard let detail = try? await metadataService.getDetail(id: String(tmdbId), type: firstRecommendation.type) else {
            return
        }

        guard aiRecommendations.first?.id == firstRecommendation.id else {
            return
        }

        aiHeroPreview = MediaPreview(
            id: fallbackPreview.id,
            type: firstRecommendation.type,
            title: detail.title,
            year: detail.year ?? firstRecommendation.year,
            posterPath: detail.posterPath,
            backdropPath: detail.backdropPath,
            imdbRating: detail.imdbRating,
            tmdbId: firstRecommendation.tmdbId
        )
    }
}
