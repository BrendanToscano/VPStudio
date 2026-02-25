import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SearchViewModelTests {
    private actor SearchMetadataStub: MetadataProvider {
        var responseByPage: [Int: MetadataSearchResult] = [:]

        func setResponses(_ responses: [Int: MetadataSearchResult]) {
            responseByPage = responses
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            responseByPage[page] ?? MetadataSearchResult(items: [], page: page, totalPages: page, totalResults: 0)
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
    func configureWithEmptyApiKeyDoesNotConfigureService() async throws {
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
        try await Self.waitUntil { !configuredViewModel.results.isEmpty }
        #expect(configuredViewModel.results.first?.id == "result-valid-key-p1")

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
}
