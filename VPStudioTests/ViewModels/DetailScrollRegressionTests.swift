import Foundation
import Testing
@testable import VPStudio

@Suite("Detail Scroll Regressions", .serialized)
struct DetailScrollRegressionTests {
    @Test
    func seriesScrollPolicyKeepsTorrentsSectionVisibleForSelectedEpisodeContext() {
        #expect(
            SeriesDetailScrollPolicy.shouldShowTorrentsSection(
                mediaType: .series,
                hasSelectedEpisode: true,
                isLoadingTorrentSearch: false,
                didSearch: false,
                hasTorrentResults: false
            )
        )

        #expect(
            SeriesDetailScrollPolicy.shouldShowTorrentsSection(
                mediaType: .series,
                hasSelectedEpisode: false,
                isLoadingTorrentSearch: false,
                didSearch: false,
                hasTorrentResults: false
            ) == false
        )

        #expect(
            SeriesDetailScrollPolicy.shouldShowTorrentsSection(
                mediaType: .series,
                hasSelectedEpisode: true,
                isLoadingTorrentSearch: true,
                didSearch: false,
                hasTorrentResults: false
            )
        )
    }

    @Test
    func scrollPolicyDoesNotAutoScrollEpisodeSelection() {
        #expect(
            SeriesDetailScrollPolicy.shouldScrollToResults(
                tappedEpisodeID: "s1e4",
                currentSelectedEpisodeID: "s1e4",
                isTaskCancelled: false
            ) == false
        )

        #expect(
            SeriesDetailScrollPolicy.shouldScrollToResults(
                tappedEpisodeID: "s1e4",
                currentSelectedEpisodeID: "s1e5",
                isTaskCancelled: false
            ) == false
        )

        #expect(
            SeriesDetailScrollPolicy.shouldScrollToResults(
                tappedEpisodeID: "s1e4",
                currentSelectedEpisodeID: "s1e4",
                isTaskCancelled: true
            ) == false
        )
    }

    @Test
    func primaryPlayPolicyTreatsSeasonSwitchingAsBusy() {
        #expect(
            SeriesPrimaryPlayPolicy.isBusy(
                isLocalPlayLoading: false,
                isPlayerOpening: false,
                isLoadingSeasonEpisodes: true
            )
        )

        #expect(
            SeriesPrimaryPlayPolicy.isBusy(
                isLocalPlayLoading: false,
                isPlayerOpening: false,
                isLoadingSeasonEpisodes: false
            ) == false
        )
    }

    @Test
    @MainActor
    func successfulSeriesSearchMarksCurrentEpisodeContextAndClearsFreshness() async {
        let appState = AppState()
        let selectedEpisode = makeEpisode(mediaID: "ttscroll1", season: 1, episode: 1, title: "Pilot")
        let indexer = ScrollRegressionIndexerManager(
            resultsByContext: [
                "s1e1": [Fixtures.torrent(hash: "hash-s1e1", title: "Show.S01E01.1080p")]
            ]
        )
        let viewModel = DetailViewModel(appState: appState, indexerManager: indexer)
        viewModel.mediaItem = MediaItem(id: "ttscroll1", type: .series, title: "Scroll Show", tmdbId: 101)
        viewModel.selectedSeason = 1
        viewModel.selectedEpisode = selectedEpisode

        await viewModel.searchTorrents()

        #expect(viewModel.torrentSearch.results.map(\.infoHash) == ["hash-s1e1"])
        #expect(viewModel.lastSearchEpisodeId == selectedEpisode.id)
        #expect(viewModel.lastSearchContextKey == "ttscroll1-s1e1")
        #expect(viewModel.requiresFreshEpisodeSearch == false)
    }

    @Test
    @MainActor
    func episodeChangeThenResearchClearsFreshnessForNewEpisode() async {
        let appState = AppState()
        let episodeOne = makeEpisode(mediaID: "ttscroll2", season: 1, episode: 1, title: "Pilot")
        let episodeTwo = makeEpisode(mediaID: "ttscroll2", season: 1, episode: 2, title: "Episode 2")
        let indexer = ScrollRegressionIndexerManager(
            resultsByContext: [
                "s1e1": [Fixtures.torrent(hash: "hash-s1e1", title: "Show.S01E01.1080p")],
                "s1e2": [Fixtures.torrent(hash: "hash-s1e2", title: "Show.S01E02.1080p")]
            ]
        )
        let viewModel = DetailViewModel(appState: appState, indexerManager: indexer)
        viewModel.mediaItem = MediaItem(id: "ttscroll2", type: .series, title: "Scroll Show", tmdbId: 102)
        viewModel.selectedSeason = 1
        viewModel.selectedEpisode = episodeOne

        await viewModel.searchTorrents()
        #expect(viewModel.requiresFreshEpisodeSearch == false)

        viewModel.selectEpisode(episodeTwo)
        #expect(viewModel.requiresFreshEpisodeSearch)
        #expect(viewModel.torrentSearch.results.isEmpty)

        await viewModel.searchTorrents()

        #expect(viewModel.torrentSearch.results.map(\.infoHash) == ["hash-s1e2"])
        #expect(viewModel.lastSearchEpisodeId == episodeTwo.id)
        #expect(viewModel.lastSearchContextKey == "ttscroll2-s1e2")
        #expect(viewModel.requiresFreshEpisodeSearch == false)
    }

    @Test
    @MainActor
    func loadDetailPreselectsFirstSeasonButLeavesEpisodeUnselectedWithoutContext() async {
        let appState = AppState()
        let seasonOneEpisodes = [
            makeEpisode(mediaID: "ttscroll3", season: 1, episode: 1, title: "Pilot"),
            makeEpisode(mediaID: "ttscroll3", season: 1, episode: 2, title: "Episode 2")
        ]
        let metadata = ScrollRegressionMetadataProvider(
            detailResult: MediaItem(id: "ttscroll3", type: .series, title: "Scroll Show", tmdbId: 103),
            seasonsResult: [
                Season(id: 1, seasonNumber: 1, name: "Season 1", overview: nil, posterPath: nil, episodeCount: 2, airDate: nil)
            ],
            episodesBySeason: [1: seasonOneEpisodes]
        )
        let viewModel = DetailViewModel(
            appState: appState,
            metadataProviderFactory: { _ in metadata },
            indexerManager: ScrollRegressionIndexerManager(resultsByContext: [:])
        )

        await viewModel.loadDetail(
            preview: MediaPreview(
                id: "ttscroll3",
                type: .series,
                title: "Scroll Show",
                year: 2026,
                posterPath: nil,
                imdbRating: nil,
                tmdbId: 103
            ),
            apiKey: ""
        )

        #expect(viewModel.selectedSeason == 1)
        #expect(viewModel.selectedEpisode == nil)
        #expect(viewModel.episodes.map(\.id) == seasonOneEpisodes.map(\.id))
    }

    @Test
    @MainActor
    func seasonChangeClearsStaleEpisodeAndResultsBeforeNewEpisodesArrive() async {
        let appState = AppState()
        let seasonOneEpisodes = [
            makeEpisode(mediaID: "ttscroll-loading", season: 1, episode: 1, title: "Pilot")
        ]
        let seasonTwoEpisodes = [
            makeEpisode(mediaID: "ttscroll-loading", season: 2, episode: 1, title: "Season 2 Premiere")
        ]
        let metadata = DelayedScrollRegressionMetadataProvider(
            detailResult: MediaItem(id: "ttscroll-loading", type: .series, title: "Scroll Show", tmdbId: 204),
            seasonsResult: [
                Season(id: 1, seasonNumber: 1, name: "Season 1", overview: nil, posterPath: nil, episodeCount: 1, airDate: nil),
                Season(id: 2, seasonNumber: 2, name: "Season 2", overview: nil, posterPath: nil, episodeCount: 1, airDate: nil)
            ],
            episodesBySeason: [
                1: seasonOneEpisodes,
                2: seasonTwoEpisodes
            ],
            delayedSeason: 2,
            delayNanoseconds: 50_000_000
        )
        let indexer = ScrollRegressionIndexerManager(
            resultsByContext: [
                "s1e1": [Fixtures.torrent(hash: "hash-s1e1", title: "Show.S01E01.1080p")]
            ]
        )
        let viewModel = DetailViewModel(
            appState: appState,
            metadataProviderFactory: { _ in metadata },
            indexerManager: indexer
        )
        viewModel.error = .indexer(.queryFailed("stale"))

        await viewModel.loadDetail(
            preview: MediaPreview(
                id: "ttscroll-loading",
                type: .series,
                title: "Scroll Show",
                year: 2026,
                posterPath: nil,
                imdbRating: nil,
                tmdbId: 204
            ),
            apiKey: ""
        )
        await viewModel.searchTorrents()

        let loadTask = Task {
            await viewModel.loadSeason(2, apiKey: "")
        }
        await Task.yield()

        #expect(viewModel.selectedSeason == 2)
        #expect(viewModel.selectedEpisode == nil)
        #expect(viewModel.episodes.isEmpty)
        #expect(viewModel.torrentSearch.results.isEmpty)
        #expect(viewModel.error == nil)
        #expect(viewModel.isLoading(.seasonEpisodes))

        await loadTask.value

        #expect(viewModel.selectedEpisode == nil)
        #expect(viewModel.episodes.map(\.id) == seasonTwoEpisodes.map(\.id))
    }

    @Test
    @MainActor
    func seasonChangeResetsSelectionInvalidatesOldResultsAndResearchClearsFreshness() async {
        let appState = AppState()
        let seasonOneEpisodes = [
            makeEpisode(mediaID: "ttscroll4", season: 1, episode: 1, title: "Pilot"),
            makeEpisode(mediaID: "ttscroll4", season: 1, episode: 2, title: "Episode 2")
        ]
        let seasonTwoEpisodes = [
            makeEpisode(mediaID: "ttscroll4", season: 2, episode: 1, title: "Season 2 Premiere"),
            makeEpisode(mediaID: "ttscroll4", season: 2, episode: 2, title: "Season 2 Episode 2")
        ]
        let metadata = ScrollRegressionMetadataProvider(
            detailResult: MediaItem(id: "ttscroll4", type: .series, title: "Scroll Show", tmdbId: 104),
            seasonsResult: [
                Season(id: 1, seasonNumber: 1, name: "Season 1", overview: nil, posterPath: nil, episodeCount: 2, airDate: nil),
                Season(id: 2, seasonNumber: 2, name: "Season 2", overview: nil, posterPath: nil, episodeCount: 2, airDate: nil)
            ],
            episodesBySeason: [
                1: seasonOneEpisodes,
                2: seasonTwoEpisodes
            ]
        )
        let indexer = ScrollRegressionIndexerManager(
            resultsByContext: [
                "s1e1": [Fixtures.torrent(hash: "hash-s1e1", title: "Show.S01E01.1080p")],
                "s2e1": [Fixtures.torrent(hash: "hash-s2e1", title: "Show.S02E01.1080p")]
            ]
        )
        let viewModel = DetailViewModel(
            appState: appState,
            metadataProviderFactory: { _ in metadata },
            indexerManager: indexer
        )
        viewModel.streams = [Fixtures.stream(fileName: "old.mkv")]
        viewModel.error = .indexer(.queryFailed("stale"))

        await viewModel.loadDetail(
            preview: MediaPreview(
                id: "ttscroll4",
                type: .series,
                title: "Scroll Show",
                year: 2026,
                posterPath: nil,
                imdbRating: nil,
                tmdbId: 104
            ),
            apiKey: ""
        )
        await viewModel.searchTorrents()
        #expect(viewModel.requiresFreshEpisodeSearch == false)

        viewModel.streams = [Fixtures.stream(fileName: "stale-after-search.mkv")]
        viewModel.error = .indexer(.queryFailed("stale again"))

        await viewModel.loadSeason(2, apiKey: "")

        #expect(viewModel.selectedSeason == 2)
        #expect(viewModel.selectedEpisode == nil)
        #expect(viewModel.torrentSearch.results.isEmpty)
        #expect(viewModel.streams.isEmpty)
        #expect(viewModel.error == nil)
        #expect(viewModel.requiresFreshEpisodeSearch)

        viewModel.selectEpisode(seasonTwoEpisodes[0])
        #expect(viewModel.requiresFreshEpisodeSearch)

        await viewModel.searchTorrents()

        #expect(viewModel.torrentSearch.results.map(\.infoHash) == ["hash-s2e1"])
        #expect(viewModel.lastSearchEpisodeId == seasonTwoEpisodes.first?.id)
        #expect(viewModel.lastSearchContextKey == "ttscroll4-s2e1")
        #expect(viewModel.requiresFreshEpisodeSearch == false)
    }

    @Test
    @MainActor
    func staleSeasonResponseDoesNotOverwriteNewerSeasonSelection() async {
        let appState = AppState()
        let seasonOneEpisodes = [
            makeEpisode(mediaID: "ttscroll-race", season: 1, episode: 1, title: "Pilot")
        ]
        let seasonTwoEpisodes = [
            makeEpisode(mediaID: "ttscroll-race", season: 2, episode: 1, title: "Season 2 Premiere")
        ]
        let metadata = DelayedScrollRegressionMetadataProvider(
            detailResult: MediaItem(id: "ttscroll-race", type: .series, title: "Race Show", tmdbId: 304),
            seasonsResult: [
                Season(id: 1, seasonNumber: 1, name: "Season 1", overview: nil, posterPath: nil, episodeCount: 1, airDate: nil),
                Season(id: 2, seasonNumber: 2, name: "Season 2", overview: nil, posterPath: nil, episodeCount: 1, airDate: nil)
            ],
            episodesBySeason: [
                1: seasonOneEpisodes,
                2: seasonTwoEpisodes
            ],
            delayedSeason: 2,
            delayNanoseconds: 60_000_000
        )
        let viewModel = DetailViewModel(
            appState: appState,
            metadataProviderFactory: { _ in metadata },
            indexerManager: ScrollRegressionIndexerManager(resultsByContext: [:])
        )

        await viewModel.loadDetail(
            preview: MediaPreview(
                id: "ttscroll-race",
                type: .series,
                title: "Race Show",
                tmdbId: 304
            ),
            apiKey: ""
        )

        let delayedSeasonLoad = Task {
            await viewModel.loadSeason(2, apiKey: "")
        }
        await Task.yield()
        await viewModel.loadSeason(1, apiKey: "")
        await delayedSeasonLoad.value

        #expect(viewModel.selectedSeason == 1)
        #expect(viewModel.selectedEpisode == nil)
        #expect(viewModel.episodes.map(\.id) == seasonOneEpisodes.map(\.id))
    }

    @Test
    @MainActor
    func retryReplaysLastFailedSeasonLoadInsteadOfTorrentSearch() async {
        let appState = AppState()
        let seasonOneEpisodes = [
            makeEpisode(mediaID: "ttscroll-retry", season: 1, episode: 1, title: "Pilot")
        ]
        let seasonTwoEpisodes = [
            makeEpisode(mediaID: "ttscroll-retry", season: 2, episode: 1, title: "Recovered Episode")
        ]
        let metadata = FlakySeasonMetadataProvider(
            detailResult: MediaItem(id: "ttscroll-retry", type: .series, title: "Retry Show", tmdbId: 404),
            seasonsResult: [
                Season(id: 1, seasonNumber: 1, name: "Season 1", overview: nil, posterPath: nil, episodeCount: 1, airDate: nil),
                Season(id: 2, seasonNumber: 2, name: "Season 2", overview: nil, posterPath: nil, episodeCount: 1, airDate: nil)
            ],
            episodesBySeason: [
                1: seasonOneEpisodes,
                2: seasonTwoEpisodes
            ],
            failingSeason: 2
        )
        let viewModel = DetailViewModel(
            appState: appState,
            metadataProviderFactory: { _ in metadata },
            indexerManager: ScrollRegressionIndexerManager(resultsByContext: [:])
        )

        await viewModel.loadDetail(
            preview: MediaPreview(
                id: "ttscroll-retry",
                type: .series,
                title: "Retry Show",
                tmdbId: 404
            ),
            apiKey: ""
        )

        await viewModel.loadSeason(2, apiKey: "")
        #expect(viewModel.error != nil)
        #expect(viewModel.torrentSearch.results.isEmpty)

        await viewModel.retryLastFailedOperation(apiKey: "")

        #expect(viewModel.error == nil)
        #expect(viewModel.selectedSeason == 2)
        #expect(viewModel.selectedEpisode == nil)
        #expect(viewModel.episodes.map(\.id) == seasonTwoEpisodes.map(\.id))
        #expect(viewModel.torrentSearch.results.isEmpty)
    }

    private func makeEpisode(mediaID: String, season: Int, episode: Int, title: String) -> Episode {
        Episode(
            id: "\(mediaID)-s\(season)e\(episode)",
            mediaId: mediaID,
            seasonNumber: season,
            episodeNumber: episode,
            title: title,
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )
    }
}

private actor ScrollRegressionMetadataProvider: DetailMetadataProviding {
    let detailResult: MediaItem
    let seasonsResult: [Season]
    let episodesBySeason: [Int: [Episode]]

    init(detailResult: MediaItem, seasonsResult: [Season], episodesBySeason: [Int: [Episode]]) {
        self.detailResult = detailResult
        self.seasonsResult = seasonsResult
        self.episodesBySeason = episodesBySeason
    }

    func getDetail(id: String, type: MediaType) async throws -> MediaItem { detailResult }
    func getSeasons(tmdbId: Int) async throws -> [Season] { seasonsResult }
    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { episodesBySeason[season] ?? [] }
}

private actor DelayedScrollRegressionMetadataProvider: DetailMetadataProviding {
    let detailResult: MediaItem
    let seasonsResult: [Season]
    let episodesBySeason: [Int: [Episode]]
    let delayedSeason: Int
    let delayNanoseconds: UInt64

    init(
        detailResult: MediaItem,
        seasonsResult: [Season],
        episodesBySeason: [Int: [Episode]],
        delayedSeason: Int,
        delayNanoseconds: UInt64
    ) {
        self.detailResult = detailResult
        self.seasonsResult = seasonsResult
        self.episodesBySeason = episodesBySeason
        self.delayedSeason = delayedSeason
        self.delayNanoseconds = delayNanoseconds
    }

    func getDetail(id: String, type: MediaType) async throws -> MediaItem { detailResult }
    func getSeasons(tmdbId: Int) async throws -> [Season] { seasonsResult }

    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] {
        if season == delayedSeason {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return episodesBySeason[season] ?? []
    }
}

private actor FlakySeasonMetadataProvider: DetailMetadataProviding {
    let detailResult: MediaItem
    let seasonsResult: [Season]
    let episodesBySeason: [Int: [Episode]]
    let failingSeason: Int
    private var failedOnce = false

    init(
        detailResult: MediaItem,
        seasonsResult: [Season],
        episodesBySeason: [Int: [Episode]],
        failingSeason: Int
    ) {
        self.detailResult = detailResult
        self.seasonsResult = seasonsResult
        self.episodesBySeason = episodesBySeason
        self.failingSeason = failingSeason
    }

    func getDetail(id: String, type: MediaType) async throws -> MediaItem { detailResult }
    func getSeasons(tmdbId: Int) async throws -> [Season] { seasonsResult }

    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] {
        if season == failingSeason, failedOnce == false {
            failedOnce = true
            throw URLError(.cannotLoadFromNetwork)
        }
        return episodesBySeason[season] ?? []
    }
}

private actor ScrollRegressionIndexerManager: DetailIndexerManaging {
    private let resultsByContext: [String: [TorrentResult]]

    init(resultsByContext: [String: [TorrentResult]]) {
        self.resultsByContext = resultsByContext
    }

    func initialize() async throws {}

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        let key = "s\(season ?? 0)e\(episode ?? 0)"
        return resultsByContext[key] ?? resultsByContext["default"] ?? []
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        []
    }
}
