import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SearchViewModelFilterTests {

    // MARK: - Test Stubs

    /// A configurable metadata stub that supports search, discover, and genre loading.
    private actor FilterTestMetadataStub: MetadataProvider {
        var searchResultByPage: [Int: MetadataSearchResult] = [:]
        var discoverResultByPage: [Int: MetadataSearchResult] = [:]
        var genresByType: [MediaType: [Genre]] = [:]
        var searchCallCount = 0
        var discoverCallCount = 0
        var genreCallCount = 0
        var lastDiscoverFilters: DiscoverFilters?
        var lastDiscoverType: MediaType?
        var shouldThrowOnGenres = false

        func setShouldThrowOnGenres(_ value: Bool) {
            shouldThrowOnGenres = value
        }

        func setSearchResults(_ results: [Int: MetadataSearchResult]) {
            searchResultByPage = results
        }

        func setDiscoverResults(_ results: [Int: MetadataSearchResult]) {
            discoverResultByPage = results
        }

        func setGenres(_ genres: [Genre], for type: MediaType) {
            genresByType[type] = genres
        }

        func getSearchCallCount() -> Int { searchCallCount }
        func getDiscoverCallCount() -> Int { discoverCallCount }
        func getGenreCallCount() -> Int { genreCallCount }
        func getLastDiscoverFilters() -> DiscoverFilters? { lastDiscoverFilters }
        func getLastDiscoverType() -> MediaType? { lastDiscoverType }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            searchCallCount += 1
            return searchResultByPage[page] ?? MetadataSearchResult(items: [], page: page, totalPages: page, totalResults: 0)
        }

        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult {
            discoverCallCount += 1
            lastDiscoverFilters = filters
            lastDiscoverType = type
            return discoverResultByPage[filters.page] ?? MetadataSearchResult(items: [], page: filters.page, totalPages: filters.page, totalResults: 0)
        }

        func getGenres(type: MediaType) async throws -> [Genre] {
            genreCallCount += 1
            if shouldThrowOnGenres { throw TestError.genreLoadFailed }
            return genresByType[type] ?? []
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    private enum TestError: Error, LocalizedError {
        case genreLoadFailed
        case aiFailure

        var errorDescription: String? {
            switch self {
            case .genreLoadFailed: return "Genre load failed"
            case .aiFailure: return "AI failure"
            }
        }
    }

    /// Polls until `condition` returns true, yielding between checks. Fails after `timeout`.
    @MainActor
    private static func waitUntil(
        timeout: Duration = .milliseconds(5000),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("waitUntil timed out after \(timeout)")
                return
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Genre Loading & Caching

    @Test
    @MainActor
    func loadGenresPopulatesGenreList() async throws {
        let stub = FilterTestMetadataStub()
        let genres = [Genre(id: 28, name: "Action"), Genre(id: 35, name: "Comedy"), Genre(id: 18, name: "Drama")]
        await stub.setGenres(genres, for: .movie)

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.loadGenres()

        try await Self.waitUntil { !viewModel.genres.isEmpty }
        #expect(viewModel.genres.count == 3)
        #expect(viewModel.genres.map(\.name) == ["Action", "Comedy", "Drama"])
    }

    @Test
    @MainActor
    func loadGenresCachesResultsAndDoesNotRefetch() async throws {
        let stub = FilterTestMetadataStub()
        let genres = [Genre(id: 28, name: "Action")]
        await stub.setGenres(genres, for: .movie)

        let viewModel = SearchViewModel(metadataService: stub)

        // First load
        viewModel.loadGenres()
        try await Self.waitUntil { !viewModel.genres.isEmpty }
        let firstCallCount = await stub.getGenreCallCount()
        #expect(firstCallCount == 1)

        // Second load should use cache
        viewModel.loadGenres()
        // Give it time to potentially make another call
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        let secondCallCount = await stub.getGenreCallCount()
        #expect(secondCallCount == 1)
        #expect(viewModel.genres.count == 1)
    }

    @Test
    @MainActor
    func loadGenresForDifferentTypeFetchesAgain() async throws {
        let stub = FilterTestMetadataStub()
        await stub.setGenres([Genre(id: 28, name: "Action")], for: .movie)
        await stub.setGenres([Genre(id: 10765, name: "Sci-Fi & Fantasy")], for: .series)

        let viewModel = SearchViewModel(metadataService: stub)

        // Load for movies (default)
        viewModel.selectedType = .movie
        viewModel.loadGenres()
        try await Self.waitUntil { !viewModel.genres.isEmpty }
        #expect(viewModel.genres.first?.name == "Action")

        // Switch to TV
        viewModel.selectedType = .series
        viewModel.loadGenres()
        try await Self.waitUntil { viewModel.genres.first?.name == "Sci-Fi & Fantasy" }
        #expect(viewModel.genres.count == 1)
        #expect(viewModel.genres.first?.name == "Sci-Fi & Fantasy")

        let callCount = await stub.getGenreCallCount()
        #expect(callCount == 2)
    }

    @Test
    @MainActor
    func loadGenresWithEmptyResultKeepsEmptyList() async throws {
        let stub = FilterTestMetadataStub()
        // No genres set — will return empty

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.loadGenres()

        await Task.yield()
        try await Task.sleep(for: .milliseconds(150))
        #expect(viewModel.genres.isEmpty)
    }

    @Test
    @MainActor
    func loadGenresFailureSilentlyHandled() async throws {
        let stub = FilterTestMetadataStub()
        await stub.setShouldThrowOnGenres(true)

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.loadGenres()

        await Task.yield()
        try await Task.sleep(for: .milliseconds(150))
        #expect(viewModel.genres.isEmpty)
        #expect(viewModel.error == nil)
    }

    // MARK: - Genre Selection → Discover

    @Test
    @MainActor
    func selectGenreTriggersDiscoverInsteadOfSearch() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 28, name: "Action")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "discover-1", title: "Action Movie")],
                page: 1, totalPages: 1, totalResults: 1
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectGenre(genre)

        try await Self.waitUntil { !viewModel.results.isEmpty }
        #expect(viewModel.results.count == 1)
        #expect(viewModel.results.first?.id == "discover-1")
        #expect(viewModel.selectedGenre?.id == 28)

        let discoverCount = await stub.getDiscoverCallCount()
        let searchCount = await stub.getSearchCallCount()
        #expect(discoverCount == 1)
        #expect(searchCount == 0)
    }

    @Test
    @MainActor
    func selectGenrePassesCorrectFilters() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 35, name: "Comedy")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "comedy-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectedType = .series
        viewModel.sortOption = .ratingDesc
        viewModel.yearFilter = 2024
        viewModel.selectGenre(genre)

        try await Self.waitUntil { !viewModel.results.isEmpty }

        let lastFilters = await stub.getLastDiscoverFilters()
        let lastType = await stub.getLastDiscoverType()
        #expect(lastFilters?.genreId == 35)
        #expect(lastFilters?.sortBy == .ratingDesc)
        #expect(lastFilters?.year == 2024)
        #expect(lastType == .series)
    }

    @Test
    @MainActor
    func deselectGenreWithTextQueryReTriggersSearch() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 28, name: "Action")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "discover-1")], page: 1, totalPages: 1, totalResults: 1)
        ])
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "search-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test query"

        // Select genre first
        viewModel.selectGenre(genre)
        try await Self.waitUntil { viewModel.results.first?.id == "discover-1" }

        // Deselect genre — should fall back to text search
        viewModel.selectGenre(nil)
        try await Self.waitUntil { viewModel.results.first?.id == "search-1" }

        #expect(viewModel.selectedGenre == nil)
        #expect(viewModel.results.first?.id == "search-1")
    }

    @Test
    @MainActor
    func deselectGenreWithoutQueryClearsResults() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 28, name: "Action")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "discover-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectGenre(genre)
        try await Self.waitUntil { !viewModel.results.isEmpty }

        viewModel.selectGenre(nil)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.selectedGenre == nil)
    }

    @Test
    @MainActor
    func genreBrowsePaginationUsesDiscover() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 28, name: "Action")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "disc-p1")], page: 1, totalPages: 2, totalResults: 2),
            2: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "disc-p2")], page: 2, totalPages: 2, totalResults: 2),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectGenre(genre)
        try await Self.waitUntil { !viewModel.results.isEmpty }

        viewModel.loadMore()
        try await Self.waitUntil { viewModel.results.count >= 2 }

        #expect(viewModel.results.count == 2)
        #expect(viewModel.results.map(\.id) == ["disc-p1", "disc-p2"])
        #expect(viewModel.currentPage == 2)

        // All calls should be discover, not search
        let searchCount = await stub.getSearchCallCount()
        #expect(searchCount == 0)
    }

    // MARK: - Sort Option

    @Test
    @MainActor
    func applySortOptionRequeriesGenreBrowse() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 28, name: "Action")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "sorted-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectGenre(genre)
        try await Self.waitUntil { !viewModel.results.isEmpty }

        let firstDiscoverCount = await stub.getDiscoverCallCount()
        #expect(firstDiscoverCount == 1)

        // Change sort — should requery. Wait for isSearching to transition (true then false again).
        viewModel.applySortOption(.ratingDesc)
        // The requery will set isSearching=true then false. Wait for it to settle.
        try await Self.waitUntil { !viewModel.isSearching && viewModel.sortOption == .ratingDesc }

        let secondDiscoverCount = await stub.getDiscoverCallCount()
        #expect(secondDiscoverCount >= 2)
        let lastFilters = await stub.getLastDiscoverFilters()
        #expect(lastFilters?.sortBy == .ratingDesc)
        #expect(viewModel.sortOption == .ratingDesc)
    }

    @Test
    @MainActor
    func applySortOptionRequeriesTextSearch() async throws {
        let stub = FilterTestMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "search-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "inception"
        viewModel.search()
        try await Self.waitUntil { !viewModel.results.isEmpty }

        let firstSearchCount = await stub.getSearchCallCount()
        viewModel.applySortOption(.releaseDateDesc)
        // Wait for requery to settle
        try await Self.waitUntil { !viewModel.isSearching && viewModel.sortOption == .releaseDateDesc }

        let secondSearchCount = await stub.getSearchCallCount()
        #expect(secondSearchCount > firstSearchCount)
        #expect(viewModel.sortOption == .releaseDateDesc)
    }

    @Test
    @MainActor
    func applyYearFilterRequeriesGenreBrowse() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 18, name: "Drama")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "year-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectGenre(genre)
        try await Self.waitUntil { !viewModel.results.isEmpty }

        viewModel.applyYearFilter(2023)
        try await Self.waitUntil { !viewModel.isSearching && viewModel.yearFilter == 2023 }

        let discoverCount = await stub.getDiscoverCallCount()
        #expect(discoverCount >= 2)
        let lastFilters = await stub.getLastDiscoverFilters()
        #expect(lastFilters?.year == 2023)
        #expect(viewModel.yearFilter == 2023)
    }

    @Test
    @MainActor
    func clearYearFilterRequeriesWithoutYear() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 18, name: "Drama")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "noyear-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.yearFilter = 2023
        viewModel.selectGenre(genre)
        try await Self.waitUntil { !viewModel.results.isEmpty }

        viewModel.applyYearFilter(nil)
        try await Self.waitUntil { !viewModel.isSearching && viewModel.yearFilter == nil }

        let discoverCount = await stub.getDiscoverCallCount()
        #expect(discoverCount >= 2)
        let lastFilters = await stub.getLastDiscoverFilters()
        #expect(lastFilters?.year == nil)
        #expect(viewModel.yearFilter == nil)
    }

    // MARK: - AI Recommendations

    @Test
    @MainActor
    func fetchAIRecommendationsPopulatesResults() async throws {
        let db = try DatabaseManager(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-ai-\(UUID().uuidString).sqlite").path)
        try await db.migrate()
        let aiManager = AIAssistantManager(database: db)
        let jsonResponse = """
        [{"title":"Interstellar","year":2014,"type":"movie","reason":"Epic sci-fi","tmdbId":157336},\
        {"title":"The Expanse","year":2015,"type":"series","reason":"Hard sci-fi show","tmdbId":63639}]
        """
        let stubProvider = StubAIProvider(
            providerKind: .openAI,
            result: .success(AIProviderResponse(provider: .openAI, content: jsonResponse, model: "test", inputTokens: 10, outputTokens: 20))
        )
        await aiManager.registerProvider(kind: .openAI, provider: stubProvider)

        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        viewModel.query = "sci-fi space exploration"
        viewModel.fetchAIRecommendations(aiManager: aiManager)

        try await Self.waitUntil { !viewModel.aiRecommendations.isEmpty }
        #expect(viewModel.aiRecommendations.count == 2)
        #expect(viewModel.aiRecommendations[0].title == "Interstellar")
        #expect(viewModel.aiRecommendations[0].type == .movie)
        #expect(viewModel.aiRecommendations[1].title == "The Expanse")
        #expect(viewModel.aiRecommendations[1].type == .series)
        #expect(viewModel.isLoadingAI == false)
    }

    @Test
    @MainActor
    func fetchAIRecommendationsWithNoProviderSetsError() async throws {
        let db = try DatabaseManager(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-ai-noprov-\(UUID().uuidString).sqlite").path)
        try await db.migrate()
        let aiManager = AIAssistantManager(database: db)
        // No provider registered

        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        viewModel.query = "something"
        viewModel.fetchAIRecommendations(aiManager: aiManager)

        try await Self.waitUntil { viewModel.aiError != nil }
        #expect(viewModel.aiError == "No AI provider configured. Set one up in Settings \u{2192} AI Assistant.")
        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.isLoadingAI == false)
    }

    @Test
    @MainActor
    func fetchAIRecommendationsWithEmptyQueryDoesNothing() async throws {
        let db = try DatabaseManager(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-ai-empty-\(UUID().uuidString).sqlite").path)
        try await db.migrate()
        let aiManager = AIAssistantManager(database: db)

        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        viewModel.query = "   "
        viewModel.fetchAIRecommendations(aiManager: aiManager)

        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.isLoadingAI == false)
    }

    @Test
    @MainActor
    func fetchAIRecommendationsWithProviderErrorSetsError() async throws {
        let db = try DatabaseManager(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("test-ai-err-\(UUID().uuidString).sqlite").path)
        try await db.migrate()
        let aiManager = AIAssistantManager(database: db)
        let stubProvider = StubAIProvider(
            providerKind: .openAI,
            result: .failure(TestError.aiFailure)
        )
        await aiManager.registerProvider(kind: .openAI, provider: stubProvider)

        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        viewModel.query = "recommendation query"
        viewModel.fetchAIRecommendations(aiManager: aiManager)

        try await Self.waitUntil { viewModel.aiError != nil }
        #expect(viewModel.aiError == "AI failure")
        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.isLoadingAI == false)
    }

    @Test
    @MainActor
    func clearAIRecommendationsResetsState() async throws {
        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        // Simulate populated AI state
        viewModel.aiRecommendations = [
            AIMovieRecommendation(title: "Test", year: 2024, type: .movie, reason: "Good", tmdbId: 1)
        ]
        viewModel.aiError = "some error"

        viewModel.clearAIRecommendations()

        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.aiError == nil)
        #expect(viewModel.isLoadingAI == false)
    }

    // MARK: - Clear Resets All State

    @Test
    @MainActor
    func clearResetsAllFilterState() async throws {
        let stub = FilterTestMetadataStub()
        let viewModel = SearchViewModel(metadataService: stub)

        // Set up state
        viewModel.query = "test"
        viewModel.results = [Fixtures.mediaPreview(id: "r1")]
        viewModel.selectedGenre = Genre(id: 28, name: "Action")
        viewModel.sortOption = .ratingDesc
        viewModel.yearFilter = 2023
        viewModel.aiRecommendations = [
            AIMovieRecommendation(title: "Test", year: 2024, type: .movie, reason: "Good", tmdbId: 1)
        ]
        viewModel.aiError = "error"

        viewModel.clear()

        #expect(viewModel.query.isEmpty)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.selectedGenre == nil)
        #expect(viewModel.sortOption == .popularityDesc)
        #expect(viewModel.yearFilter == nil)
        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.aiError == nil)
        #expect(viewModel.currentPage == 1)
        #expect(viewModel.totalPages == 1)
    }

    // MARK: - isGenreBrowsing Computed Property

    @Test
    @MainActor
    func isGenreBrowsingTrueWhenGenreSelectedAndNoQuery() {
        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        viewModel.selectedGenre = Genre(id: 28, name: "Action")
        viewModel.query = ""
        #expect(viewModel.isGenreBrowsing == true)
    }

    @Test
    @MainActor
    func isGenreBrowsingFalseWhenNoGenreSelected() {
        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        viewModel.selectedGenre = nil
        viewModel.query = "test"
        #expect(viewModel.isGenreBrowsing == false)
    }

    @Test
    @MainActor
    func isGenreBrowsingFalseWhenGenreSelectedButQueryPresent() {
        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        viewModel.selectedGenre = Genre(id: 28, name: "Action")
        viewModel.query = "action movies"
        #expect(viewModel.isGenreBrowsing == false)
    }

    // MARK: - Default Sort Option

    @Test
    @MainActor
    func defaultSortOptionIsPopularityDesc() {
        let viewModel = SearchViewModel(metadataService: FilterTestMetadataStub())
        #expect(viewModel.sortOption == .popularityDesc)
    }

    // MARK: - No Metadata Service Configured

    @Test
    @MainActor
    func loadGenresWithNoServiceDoesNotCrash() async throws {
        let viewModel = SearchViewModel()
        // No metadata service configured
        viewModel.loadGenres()

        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.genres.isEmpty)
    }

    @Test
    @MainActor
    func selectGenreWithNoServiceDoesNotCrash() async throws {
        let viewModel = SearchViewModel()
        viewModel.selectGenre(Genre(id: 28, name: "Action"))

        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.selectedGenre?.id == 28)
    }

    // MARK: - AIMovieRecommendation → MediaPreview

    @Test
    func aiRecommendationToMediaPreviewWithTmdbId() {
        let rec = AIMovieRecommendation(title: "Dune", year: 2021, type: .movie, reason: "Great", tmdbId: 438631)
        let preview = rec.toMediaPreview()
        #expect(preview.id == "movie-tmdb-438631")
        #expect(preview.title == "Dune")
        #expect(preview.year == 2021)
        #expect(preview.type == .movie)
        #expect(preview.tmdbId == 438631)
    }

    @Test
    func aiRecommendationToMediaPreviewWithoutTmdbId() {
        let rec = AIMovieRecommendation(title: "Unknown Film", year: 2020, type: .series, reason: "Interesting")
        let preview = rec.toMediaPreview()
        #expect(preview.id == "unknown-film-2020-series")
        #expect(preview.title == "Unknown Film")
        #expect(preview.type == .series)
        #expect(preview.tmdbId == nil)
    }

    // MARK: - Interaction: Genre + Sort Combined

    @Test
    @MainActor
    func genreAndSortCombinedInDiscover() async throws {
        let stub = FilterTestMetadataStub()
        let genre = Genre(id: 878, name: "Science Fiction")
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "scifi-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.sortOption = .releaseDateDesc
        viewModel.yearFilter = 2025
        viewModel.selectedType = .movie
        viewModel.selectGenre(genre)

        try await Self.waitUntil { !viewModel.results.isEmpty }

        let lastFilters = await stub.getLastDiscoverFilters()
        #expect(lastFilters?.genreId == 878)
        #expect(lastFilters?.sortBy == .releaseDateDesc)
        #expect(lastFilters?.year == 2025)
        #expect(lastFilters?.page == 1)
    }
}
