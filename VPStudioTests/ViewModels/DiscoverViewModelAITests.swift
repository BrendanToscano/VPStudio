import Foundation
import Testing
@testable import VPStudio

@Suite("DiscoverViewModel AI Recommendations", .serialized)
struct DiscoverViewModelAITests {

    // MARK: - Helpers

    /// Builds an in-memory database, settings manager, and AI manager with a registered stub provider.
    private static func makeDependencies(
        jsonResponse: String = """
        [{"title":"Test Movie","year":2024,"type":"movie","reason":"Great","tmdbId":123}]
        """
    ) async throws -> (db: DatabaseManager, settings: SettingsManager, aiManager: AIAssistantManager) {
        let db = try DatabaseManager()
        try await db.migrate()
        let secretStore = TestSecretStore()
        let settings = SettingsManager(database: db, secretStore: secretStore)
        let aiManager = AIAssistantManager(database: db)
        let stubProvider = StubAIProvider(
            providerKind: .anthropic,
            result: .success(AIProviderResponse(
                provider: .anthropic,
                content: jsonResponse,
                model: "test",
                inputTokens: 0,
                outputTokens: 0
            ))
        )
        await aiManager.registerProvider(kind: .anthropic, provider: stubProvider)
        return (db, settings, aiManager)
    }

    /// Creates a DiscoverViewModel with the given database so filterOutWatchedAndRated can query it.
    @MainActor
    private static func makeViewModel(database: DatabaseManager) -> DiscoverViewModel {
        DiscoverViewModel(database: database)
    }

    /// Builds a sample `AIMovieRecommendation`.
    private static func sampleRecommendation(
        title: String = "Test Movie",
        year: Int? = 2024,
        type: MediaType = .movie,
        reason: String = "Great",
        tmdbId: Int? = 123
    ) -> AIMovieRecommendation {
        AIMovieRecommendation(title: title, year: year, type: type, reason: reason, tmdbId: tmdbId)
    }

    // MARK: - Initial State

    @Test
    @MainActor
    func initialStateHasEmptyAIRecommendations() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)
        #expect(vm.aiRecommendations.isEmpty)
    }

    @Test
    @MainActor
    func aiRecommendationsEnabledDefaultsToFalse() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)
        #expect(vm.aiRecommendationsEnabled == false)
    }

    @Test
    @MainActor
    func isLoadingAIRecommendationsDefaultsToFalse() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)
        #expect(vm.isLoadingAIRecommendations == false)
    }

    // MARK: - loadAIRecommendationsIfNeeded

    @Test
    @MainActor
    func loadAIRecommendationsIfNeededDoesNothingWhenDisabled() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        // Explicitly disable to guard against state pollution from prior test runs
        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: false)

        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.isEmpty)
        #expect(vm.aiRecommendationsEnabled == false)
        #expect(vm.isLoadingAIRecommendations == false)
    }

    @Test
    @MainActor
    func loadAIRecommendationsIfNeededSetsEnabledTrueWhenSettingIsOn() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        // Enable the setting
        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)

        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendationsEnabled == true)
    }

    @Test
    @MainActor
    func loadAIRecommendationsIfNeededDoesNotDoubleLoad() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)

        // First call loads
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)
        let countAfterFirst = vm.aiRecommendations.count

        // Manually clear to detect if second call refetches
        vm.aiRecommendations = []

        // Second call should be a no-op because aiRecommendationsLoaded is true
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.isEmpty, "Second call should not reload — guard prevents re-fetch")
        _ = countAfterFirst // Suppress unused warning
    }

    // MARK: - refreshAIRecommendations

    @Test
    @MainActor
    func refreshAIRecommendationsReloadsEvenAfterLoaded() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)

        // Initial load
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)
        #expect(!vm.aiRecommendations.isEmpty)

        // Clear manually
        vm.aiRecommendations = []
        #expect(vm.aiRecommendations.isEmpty)

        // refresh should re-fetch even though aiRecommendationsLoaded was true
        await vm.refreshAIRecommendations(aiManager: deps.aiManager)

        #expect(!vm.aiRecommendations.isEmpty, "Refresh should reload recommendations")
        #expect(vm.isLoadingAIRecommendations == false)
    }

    // MARK: - removeAIRecommendation(matchingMediaId:)

    @Test
    @MainActor
    func removeByMediaIdRemovesMatchingItem() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        let rec = Self.sampleRecommendation(title: "Test Movie", tmdbId: 123)
        vm.aiRecommendations = [rec]
        let mediaId = rec.toMediaPreview().id

        vm.removeAIRecommendation(matchingMediaId: mediaId)

        #expect(vm.aiRecommendations.isEmpty)
    }

    @Test
    @MainActor
    func removeByMediaIdLeavesNonMatchingItems() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        let rec1 = Self.sampleRecommendation(title: "Movie A", tmdbId: 100)
        let rec2 = Self.sampleRecommendation(title: "Movie B", tmdbId: 200)
        vm.aiRecommendations = [rec1, rec2]

        // Remove only rec1's media ID
        let mediaId = rec1.toMediaPreview().id
        vm.removeAIRecommendation(matchingMediaId: mediaId)

        #expect(vm.aiRecommendations.count == 1)
        #expect(vm.aiRecommendations.first?.title == "Movie B")
    }

    // MARK: - removeAIRecommendation(matchingTitle:)

    @Test
    @MainActor
    func removeByTitleIsCaseInsensitive() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        let rec = Self.sampleRecommendation(title: "Inception", tmdbId: 27205)
        vm.aiRecommendations = [rec]

        // Remove with different casing
        vm.removeAIRecommendation(matchingTitle: "INCEPTION")

        #expect(vm.aiRecommendations.isEmpty, "Removal should be case-insensitive")
    }

    @Test
    @MainActor
    func removeByTitleLeavesNonMatchingItems() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        let rec1 = Self.sampleRecommendation(title: "Arrival", tmdbId: 329865)
        let rec2 = Self.sampleRecommendation(title: "Interstellar", tmdbId: 157336)
        vm.aiRecommendations = [rec1, rec2]

        vm.removeAIRecommendation(matchingTitle: "arrival")

        #expect(vm.aiRecommendations.count == 1)
        #expect(vm.aiRecommendations.first?.title == "Interstellar")
    }

    // MARK: - Library Filtering (filterOutWatchedAndRated)

    /// Helper: adds a library entry and its cached media item so both mediaId and title matching work.
    private static func addLibraryEntry(
        db: DatabaseManager,
        mediaId: String,
        title: String,
        type: MediaType = .movie,
        listType: UserLibraryEntry.ListType = .watchlist,
        tmdbId: Int? = nil
    ) async throws {
        // Cache the media item so title-based lookup resolves
        let item = MediaItem(id: mediaId, type: type, title: title, tmdbId: tmdbId)
        try await db.saveMediaItem(item)

        let entry = UserLibraryEntry(
            id: "\(mediaId)-\(listType.rawValue)",
            mediaId: mediaId,
            folderId: "",
            listType: listType,
            addedAt: Date()
        )
        try await db.addToLibrary(entry)
    }

    @Test
    @MainActor
    func filterRemovesWatchlistItemByMediaId() async throws {
        let json = """
        [{"title":"Inception","year":2010,"type":"movie","reason":"Classic","tmdbId":27205},
         {"title":"Arrival","year":2016,"type":"movie","reason":"Thoughtful","tmdbId":329865}]
        """
        let deps = try await Self.makeDependencies(jsonResponse: json)
        let vm = Self.makeViewModel(database: deps.db)

        // Add Inception to watchlist
        try await Self.addLibraryEntry(
            db: deps.db,
            mediaId: "movie-tmdb-27205",
            title: "Inception",
            listType: .watchlist,
            tmdbId: 27205
        )

        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.count == 1, "Watchlist item should be filtered out")
        #expect(vm.aiRecommendations.first?.title == "Arrival")
    }

    @Test
    @MainActor
    func filterRemovesFavoritesItemByMediaId() async throws {
        let json = """
        [{"title":"Arrival","year":2016,"type":"movie","reason":"Thoughtful","tmdbId":329865}]
        """
        let deps = try await Self.makeDependencies(jsonResponse: json)
        let vm = Self.makeViewModel(database: deps.db)

        // Add Arrival to favorites
        try await Self.addLibraryEntry(
            db: deps.db,
            mediaId: "movie-tmdb-329865",
            title: "Arrival",
            listType: .favorites,
            tmdbId: 329865
        )

        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.isEmpty, "Favorites item should be filtered out")
    }

    @Test
    @MainActor
    func filterRemovesLibraryItemByTitleWhenTmdbIdMissing() async throws {
        // Recommendation has no tmdbId — only title-based matching can filter it
        let json = """
        [{"title":"Inception","year":2010,"type":"movie","reason":"Classic"}]
        """
        let deps = try await Self.makeDependencies(jsonResponse: json)
        let vm = Self.makeViewModel(database: deps.db)

        // Add with a different mediaId format (e.g. IMDb-style) — title match should still catch it
        try await Self.addLibraryEntry(
            db: deps.db,
            mediaId: "movie-imdb-tt1375666",
            title: "Inception",
            listType: .watchlist
        )

        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.isEmpty, "Title-based library match should filter out recommendation")
    }

    @Test
    @MainActor
    func filterKeepsItemsNotInLibrary() async throws {
        let json = """
        [{"title":"Arrival","year":2016,"type":"movie","reason":"Thoughtful","tmdbId":329865},
         {"title":"Interstellar","year":2014,"type":"movie","reason":"Epic","tmdbId":157336}]
        """
        let deps = try await Self.makeDependencies(jsonResponse: json)
        let vm = Self.makeViewModel(database: deps.db)

        // Add only Arrival to watchlist — Interstellar should survive
        try await Self.addLibraryEntry(
            db: deps.db,
            mediaId: "movie-tmdb-329865",
            title: "Arrival",
            listType: .watchlist,
            tmdbId: 329865
        )

        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.count == 1)
        #expect(vm.aiRecommendations.first?.title == "Interstellar")
    }

    @Test
    @MainActor
    func filterRemovesLibraryItemCaseInsensitiveTitle() async throws {
        let json = """
        [{"title":"INCEPTION","year":2010,"type":"movie","reason":"Classic","tmdbId":99999}]
        """
        let deps = try await Self.makeDependencies(jsonResponse: json)
        let vm = Self.makeViewModel(database: deps.db)

        // Library has lowercase title; recommendation has uppercase
        try await Self.addLibraryEntry(
            db: deps.db,
            mediaId: "movie-tmdb-27205",
            title: "inception",
            listType: .favorites,
            tmdbId: 27205
        )

        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.isEmpty, "Case-insensitive title match should filter library items")
    }

    @Test
    @MainActor
    func filterCombinesLibraryAndRatedAndWatched() async throws {
        let json = """
        [{"title":"Movie A","year":2024,"type":"movie","reason":"A","tmdbId":100},
         {"title":"Movie B","year":2024,"type":"movie","reason":"B","tmdbId":200},
         {"title":"Movie C","year":2024,"type":"movie","reason":"C","tmdbId":300}]
        """
        let deps = try await Self.makeDependencies(jsonResponse: json)
        let vm = Self.makeViewModel(database: deps.db)

        // Movie A: in library (watchlist)
        try await Self.addLibraryEntry(
            db: deps.db,
            mediaId: "movie-tmdb-100",
            title: "Movie A",
            listType: .watchlist,
            tmdbId: 100
        )

        // Movie B: rated via taste event
        let tasteEvent = TasteEvent(
            mediaId: "movie-tmdb-200",
            eventType: .rated,
            metadata: ["title": "Movie B", "rating": "8"]
        )
        try await deps.db.saveTasteEvent(tasteEvent)

        // Movie C: not in library, not rated, not watched — should survive
        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.count == 1, "Only Movie C should survive filtering")
        #expect(vm.aiRecommendations.first?.title == "Movie C")
    }

    // MARK: - Auto-generate Toggle

    @Test
    @MainActor
    func aiAutoGenerateDefaultsToTrue() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)
        #expect(vm.aiAutoGenerate == true, "aiAutoGenerate should default to true")
    }

    @Test
    @MainActor
    func autoGenerateOffSkipsAIFetchAndLoadsCachedRecommendations() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        // Enable AI row, disable auto-generate
        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        try await deps.settings.setBool(key: SettingsKeys.aiAutoGenerate, value: false)

        // Pre-cache some recommendations
        let cached = [Self.sampleRecommendation(title: "Cached Movie", tmdbId: 999)]
        let data = try JSONEncoder().encode(cached)
        let json = String(data: data, encoding: .utf8)!
        try await deps.settings.setString(key: SettingsKeys.aiCachedRecommendations, value: json)

        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiAutoGenerate == false, "aiAutoGenerate should be false after loading setting")
        #expect(vm.aiRecommendations.count == 1, "Should load cached recommendations")
        #expect(vm.aiRecommendations.first?.title == "Cached Movie", "Should show cached title")
    }

    @Test
    @MainActor
    func autoGenerateOffWithNoCacheResultsInEmptyRecommendations() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        // Enable AI row, disable auto-generate, explicitly clear any cached recommendations
        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        try await deps.settings.setBool(key: SettingsKeys.aiAutoGenerate, value: false)
        try await deps.settings.setString(key: SettingsKeys.aiCachedRecommendations, value: nil)

        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiRecommendations.isEmpty, "No cache means empty recommendations when auto-generate is off")
    }

    @Test
    @MainActor
    func regenerateAIRecommendationsWorksRegardlessOfToggleState() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        // Enable AI row, disable auto-generate, clear any cached data from prior tests
        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        try await deps.settings.setBool(key: SettingsKeys.aiAutoGenerate, value: false)
        try await deps.settings.setString(key: SettingsKeys.aiCachedRecommendations, value: nil)

        // Initial load should use cache (empty since no cache exists)
        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)
        #expect(vm.aiRecommendations.isEmpty)

        // Regenerate should force-fetch from AI regardless of auto-generate being off
        await vm.regenerateAIRecommendations(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(!vm.aiRecommendations.isEmpty, "Regenerate should fetch new recommendations even when auto-generate is off")
        #expect(vm.aiRecommendations.first?.title == "Test Movie")
    }

    @Test
    @MainActor
    func regenerateAIRecommendationsCachesResults() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        // Regenerate fetches and should cache
        await vm.regenerateAIRecommendations(aiManager: deps.aiManager, settingsManager: deps.settings)
        #expect(!vm.aiRecommendations.isEmpty)

        // Verify cache was written by reading it back
        let cachedJSON = try await deps.settings.getString(key: SettingsKeys.aiCachedRecommendations)
        #expect(cachedJSON != nil, "Regenerate should cache recommendations")

        let data = cachedJSON!.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([AIMovieRecommendation].self, from: data)
        #expect(decoded.first?.title == "Test Movie", "Cached recommendations should match fetched ones")
    }

    @Test
    @MainActor
    func cachedRecommendationsRoundTripEncodeDecode() async throws {
        let recommendations = [
            Self.sampleRecommendation(title: "Movie A", year: 2024, type: .movie, reason: "Great", tmdbId: 100),
            Self.sampleRecommendation(title: "Show B", year: 2023, type: .series, reason: "Amazing", tmdbId: 200),
            Self.sampleRecommendation(title: "No TMDB", year: nil, type: .movie, reason: "Interesting", tmdbId: nil),
        ]

        let data = try JSONEncoder().encode(recommendations)
        let decoded = try JSONDecoder().decode([AIMovieRecommendation].self, from: data)

        #expect(decoded.count == 3)
        #expect(decoded[0].title == "Movie A")
        #expect(decoded[0].year == 2024)
        #expect(decoded[0].type == .movie)
        #expect(decoded[0].reason == "Great")
        #expect(decoded[0].tmdbId == 100)
        #expect(decoded[1].title == "Show B")
        #expect(decoded[1].type == .series)
        #expect(decoded[2].title == "No TMDB")
        #expect(decoded[2].year == nil)
        #expect(decoded[2].tmdbId == nil)
    }

    @Test
    @MainActor
    func autoGenerateOnFetchesAndCachesRecommendations() async throws {
        let deps = try await Self.makeDependencies()
        let vm = Self.makeViewModel(database: deps.db)

        // Enable AI row, explicitly set auto-generate on (guards against prior test pollution)
        try await deps.settings.setBool(key: SettingsKeys.discoverAIRecommendationsEnabled, value: true)
        try await deps.settings.setBool(key: SettingsKeys.aiAutoGenerate, value: true)

        await vm.loadAIRecommendationsIfNeeded(aiManager: deps.aiManager, settingsManager: deps.settings)

        #expect(vm.aiAutoGenerate == true)
        #expect(!vm.aiRecommendations.isEmpty, "Auto-generate on should fetch from AI")

        // Verify it also cached the result
        let cachedJSON = try await deps.settings.getString(key: SettingsKeys.aiCachedRecommendations)
        #expect(cachedJSON != nil, "Auto-generate on should also cache recommendations")
    }
}
