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
    var upcomingMovies: [MediaPreview] = []  // Future releases (release date > today)
    var newReleaseMovies: [MediaPreview] = []  // Recent releases (release date <= today, last 90 days)
    var featuredBackdrops: [MediaPreview] = []
    var isLoading = true
    var error: AppError?

    // MARK: - AI Curated Recommendations

    var aiRecommendations: [AIMovieRecommendation] = []
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

        if let configuredApiKey {
            if !normalizedKey.isEmpty, configuredApiKey != normalizedKey {
                metadataService = metadataServiceFactory(normalizedKey)
                self.configuredApiKey = normalizedKey
            }
        } else if metadataService == nil {
            guard !normalizedKey.isEmpty else {
                isLoading = false
                error = .unknown("API key required to load discover content.")
                return
            }
            metadataService = metadataServiceFactory(normalizedKey)
            configuredApiKey = normalizedKey
        }
        guard let service = metadataService else {
            isLoading = false
            error = .unknown("Metadata service unavailable.")
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
        async let upcomingResult = fetchResult { try await service.getCategory(.upcoming, type: .movie, page: 1) }

        // New Releases: movies from the last 90 days (using discover with date filter)
        let newReleasesDateGte = DiscoverFilters.dateString(daysFromNow: -90)
        let newReleasesDateLte = DiscoverFilters.todayString()
        async let newReleasesResult = fetchResult {
            let filters = DiscoverFilters(
                sortBy: .releaseDateDesc,
                page: 1,
                releaseDateGte: newReleasesDateGte,
                releaseDateLte: newReleasesDateLte
            )
            return try await service.discover(type: .movie, filters: filters)
        }

        let (moviesResult, showsResult, popularResultValue, topRatedResultValue, nowPlayingResultValue, upcomingResultValue, newReleasesResultValue) = await (
            trendingMoviesResult, trendingShowsResult, popularResult, topRatedResult, nowPlayingResult, upcomingResult, newReleasesResult
        )

        let results = [moviesResult, showsResult, popularResultValue, topRatedResultValue, nowPlayingResultValue, upcomingResultValue, newReleasesResultValue]
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
        if case .success(let upcoming) = upcomingResultValue { upcomingMovies = upcoming.items }
        if case .success(let newReleases) = newReleasesResultValue { newReleaseMovies = newReleases.items }

        if trendingMovies.isEmpty,
           trendingShows.isEmpty,
           popularMovies.isEmpty,
           topRatedMovies.isEmpty,
           nowPlayingMovies.isEmpty,
           upcomingMovies.isEmpty,
           newReleaseMovies.isEmpty,
           let firstFailure {
            error = AppError(firstFailure, fallback: .network(.transport("Failed to load discover content.")))
        }

        isLoading = false
    }

    func refresh() async {
        guard metadataService != nil else { return }
        await load(apiKey: "")
    }

    func loadContinueWatching() async {
        guard let database else { return }
        do {
            let recentHistory = try await database.fetchWatchHistory(limit: 20)
            let inProgress = recentHistory.filter { !$0.isCompleted && $0.progressPercent > 0.02 && $0.progressPercent < 0.95 }
            var items: [(history: WatchHistory, preview: MediaPreview)] = []
            for entry in inProgress.prefix(10) {
                if let cached = try? await database.fetchMediaItem(id: entry.mediaId) {
                    items.append((entry, MediaPreview(
                        id: cached.id,
                        type: cached.type,
                        title: cached.title,
                        year: cached.year,
                        posterPath: cached.posterPath,
                        backdropPath: cached.backdropPath,
                        imdbRating: cached.imdbRating,
                        tmdbId: cached.tmdbId
                    )))
                }
            }
            continueWatching = items
        } catch {
            // Continue watching is non-critical — don't surface errors.
        }
    }

    private func fetchResult<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
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
            aiRecommendations = filtered
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
              let cached = try? JSONDecoder().decode([AIMovieRecommendation].self, from: data) else { return }
        aiRecommendations = cached
    }

    private func filterOutWatchedAndRated(recommendations: [AIMovieRecommendation]) async -> [AIMovieRecommendation] {
        guard let database else { return recommendations }
        do {
            let ratedEvents = try await database.fetchTasteEvents(eventType: .rated, limit: 500)
            let history = try await database.fetchWatchHistory(limit: 500)
            let watchlistEntries = try await database.fetchLibraryEntries(listType: .watchlist)
            let favoritesEntries = try await database.fetchLibraryEntries(listType: .favorites)
            let libraryEntries = watchlistEntries + favoritesEntries

            let ratedMediaIds = Set(ratedEvents.compactMap(\.mediaId))
            let ratedTitles = Set(ratedEvents.compactMap { $0.metadata["title"]?.lowercased() })
            let watchedTitles = Set(history.map { $0.title.lowercased() })
            let libraryMediaIds = Set(libraryEntries.map(\.mediaId))

            // Resolve library titles from cached media items for title-based matching
            var libraryTitles = Set<String>()
            for entry in libraryEntries {
                if let cached = try? await database.fetchMediaItem(id: entry.mediaId) {
                    libraryTitles.insert(cached.title.lowercased())
                }
            }

            return recommendations.filter { rec in
                let titleLower = rec.title.lowercased()
                if let tmdbId = rec.tmdbId {
                    let mediaId = "\(rec.type.rawValue)-tmdb-\(tmdbId)"
                    if ratedMediaIds.contains(mediaId) { return false }
                    if libraryMediaIds.contains(mediaId) { return false }
                }
                if ratedTitles.contains(titleLower) { return false }
                if watchedTitles.contains(titleLower) { return false }
                if libraryTitles.contains(titleLower) { return false }
                return true
            }
        } catch {
            return recommendations
        }
    }

    func removeAIRecommendation(matchingMediaId mediaId: String) {
        aiRecommendations.removeAll { $0.toMediaPreview().id == mediaId }
    }

    func removeAIRecommendation(matchingTitle title: String) {
        let lower = title.lowercased()
        aiRecommendations.removeAll { $0.title.lowercased() == lower }
    }
}
