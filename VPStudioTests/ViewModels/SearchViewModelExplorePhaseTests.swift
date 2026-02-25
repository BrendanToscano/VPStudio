import Foundation
import Testing
@testable import VPStudio

@Suite("SearchViewModel - ExplorePhase & Recent Searches")
@MainActor
struct SearchViewModelExplorePhaseTests {

    // MARK: - Test Stubs

    private actor PhaseTestMetadataStub: MetadataProvider {
        var searchResultByPage: [Int: MetadataSearchResult] = [:]
        var discoverResultByPage: [Int: MetadataSearchResult] = [:]

        func setSearchResults(_ results: [Int: MetadataSearchResult]) {
            searchResultByPage = results
        }

        func setDiscoverResults(_ results: [Int: MetadataSearchResult]) {
            discoverResultByPage = results
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            searchResultByPage[page] ?? MetadataSearchResult(items: [], page: page, totalPages: page, totalResults: 0)
        }

        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult {
            discoverResultByPage[filters.page] ?? MetadataSearchResult(items: [], page: filters.page, totalPages: filters.page, totalResults: 0)
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }
        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] { [] }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    /// Polls until `condition` returns true, yielding between checks. Fails after `timeout`.
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

    // MARK: - ExplorePhase Enum Cases

    @Test func explorePhaseHasFiveCases() {
        let cases: [ExplorePhase] = [.idle, .searching, .results, .empty, .error]
        #expect(cases.count == 5)
    }

    @Test func explorePhaseIdleCaseExists() {
        let phase = ExplorePhase.idle
        if case .idle = phase {
            // success
        } else {
            Issue.record("Expected .idle")
        }
    }

    @Test func explorePhaseSearchingCaseExists() {
        let phase = ExplorePhase.searching
        if case .searching = phase {
            // success
        } else {
            Issue.record("Expected .searching")
        }
    }

    @Test func explorePhaseResultsCaseExists() {
        let phase = ExplorePhase.results
        if case .results = phase {
            // success
        } else {
            Issue.record("Expected .results")
        }
    }

    @Test func explorePhaseEmptyCaseExists() {
        let phase = ExplorePhase.empty
        if case .empty = phase {
            // success
        } else {
            Issue.record("Expected .empty")
        }
    }

    @Test func explorePhaseErrorCaseExists() {
        let phase = ExplorePhase.error
        if case .error = phase {
            // success
        } else {
            Issue.record("Expected .error")
        }
    }

    // MARK: - Initial State

    @Test func initialPhaseIsIdle() {
        let viewModel = SearchViewModel()
        #expect(viewModel.explorePhase == .idle)
    }

    @Test func initialQueryIsEmpty() {
        let viewModel = SearchViewModel()
        #expect(viewModel.query.isEmpty)
    }

    @Test func initialResultsAreEmpty() {
        let viewModel = SearchViewModel()
        #expect(viewModel.results.isEmpty)
    }

    @Test func initialIsSearchingIsFalse() {
        let viewModel = SearchViewModel()
        #expect(viewModel.isSearching == false)
    }

    @Test func initialErrorIsNil() {
        let viewModel = SearchViewModel()
        #expect(viewModel.error == nil)
    }

    @Test func initialSelectedTypeIsNil() {
        let viewModel = SearchViewModel()
        #expect(viewModel.selectedType == nil)
    }

    @Test func initialCurrentPageIsOne() {
        let viewModel = SearchViewModel()
        #expect(viewModel.currentPage == 1)
    }

    @Test func initialTotalPagesIsOne() {
        let viewModel = SearchViewModel()
        #expect(viewModel.totalPages == 1)
    }

    @Test func initialHasMoreIsFalse() {
        let viewModel = SearchViewModel()
        #expect(viewModel.hasMore == false)
    }

    @Test func initialSearchGenerationIsZero() {
        let viewModel = SearchViewModel()
        #expect(viewModel.searchGeneration == 0)
    }

    @Test func initialIsLoadingMoreIsFalse() {
        let viewModel = SearchViewModel()
        #expect(viewModel.isLoadingMore == false)
    }

    @Test func initialScrollToTopTriggerIsZero() {
        let viewModel = SearchViewModel()
        #expect(viewModel.scrollToTopTrigger == 0)
    }

    @Test func initialRecentSearchesIsEmpty() {
        let viewModel = SearchViewModel()
        #expect(viewModel.recentSearches.isEmpty)
    }

    @Test func initialSelectedGenreIsNil() {
        let viewModel = SearchViewModel()
        #expect(viewModel.selectedGenre == nil)
    }

    @Test func initialSortOptionIsPopularityDesc() {
        let viewModel = SearchViewModel()
        #expect(viewModel.sortOption == .popularityDesc)
    }

    @Test func initialYearFilterIsNil() {
        let viewModel = SearchViewModel()
        #expect(viewModel.yearFilter == nil)
    }

    @Test func initialLanguageFiltersContainsEnUS() {
        let viewModel = SearchViewModel()
        #expect(viewModel.languageFilters == ["en-US"])
    }

    @Test func initialAiRecommendationsIsEmpty() {
        let viewModel = SearchViewModel()
        #expect(viewModel.aiRecommendations.isEmpty)
    }

    @Test func initialIsLoadingAIIsFalse() {
        let viewModel = SearchViewModel()
        #expect(viewModel.isLoadingAI == false)
    }

    @Test func initialAiErrorIsNil() {
        let viewModel = SearchViewModel()
        #expect(viewModel.aiError == nil)
    }

    @Test func initialIsGenreBrowsingIsFalse() {
        let viewModel = SearchViewModel()
        #expect(viewModel.isGenreBrowsing == false)
    }

    @Test func initialGenresIsEmpty() {
        let viewModel = SearchViewModel()
        #expect(viewModel.genres.isEmpty)
    }

    // MARK: - ExplorePhase Computed Property Transitions

    @Test func phaseIsSearchingWhenIsSearchingIsTrue() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.isSearching = true
        #expect(viewModel.explorePhase == .searching)
    }

    @Test func phaseIsResultsWhenResultsExist() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.results = [Fixtures.mediaPreview(id: "test-1")]
        #expect(viewModel.explorePhase == .results)
    }

    @Test func phaseIsResultsWhenAiRecommendationsExist() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.aiRecommendations = [
            AIMovieRecommendation(title: "Test", year: 2024, type: .movie, reason: "Good", tmdbId: 1)
        ]
        #expect(viewModel.explorePhase == .results)
    }

    @Test func phaseIsResultsWhenGenreIsSelected() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.selectedGenre = Genre(id: 28, name: "Action")
        #expect(viewModel.explorePhase == .results)
    }

    @Test func phaseIsEmptyWhenQueryExistsButNoResults() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.query = "no match query"
        #expect(viewModel.explorePhase == .empty)
    }

    @Test func phaseIsIdleWhenQueryIsEmptyAndNoResults() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.query = ""
        viewModel.results = []
        #expect(viewModel.explorePhase == .idle)
    }

    @Test func phaseIsIdleWhenQueryIsWhitespaceOnly() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.query = "   "
        #expect(viewModel.explorePhase == .idle)
    }

    @Test func searchingTakesPriorityOverResults() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.isSearching = true
        viewModel.results = [Fixtures.mediaPreview(id: "test-1")]
        #expect(viewModel.explorePhase == .searching)
    }

    @Test func searchingTakesPriorityOverEmpty() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.isSearching = true
        viewModel.query = "something"
        #expect(viewModel.explorePhase == .searching)
    }

    @Test func resultsTakesPriorityOverEmpty() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.query = "something"
        viewModel.results = [Fixtures.mediaPreview(id: "test-1")]
        #expect(viewModel.explorePhase == .results)
    }

    @Test func phaseIsErrorWhenErrorExistsAndNoResults() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.error = .network(.transport("Search failed."))
        viewModel.results = []
        #expect(viewModel.explorePhase == .error)
    }

    @Test func phaseIsResultsWhenErrorExistsButResultsAlsoExist() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.error = .network(.transport("Partial failure"))
        viewModel.results = [Fixtures.mediaPreview(id: "test-1")]
        #expect(viewModel.explorePhase == .results)
    }

    @Test func searchingTakesPriorityOverError() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.isSearching = true
        viewModel.error = .network(.transport("Error"))
        #expect(viewModel.explorePhase == .searching)
    }

    @Test func errorTakesPriorityOverEmptyAndIdle() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.error = .network(.transport("Error"))
        viewModel.query = ""
        viewModel.results = []
        // error != nil && results.isEmpty => .error (checked before hasQuery)
        #expect(viewModel.explorePhase == .error)
    }

    // MARK: - primaryLanguage Computed Property

    @Test func primaryLanguageReturnsFirstSortedLanguage() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["fr-FR", "en-US"]
        // Sorted: ["en-US", "fr-FR"], first = "en-US"
        #expect(viewModel.primaryLanguage == "en-US")
    }

    @Test func primaryLanguageReturnsSingleLanguage() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["ja-JP"]
        #expect(viewModel.primaryLanguage == "ja-JP")
    }

    @Test func primaryLanguageReturnsNilWhenEmpty() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = []
        #expect(viewModel.primaryLanguage == nil)
    }

    // MARK: - Recent Searches: Add

    @Test func addRecentSearchInsertsAtFront() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("Interstellar")
        viewModel.addRecentSearch("Dune")
        #expect(viewModel.recentSearches == ["Dune", "Interstellar"])
    }

    @Test func addRecentSearchTrimsWhitespace() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("  Inception  ")
        #expect(viewModel.recentSearches == ["Inception"])
    }

    @Test func addRecentSearchIgnoresEmptyString() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("")
        #expect(viewModel.recentSearches.isEmpty)
    }

    @Test func addRecentSearchIgnoresWhitespaceOnly() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("   ")
        #expect(viewModel.recentSearches.isEmpty)
    }

    @Test func addRecentSearchDeduplicatesCaseInsensitive() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("inception")
        viewModel.addRecentSearch("INCEPTION")
        #expect(viewModel.recentSearches.count == 1)
        #expect(viewModel.recentSearches.first == "INCEPTION")
    }

    @Test func addRecentSearchMovesDuplicateToFront() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("Dune")
        viewModel.addRecentSearch("Interstellar")
        viewModel.addRecentSearch("Dune")
        #expect(viewModel.recentSearches == ["Dune", "Interstellar"])
    }

    @Test func addRecentSearchCapsAtTwenty() {
        let viewModel = SearchViewModel()
        for i in 1...25 {
            viewModel.addRecentSearch("Search \(i)")
        }
        #expect(viewModel.recentSearches.count == 20)
        #expect(viewModel.recentSearches.first == "Search 25")
        #expect(viewModel.recentSearches.last == "Search 6")
    }

    @Test func addRecentSearchPreservesExistingOrder() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("Alpha")
        viewModel.addRecentSearch("Beta")
        viewModel.addRecentSearch("Gamma")
        #expect(viewModel.recentSearches == ["Gamma", "Beta", "Alpha"])
    }

    // MARK: - Recent Searches: Remove

    @Test func removeRecentSearchRemovesExactMatch() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("Alpha")
        viewModel.addRecentSearch("Beta")
        viewModel.removeRecentSearch("Alpha")
        #expect(viewModel.recentSearches == ["Beta"])
    }

    @Test func removeRecentSearchDoesNothingForNonexistent() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("Alpha")
        viewModel.removeRecentSearch("Beta")
        #expect(viewModel.recentSearches == ["Alpha"])
    }

    @Test func removeRecentSearchIsCaseSensitive() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("Alpha")
        viewModel.removeRecentSearch("alpha")
        // removeAll uses exact match ($0 == term), not lowercased
        #expect(viewModel.recentSearches == ["Alpha"])
    }

    // MARK: - Recent Searches: Clear

    @Test func clearRecentSearchesRemovesAll() {
        let viewModel = SearchViewModel()
        viewModel.addRecentSearch("Alpha")
        viewModel.addRecentSearch("Beta")
        viewModel.addRecentSearch("Gamma")
        viewModel.clearRecentSearches()
        #expect(viewModel.recentSearches.isEmpty)
    }

    @Test func clearRecentSearchesOnEmptyListIsNoop() {
        let viewModel = SearchViewModel()
        viewModel.clearRecentSearches()
        #expect(viewModel.recentSearches.isEmpty)
    }

    // MARK: - hasMore Computed Property

    @Test func hasMoreTrueWhenMorePagesExist() {
        let viewModel = SearchViewModel()
        viewModel.currentPage = 1
        viewModel.totalPages = 3
        #expect(viewModel.hasMore == true)
    }

    @Test func hasMoreFalseWhenOnLastPage() {
        let viewModel = SearchViewModel()
        viewModel.currentPage = 3
        viewModel.totalPages = 3
        #expect(viewModel.hasMore == false)
    }

    @Test func hasMoreFalseWhenSinglePage() {
        let viewModel = SearchViewModel()
        viewModel.currentPage = 1
        viewModel.totalPages = 1
        #expect(viewModel.hasMore == false)
    }

    // MARK: - Mood Card Selection

    @Test func selectNewReleasesMoodCardSetsSortToReleaseDateDesc() async throws {
        let stub = PhaseTestMetadataStub()
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "new-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        let newReleasesCard = ExploreGenreCatalog.cards.first(where: { $0.id == "new" })!
        viewModel.selectMoodCard(newReleasesCard)

        #expect(viewModel.sortOption == .releaseDateDesc)
        #expect(viewModel.selectedGenre == nil)
    }

    @Test func selectGenreMoodCardSetsSelectedGenre() async throws {
        let stub = PhaseTestMetadataStub()
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "action-1")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        let actionCard = ExploreGenreCatalog.cards.first(where: { $0.id == "action" })!
        viewModel.selectMoodCard(actionCard)

        try await Self.waitUntil { !viewModel.results.isEmpty }
        #expect(viewModel.selectedGenre != nil)
        // For movies (default), uses movieGenreId
        #expect(viewModel.selectedGenre?.id == 28)
        #expect(viewModel.selectedGenre?.name == "Action")
    }

    @Test func selectMoodCardUsesTvGenreIdForSeries() async throws {
        let stub = PhaseTestMetadataStub()
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "action-tv")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectedType = .series
        let actionCard = ExploreGenreCatalog.cards.first(where: { $0.id == "action" })!
        viewModel.selectMoodCard(actionCard)

        try await Self.waitUntil { !viewModel.results.isEmpty }
        #expect(viewModel.selectedGenre?.id == 10759)
    }

    @Test func selectMoodCardUsesMovieGenreIdForMovies() async throws {
        let stub = PhaseTestMetadataStub()
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "action-movie")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectedType = .movie
        let actionCard = ExploreGenreCatalog.cards.first(where: { $0.id == "action" })!
        viewModel.selectMoodCard(actionCard)

        try await Self.waitUntil { !viewModel.results.isEmpty }
        #expect(viewModel.selectedGenre?.id == 28)
    }

    @Test func selectMoodCardUsesMovieGenreIdWhenSelectedTypeIsNil() async throws {
        let stub = PhaseTestMetadataStub()
        await stub.setDiscoverResults([
            1: MetadataSearchResult(items: [Fixtures.mediaPreview(id: "scifi-default")], page: 1, totalPages: 1, totalResults: 1)
        ])

        let viewModel = SearchViewModel(metadataService: stub)
        viewModel.selectedType = nil
        let scifiCard = ExploreGenreCatalog.cards.first(where: { $0.id == "scifi" })!
        viewModel.selectMoodCard(scifiCard)

        try await Self.waitUntil { !viewModel.results.isEmpty }
        // selectedType nil defaults to .movie in selectMoodCard
        #expect(viewModel.selectedGenre?.id == 878)
    }

    // MARK: - Clear Resets Language Filters

    @Test func clearResetsLanguageFiltersToDefault() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["ja-JP", "ko-KR"]
        viewModel.clear()
        #expect(viewModel.languageFilters == ["en-US"])
    }

    // MARK: - Configure

    @Test func configureWithSameKeyDoesNotRecreateService() async throws {
        var factoryCallCount = 0
        let viewModel = SearchViewModel(metadataServiceFactory: { key in
            factoryCallCount += 1
            return PhaseTestMetadataStub()
        })
        viewModel.configure(apiKey: "my-key")
        let firstCount = factoryCallCount
        viewModel.configure(apiKey: "my-key")
        #expect(factoryCallCount == firstCount, "Factory should not be called again for same key")
    }

    @Test func configureTrimsApiKey() async throws {
        var receivedKey: String?
        let viewModel = SearchViewModel(metadataServiceFactory: { key in
            receivedKey = key
            return PhaseTestMetadataStub()
        })
        viewModel.configure(apiKey: "  my-key  ")
        #expect(receivedKey == "my-key")
    }

    // MARK: - Apply Language Filters

    @Test func applyLanguageFiltersUpdatesFilters() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.applyLanguageFilters(["ja-JP", "ko-KR"])
        #expect(viewModel.languageFilters == ["ja-JP", "ko-KR"])
    }

    @Test func applyLanguageFiltersToEmptySet() {
        let viewModel = SearchViewModel(metadataService: PhaseTestMetadataStub())
        viewModel.applyLanguageFilters([])
        #expect(viewModel.languageFilters.isEmpty)
        #expect(viewModel.primaryLanguage == nil)
    }
}
