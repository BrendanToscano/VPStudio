import Foundation
import SwiftUI
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SearchViewModelDebounceOptimizationTests {

    // MARK: - Test Stubs

    private actor CountingMetadataStub: MetadataProvider {
        var searchCallCount = 0
        var lastSearchQuery: String?
        var searchResultByPage: [Int: MetadataSearchResult] = [:]

        func setSearchResults(_ results: [Int: MetadataSearchResult]) {
            searchResultByPage = results
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            searchCallCount += 1
            lastSearchQuery = query
            return searchResultByPage[page] ?? MetadataSearchResult(items: [], page: page, totalPages: page, totalResults: 0)
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

    // MARK: - Minimum Query Length Tests

    @Test
    @MainActor
    func minimumQueryLengthIsTwo() {
        #expect(SearchViewModel.minimumQueryLength == 2)
    }

    @Test
    @MainActor
    func debouncedSearchSkipsSingleCharacterQuery() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(50))
        
        // Single character should not trigger search
        viewModel.query = "a"
        viewModel.debouncedSearch()
        
        // Wait longer than debounce
        try await Task.sleep(for: .milliseconds(150))
        
        let callCount = await stub.searchCallCount
        #expect(callCount == 0)
        #expect(viewModel.results.isEmpty)
    }

    @Test
    @MainActor
    func debouncedSearchSkipsEmptyQuery() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(50))
        
        // Empty query should not trigger search
        viewModel.query = ""
        viewModel.debouncedSearch()
        
        try await Task.sleep(for: .milliseconds(150))
        
        let callCount = await stub.searchCallCount
        #expect(callCount == 0)
    }

    @Test
    @MainActor
    func debouncedSearchTriggersForTwoCharacterQuery() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(50))
        
        // Two characters should trigger search
        viewModel.query = "ab"
        viewModel.debouncedSearch()
        
        try await Self.waitUntil { !viewModel.results.isEmpty }
        
        let callCount = await stub.searchCallCount
        #expect(callCount == 1)
        #expect(viewModel.results.first?.id == "result")
    }

    @Test
    @MainActor
    func explicitSearchStillWorksWithShortQuery() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "explicit-result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        
        // Explicit search bypasses minimum length check
        viewModel.query = "a"
        viewModel.search()
        
        try await Self.waitUntil { !viewModel.results.isEmpty }
        
        let callCount = await stub.searchCallCount
        #expect(callCount == 1)
    }

    // MARK: - Duplicate Debounce Prevention Tests

    @Test
    @MainActor
    func debouncedSearchSkipsWhenQueryUnchanged() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(100))
        
        // Set initial query
        viewModel.query = "test"
        viewModel.debouncedSearch()
        
        // Set same query again - should not trigger new debounce
        viewModel.query = "test"
        viewModel.debouncedSearch()
        
        // Wait for first debounce to fire
        try await Self.waitUntil { !viewModel.results.isEmpty }
        
        // Should only have one search call
        let callCount = await stub.searchCallCount
        #expect(callCount == 1)
    }

    @Test
    @MainActor
    func debouncedSearchTriggersOnNewQuery() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "first")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(100))
        
        // First query
        viewModel.query = "first"
        viewModel.debouncedSearch()
        
        // Wait for first debounce to fire
        try await Self.waitUntil { viewModel.results.first?.id == "first" }
        
        // Now change query - should trigger new search
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "second")], page: 1, totalPages: 1, totalResults: 1)
        ])
        
        viewModel.query = "second"
        viewModel.debouncedSearch()
        
        try await Self.waitUntil { viewModel.results.first?.id == "second" }
        
        // Should have two search calls
        let callCount = await stub.searchCallCount
        #expect(callCount == 2)
    }

    @Test
    @MainActor
    func clearResetsLastDebouncedQuery() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(50))
        
        viewModel.query = "test"
        viewModel.debouncedSearch()
        
        // Clear should reset the last debounced query
        viewModel.clear()
        
        // Now set the same query - should trigger new search since we cleared
        viewModel.query = "test"
        viewModel.debouncedSearch()
        
        try await Self.waitUntil { !viewModel.results.isEmpty }
        
        let callCount = await stub.searchCallCount
        #expect(callCount == 1)
    }

    @Test
    @MainActor
    func debouncedSearchClearsPendingTaskForShortQuery() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(200))
        
        // Start with valid query
        viewModel.query = "test"
        viewModel.debouncedSearch()
        
        // Quickly change to short query - should cancel pending debounce
        viewModel.query = "a"
        viewModel.debouncedSearch()
        
        // Wait for original debounce to expire
        try await Task.sleep(for: .milliseconds(400))
        
        // Should not have any search calls since query was shortened
        let callCount = await stub.searchCallCount
        #expect(callCount == 0)
    }

    @Test
    @MainActor
    func debouncedSearchVerifiesQueryAfterDelay() async throws {
        let stub = CountingMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "result")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub, debounceInterval: .milliseconds(100))
        
        // Start with valid query
        viewModel.query = "test"
        viewModel.debouncedSearch()
        
        // Change query before debounce fires
        try await Task.sleep(for: .milliseconds(50))
        viewModel.query = "changed"
        
        // Wait for debounce to fire
        try await Self.waitUntil { !viewModel.results.isEmpty }
        
        // Should search with the final query
        let lastQuery = await stub.lastSearchQuery
        #expect(lastQuery == "changed")
    }
}
