import Foundation
import Testing
@testable import VPStudio

@Suite("Refresh Loading Presentation Policies")
struct RefreshLoadingPolicyTests {
    @Test
    func discoverUsesBlockingSkeletonForInitialLoad() {
        #expect(
            DiscoverLoadingPresentationPolicy.presentationMode(
                isLoading: true,
                featuredBackdropCount: 0,
                continueWatchingCount: 0,
                catalogRowCount: 0,
                aiRecommendationCount: 0
            ) == .blockingSkeleton
        )
    }

    @Test
    func discoverUsesRefreshingModeWhenContentExists() {
        #expect(
            DiscoverLoadingPresentationPolicy.presentationMode(
                isLoading: true,
                featuredBackdropCount: 1,
                continueWatchingCount: 0,
                catalogRowCount: 0,
                aiRecommendationCount: 0
            ) == .refreshingRetainedContent
        )

        #expect(
            DiscoverLoadingPresentationPolicy.presentationMode(
                isLoading: true,
                featuredBackdropCount: 0,
                continueWatchingCount: 0,
                catalogRowCount: 2,
                aiRecommendationCount: 0
            ) == .refreshingRetainedContent
        )
    }

    @Test
    func discoverUsesContentModeWhenNotLoading() {
        #expect(
            DiscoverLoadingPresentationPolicy.presentationMode(
                isLoading: false,
                featuredBackdropCount: 0,
                continueWatchingCount: 0,
                catalogRowCount: 0,
                aiRecommendationCount: 0
            ) == .content
        )
    }

    @Test
    func searchUsesBlockingSkeletonForInitialSearchingState() {
        #expect(
            SearchLoadingPresentationPolicy.presentationMode(
                explorePhase: .searching,
                resultCount: 0,
                aiRecommendationCount: 0
            ) == .blockingSkeleton
        )
    }

    @Test
    func searchUsesRefreshingModeWhenRetainingResults() {
        #expect(
            SearchLoadingPresentationPolicy.presentationMode(
                explorePhase: .searching,
                resultCount: 4,
                aiRecommendationCount: 0
            ) == .refreshingRetainedResults
        )

        #expect(
            SearchLoadingPresentationPolicy.presentationMode(
                explorePhase: .searching,
                resultCount: 0,
                aiRecommendationCount: 2
            ) == .refreshingRetainedResults
        )
    }

    @Test
    func searchPassesThroughNonSearchingPhases() {
        #expect(
            SearchLoadingPresentationPolicy.presentationMode(
                explorePhase: .idle,
                resultCount: 0,
                aiRecommendationCount: 0
            ) == .idle
        )

        #expect(
            SearchLoadingPresentationPolicy.presentationMode(
                explorePhase: .results,
                resultCount: 3,
                aiRecommendationCount: 0
            ) == .results
        )

        #expect(
            SearchLoadingPresentationPolicy.presentationMode(
                explorePhase: .empty,
                resultCount: 0,
                aiRecommendationCount: 0
            ) == .empty
        )

        #expect(
            SearchLoadingPresentationPolicy.presentationMode(
                explorePhase: .error,
                resultCount: 0,
                aiRecommendationCount: 0
            ) == .error
        )
    }

    @Test
    func detailOverlayPolicyBlocksOnlyForInitialDetailLoad() {
        #expect(
            DetailRefreshLoadingPresentationPolicy.shouldShowBlockingOverlay(
                isLoadingDetail: true,
                isLoadingSeasonEpisodes: false,
                hasMediaItem: false
            )
        )

        #expect(
            DetailRefreshLoadingPresentationPolicy.shouldShowBlockingOverlay(
                isLoadingDetail: false,
                isLoadingSeasonEpisodes: true,
                hasMediaItem: true
            ) == false
        )
    }

    @Test
    func detailOverlayPolicyUsesInlineRefreshForSamePreviewReload() {
        #expect(
            DetailRefreshLoadingPresentationPolicy.shouldShowBlockingOverlay(
                isLoadingDetail: true,
                isLoadingSeasonEpisodes: false,
                hasMediaItem: true
            ) == false
        )

        #expect(
            DetailRefreshLoadingPresentationPolicy.shouldShowRefreshIndicator(
                isLoadingDetail: true,
                isLoadingSeasonEpisodes: false,
                hasMediaItem: true
            )
        )

        #expect(
            DetailRefreshLoadingPresentationPolicy.shouldShowRefreshIndicator(
                isLoadingDetail: false,
                isLoadingSeasonEpisodes: true,
                hasMediaItem: true
            ) == false
        )
    }

    @Test
    func seriesSeasonLoadingPresentationKeepsEpisodesShellVisible() {
        #expect(
            SeriesSeasonLoadingPresentationPolicy.shouldShowEpisodesSection(
                hasSeasons: true,
                episodeCount: 0,
                isLoadingSeasonEpisodes: true
            )
        )

        #expect(
            SeriesSeasonLoadingPresentationPolicy.shouldShowEpisodesSection(
                hasSeasons: true,
                episodeCount: 5,
                isLoadingSeasonEpisodes: false
            )
        )

        #expect(
            SeriesSeasonLoadingPresentationPolicy.shouldShowEpisodesSection(
                hasSeasons: false,
                episodeCount: 0,
                isLoadingSeasonEpisodes: true
            ) == false
        )
    }

    @Test
    func detailRetentionPolicyPreservesForSameMediaContext() {
        let current = MediaItem(
            id: "tt0111161",
            type: .movie,
            title: "The Shawshank Redemption",
            year: 1994,
            tmdbId: 278
        )

        let sameIDPreview = MediaPreview(
            id: "tt0111161",
            type: .movie,
            title: "The Shawshank Redemption",
            year: 1994,
            posterPath: nil,
            backdropPath: nil,
            imdbRating: nil,
            tmdbId: 278
        )
        #expect(
            DetailRefreshRetentionPolicy.shouldPreserveExistingContent(
                currentMediaItem: current,
                incomingPreview: sameIDPreview
            )
        )

        let sameTMDBDifferentIDPreview = MediaPreview(
            id: "movie-tmdb-278",
            type: .movie,
            title: "The Shawshank Redemption",
            year: 1994,
            posterPath: nil,
            backdropPath: nil,
            imdbRating: nil,
            tmdbId: 278
        )
        #expect(
            DetailRefreshRetentionPolicy.shouldPreserveExistingContent(
                currentMediaItem: current,
                incomingPreview: sameTMDBDifferentIDPreview
            )
        )
    }

    @Test
    func detailRetentionPolicyRejectsDifferentContentOrType() {
        let current = MediaItem(
            id: "tt0903747",
            type: .series,
            title: "Breaking Bad",
            year: 2008,
            tmdbId: 1396
        )

        let differentSeriesPreview = MediaPreview(
            id: "tt7366338",
            type: .series,
            title: "Chernobyl",
            year: 2019,
            posterPath: nil,
            backdropPath: nil,
            imdbRating: nil,
            tmdbId: 87108
        )
        #expect(
            DetailRefreshRetentionPolicy.shouldPreserveExistingContent(
                currentMediaItem: current,
                incomingPreview: differentSeriesPreview
            ) == false
        )

        let differentTypePreview = MediaPreview(
            id: "tt0109830",
            type: .movie,
            title: "Forrest Gump",
            year: 1994,
            posterPath: nil,
            backdropPath: nil,
            imdbRating: nil,
            tmdbId: 13
        )
        #expect(
            DetailRefreshRetentionPolicy.shouldPreserveExistingContent(
                currentMediaItem: current,
                incomingPreview: differentTypePreview
            ) == false
        )

        #expect(
            DetailRefreshRetentionPolicy.shouldPreserveExistingContent(
                currentMediaItem: nil,
                incomingPreview: differentSeriesPreview
            ) == false
        )
    }
}
