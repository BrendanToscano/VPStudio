import Foundation
import Testing
@testable import VPStudio

@Suite("Discover AI Curated Section Policy")
struct DiscoverAICuratedSectionPolicyTests {
    @Test
    func disabledSectionReturnsNil() {
        let state = DiscoverAICuratedSectionPolicy.makeState(
            enabled: false,
            isLoading: false,
            heroPreview: nil,
            recommendations: [makeRecommendation(title: "Arrival")]
        )

        #expect(state == nil)
    }

    @Test
    func loadingStateDisablesRegenerateAndSuppressesEmptyChrome() {
        let state = DiscoverAICuratedSectionPolicy.makeState(
            enabled: true,
            isLoading: true,
            heroPreview: nil,
            recommendations: []
        )

        #expect(state?.isLoading == true)
        #expect(state?.isRegenerateEnabled == false)
        #expect(state?.primaryRecommendation == nil)
        #expect(state?.supportingRecommendations.isEmpty == true)
        #expect(state?.showsEmptyState == false)
    }

    @Test
    func policyPromotesLeadRecommendationAndCapsSupportingRows() {
        let recommendations = [
            makeRecommendation(title: "Arrival"),
            makeRecommendation(title: "Dune"),
            makeRecommendation(title: "Annihilation"),
            makeRecommendation(title: "Blade Runner 2049"),
            makeRecommendation(title: "Ex Machina"),
        ]
        let heroPreview = Fixtures.mediaPreview(id: "movie-tmdb-11", title: "Arrival", tmdbId: 11)

        let state = DiscoverAICuratedSectionPolicy.makeState(
            enabled: true,
            isLoading: false,
            heroPreview: heroPreview,
            recommendations: recommendations
        )

        #expect(state?.primaryRecommendation?.title == "Arrival")
        #expect(state?.primaryPreview == heroPreview)
        #expect(state?.supportingRecommendations.map(\.title) == ["Dune", "Annihilation", "Blade Runner 2049"])
        #expect(state?.showsEmptyState == false)
    }

    @Test
    func emptyStateAppearsWhenEnabledButNoRecommendationsRemain() {
        let state = DiscoverAICuratedSectionPolicy.makeState(
            enabled: true,
            isLoading: false,
            heroPreview: nil,
            recommendations: []
        )

        #expect(state?.isLoading == false)
        #expect(state?.primaryRecommendation == nil)
        #expect(state?.showsEmptyState == true)
        #expect(state?.isRegenerateEnabled == true)
    }
}

@Suite("Discover View Model AI Hero Preview", .serialized)
struct DiscoverViewModelAIHeroPreviewTests {
    private actor DiscoverAIHeroMetadataStub: MetadataProvider {
        var detailByID: [String: MediaItem] = [:]
        var searchResultsByQuery: [String: [MediaPreview]] = [:]
        var marker: String?

        init(
            detailByID: [String: MediaItem] = [:],
            searchResultsByQuery: [String: [MediaPreview]] = [:],
            marker: String? = nil
        ) {
            self.detailByID = detailByID
            self.searchResultsByQuery = searchResultsByQuery
            self.marker = marker
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
            try await search(query: query, type: type, page: page, year: nil, language: nil)
        }

        func search(query: String, type: MediaType?, page: Int, year: Int?, language: String?) async throws -> MetadataSearchResult {
            if let results = searchResultsByQuery[query] {
                return MetadataSearchResult(items: results, page: page, totalPages: 1, totalResults: results.count)
            }

            if let marker, let type {
                return MetadataSearchResult(
                    items: [
                        MediaPreview(
                            id: "\(type.rawValue)-tmdb-11",
                            type: type,
                            title: query,
                            year: year,
                            posterPath: "/poster-\(marker).jpg",
                            backdropPath: "/backdrop-\(marker).jpg",
                            imdbRating: 8.4,
                            tmdbId: 11
                        )
                    ],
                    page: page,
                    totalPages: 1,
                    totalResults: 1
                )
            }

            return MetadataSearchResult(items: [], page: page, totalPages: 1, totalResults: 0)
        }

        func getDetail(id: String, type: MediaType) async throws -> MediaItem {
            if let item = detailByID[id] {
                return item
            }

            if let marker {
                return MediaItem(
                    id: id,
                    type: type,
                    title: "Hero \(marker)",
                    year: 2025,
                    posterPath: "/poster-\(marker).jpg",
                    backdropPath: "/backdrop-\(marker).jpg",
                    overview: nil,
                    genres: [],
                    imdbRating: 8.4,
                    runtime: nil,
                    status: nil,
                    tmdbId: Int(id)
                )
            }

            throw NSError(domain: "DiscoverAIHeroMetadataStub", code: 404)
        }

        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult {
            MetadataSearchResult(items: [], page: page, totalPages: 1, totalResults: 0)
        }

        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult {
            MetadataSearchResult(items: [], page: page, totalPages: 1, totalResults: 0)
        }

        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] { [] }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    @Test
    @MainActor
    func updateAIRecommendationsUsesMetadataArtworkForHeroPreview() async {
        let detail = MediaItem(
            id: "11",
            type: .movie,
            title: "Arrival",
            year: 2016,
            posterPath: "/arrival-poster.jpg",
            backdropPath: "/arrival-backdrop.jpg",
            overview: nil,
            genres: [],
            imdbRating: 8.0,
            runtime: nil,
            status: nil,
            tmdbId: 11
        )
        let metadata = DiscoverAIHeroMetadataStub(detailByID: ["11": detail])
        let viewModel = DiscoverViewModel(metadataService: metadata)

        await viewModel.updateAIRecommendations([
            makeRecommendation(title: "Arrival", year: 2016, tmdbId: 11, score: 0.95)
        ])

        #expect(viewModel.aiHeroPreview?.id == "movie-tmdb-11")
        #expect(viewModel.aiHeroPreview?.title == "Arrival")
        #expect(viewModel.aiHeroPreview?.posterPath == "/arrival-poster.jpg")
        #expect(viewModel.aiHeroPreview?.backdropPath == "/arrival-backdrop.jpg")
        #expect(viewModel.aiHeroPreview?.imdbRating == 8.0)
    }

    @Test
    @MainActor
    func updateAIRecommendationsIgnoresMismatchedTmdbHintAndUsesValidatedSearchMatch() async {
        let wrongDetail = MediaItem(
            id: "22",
            type: .movie,
            title: "Thor",
            year: 2011,
            posterPath: "/thor-poster.jpg",
            backdropPath: "/thor-backdrop.jpg",
            overview: nil,
            genres: [],
            imdbRating: 7.0,
            runtime: nil,
            status: nil,
            tmdbId: 22
        )
        let arrivalPreview = MediaPreview(
            id: "movie-tmdb-329865",
            type: .movie,
            title: "Arrival",
            year: 2016,
            posterPath: "/arrival-search-poster.jpg",
            backdropPath: "/arrival-search-backdrop.jpg",
            imdbRating: 8.1,
            tmdbId: 329865
        )
        let metadata = DiscoverAIHeroMetadataStub(
            detailByID: ["22": wrongDetail],
            searchResultsByQuery: ["Arrival": [arrivalPreview]]
        )
        let viewModel = DiscoverViewModel(metadataService: metadata)

        await viewModel.updateAIRecommendations([
            makeRecommendation(title: "Arrival", year: 2016, tmdbId: 22, score: 0.95)
        ])

        #expect(viewModel.aiRecommendations.first?.tmdbId == 329865)
        #expect(viewModel.aiHeroPreview?.title == "Arrival")
        #expect(viewModel.aiHeroPreview?.backdropPath == "/arrival-search-backdrop.jpg")
        #expect(viewModel.aiHeroPreview?.tmdbId == 329865)
    }

    @Test
    @MainActor
    func updateAIRecommendationsFallsBackWhenNoMetadataArtworkIsAvailable() async {
        let viewModel = DiscoverViewModel(metadataService: nil)

        await viewModel.updateAIRecommendations([
            makeRecommendation(title: "Primer", year: 2004, tmdbId: nil, score: 0.82)
        ])

        #expect(viewModel.aiHeroPreview == MediaPreview(
            id: "primer-2004-movie",
            type: .movie,
            title: "Primer",
            year: 2004,
            posterPath: nil,
            backdropPath: nil,
            imdbRating: nil,
            tmdbId: nil
        ))
    }

    @Test
    @MainActor
    func removingLeadRecommendationAdvancesHeroPreview() async {
        let metadata = DiscoverAIHeroMetadataStub(detailByID: [
            "11": MediaItem(id: "11", type: .movie, title: "Arrival", year: 2016, posterPath: "/arrival-poster.jpg", backdropPath: "/arrival-backdrop.jpg", overview: nil, genres: [], imdbRating: 8.0, runtime: nil, status: nil, tmdbId: 11),
            "12": MediaItem(id: "12", type: .movie, title: "Dune", year: 2021, posterPath: "/dune-poster.jpg", backdropPath: "/dune-backdrop.jpg", overview: nil, genres: [], imdbRating: 8.1, runtime: nil, status: nil, tmdbId: 12),
        ])
        let viewModel = DiscoverViewModel(metadataService: metadata)

        await viewModel.updateAIRecommendations([
            makeRecommendation(title: "Arrival", year: 2016, tmdbId: 11, score: 0.95),
            makeRecommendation(title: "Dune", year: 2021, tmdbId: 12, score: 0.91),
        ])

        viewModel.removeAIRecommendation(matchingMediaId: "movie-tmdb-11")
        await Task.yield()

        #expect(viewModel.aiRecommendations.map(\.title) == ["Dune"])
        #expect(viewModel.aiHeroPreview?.id == "movie-tmdb-12")
        #expect(viewModel.aiHeroPreview?.title == "Dune")
    }

    @Test
    @MainActor
    func loadWithNewTMDBKeyUpgradesExistingHeroPreview() async {
        let viewModel = DiscoverViewModel(metadataServiceFactory: { key in
            DiscoverAIHeroMetadataStub(marker: key)
        })

        await viewModel.updateAIRecommendations([
            makeRecommendation(title: "Arrival", year: 2016, tmdbId: 11, score: 0.95)
        ])
        #expect(viewModel.aiHeroPreview?.posterPath == nil)

        await viewModel.load(apiKey: "tmdb-key")

        #expect(viewModel.aiHeroPreview?.id == "movie-tmdb-11")
        #expect(viewModel.aiHeroPreview?.posterPath == "/poster-tmdb-key.jpg")
        #expect(viewModel.aiHeroPreview?.backdropPath == "/backdrop-tmdb-key.jpg")
    }

    @Test
    @MainActor
    func refreshLocalPersonalizationClearsHeroPreviewWhenRecommendationsAreGone() async {
        let metadata = DiscoverAIHeroMetadataStub(detailByID: [
            "11": MediaItem(id: "11", type: .movie, title: "Arrival", year: 2016, posterPath: "/arrival-poster.jpg", backdropPath: "/arrival-backdrop.jpg", overview: nil, genres: [], imdbRating: 8.0, runtime: nil, status: nil, tmdbId: 11),
        ])
        let viewModel = DiscoverViewModel(metadataService: metadata)

        await viewModel.updateAIRecommendations([
            makeRecommendation(title: "Arrival", year: 2016, tmdbId: 11, score: 0.95)
        ])
        #expect(viewModel.aiHeroPreview != nil)

        await viewModel.updateAIRecommendations([])
        await viewModel.refreshLocalPersonalizationState()

        #expect(viewModel.aiRecommendations.isEmpty)
        #expect(viewModel.aiHeroPreview == nil)
    }
}

private func makeRecommendation(
    title: String,
    year: Int? = 2024,
    type: MediaType = .movie,
    reason: String = "Matches your recent favorites.",
    tmdbId: Int? = 1,
    score: Double? = 0.9
) -> AIMovieRecommendation {
    AIMovieRecommendation(
        title: title,
        year: year,
        type: type,
        reason: reason,
        tmdbId: tmdbId,
        score: score
    )
}
