import Foundation
import Testing
@testable import VPStudio

@Suite("Detail Lifecycle Behavior", .serialized)
struct DetailLifecycleBehaviorTests {
    @Test
    @MainActor
    func searchPublishesInitialBatchAndLoadMoreRevealsTenAtATime() async {
        let appState = AppState()
        let indexer = FixedDetailIndexerManager(results: makeTorrentResults(count: 25))
        let debrid = StubDebridManager()
        let downloads = StubDownloadManager()
        let viewModel = DetailViewModel(
            appState: appState,
            indexerManager: indexer,
            debridManager: debrid,
            downloadManager: downloads
        )
        viewModel.mediaItem = MediaItem(id: "tt2300001", type: .movie, title: "Batch Test")

        await viewModel.searchTorrents()

        #expect(viewModel.torrentSearch.results.count == 10)
        #expect(viewModel.canLoadMoreTorrents)
        #expect(viewModel.remainingTorrentCount == 15)
        #expect(viewModel.nextTorrentBatchCount == 10)

        viewModel.loadMoreTorrentResults()
        #expect(viewModel.torrentSearch.results.count == 20)
        #expect(viewModel.remainingTorrentCount == 5)
        #expect(viewModel.nextTorrentBatchCount == 5)

        viewModel.loadMoreTorrentResults()
        #expect(viewModel.torrentSearch.results.count == 25)
        #expect(viewModel.remainingTorrentCount == 0)
        #expect(viewModel.canLoadMoreTorrents == false)
    }

    @Test
    @MainActor
    func newSearchResetsPreviouslyExpandedBatchWindow() async {
        let appState = AppState()
        let indexer = SequentialDetailIndexerManager(
            firstResults: makeTorrentResults(count: 24),
            secondResults: makeTorrentResults(count: 4)
        )
        let debrid = StubDebridManager()
        let downloads = StubDownloadManager()
        let viewModel = DetailViewModel(
            appState: appState,
            indexerManager: indexer,
            debridManager: debrid,
            downloadManager: downloads
        )
        viewModel.mediaItem = MediaItem(id: "tt2300002", type: .movie, title: "Batch Reset Test")

        await viewModel.searchTorrents()
        viewModel.loadMoreTorrentResults()
        #expect(viewModel.torrentSearch.results.count == 20)

        await viewModel.searchTorrents()

        #expect(viewModel.torrentSearch.results.count == 4)
        #expect(viewModel.remainingTorrentCount == 0)
        #expect(viewModel.canLoadMoreTorrents == false)
    }

    @Test
    @MainActor
    func secondSearchCancelsBlockedFirstSearchAndKeepsNewestResults() async {
        let appState = AppState()
        let staleResult = Fixtures.torrent(hash: "stale-hash", title: "Old.Result")
        let freshResult = Fixtures.torrent(hash: "fresh-hash", title: "New.Result")
        let indexer = BlockingDetailIndexerManager(firstResults: [staleResult], secondResults: [freshResult])
        let debrid = StubDebridManager()
        let downloads = StubDownloadManager()
        let viewModel = DetailViewModel(
            appState: appState,
            indexerManager: indexer,
            debridManager: debrid,
            downloadManager: downloads
        )
        viewModel.mediaItem = MediaItem(id: "tt1234567", type: .movie, title: "Cancellation Test")

        defer { Task { await indexer.unblockFirstSearchWithStaleResults() } }

        let firstSearch = Task { await viewModel.searchTorrents() }
        await indexer.waitForFirstSearchToStart()

        await viewModel.searchTorrents()
        await firstSearch.value

        #expect(await indexer.searchCallCount() == 2)
        #expect(viewModel.torrentSearch.results.map(\.infoHash) == ["fresh-hash"])
        #expect(viewModel.torrentSearch.didSearch)
    }

    @Test
    @MainActor
    func cancelInFlightWorkStopsBlockedSearchBeforeItCanPublishResults() async {
        let appState = AppState()
        let staleResult = Fixtures.torrent(hash: "stale-hash", title: "Old.Result")
        let indexer = BlockingDetailIndexerManager(firstResults: [staleResult], secondResults: [])
        let debrid = StubDebridManager()
        let downloads = StubDownloadManager()
        let viewModel = DetailViewModel(
            appState: appState,
            indexerManager: indexer,
            debridManager: debrid,
            downloadManager: downloads
        )
        viewModel.mediaItem = MediaItem(id: "tt7654321", type: .movie, title: "Cancellation Test")

        defer { Task { await indexer.unblockFirstSearchWithStaleResults() } }

        let searchTask = Task { await viewModel.searchTorrents() }
        await indexer.waitForFirstSearchToStart()

        viewModel.cancelInFlightWork()
        await searchTask.value

        #expect(await indexer.searchCallCount() == 1)
        #expect(viewModel.torrentSearch.results.isEmpty)
        #expect(viewModel.torrentSearch.didSearch == false)
    }

    @Test
    @MainActor
    func selectingAnotherEpisodeCancelsInFlightSearchAndSuppressesStaleResults() async {
        let appState = AppState()
        let staleResult = Fixtures.torrent(hash: "stale-episode-hash", title: "Old.Episode.Result")
        let indexer = BlockingDetailIndexerManager(firstResults: [staleResult], secondResults: [])
        let debrid = StubDebridManager()
        let downloads = StubDownloadManager()
        let viewModel = DetailViewModel(
            appState: appState,
            indexerManager: indexer,
            debridManager: debrid,
            downloadManager: downloads
        )
        viewModel.mediaItem = MediaItem(id: "tt3333333", type: .series, title: "Episode Cancellation Test")
        viewModel.selectedSeason = 1
        let episodeOne = Episode(
            id: "tt3333333-s1e1",
            mediaId: "tt3333333",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Episode 1",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )
        let episodeTwo = Episode(
            id: "tt3333333-s1e2",
            mediaId: "tt3333333",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Episode 2",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )
        viewModel.episodes = [episodeOne, episodeTwo]
        viewModel.selectedEpisode = episodeOne

        defer { Task { await indexer.unblockFirstSearchWithStaleResults() } }

        let searchTask = Task { await viewModel.searchTorrents() }
        await indexer.waitForFirstSearchToStart()

        viewModel.selectEpisode(episodeTwo)
        await searchTask.value

        #expect(await indexer.searchCallCount() == 1)
        #expect(viewModel.selectedEpisode?.id == episodeTwo.id)
        #expect(viewModel.torrentSearch.results.isEmpty)
        #expect(viewModel.torrentSearch.didSearch == false)
    }

    private func makeTorrentResults(count: Int) -> [TorrentResult] {
        (0..<count).map { index in
            Fixtures.torrent(
                hash: "batch-hash-\(index)",
                title: "Batch.Result.\(index).1080p"
            )
        }
    }
}

private actor FixedDetailIndexerManager: DetailIndexerManaging {
    private let results: [TorrentResult]

    init(results: [TorrentResult]) {
        self.results = results
    }

    func initialize() async throws {}

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        results
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        []
    }
}

private actor SequentialDetailIndexerManager: DetailIndexerManaging {
    private let firstResults: [TorrentResult]
    private let secondResults: [TorrentResult]
    private var searchCalls = 0

    init(firstResults: [TorrentResult], secondResults: [TorrentResult]) {
        self.firstResults = firstResults
        self.secondResults = secondResults
    }

    func initialize() async throws {}

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        searchCalls += 1
        if searchCalls == 1 {
            return firstResults
        }
        return secondResults
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        []
    }
}

private actor BlockingDetailIndexerManager: DetailIndexerManaging {
    private let firstResults: [TorrentResult]
    private let secondResults: [TorrentResult]

    private var searchCalls = 0
    private var firstSearchContinuation: CheckedContinuation<[TorrentResult], Error>?
    private var firstSearchStartedContinuation: CheckedContinuation<Void, Never>?

    init(firstResults: [TorrentResult], secondResults: [TorrentResult]) {
        self.firstResults = firstResults
        self.secondResults = secondResults
    }

    func initialize() async throws {}

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        searchCalls += 1
        if searchCalls == 1 {
            return try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        firstSearchContinuation = continuation
                        firstSearchStartedContinuation?.resume()
                        firstSearchStartedContinuation = nil
                    }
                },
                onCancel: {
                    Task { await self.resumeFirstSearchIfNeeded(throwing: CancellationError()) }
                }
            )
        }

        return secondResults
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        []
    }

    func waitForFirstSearchToStart() async {
        if firstSearchContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            firstSearchStartedContinuation = continuation
        }
    }

    func unblockFirstSearchWithStaleResults() {
        firstSearchContinuation?.resume(returning: firstResults)
        firstSearchContinuation = nil
    }

    private func resumeFirstSearchIfNeeded(throwing error: Error) {
        firstSearchContinuation?.resume(throwing: error)
        firstSearchContinuation = nil
    }

    func searchCallCount() -> Int {
        searchCalls
    }
}
