import Foundation
import Testing
@testable import VPStudio

@Suite("Detail Episode State", .serialized)
struct DetailEpisodeStateTests {
    @MainActor
    @Test func changingEpisodeInvalidatesPreviousSearchResults() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)

        let firstEpisode = Episode(
            id: "tmdb-42-s1e1",
            mediaId: "tmdb-42",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Pilot",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )
        let secondEpisode = Episode(
            id: "tmdb-42-s1e2",
            mediaId: "tmdb-42",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Episode 2",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )

        viewModel.mediaItem = MediaItem(id: "tt7654321", type: .series, title: "Example", tmdbId: 42)
        viewModel.selectedEpisode = firstEpisode
        viewModel.didSearch = true
        viewModel.lastSearchEpisodeId = firstEpisode.id
        viewModel.torrents = [makeTorrent(hash: "aaa", title: "Example.S01E01.1080p")]

        viewModel.selectEpisode(secondEpisode)

        #expect(viewModel.torrents.isEmpty)
        #expect(viewModel.requiresFreshEpisodeSearch)
        #expect(viewModel.lastSearchEpisodeId == firstEpisode.id)
        #expect(viewModel.selectedEpisode?.id == secondEpisode.id)
    }

    @MainActor
    @Test func selectingSameEpisodeDoesNotClearResults() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)

        let episode = Episode(
            id: "tmdb-50-s1e1",
            mediaId: "tmdb-50",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Pilot",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )

        viewModel.mediaItem = MediaItem(id: "tt123", type: .series, title: "Example", tmdbId: 50)
        viewModel.selectedEpisode = episode
        viewModel.torrents = [makeTorrent(hash: "bbb", title: "Example.S01E01.1080p")]

        viewModel.selectEpisode(episode)

        #expect(viewModel.torrents.count == 1)
        #expect(viewModel.requiresFreshEpisodeSearch == false)
    }

    @MainActor
    @Test func moviesNeverRequireEpisodeRefresh() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)

        viewModel.mediaItem = MediaItem(id: "tt999", type: .movie, title: "Movie")
        viewModel.didSearch = true
        viewModel.lastSearchEpisodeId = "some-episode"

        #expect(viewModel.requiresFreshEpisodeSearch == false)
    }

    private func makeTorrent(hash: String, title: String) -> TorrentResult {
        TorrentResult.fromSearch(
            infoHash: hash,
            title: title,
            sizeBytes: 1_000,
            seeders: 50,
            leechers: 3,
            indexerName: "Test"
        )
    }
}
