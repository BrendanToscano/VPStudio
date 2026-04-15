import Testing
@testable import VPStudio

@Suite("Discover Hierarchy Policy")
struct DiscoverHierarchyPolicyTests {
    @Test
    func heroItemsPreferFeaturedBackdropsWhenAvailable() {
        let featured = [
            Fixtures.mediaPreview(id: "featured-1", type: .movie),
            Fixtures.mediaPreview(id: "featured-2", type: .movie),
        ]
        let fallback = [Fixtures.mediaPreview(id: "fallback-1", type: .series)]

        let heroItems = DiscoverHeroPresentationPolicy.heroItems(
            featuredBackdrops: featured,
            trendingMovies: fallback,
            trendingShows: [],
            popularMovies: [],
            topRatedMovies: [],
            nowPlayingMovies: [],
            continueWatching: []
        )

        #expect(heroItems.map(\.id) == featured.map(\.id))
    }

    @Test
    func heroItemsFallBackToFirstPopulatedCatalogSource() {
        let trendingShows = [Fixtures.mediaPreview(id: "show-1", type: .series)]
        let popular = [Fixtures.mediaPreview(id: "popular-1", type: .movie)]

        let heroItems = DiscoverHeroPresentationPolicy.heroItems(
            featuredBackdrops: [],
            trendingMovies: [],
            trendingShows: trendingShows,
            popularMovies: popular,
            topRatedMovies: [],
            nowPlayingMovies: [],
            continueWatching: []
        )

        #expect(heroItems.map(\.id) == trendingShows.map(\.id))
    }

    @Test
    func heroItemsFallBackToContinueWatchingWhenCatalogIsEmpty() {
        let continueWatching = [Fixtures.mediaPreview(id: "cw-1", type: .movie)]

        let heroItems = DiscoverHeroPresentationPolicy.heroItems(
            featuredBackdrops: [],
            trendingMovies: [],
            trendingShows: [],
            popularMovies: [],
            topRatedMovies: [],
            nowPlayingMovies: [],
            continueWatching: continueWatching
        )

        #expect(heroItems.map(\.id) == continueWatching.map(\.id))
    }

    @Test
    func continueWatchingVisibilityDependsOnCount() {
        #expect(DiscoverHierarchyPolicy.shouldShowContinueWatching(count: 0) == false)
        #expect(DiscoverHierarchyPolicy.shouldShowContinueWatching(count: 1))
        #expect(DiscoverHierarchyPolicy.shouldShowContinueWatching(count: 8))
    }

    @Test
    func visibleCatalogRowsHideEmptySections() {
        let rows = DiscoverHierarchyPolicy.visibleCatalogRows(
            trendingMovies: [Fixtures.mediaPreview(id: "tm-1", type: .movie)],
            trendingShows: [],
            popularMovies: [],
            topRatedMovies: [Fixtures.mediaPreview(id: "top-1", type: .movie)],
            nowPlayingMovies: []
        )

        #expect(rows.map(\.id) == ["trending-movies", "top-rated-movies"])
    }

    @Test
    func visibleCatalogRowsPreserveCanonicalOrder() {
        let rows = DiscoverHierarchyPolicy.visibleCatalogRows(
            trendingMovies: [Fixtures.mediaPreview(id: "tm-1", type: .movie)],
            trendingShows: [Fixtures.mediaPreview(id: "ts-1", type: .series)],
            popularMovies: [Fixtures.mediaPreview(id: "popular-1", type: .movie)],
            topRatedMovies: [Fixtures.mediaPreview(id: "top-1", type: .movie)],
            nowPlayingMovies: [Fixtures.mediaPreview(id: "now-1", type: .movie)]
        )

        #expect(rows.map(\.id) == [
            "trending-movies",
            "trending-shows",
            "popular-movies",
            "top-rated-movies",
            "now-playing-movies",
        ])
    }

    @Test
    func visibleCatalogRowsAssignCompactAnimationDelaysForVisibleRows() {
        let rows = DiscoverHierarchyPolicy.visibleCatalogRows(
            trendingMovies: [],
            trendingShows: [Fixtures.mediaPreview(id: "ts-1", type: .series)],
            popularMovies: [],
            topRatedMovies: [Fixtures.mediaPreview(id: "top-1", type: .movie)],
            nowPlayingMovies: [Fixtures.mediaPreview(id: "now-1", type: .movie)]
        )

        #expect(rows.count == 3)
        expectApproxEqual(rows[0].animationDelay, 0.05)
        expectApproxEqual(rows[1].animationDelay, 0.12)
        expectApproxEqual(rows[2].animationDelay, 0.19)
    }

    @Test
    func visibleCatalogRowsKeepTitleAndSymbolMetadata() {
        let rows = DiscoverHierarchyPolicy.visibleCatalogRows(
            trendingMovies: [Fixtures.mediaPreview(id: "tm-1", type: .movie)],
            trendingShows: [Fixtures.mediaPreview(id: "ts-1", type: .series)],
            popularMovies: [],
            topRatedMovies: [],
            nowPlayingMovies: []
        )

        #expect(rows[0].title == "Trending Now")
        #expect(rows[0].symbol == "flame")
        #expect(rows[1].title == "Trending TV Shows")
        #expect(rows[1].symbol == "tv")
    }

    @Test
    func visibleCatalogRowsReturnEmptyWhenNoDataAvailable() {
        let rows = DiscoverHierarchyPolicy.visibleCatalogRows(
            trendingMovies: [],
            trendingShows: [],
            popularMovies: [],
            topRatedMovies: [],
            nowPlayingMovies: []
        )

        #expect(rows.isEmpty)
    }

    private func expectApproxEqual(_ value: Double, _ expected: Double, tolerance: Double = 0.0001) {
        #expect(abs(value - expected) < tolerance)
    }
}
