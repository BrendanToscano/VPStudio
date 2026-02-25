import Foundation
import SwiftUI
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SearchViewModelPerformanceTests {

    // MARK: - Test Stubs

    /// A metadata stub that records search call count and supports configurable delays.
    private actor CountingMetadataStub: MetadataProvider {
        var searchCallCount = 0
        var discoverCallCount = 0
        var genreCallCount = 0
        var searchResultByPage: [Int: MetadataSearchResult] = [:]
        var discoverResultByPage: [Int: MetadataSearchResult] = [:]
        var genresByType: [MediaType: [Genre]] = [:]
        var searchDelay: Duration?
        var lastSearchQuery: String?

        func setSearchResults(_ results: [Int: MetadataSearchResult]) {
            searchResultByPage = results
        }

        func setDiscoverResults(_ results: [Int: MetadataSearchResult]) {
            discoverResultByPage = results
        }

        func setGenres(_ genres: [Genre], for type: MediaType) {
            genresByType[type] = genres
        }

        func setSearchDelay(_ delay: Duration?) {
            searchDelay = delay
        }

        func getSearchCallCount() -> Int { searchCallCount }
        func getDiscoverCallCount() -> Int { discoverCallCount }
        func getGenreCallCount() -> Int { genreCallCount }
        func getLastSearchQuery() -> String? { lastSearchQuery }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            searchCallCount += 1
            lastSearchQuery = query
            if let delay = searchDelay {
                try await Task.sleep(for: delay)
            }
            return searchResultByPage[page] ?? MetadataSearchResult(items: [], page: page, totalPages: page, totalResults: 0)
        }

        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult {
            discoverCallCount += 1
            if let delay = searchDelay {
                try await Task.sleep(for: delay)
            }
            return discoverResultByPage[filters.page] ?? MetadataSearchResult(items: [], page: filters.page, totalPages: filters.page, totalResults: 0)
        }

        func getGenres(type: MediaType) async throws -> [Genre] {
            genreCallCount += 1
            return genresByType[type] ?? []
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
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
            await Task.yield()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Debounce Tests

    @Test
    @MainActor
    func debouncedSearchWaitsBeforeExecuting() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "debounce-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        // Use a 100ms debounce for faster testing
        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(100))
        viewModel.query = "test"

        viewModel.debouncedSearch()

        // Immediately after calling debouncedSearch, no search should have been made yet
        let immediateCount = await stub.getSearchCallCount()
        #expect(immediateCount == 0)

        // Wait for the debounce interval to expire
        try await Self.waitUntil { !viewModel.results.isEmpty }

        let afterDebounceCount = await stub.getSearchCallCount()
        #expect(afterDebounceCount == 1)
        #expect(viewModel.results.first?.id == "debounce-1")
    }

    @Test
    @MainActor
    func rapidDebouncedSearchCallsOnlyTriggerOneFinalSearch() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "final-result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(80))

        // Simulate rapid typing: each keystroke triggers debouncedSearch
        viewModel.query = "t"
        viewModel.debouncedSearch()
        try await Task.sleep(for: .milliseconds(20))

        viewModel.query = "te"
        viewModel.debouncedSearch()
        try await Task.sleep(for: .milliseconds(20))

        viewModel.query = "tes"
        viewModel.debouncedSearch()
        try await Task.sleep(for: .milliseconds(20))

        viewModel.query = "test"
        viewModel.debouncedSearch()

        // Wait long enough for the final debounce to fire
        try await Self.waitUntil(timeout: .milliseconds(3000)) { !viewModel.results.isEmpty }

        // Only the final search should have been executed
        let callCount = await stub.getSearchCallCount()
        #expect(callCount == 1)
        let lastQuery = await stub.getLastSearchQuery()
        #expect(lastQuery == "test")
    }

    @Test
    @MainActor
    func explicitSearchBypassesDebounce() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "explicit-result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        // Long debounce to ensure we can differentiate
        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(5000))
        viewModel.query = "test"

        // Start a debounced search first (which would take 5 seconds)
        viewModel.debouncedSearch()

        // Immediately call explicit search — should execute right away
        viewModel.search()
        try await Self.waitUntil { !viewModel.results.isEmpty }

        let callCount = await stub.getSearchCallCount()
        #expect(callCount == 1)
        #expect(viewModel.results.first?.id == "explicit-result")
    }

    @Test
    @MainActor
    func debouncedSearchCancelledByCancelInFlightWork() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "should-not-appear")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(100))
        viewModel.query = "test"

        viewModel.debouncedSearch()

        // Cancel before debounce fires
        viewModel.cancelInFlightWork()

        // Wait long enough that the debounce would have fired
        try await Task.sleep(for: .milliseconds(200))

        let callCount = await stub.getSearchCallCount()
        #expect(callCount == 0)
        #expect(viewModel.results.isEmpty)
    }

    @Test
    @MainActor
    func debouncedSearchWithEmptyQueryDoesNotExecute() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "should-not-appear")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(50))
        viewModel.query = "   "

        viewModel.debouncedSearch()

        // Wait for debounce to expire
        try await Task.sleep(for: .milliseconds(150))

        // search() itself guards on non-empty query, so even though debounce fires, search won't execute
        let callCount = await stub.getSearchCallCount()
        #expect(callCount == 0)
        #expect(viewModel.results.isEmpty)
    }

    @Test
    @MainActor
    func debounceIntervalIsConfigurable() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "custom-interval")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(50))
        #expect(viewModel.debounceInterval == .milliseconds(50))

        viewModel.query = "test"
        viewModel.debouncedSearch()

        // Should fire quickly with 50ms debounce
        try await Self.waitUntil(timeout: .milliseconds(500)) { !viewModel.results.isEmpty }
        let callCount = await stub.getSearchCallCount()
        #expect(callCount == 1)
    }

    @Test
    @MainActor
    func defaultDebounceIntervalIs300ms() {
        let viewModel = SearchViewModel()
        #expect(viewModel.debounceInterval == .milliseconds(300))
    }

    // MARK: - Search Generation Tests

    @Test
    @MainActor
    func searchGenerationIncrementsOnEachSearch() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "gen-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        #expect(viewModel.searchGeneration == 0)

        viewModel.query = "first"
        viewModel.search()
        #expect(viewModel.searchGeneration == 1)

        try await Self.waitUntil { !viewModel.isSearching }

        viewModel.query = "second"
        viewModel.search()
        #expect(viewModel.searchGeneration == 2)
    }

    @Test
    @MainActor
    func searchGenerationIncrementsOnGenreBrowse() async throws {
        let stub = CountingMetadataStub()
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "genre-gen")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        #expect(viewModel.searchGeneration == 0)

        viewModel.browseGenre(Genre(id: 28, name: "Action"))
        #expect(viewModel.searchGeneration == 1)

        try await Self.waitUntil { !viewModel.isSearching }

        viewModel.browseGenre(Genre(id: 35, name: "Comedy"))
        #expect(viewModel.searchGeneration == 2)
    }

    @Test
    @MainActor
    func staleSearchResultsAreDiscarded() async throws {
        let stub = CountingMetadataStub()
        // The first search returns slowly
        await stub.setSearchDelay(.milliseconds(200))
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "stale-result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "first"
        viewModel.search()
        let firstGeneration = viewModel.searchGeneration

        // Before the first search finishes, start a new one
        // The slow stub means "first" is still in-flight
        try await Task.sleep(for: .milliseconds(50))
        await stub.setSearchDelay(nil) // Second search returns instantly
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "fresh-result")], page: 1, totalPages: 1, totalResults: 1)
        ])
        viewModel.query = "second"
        viewModel.search()
        let secondGeneration = viewModel.searchGeneration

        #expect(secondGeneration > firstGeneration)

        // Wait for the second search to finish
        try await Self.waitUntil { !viewModel.results.isEmpty }

        // Results should be from the second search, not the stale first
        #expect(viewModel.results.first?.id == "fresh-result")
    }

    @Test
    @MainActor
    func searchGenerationIncrementsOnMoodCardSelection() async throws {
        let stub = CountingMetadataStub()
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "mood-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        #expect(viewModel.searchGeneration == 0)

        let newReleasesCard = ExploreMoodCard(
            id: "new", title: "New Releases", subtitle: "JUST DROPPED",
            symbol: "flame.fill", color: .red, movieGenreId: -1, tvGenreId: -1
        )
        viewModel.selectMoodCard(newReleasesCard)
        #expect(viewModel.searchGeneration == 1)
    }

    // MARK: - Pagination Throttling Tests

    @Test
    @MainActor
    func loadMoreIsBlockedWhileAlreadyLoadingMore() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p1")],
                page: 1, totalPages: 3, totalResults: 60
            ),
            2: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p2")],
                page: 2, totalPages: 3, totalResults: 60
            ),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"

        // Initial search — no delay
        viewModel.search()
        try await Self.waitUntil { !viewModel.results.isEmpty }

        // Add a long delay so the loadMore stays in-flight
        await stub.setSearchDelay(.milliseconds(2000))

        // First loadMore should start and stay in-flight due to the delay
        viewModel.loadMore()

        // isLoadingMore should be true synchronously right after the call
        let firstLoadingMore = viewModel.isLoadingMore
        #expect(firstLoadingMore == true)

        // Second loadMore should be blocked (no-op because isLoadingMore is true)
        // This is a synchronous check — no awaits between loadMore calls
        viewModel.loadMore()
        viewModel.loadMore()

        // Wait a bit and verify only 2 total calls to stub (1 search + 1 loadMore)
        try await Task.sleep(for: .milliseconds(100))
        let totalSearchCalls = await stub.getSearchCallCount()
        // 1 = initial search, 2 = the one loadMore that got through
        #expect(totalSearchCalls == 2)
    }

    @Test
    @MainActor
    func loadMoreResetsIsLoadingMoreWhenComplete() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p1")],
                page: 1, totalPages: 2, totalResults: 2
            ),
            2: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p2")],
                page: 2, totalPages: 2, totalResults: 2
            ),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.search()
        try await Self.waitUntil { !viewModel.results.isEmpty }

        #expect(viewModel.isLoadingMore == false)

        viewModel.loadMore()
        try await Self.waitUntil { viewModel.results.count >= 2 }

        #expect(viewModel.isLoadingMore == false)
    }

    @Test
    @MainActor
    func newSearchResetsIsLoadingMore() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p1")],
                page: 1, totalPages: 3, totalResults: 60
            ),
            2: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p2")],
                page: 2, totalPages: 3, totalResults: 60
            ),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.search()
        try await Self.waitUntil { !viewModel.results.isEmpty }

        // Start loading more with a delay
        await stub.setSearchDelay(.milliseconds(300))
        viewModel.loadMore()
        #expect(viewModel.isLoadingMore == true)

        // Now fire a new search — should reset isLoadingMore
        await stub.setSearchDelay(nil)
        viewModel.query = "new query"
        viewModel.search()
        #expect(viewModel.isLoadingMore == false)
    }

    @Test
    @MainActor
    func clearResetsIsLoadingMore() {
        let stub = CountingMetadataStub()
        let viewModel = SearchViewModel(metadataService: stub)

        // Manually set loading state to simulate in-flight loadMore
        viewModel.clear()
        #expect(viewModel.isLoadingMore == false)
    }

    @Test
    @MainActor
    func loadMoreBlockedDuringActiveSearch() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p1")],
                page: 1, totalPages: 3, totalResults: 60
            ),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"

        // Start search with delay
        await stub.setSearchDelay(.milliseconds(200))
        viewModel.search()

        // Try to loadMore while isSearching is true
        viewModel.loadMore()

        try await Task.sleep(for: .milliseconds(50))

        // Only the search should have fired, not loadMore
        let callCount = await stub.getSearchCallCount()
        #expect(callCount == 1)
    }

    // MARK: - Genre Browse Pagination Throttling

    @Test
    @MainActor
    func genreBrowseLoadMoreIsThrottled() async throws {
        let stub = CountingMetadataStub()
        await stub.setDiscoverResults([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "disc-p1")],
                page: 1, totalPages: 3, totalResults: 60
            ),
            2: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "disc-p2")],
                page: 2, totalPages: 3, totalResults: 60
            ),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectGenre(Genre(id: 28, name: "Action"))
        try await Self.waitUntil { !viewModel.results.isEmpty }

        // Start loadMore with a delay
        await stub.setSearchDelay(.milliseconds(200))
        viewModel.loadMore()
        #expect(viewModel.isLoadingMore == true)

        // Second loadMore should be blocked
        viewModel.loadMore()

        try await Task.sleep(for: .milliseconds(50))

        // Only 1 discover for initial browse + 1 for the first loadMore = 2 total
        let discoverCount = await stub.getDiscoverCallCount()
        #expect(discoverCount == 2)
    }

    // MARK: - Lazy Genre Loading Tests

    @Test
    @MainActor
    func genresNotLoadedOnInit() async throws {
        let stub = CountingMetadataStub()
        await stub.setGenres([Genre(id: 28, name: "Action")], for: .movie)

        let _ = SearchViewModel(metadataService: stub)

        // Give time for any hypothetical eager loading
        try await Task.sleep(for: .milliseconds(100))

        let genreCallCount = await stub.getGenreCallCount()
        #expect(genreCallCount == 0)
    }

    @Test
    @MainActor
    func genresLoadedOnExplicitCall() async throws {
        let stub = CountingMetadataStub()
        await stub.setGenres([Genre(id: 28, name: "Action"), Genre(id: 35, name: "Comedy")], for: .movie)

        let viewModel = SearchViewModel(metadataService: stub)

        // No genres loaded yet
        #expect(viewModel.genres.isEmpty)

        viewModel.loadGenres()
        try await Self.waitUntil { !viewModel.genres.isEmpty }

        #expect(viewModel.genres.count == 2)
        let genreCallCount = await stub.getGenreCallCount()
        #expect(genreCallCount == 1)
    }

    @Test
    @MainActor
    func cachedGenresReturnImmediatelyWithoutNetworkCall() async throws {
        let stub = CountingMetadataStub()
        await stub.setGenres([Genre(id: 28, name: "Action")], for: .movie)

        let viewModel = SearchViewModel(metadataService: stub)

        // First load — network call
        viewModel.loadGenres()
        try await Self.waitUntil { !viewModel.genres.isEmpty }
        let firstCount = await stub.getGenreCallCount()
        #expect(firstCount == 1)

        // Clear genres to verify cache restores them synchronously
        viewModel.genres = []

        // Second load — should use cache (no additional network call)
        viewModel.loadGenres()
        #expect(viewModel.genres.count == 1) // Synchronous cache hit
        let secondCount = await stub.getGenreCallCount()
        #expect(secondCount == 1) // No additional call
    }

    // MARK: - Debounce + Genre Browse Interaction

    @Test
    @MainActor
    func browseGenreCancelsPendingDebounce() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "text-search-result")], page: 1, totalPages: 1, totalResults: 1)
        ])
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "genre-result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(500))
        viewModel.query = "test"

        // Start a debounced search (won't fire for 500ms)
        viewModel.debouncedSearch()

        // Immediately browse a genre — should cancel the debounce
        viewModel.browseGenre(Genre(id: 28, name: "Action"))
        try await Self.waitUntil { !viewModel.results.isEmpty }

        // The result should be from the genre browse, not from the text search
        #expect(viewModel.results.first?.id == "genre-result")

        // Wait to ensure the debounced search doesn't fire after
        try await Task.sleep(for: .milliseconds(600))
        let searchCount = await stub.getSearchCallCount()
        #expect(searchCount == 0) // No text search should have been made
    }

    @Test
    @MainActor
    func selectMoodCardCancelsPendingDebounce() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "text-result")], page: 1, totalPages: 1, totalResults: 1)
        ])
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "mood-result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(500))
        viewModel.query = "test"
        viewModel.debouncedSearch()

        // Select a mood card (new releases) — should cancel debounce
        let newReleasesCard = ExploreMoodCard(
            id: "new", title: "New Releases", subtitle: "JUST DROPPED",
            symbol: "flame.fill", color: .red, movieGenreId: -1, tvGenreId: -1
        )
        viewModel.selectMoodCard(newReleasesCard)
        try await Self.waitUntil { !viewModel.results.isEmpty }

        #expect(viewModel.results.first?.id == "mood-result")

        // Ensure the debounced search doesn't fire
        try await Task.sleep(for: .milliseconds(600))
        let searchCount = await stub.getSearchCallCount()
        #expect(searchCount == 0)
    }

    // MARK: - Cancel In-Flight Work

    @Test
    @MainActor
    func cancelInFlightWorkCancelsDebounceTask() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "should-not-appear")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(100))
        viewModel.query = "test"
        viewModel.debouncedSearch()

        // Cancel everything
        viewModel.cancelInFlightWork()

        // Wait longer than debounce interval
        try await Task.sleep(for: .milliseconds(200))

        let callCount = await stub.getSearchCallCount()
        #expect(callCount == 0)
        #expect(viewModel.results.isEmpty)
    }

    @Test
    @MainActor
    func cancelInFlightWorkCancelsAllTaskTypes() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "p1")], page: 1, totalPages: 2, totalResults: 2)
        ])
        await stub.setSearchDelay(.milliseconds(500))

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(100))
        viewModel.query = "test"

        // Start all task types
        viewModel.debouncedSearch()
        viewModel.loadGenres()

        // Cancel everything
        viewModel.cancelInFlightWork()

        // Wait for any potential tasks to complete
        try await Task.sleep(for: .milliseconds(300))

        // No results should appear
        let searchCount = await stub.getSearchCallCount()
        #expect(searchCount == 0)
        #expect(viewModel.results.isEmpty)
        #expect(viewModel.genres.isEmpty)
    }

    // MARK: - Edge Cases

    @Test
    @MainActor
    func multipleDebouncedSearchesThenExplicitSearchCancelsDebounce() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "explicit")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(200))

        // Rapid debounced calls
        viewModel.query = "a"
        viewModel.debouncedSearch()
        viewModel.query = "ab"
        viewModel.debouncedSearch()
        viewModel.query = "abc"
        viewModel.debouncedSearch()

        // Then explicit submit
        viewModel.search()
        try await Self.waitUntil { !viewModel.results.isEmpty }

        // Only one search call from the explicit search
        let callCount = await stub.getSearchCallCount()
        #expect(callCount == 1)

        // Wait to verify debounce doesn't fire after
        try await Task.sleep(for: .milliseconds(400))
        let laterCount = await stub.getSearchCallCount()
        #expect(laterCount == 1)
    }

    @Test
    @MainActor
    func searchGenerationPreventsStaleLoadMore() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p1-old")],
                page: 1, totalPages: 2, totalResults: 2
            ),
            2: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p2-old")],
                page: 2, totalPages: 2, totalResults: 2
            ),
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "first-query"
        viewModel.search()
        try await Self.waitUntil { !viewModel.results.isEmpty }

        // Start a slow loadMore
        await stub.setSearchDelay(.milliseconds(300))
        viewModel.loadMore()

        // While loadMore is in-flight, start a completely new search
        await stub.setSearchDelay(nil)
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [Fixtures.mediaPreview(id: "p1-new")],
                page: 1, totalPages: 1, totalResults: 1
            ),
        ])
        viewModel.query = "second-query"
        viewModel.search()

        try await Self.waitUntil { viewModel.results.first?.id == "p1-new" }

        // Wait for the old loadMore to potentially finish
        try await Task.sleep(for: .milliseconds(500))

        // Results should only contain the new search results, not stale page 2 from old query
        #expect(viewModel.results.count == 1)
        #expect(viewModel.results.first?.id == "p1-new")
    }

    @Test
    @MainActor
    func loadMoreNotCalledWhenNoMorePages() {
        let stub = CountingMetadataStub()
        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.currentPage = 1
        viewModel.totalPages = 1

        #expect(viewModel.hasMore == false)
        viewModel.loadMore() // Should be a no-op
        #expect(viewModel.isLoadingMore == false)
    }
}
// EOF - linter content removed
