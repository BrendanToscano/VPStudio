import Foundation
import SwiftUI
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SearchViewModelTests {
    private enum SearchStubError: Error {
        case forcedFailure
    }

    private actor SearchMetadataStub: MetadataProvider {
        var responseByPage: [Int: MetadataSearchResult] = [:]
        var failingPages: Set<Int> = []

        func setResponses(_ responses: [Int: MetadataSearchResult]) {
            responseByPage = responses
        }

        func setFailingPages(_ pages: Set<Int>) {
            failingPages = pages
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            if failingPages.contains(page) {
                throw SearchStubError.forcedFailure
            }
            return responseByPage[page] ?? MetadataSearchResult(items: [], page: page, totalPages: page, totalResults: 0)
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] { [] }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    private actor GenreLoadCountingMetadataStub: MetadataProvider {
        private(set) var getGenresCallCount = 0
        private let genres: [Genre]

        init(genres: [Genre] = [Genre(id: 28, name: "Action")]) {
            self.genres = genres
        }

        func recordGenresRequest() -> Int {
            getGenresCallCount
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            MetadataSearchResult(items: [], page: page, totalPages: 1, totalResults: 0)
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] {
            getGenresCallCount += 1
            return genres
        }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    private actor SlowGenreMetadataStub: MetadataProvider {
        private(set) var getGenresCallCount = 0
        private let genresByType: [MediaType: [Genre]]
        private let delay: Duration

        init(
            delay: Duration = .milliseconds(400),
            genresByType: [MediaType: [Genre]] = [
                .movie: [Genre(id: 28, name: "Action")],
                .series: [Genre(id: 10765, name: "Sci-Fi & Fantasy")]
            ]
        ) {
            self.delay = delay
            self.genresByType = genresByType
        }

        func recordGenresRequest() -> Int {
            getGenresCallCount
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            MetadataSearchResult(items: [], page: page, totalPages: 1, totalResults: 0)
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] {
            getGenresCallCount += 1
            // Deliberately ignore cancellation to emulate non-cooperative network code.
            try? await Task.sleep(for: delay)
            return genresByType[type] ?? []
        }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    private actor KeyedSearchMetadataStub: MetadataProvider {
        let marker: String

        init(marker: String) {
            self.marker = marker
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "result-\(marker)-p\(page)")],
                page: page,
                totalPages: 1,
                totalResults: 1
            )
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] { [] }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    private actor BlockingSearchMetadataStub: MetadataProvider {
        private var continuation: CheckedContinuation<MetadataSearchResult, Error>?

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        self.continuation = continuation
                    }
                },
                onCancel: {
                    Task { await self.resumeIfNeeded(throwing: CancellationError()) }
                }
            )
        }

        func unblock(with result: MetadataSearchResult = MetadataSearchResult(items: [], page: 1, totalPages: 1, totalResults: 0)) async {
            await resumeIfNeeded(returning: result)
        }

        private func resumeIfNeeded(returning result: MetadataSearchResult) {
            continuation?.resume(returning: result)
            continuation = nil
        }

        private func resumeIfNeeded(throwing error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] { [] }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    private actor DiscoverFilterCaptureMetadataStub: MetadataProvider {
        private(set) var lastDiscoverFilters: DiscoverFilters?
        private(set) var discoverCallCount = 0

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            MetadataSearchResult(items: [], page: 1, totalPages: 1, totalResults: 0)
        }

        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult {
            discoverCallCount += 1
            lastDiscoverFilters = filters
            return MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "discover-\(type.rawValue)-\(filters.page)")],
                page: filters.page,
                totalPages: 1,
                totalResults: 1
            )
        }

        func currentOriginalLanguage() -> String? {
            lastDiscoverFilters?.originalLanguage
        }

        func currentLanguage() -> String? {
            lastDiscoverFilters?.language
        }

        func currentDiscoverCallCount() -> Int {
            discoverCallCount
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] { [Genre(id: 18, name: "Drama")] }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
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
            // Yield first to give pending Tasks a chance to run on the main actor,
            // then sleep to avoid busy-waiting.
            await Task.yield()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static let searchCases = ExhaustiveMode.choose(fast: Array(0..<18), full: Array(0..<36))
    private static let paginationCases = ExhaustiveMode.choose(fast: Array(0..<18), full: Array(0..<36))

    @Test(arguments: searchCases)
    @MainActor
    func searchRespectsTrimAndState(index: Int) async throws {
        let stub = SearchMetadataStub()
        await stub.setResponses([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "movie-tmdb-\(index)")], page: 1, totalPages: 3, totalResults: 3)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = index % 2 == 0 ? "  Query \(index)  " : "Query \(index)"

        viewModel.search()
        // Wait for results to appear (isSearching starts false, so we can't poll on it).
        try await Self.waitUntil { !viewModel.results.isEmpty }

        #expect(viewModel.currentPage == 1)
        #expect(viewModel.totalPages == 3)
        #expect(viewModel.results.count == 1)
        #expect(viewModel.results.first?.id == "movie-tmdb-\(index)")
    }

    @Test(arguments: paginationCases)
    @MainActor
    func loadMoreAppendsResults(index: Int) async throws {
        let stub = SearchMetadataStub()
        await stub.setResponses([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "p1-\(index)")], page: 1, totalPages: 2, totalResults: 2),
            2: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "p2-\(index)")], page: 2, totalPages: 2, totalResults: 2),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"

        viewModel.search()
        // Wait for first page results before calling loadMore
        // (loadMore guards on hasMore which requires totalPages to be set).
        try await Self.waitUntil { !viewModel.results.isEmpty }
        viewModel.loadMore()
        try await Self.waitUntil { viewModel.results.count >= 2 }

        #expect(viewModel.results.count == 2)
        #expect(viewModel.currentPage == 2)
        #expect(viewModel.results.map(\.id) == ["p1-\(index)", "p2-\(index)"])

        viewModel.clear()
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.query.isEmpty)
        #expect(viewModel.currentPage == 1)
    }

    @Test
    @MainActor
    func loadMoreDeduplicatesOverlappingPageResults() async throws {
        let stub = SearchMetadataStub()
        await stub.setResponses([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "page-1-a"),
                    Fixtures.mediaPreview(id: "page-1-b"),
                ],
                page: 1,
                totalPages: 2,
                totalResults: 3
            ),
            2: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "page-1-b"),
                    Fixtures.mediaPreview(id: "page-2-c"),
                ],
                page: 2,
                totalPages: 2,
                totalResults: 3
            ),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.search()
        try await Self.waitUntil { viewModel.results.count == 2 }

        viewModel.loadMore()
        try await Self.waitUntil { viewModel.currentPage == 2 && viewModel.isLoadingMore == false }

        #expect(viewModel.results.map(\.id) == ["page-1-a", "page-1-b", "page-2-c"])
    }

    @Test
    @MainActor
    func loadMoreFailureSurfacesErrorAndAllowsImmediateRetry() async throws {
        let stub = SearchMetadataStub()
        await stub.setResponses([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "page-1")],
                page: 1,
                totalPages: 2,
                totalResults: 2
            ),
            2: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "page-2")],
                page: 2,
                totalPages: 2,
                totalResults: 2
            ),
        ])
        await stub.setFailingPages([2])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "retry me"
        viewModel.search()
        try await Self.waitUntil { viewModel.results.count == 1 }

        viewModel.loadMore()
        try await Self.waitUntil { viewModel.isLoadingMore == false && viewModel.error != nil }

        #expect(viewModel.results.map(\.id) == ["page-1"])
        #expect(viewModel.currentPage == 1)

        await stub.setFailingPages([])
        viewModel.loadMore()
        try await Self.waitUntil { viewModel.results.count == 2 }

        #expect(viewModel.results.map(\.id) == ["page-1", "page-2"])
        #expect(viewModel.currentPage == 2)
        #expect(viewModel.error == nil)
    }

    @Test
    @MainActor
    func genreLoadingIsLazyUntilExplicitRequest() async throws {
        let stub = GenreLoadCountingMetadataStub(genres: [
            Genre(id: 28, name: "Action"),
            Genre(id: 35, name: "Comedy")
        ])
        let viewModel = SearchViewModel(metadataService: stub)

        viewModel.query = "noop"
        viewModel.search()

        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))

        #expect(await stub.recordGenresRequest() == 0)
        #expect(viewModel.genres.isEmpty)

        viewModel.loadGenres()

        var attempts = 0
        var genreLoads = await stub.recordGenresRequest()
        while genreLoads == 0 && attempts < 80 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(50))
            genreLoads = await stub.recordGenresRequest()
        }

        #expect(genreLoads == 1)
        #expect(viewModel.genres.count == 2)

        viewModel.loadGenres()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await stub.recordGenresRequest() == 1)
    }

    @Test
    @MainActor
    func loadGenresCoalescesDuplicateInFlightRequests() async throws {
        let stub = SlowGenreMetadataStub(delay: .milliseconds(500))
        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectedType = .movie

        viewModel.loadGenres()
        viewModel.loadGenres()

        try await Self.waitUntil { !viewModel.genres.isEmpty }

        // Duplicate taps/reopens while the first request is in-flight should be coalesced
        // into a single genre-network call.
        #expect(await stub.recordGenresRequest() == 1)
        #expect(viewModel.genres.first?.name == "Action")
    }

    // MARK: - Edge cases (P1-T09)

    @Test
    @MainActor
    func searchWithEmptyQueryDoesNothing() async throws {
        let stub = SearchMetadataStub()
        await stub.setResponses([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "should-not-appear")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = ""
        viewModel.search()

        // Give any potential Task time to run
        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.currentPage == 1)
    }

    @Test
    @MainActor
    func searchWithWhitespaceOnlyQueryDoesNothing() async throws {
        let stub = SearchMetadataStub()
        await stub.setResponses([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "should-not-appear")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "   \t   "
        viewModel.search()

        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.currentPage == 1)
    }

    @Test
    @MainActor
    func searchWithLongQueryStillWorks() async throws {
        let stub = SearchMetadataStub()
        let longQuery = String(repeating: "a", count: 500)
        await stub.setResponses([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "long-result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = longQuery
        viewModel.search()
        try await Self.waitUntil { !viewModel.results.isEmpty }

        #expect(viewModel.results.count == 1)
        #expect(viewModel.results.first?.id == "long-result")
    }

    @Test
    @MainActor
    func configureReplacesMetadataServiceWhenApiKeyChanges() async throws {
        let viewModel = SearchViewModel(metadataServiceFactory: { key in
            KeyedSearchMetadataStub(marker: key)
        })
        viewModel.query = "api-key-rotation"

        viewModel.configure(apiKey: "key-a")
        viewModel.search()
        try await Self.waitUntil { viewModel.results.first?.id == "result-key-a-p1" }
        #expect(viewModel.results.first?.id == "result-key-a-p1")

        viewModel.configure(apiKey: "key-b")
        viewModel.search()
        try await Self.waitUntil { viewModel.results.first?.id == "result-key-b-p1" }
        #expect(viewModel.results.first?.id == "result-key-b-p1")
    }

    @Test
    @MainActor
    func configureWithEmptyApiKeyClearsConfiguredService() async throws {
        let configuredViewModel = SearchViewModel(metadataServiceFactory: { key in
            KeyedSearchMetadataStub(marker: key.isEmpty ? "empty" : key)
        })
        configuredViewModel.query = "query"
        configuredViewModel.configure(apiKey: "valid-key")
        configuredViewModel.search()
        try await Self.waitUntil { configuredViewModel.results.first?.id == "result-valid-key-p1" }

        configuredViewModel.results = []
        configuredViewModel.configure(apiKey: "   ")
        configuredViewModel.search()

        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))
        #expect(configuredViewModel.results.isEmpty)

        configuredViewModel.configure(apiKey: "new-key")
        configuredViewModel.search()
        try await Self.waitUntil { configuredViewModel.results.first?.id == "result-new-key-p1" }
        #expect(configuredViewModel.results.first?.id == "result-new-key-p1")

        let unconfiguredViewModel = SearchViewModel(metadataServiceFactory: { key in
            KeyedSearchMetadataStub(marker: key.isEmpty ? "empty" : key)
        })
        unconfiguredViewModel.query = "query"
        unconfiguredViewModel.configure(apiKey: "   ")
        unconfiguredViewModel.search()

        await Task.yield()
        try await Task.sleep(for: .milliseconds(100))

        #expect(unconfiguredViewModel.results.isEmpty)
    }

    @Test
    @MainActor
    func searchWithoutMetadataServiceSurfacesTmdbSetupError() async {
        let viewModel = SearchViewModel()
        viewModel.query = "Dune"

        viewModel.search()

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.error == .tmdbSetupRequired(feature: "Search"))
        #expect(viewModel.submittedQuery == "Dune")
    }

    @Test
    @MainActor
    func browseGenreWithoutMetadataServiceSurfacesTmdbSetupError() {
        let viewModel = SearchViewModel()

        viewModel.selectGenre(Genre(id: 28, name: "Action"))

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.selectedGenre?.id == 28)
        #expect(viewModel.error == .tmdbSetupRequired(feature: "Search"))
    }

    @Test
    @MainActor
    func specialMoodBrowseWithoutMetadataServiceSurfacesTmdbSetupError() {
        let viewModel = SearchViewModel()
        let newReleasesCard = ExploreGenreCatalog.cards.first(where: { $0.id == "new" })!

        viewModel.selectMoodCard(newReleasesCard)

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.activeMoodCard?.id == newReleasesCard.id)
        #expect(viewModel.error == .tmdbSetupRequired(feature: "Search"))
    }

    @Test
    @MainActor
    func configureWithEmptyApiKeyClearsKeyOwnedSearchState() async throws {
        let viewModel = SearchViewModel(metadataServiceFactory: { key in
            KeyedSearchMetadataStub(marker: key.isEmpty ? "empty" : key)
        })

        viewModel.configure(apiKey: "valid-key")
        viewModel.query = "query"
        viewModel.search()
        try await Self.waitUntil { viewModel.results.first?.id == "result-valid-key-p1" }

        viewModel.selectedGenre = Genre(id: 28, name: "Action")
        viewModel.currentPage = 2
        viewModel.totalPages = 5

        viewModel.configure(apiKey: "   ")

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.selectedGenre == nil)
        #expect(viewModel.currentPage == 1)
        #expect(viewModel.totalPages == 1)
        #expect(viewModel.isSearching == false)
        #expect(viewModel.isLoadingMore == false)
    }

    @Test
    @MainActor
    func inFlightSearchDoesNotRetainViewModelAfterRelease() async throws {
        let stub = BlockingSearchMetadataStub()
        var viewModel: SearchViewModel? = SearchViewModel(metadataService: stub)
        weak var weakViewModel = viewModel

        viewModel?.query = "retention-test"
        viewModel?.search()

        await Task.yield()
        viewModel = nil

        for _ in 0..<20 {
            if weakViewModel == nil { break }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(weakViewModel == nil)
        await stub.unblock()
    }

    @Test
    @MainActor
    func originalLanguageCodeDoesNotSendForDefaultEnglishOnly() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["en-US"]

        #expect(viewModel.originalLanguageCode == nil)
    }

    @Test
    @MainActor
    func originalLanguageCodeDoesNotSendForMultipleSelections() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["en-US", "fr-FR"]

        #expect(viewModel.originalLanguageCode == nil)
    }

    @Test
    @MainActor
    func primaryLanguagePrefersFirstKnownLanguageWhenMultipleSelected() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["ja-JP", "fr-FR"]

        #expect(viewModel.primaryLanguage == "fr-FR")
    }

    @Test(arguments: ["hi-IN", "ta-IN", "te-IN", "bn-IN"])
    @MainActor
    func originalLanguageCodeDoesNotSendForHindiOrRelatedIndianLocales(localeCode: String) {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = [localeCode]

        #expect(viewModel.originalLanguageCode == nil)
    }

    @Test
    @MainActor
    func originalLanguageCodeUsesIso639ForOtherSingleNonEnglishLocale() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["fr-FR"]

        #expect(viewModel.originalLanguageCode == "fr")
    }

    @Test
    @MainActor
    func browseGenreOmitsOriginalLanguageForHindiLocaleSelection() async throws {
        let stub = DiscoverFilterCaptureMetadataStub()
        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.languageFilters = ["hi-IN"]

        viewModel.selectGenre(Genre(id: 18, name: "Drama"))

        var calls = await stub.currentDiscoverCallCount()
        var attempts = 0
        while calls == 0 && attempts < 40 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(40))
            calls = await stub.currentDiscoverCallCount()
        }

        #expect(await stub.currentDiscoverCallCount() > 0)
        #expect(await stub.currentOriginalLanguage() == nil)
    }

    @Test
    @MainActor
    func browseGenreSendsOriginalLanguageForSingleFrenchLocaleSelection() async throws {
        let stub = DiscoverFilterCaptureMetadataStub()
        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.languageFilters = ["fr-FR"]

        viewModel.selectGenre(Genre(id: 18, name: "Drama"))

        var captured = await stub.currentOriginalLanguage()
        var attempts = 0
        while captured != "fr" && attempts < 40 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(40))
            captured = await stub.currentOriginalLanguage()
        }

        #expect(await stub.currentDiscoverCallCount() > 0)
        #expect(await stub.currentOriginalLanguage() == "fr")
    }

    @Test
    @MainActor
    func browseGenreUsesPreferredLanguageWhenMultipleLanguagesSelected() async throws {
        let stub = DiscoverFilterCaptureMetadataStub()
        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.languageFilters = ["ja-JP", "fr-FR"]

        viewModel.selectGenre(Genre(id: 18, name: "Drama"))

        var capturedLanguage = await stub.currentLanguage()
        var attempts = 0
        while capturedLanguage != "fr-FR" && attempts < 40 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(40))
            capturedLanguage = await stub.currentLanguage()
        }

        #expect(await stub.currentDiscoverCallCount() > 0)
        #expect(await stub.currentLanguage() == "fr-FR")
        #expect(await stub.currentOriginalLanguage() == nil)
    }
}
