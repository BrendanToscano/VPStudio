import Foundation
import Testing
@testable import VPStudio

struct LaneBFixesTests {
    @Test func discoverFilteringRejectsRatedRawMediaIdentifier() {
        let keep = DiscoverViewModel.shouldKeepRecommendation(
            title: "Indie Favorite",
            recommendationMediaID: "tt1234567",
            recommendationType: .movie,
            tmdbId: nil,
            ratedMediaIds: ["tt1234567"],
            libraryMediaIds: [],
            ratedTitles: [],
            watchedTitles: [],
            libraryTitles: []
        )

        #expect(keep == false)
    }

    @Test func discoverMissingKeyResetPolicyOnlyTriggersForConfiguredKey() {
        #expect(DiscoverViewModel.shouldResetRemoteServiceForMissingKey(configuredApiKey: "abc") == true)
        #expect(DiscoverViewModel.shouldResetRemoteServiceForMissingKey(configuredApiKey: nil) == false)
        #expect(DiscoverViewModel.shouldResetRemoteServiceForMissingKey(configuredApiKey: "   ") == false)
    }

    @Test func detailAutoSearchPolicyDefersSeriesSearchUntilExplicitUserAction() {
        #expect(
            DetailAutoSearchPolicy.shouldAutoSearch(
                previewType: .movie,
                hasMediaItem: true,
                hasSelectedEpisode: false,
                hasExplicitEpisodeContext: false
            ) == true
        )
        #expect(
            DetailAutoSearchPolicy.shouldAutoSearch(
                previewType: .series,
                hasMediaItem: true,
                hasSelectedEpisode: false,
                hasExplicitEpisodeContext: false
            ) == false
        )
        #expect(
            DetailAutoSearchPolicy.shouldAutoSearch(
                previewType: .series,
                hasMediaItem: true,
                hasSelectedEpisode: true,
                hasExplicitEpisodeContext: false
            ) == false
        )
        #expect(
            DetailAutoSearchPolicy.shouldAutoSearch(
                previewType: .series,
                hasMediaItem: true,
                hasSelectedEpisode: true,
                hasExplicitEpisodeContext: true
            ) == false
        )
    }

    @Test func detailInitialRenderPolicyKeepsFirstOpenOnSkeletonUntilInitialTaskFinishes() {
        #expect(
            DetailInitialRenderPolicy.shouldShowContent(
                hasViewModel: false,
                isPreparingInitialPresentation: true
            ) == false
        )

        #expect(
            DetailInitialRenderPolicy.shouldShowContent(
                hasViewModel: true,
                isPreparingInitialPresentation: true
            ) == false
        )

        #expect(
            DetailInitialRenderPolicy.shouldShowContent(
                hasViewModel: true,
                isPreparingInitialPresentation: false
            ) == true
        )
    }

    @Test func librarySelectionTransitionResetsOnlyWhenListChanges() {
        #expect(
            LibrarySelectionTransitionPolicy.shouldResetTransientFolderState(
                previous: .watchlist,
                next: .history
            ) == true
        )
        #expect(
            LibrarySelectionTransitionPolicy.shouldResetTransientFolderState(
                previous: .favorites,
                next: .favorites
            ) == false
        )
    }

    @Test func libraryTitleRefreshPolicyBlocksHistoryAndInFlightRefreshes() {
        #expect(LibraryTitleRefreshPolicy.canStartRefresh(selectedList: .watchlist, isRefreshing: false) == true)
        #expect(LibraryTitleRefreshPolicy.canStartRefresh(selectedList: .history, isRefreshing: false) == false)
        #expect(LibraryTitleRefreshPolicy.canStartRefresh(selectedList: .favorites, isRefreshing: true) == false)
    }

    @Test func downloadProgressPolicyNormalizesFromBytesAndClampsInvalidProgress() {
        let bytesBacked = DownloadProgressPolicy.normalizedProgress(
            progress: .nan,
            bytesWritten: 50,
            totalBytes: 100,
            status: .downloading
        )
        #expect(abs(bytesBacked - 0.5) < 0.000_1)

        let invalidProgress = DownloadProgressPolicy.normalizedProgress(
            progress: .nan,
            bytesWritten: 0,
            totalBytes: nil,
            status: .downloading
        )
        #expect(invalidProgress == 0)

        let completedWithoutTotal = DownloadProgressPolicy.normalizedProgress(
            progress: 0.2,
            bytesWritten: 0,
            totalBytes: nil,
            status: .completed
        )
        #expect(completedWithoutTotal == 1)
    }

    @Test func downloadProgressPolicyUsesLatestTaskTimestamp() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)

        let tasks = [
            DownloadTask(
                id: "a",
                mediaId: "m1",
                streamURL: "https://example.com/a",
                fileName: "old.mkv",
                status: .queued,
                progress: 0,
                bytesWritten: 0,
                totalBytes: nil,
                destinationPath: nil,
                errorMessage: nil,
                mediaTitle: "Old",
                mediaType: "movie",
                posterPath: nil,
                seasonNumber: nil,
                episodeNumber: nil,
                episodeTitle: nil,
                createdAt: older,
                updatedAt: older
            ),
            DownloadTask(
                id: "b",
                mediaId: "m1",
                streamURL: "https://example.com/b",
                fileName: "new.mkv",
                status: .downloading,
                progress: 0.1,
                bytesWritten: 1,
                totalBytes: 10,
                destinationPath: nil,
                errorMessage: nil,
                mediaTitle: "New",
                mediaType: "movie",
                posterPath: nil,
                seasonNumber: nil,
                episodeNumber: nil,
                episodeTitle: nil,
                createdAt: newer,
                updatedAt: newer
            )
        ]

        #expect(DownloadProgressPolicy.latestUpdatedAt(in: tasks) == newer)
    }

    @Test func seriesPrimaryPlayPolicyUsesSharedBusyGateAndFeedbackMessage() {
        #expect(SeriesPrimaryPlayPolicy.isBusy(isLocalPlayLoading: true, isPlayerOpening: false, isLoadingSeasonEpisodes: false) == true)
        #expect(SeriesPrimaryPlayPolicy.isBusy(isLocalPlayLoading: false, isPlayerOpening: true, isLoadingSeasonEpisodes: false) == true)
        #expect(SeriesPrimaryPlayPolicy.isBusy(isLocalPlayLoading: false, isPlayerOpening: false, isLoadingSeasonEpisodes: false) == false)
        #expect(SeriesPrimaryPlayPolicy.noStreamsMessage.contains("No streams found"))
    }

    @Test func searchShellCopyPolicyReturnsContextAwareCopy() {
        #expect(
            SearchShellCopyPolicy.title(
                explorePhase: .results,
                submittedQuery: "dune",
                hasSelectedGenre: false,
                hasActiveMoodCard: false
            ) == "Search the catalog"
        )

        let subtitle = SearchShellCopyPolicy.subtitle(
            activeMoodCardTitle: "Dark Thrillers",
            selectedGenreName: nil,
            submittedQuery: ""
        )
        #expect(subtitle.contains("dark thrillers"))
    }

    @Test func searchGenreRemapPrefersIdThenCaseInsensitiveName() {
        let sourceGenre = Genre(id: 28, name: "Action")
        let byID = SearchViewModel.remapGenre(sourceGenre, in: [Genre(id: 28, name: "Action & Adventure")])
        #expect(byID?.id == 28)

        let byName = SearchViewModel.remapGenre(sourceGenre, in: [Genre(id: 999, name: "action")])
        #expect(byName?.id == 999)
    }
}
