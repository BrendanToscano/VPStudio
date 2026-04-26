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
    func detailPresentationPolicyFormatsMetadataAndFeedbackDefaults() {
        #expect(DetailPresentationPolicy.activeSessionToastText == "A video is already playing")
        #expect(DetailPresentationPolicy.yearText(nil) == nil)
        #expect(DetailPresentationPolicy.yearText(1999) == "1999")
        #expect(DetailPresentationPolicy.imdbRatingText(nil) == nil)
        #expect(DetailPresentationPolicy.imdbRatingText(0) == nil)
        #expect(DetailPresentationPolicy.imdbRatingText(7.94) == "7.9")
        #expect(DetailPresentationPolicy.runtimeText(nil) == nil)
        #expect(DetailPresentationPolicy.runtimeText("") == nil)
        #expect(DetailPresentationPolicy.runtimeText("2h 12m") == "2h 12m")

        #expect(DetailPresentationPolicy.feedbackDraftValue(
            currentValue: nil,
            scaleMode: .likeDislike
        ) == 1)
        #expect(DetailPresentationPolicy.feedbackDraftValue(
            currentValue: 14,
            scaleMode: .oneToTen
        ) == 10)
        #expect(DetailPresentationPolicy.feedbackDraftValue(
            currentValue: -4,
            scaleMode: .oneToHundred
        ) == 1)
    }

    @Test
    func detailPresentationPolicyBuildsStableShareItems() {
        #expect(DetailPresentationPolicy.shareItem(
            previewID: "tt0111161",
            previewTitle: "Fallback Title",
            previewType: .movie,
            previewTMDBID: 278,
            mediaTitle: "The Shawshank Redemption",
            mediaTMDBID: nil
        ) == "The Shawshank Redemption\nhttps://www.imdb.com/title/tt0111161/")

        #expect(DetailPresentationPolicy.shareItem(
            previewID: "movie-278",
            previewTitle: "Fallback Title",
            previewType: .movie,
            previewTMDBID: 278,
            mediaTitle: nil,
            mediaTMDBID: nil
        ) == "Fallback Title\nhttps://www.themoviedb.org/movie/278")

        #expect(DetailPresentationPolicy.shareItem(
            previewID: "tv-1396",
            previewTitle: "Breaking Bad",
            previewType: .series,
            previewTMDBID: nil,
            mediaTitle: "Better Title",
            mediaTMDBID: 1396
        ) == "Better Title\nhttps://www.themoviedb.org/tv/1396")

        #expect(DetailPresentationPolicy.shareItem(
            previewID: "local",
            previewTitle: "Local Only",
            previewType: .movie,
            previewTMDBID: nil,
            mediaTitle: nil,
            mediaTMDBID: nil
        ) == "Local Only")
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
