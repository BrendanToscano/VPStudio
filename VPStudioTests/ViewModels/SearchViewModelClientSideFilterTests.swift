import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SearchViewModelClientSideFilterTests {

    // MARK: - Test Stubs

    private actor ClientFilterTestMetadataStub: MetadataProvider {
        var searchResultByPage: [Int: MetadataSearchResult] = [:]
        var discoverResultByPage: [Int: MetadataSearchResult] = [:]
        var genresByType: [MediaType: [Genre]] = [:]
        var searchCallCount = 0
        var discoverCallCount = 0
        var lastSearchQuery: String?
        var lastSearchYear: Int?

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
        func getLastSearchQuery() -> String? { lastSearchQuery }
        func getLastSearchYear() -> Int? { lastSearchYear }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            searchCallCount += 1
            lastSearchQuery = query
            return searchResultByPage[page] ?? MetadataSearchResult(items: [], page: page, totalPages: page, totalResults: 0)
        }

        func search(query: String, type: MediaType?, page: Int, year: Int?, language: String?) async throws -> MetadataSearchResult {
            searchCallCount += 1
            lastSearchQuery = query
            lastSearchYear = year
            return searchResultByPage[page] ?? MetadataSearchResult(items: [], page: page, totalPages: page, totalResults: 0)
        }

        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult {
            discoverCallCount += 1
            return discoverResultByPage[filters.page] ?? MetadataSearchResult(items: [], page: filters.page, totalPages: filters.page, totalResults: 0)
        }

        func getGenres(type: MediaType) async throws -> [Genre] {
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
        case testFailure

        var errorDescription: String? { "Test failure" }
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

    // MARK: - Client-Side Sorting Tests

    @Test
    @MainActor
    func searchWithRatingSortAppliesClientSideSorting() async throws {
        let stub = ClientFilterTestMetadataStub()
        // Results are unsorted from API (mixed ratings)
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "low-rated", title: "Low Rated", imdbRating: 5.0),
                    Fixtures.mediaPreview(id: "high-rated", title: "High Rated", imdbRating: 9.0),
                    Fixtures.mediaPreview(id: "mid-rated", title: "Mid Rated", imdbRating: 7.0),
                ],
                page: 1, totalPages: 1, totalResults: 3
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.sortOption = .ratingDesc  // Non-default sort requires client-side sorting
        viewModel.search()

        try await Self.waitUntil { !viewModel.isSearching && !viewModel.results.isEmpty }

        // Results should be sorted by rating descending (client-side)
        #expect(viewModel.results.count == 3)
        #expect(viewModel.results[0].id == "high-rated")
        #expect(viewModel.results[1].id == "mid-rated")
        #expect(viewModel.results[2].id == "low-rated")
    }

    @Test
    @MainActor
    func searchWithTitleSortAppliesClientSideSorting() async throws {
        let stub = ClientFilterTestMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "z-movie", title: "Zebra Movie", imdbRating: 7.0),
                    Fixtures.mediaPreview(id: "a-movie", title: "Alpha Movie", imdbRating: 7.0),
                    Fixtures.mediaPreview(id: "m-movie", title: "Mike Movie", imdbRating: 7.0),
                ],
                page: 1, totalPages: 1, totalResults: 3
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.sortOption = .titleAsc
        viewModel.search()

        try await Self.waitUntil { !viewModel.isSearching && !viewModel.results.isEmpty }

        // Results should be sorted alphabetically
        #expect(viewModel.results.count == 3)
        #expect(viewModel.results[0].id == "a-movie")
        #expect(viewModel.results[1].id == "m-movie")
        #expect(viewModel.results[2].id == "z-movie")
    }

    @Test
    @MainActor
    func searchWithReleaseDateSortAppliesClientSideSorting() async throws {
        let stub = ClientFilterTestMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "old-movie", title: "Old Movie", year: 2000),
                    Fixtures.mediaPreview(id: "new-movie", title: "New Movie", year: 2024),
                    Fixtures.mediaPreview(id: "mid-movie", title: "Mid Movie", year: 2010),
                ],
                page: 1, totalPages: 1, totalResults: 3
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.sortOption = .releaseDateDesc
        viewModel.search()

        try await Self.waitUntil { !viewModel.isSearching && !viewModel.results.isEmpty }

        // Results should be sorted by year descending (newest first)
        #expect(viewModel.results.count == 3)
        #expect(viewModel.results[0].id == "new-movie")
        #expect(viewModel.results[1].id == "mid-movie")
        #expect(viewModel.results[2].id == "old-movie")
    }

    // MARK: - Year Range Preset Filter Tests

    @Test
    @MainActor
    func searchWithYearPresetFilterAppliesClientSide() async throws {
        let stub = ClientFilterTestMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "movie-2024", title: "Movie 2024", year: 2024),
                    Fixtures.mediaPreview(id: "movie-2025", title: "Movie 2025", year: 2025),
                    Fixtures.mediaPreview(id: "movie-2015", title: "Movie 2015", year: 2015),
                    Fixtures.mediaPreview(id: "movie-2023", title: "Movie 2023", year: 2023),
                ],
                page: 1, totalPages: 1, totalResults: 4
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.applyYearRangePreset(.recent)  // 2024-2026
        viewModel.search()

        try await Self.waitUntil { !viewModel.isSearching && !viewModel.results.isEmpty }

        // Should filter to only 2024-2026 movies
        #expect(viewModel.results.count == 3)
        #expect(viewModel.results.allSatisfy { $0.year ?? 0 >= 2024 })
    }

    @Test
    @MainActor
    func searchWithTwentiesPresetFilter() async throws {
        let stub = ClientFilterTestMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "m-2020", title: "2020", year: 2020),
                    Fixtures.mediaPreview(id: "m-2025", title: "2025", year: 2025),
                    Fixtures.mediaPreview(id: "m-2010", title: "2010", year: 2010),
                    Fixtures.mediaPreview(id: "m-1999", title: "1999", year: 1999),
                ],
                page: 1, totalPages: 1, totalResults: 4
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.applyYearRangePreset(.twenties)  // 2020-2029
        viewModel.search()

        try await Self.waitUntil { !viewModel.isSearching && !viewModel.results.isEmpty }

        // Should filter to only 2020s movies
        #expect(viewModel.results.count == 2)
        #expect(viewModel.results.allSatisfy { ($0.year ?? 0) >= 2020 && ($0.year ?? 0) <= 2029 })
    }

    @Test
    @MainActor
    func searchWithClassicPresetFilter() async throws {
        let stub = ClientFilterTestMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "m-1990", title: "1990", year: 1990),
                    Fixtures.mediaPreview(id: "m-2010", title: "2010", year: 2010),
                    Fixtures.mediaPreview(id: "m-1985", title: "1985", year: 1985),
                    Fixtures.mediaPreview(id: "m-2005", title: "2005", year: 2005),
                ],
                page: 1, totalPages: 1, totalResults: 4
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.applyYearRangePreset(.classic)  // Pre-2000
        viewModel.search()

        try await Self.waitUntil { !viewModel.isSearching && !viewModel.results.isEmpty }

        // Should filter to only classic (pre-2000) movies
        #expect(viewModel.results.count == 2)
        #expect(viewModel.results.allSatisfy { ($0.year ?? 0) < 2000 })
    }

    // MARK: - Pagination with Filters Tests

    @Test
    @MainActor
    func loadMoreAppliesSortingToPaginatedResults() async throws {
        let stub = ClientFilterTestMetadataStub()
        // Page 1: mixed ratings
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "p1-low", title: "Page1 Low", imdbRating: 5.0),
                ],
                page: 1, totalPages: 2, totalResults: 2
            ),
            2: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "p2-high", title: "Page2 High", imdbRating: 9.0),
                ],
                page: 2, totalPages: 2, totalResults: 2
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.sortOption = .ratingDesc
        viewModel.search()

        try await Self.waitUntil { !viewModel.isSearching && viewModel.results.count == 1 }

        // Load more
        viewModel.loadMore()
        try await Self.waitUntil { viewModel.results.count == 2 }

        // Both results should be sorted by rating descending
        #expect(viewModel.results.count == 2)
        #expect(viewModel.results[0].imdbRating ?? 0 >= viewModel.results[1].imdbRating ?? 0)
    }

    @Test
    @MainActor
    func loadMoreAppliesYearPresetFilterToPaginatedResults() async throws {
        let stub = ClientFilterTestMetadataStub()
        await stub.setSearchResults([
            1: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "p1-2024", title: "2024", year: 2024),
                ],
                page: 1, totalPages: 2, totalResults: 4
            ),
            2: MetadataSearchResult(
                items: [
                    Fixtures.mediaPreview(id: "p2-2015", title: "2015", year: 2015),
                ],
                page: 2, totalPages: 2, totalResults: 4
            )
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.query = "test"
        viewModel.applyYearRangePreset(.recent)  // 2024-2026
        viewModel.search()

        try await Self.waitUntil { !viewModel.isSearching && viewModel.results.count == 1 }

        // Load more - should NOT include 2015 (outside preset range)
        viewModel.loadMore()
        try await Self.waitUntil { viewModel.results.count == 2 }

        // All results should be within 2024-2026
        #expect(viewModel.results.count == 2)
        #expect(viewModel.results.allSatisfy { ($0.year ?? 0) >= 2024 })
    }

    // MARK: - hasActiveFilters Tests

    @Test
    @MainActor
    func hasActiveFiltersTrueWhenSortNotDefault() {
        let viewModel = SearchViewModel(metadataService: ClientFilterTestMetadataStub())
        #expect(viewModel.hasActiveFilters == false)

        viewModel.sortOption = .ratingDesc
        #expect(viewModel.hasActiveFilters == true)
    }

    @Test
    @MainActor
    func hasActiveFiltersTrueWhenYearFilterSet() {
        let viewModel = SearchViewModel(metadataService: ClientFilterTestMetadataStub())
        #expect(viewModel.hasActiveFilters == false)

        viewModel.yearFilter = 2024
        #expect(viewModel.hasActiveFilters == true)
    }

    @Test
    @MainActor
    func hasActiveFiltersTrueWhenYearRangePresetSet() {
        let viewModel = SearchViewModel(metadataService: ClientFilterTestMetadataStub())
        #expect(viewModel.hasActiveFilters == false)

        viewModel.yearRangePreset = .recent
        #expect(viewModel.hasActiveFilters == true)
    }

    @Test
    @MainActor
    func hasActiveFiltersTrueWhenLanguageFilterNotDefault() {
        let viewModel = SearchViewModel(metadataService: ClientFilterTestMetadataStub())
        #expect(viewModel.hasActiveFilters == false)

        viewModel.languageFilters = ["ja-JP"]
        #expect(viewModel.hasActiveFilters == true)
    }

    @Test
    @MainActor
    func hasActiveFiltersTrueWhenGenreSelected() {
        let viewModel = SearchViewModel(metadataService: ClientFilterTestMetadataStub())
        #expect(viewModel.hasActiveFilters == false)

        viewModel.selectedGenre = Genre(id: 28, name: "Action")
        #expect(viewModel.hasActiveFilters == true)
    }

    @Test
    @MainActor
    func activeFilterCountReturnsCorrectCount() {
        let viewModel = SearchViewModel(metadataService: ClientFilterTestMetadataStub())
        #expect(viewModel.activeFilterCount == 0)

        viewModel.sortOption = .ratingDesc
        #expect(viewModel.activeFilterCount == 1)

        viewModel.yearFilter = 2024
        #expect(viewModel.activeFilterCount == 2)

        viewModel.languageFilters = ["ja-JP"]
        #expect(viewModel.activeFilterCount == 3)

        viewModel.selectedGenre = Genre(id: 28, name: "Action")
        #expect(viewModel.activeFilterCount == 4)
    }
}
