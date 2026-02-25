import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct DetailViewModelStateMachineTests {
    struct FreshnessCase: Sendable {
        let mediaType: MediaType
        let didSearch: Bool
        let selectedSeason: Int
        let selectedEpisode: Int
        let lastSeason: Int
        let lastEpisode: Int
        let expectedRequiresFreshSearch: Bool
    }

    struct SelectionCase: Sendable {
        let currentEpisode: Int
        let nextEpisode: Int
        let shouldInvalidate: Bool
    }

    private static let freshnessCases: [FreshnessCase] = {
        var values: [FreshnessCase] = []
        for index in 0..<60 {
            let mediaType: MediaType = index % 5 == 0 ? .movie : .series
            let didSearch = index % 3 != 0
            let selectedSeason = (index % 4) + 1
            let selectedEpisode = (index % 6) + 1
            let sameContext = index % 2 == 0
            let lastSeason = sameContext ? selectedSeason : selectedSeason + 1
            let lastEpisode = sameContext ? selectedEpisode : selectedEpisode + 1
            let expected = mediaType == .series && didSearch && !sameContext
            values.append(
                FreshnessCase(
                    mediaType: mediaType,
                    didSearch: didSearch,
                    selectedSeason: selectedSeason,
                    selectedEpisode: selectedEpisode,
                    lastSeason: lastSeason,
                    lastEpisode: lastEpisode,
                    expectedRequiresFreshSearch: expected
                )
            )
        }
        return values
    }()

    private static let selectionCases: [SelectionCase] = {
        var values: [SelectionCase] = []
        for index in 0..<50 {
            let current = (index % 8) + 1
            let same = index % 2 == 0
            let next = same ? current : current + 1
            values.append(
                SelectionCase(
                    currentEpisode: current,
                    nextEpisode: next,
                    shouldInvalidate: !same
                )
            )
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(freshnessCases.prefix(20)), full: freshnessCases))
    @MainActor
    func requiresFreshEpisodeSearchMatrix(data: FreshnessCase) {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)

        viewModel.mediaItem = MediaItem(id: "tt\(data.mediaType == .movie ? 11 : 22)", type: data.mediaType, title: "Title")
        viewModel.didSearch = data.didSearch
        viewModel.selectedSeason = data.selectedSeason
        viewModel.selectedEpisode = Episode(
            id: "ep-\(data.selectedSeason)-\(data.selectedEpisode)",
            mediaId: "series",
            seasonNumber: data.selectedSeason,
            episodeNumber: data.selectedEpisode,
            title: "E\(data.selectedEpisode)",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )
        viewModel.lastSearchContextKey = viewModel.searchContextKey(
            mediaID: "tt22",
            season: data.lastSeason,
            episode: data.lastEpisode
        )

        #expect(viewModel.requiresFreshEpisodeSearch == data.expectedRequiresFreshSearch)
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(selectionCases.prefix(16)), full: selectionCases))
    @MainActor
    func selectEpisodeInvalidationMatrix(data: SelectionCase) {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)

        viewModel.mediaItem = MediaItem(id: "tt1", type: .series, title: "Show")
        viewModel.selectedSeason = 1
        viewModel.selectedEpisode = Episode(
            id: "ep-1-\(data.currentEpisode)",
            mediaId: "show",
            seasonNumber: 1,
            episodeNumber: data.currentEpisode,
            title: "Current",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )
        viewModel.torrents = [Fixtures.torrent(hash: "abc", title: "Show.S01E\(String(format: "%02d", data.currentEpisode))")]
        viewModel.streams = [Fixtures.stream(fileName: "x.mkv")]
        viewModel.error = .indexer(.queryFailed("old error"))

        let newEpisode = Episode(
            id: "ep-1-\(data.nextEpisode)",
            mediaId: "show",
            seasonNumber: 1,
            episodeNumber: data.nextEpisode,
            title: "Next",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )

        viewModel.selectEpisode(newEpisode)

        if data.shouldInvalidate {
            #expect(viewModel.torrents.isEmpty)
            #expect(viewModel.streams.isEmpty)
            #expect(viewModel.error == nil)
        } else {
            #expect(!viewModel.torrents.isEmpty)
            #expect(!viewModel.streams.isEmpty)
        }
    }
}
