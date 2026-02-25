import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct DiscoverViewModelTests {
    private actor DiscoverMetadataStub: MetadataProvider {
        var trendingMovieItems: [MediaPreview] = []
        var trendingShowItems: [MediaPreview] = []
        var popularItems: [MediaPreview] = []
        var topRatedItems: [MediaPreview] = []
        var nowPlayingItems: [MediaPreview] = []

        func setTrendingMovieItems(_ items: [MediaPreview]) { trendingMovieItems = items }
        func setTrendingShowItems(_ items: [MediaPreview]) { trendingShowItems = items }
        func setPopularItems(_ items: [MediaPreview]) { popularItems = items }
        func setTopRatedItems(_ items: [MediaPreview]) { topRatedItems = items }
        func setNowPlayingItems(_ items: [MediaPreview]) { nowPlayingItems = items }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }

        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult {
            let items = type == .movie ? trendingMovieItems : trendingShowItems
            return MetadataSearchResult(items: items, page: page, totalPages: 1, totalResults: items.count)
        }

        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult {
            let items: [MediaPreview]
            switch category {
            case .popular: items = popularItems
            case .topRated: items = topRatedItems
            case .nowPlaying: items = nowPlayingItems
            default: items = []
            }
            return MetadataSearchResult(items: items, page: page, totalPages: 1, totalResults: items.count)
        }

        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] { [] }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    private actor KeyedDiscoverMetadataStub: MetadataProvider {
        let marker: String

        init(marker: String) {
            self.marker = marker
        }

        func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult { fatalError("unused") }
        func getDetail(id: String, type: MediaType) async throws -> MediaItem { fatalError("unused") }

        func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult {
            let id = type == .movie ? "tm-\(marker)" : "ts-\(marker)"
            return MetadataSearchResult(items: [Fixtures.mediaPreview(id: id, type: type)], page: page, totalPages: 1, totalResults: 1)
        }

        func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult {
            let id: String
            switch category {
            case .popular: id = "popular-\(marker)"
            case .topRated: id = "top-\(marker)"
            case .nowPlaying: id = "now-\(marker)"
            default: id = "other-\(marker)"
            }
            return MetadataSearchResult(items: [Fixtures.mediaPreview(id: id, type: type)], page: page, totalPages: 1, totalResults: 1)
        }

        func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { fatalError("unused") }
        func getGenres(type: MediaType) async throws -> [Genre] { [] }
        func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
        func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
        func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds(imdbId: nil, tvdbId: nil) }
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<10), full: Array(0..<20)))
    @MainActor
    func loadPopulatesAllBuckets(index: Int) async {
        let stub = DiscoverMetadataStub()
        await stub.setTrendingMovieItems([Fixtures.mediaPreview(id: "tm-\(index)", type: .movie)])
        await stub.setTrendingShowItems([Fixtures.mediaPreview(id: "ts-\(index)", type: .series)])
        await stub.setPopularItems([Fixtures.mediaPreview(id: "popular-\(index)", type: .movie)])
        await stub.setTopRatedItems([Fixtures.mediaPreview(id: "top-\(index)", type: .movie)])
        await stub.setNowPlayingItems([Fixtures.mediaPreview(id: "now-\(index)", type: .movie)])

        let viewModel = DiscoverViewModel(metadataService: stub)
        await viewModel.load(apiKey: "unused")

        #expect(viewModel.trendingMovies.count == 1)
        #expect(viewModel.trendingShows.count == 1)
        #expect(viewModel.popularMovies.count == 1)
        #expect(viewModel.topRatedMovies.count == 1)
        #expect(viewModel.nowPlayingMovies.count == 1)
        #expect(viewModel.featuredBackdrops.first?.id == "tm-\(index)")
        #expect(viewModel.isLoading == false)
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<10), full: Array(0..<20)))
    @MainActor
    func refreshOnlyReplacesTrendingMovies(index: Int) async {
        let stub = DiscoverMetadataStub()
        await stub.setTrendingMovieItems([Fixtures.mediaPreview(id: "first-\(index)", type: .movie)])
        await stub.setTrendingShowItems([Fixtures.mediaPreview(id: "show-\(index)", type: .series)])

        let viewModel = DiscoverViewModel(metadataService: stub)
        await viewModel.load(apiKey: "unused")

        await stub.setTrendingMovieItems([Fixtures.mediaPreview(id: "second-\(index)", type: .movie)])
        await viewModel.refresh()

        #expect(viewModel.trendingMovies.first?.id == "second-\(index)")
        #expect(viewModel.featuredBackdrops.first?.id == "second-\(index)")
        #expect(viewModel.trendingShows.first?.id == "show-\(index)")
    }

    @Test
    @MainActor
    func loadReplacesMetadataServiceWhenApiKeyChanges() async {
        let viewModel = DiscoverViewModel(metadataServiceFactory: { key in
            KeyedDiscoverMetadataStub(marker: key)
        })

        await viewModel.load(apiKey: "key-a")
        #expect(viewModel.trendingMovies.first?.id == "tm-key-a")
        #expect(viewModel.featuredBackdrops.first?.id == "tm-key-a")
        #expect(viewModel.error == nil)

        await viewModel.load(apiKey: "key-b")
        #expect(viewModel.trendingMovies.first?.id == "tm-key-b")
        #expect(viewModel.featuredBackdrops.first?.id == "tm-key-b")
        #expect(viewModel.trendingShows.first?.id == "ts-key-b")
        #expect(viewModel.error == nil)
    }

    @Test
    @MainActor
    func loadWithEmptyApiKeyRequiresOrReusesConfiguredService() async {
        let viewModel = DiscoverViewModel(metadataServiceFactory: { key in
            KeyedDiscoverMetadataStub(marker: key.isEmpty ? "empty" : key)
        })

        await viewModel.load(apiKey: "   ")
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == .unknown("API key required to load discover content."))
        #expect(viewModel.trendingMovies.isEmpty)

        await viewModel.load(apiKey: "valid-key")
        #expect(viewModel.trendingMovies.first?.id == "tm-valid-key")
        #expect(viewModel.error == nil)

        await viewModel.refresh()
        #expect(viewModel.trendingMovies.first?.id == "tm-valid-key")
        #expect(viewModel.error == nil)
    }
}
