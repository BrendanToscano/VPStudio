import Foundation
import Testing
@testable import VPStudio

@Suite("Player Session Routing", .serialized)
struct PlayerSessionRoutingTests {
    @MainActor
    @Test func seriesSessionCarriesMediaAndEpisodeContext() {
        let appState = AppState(testHooks: .init())
        let viewModel = DetailViewModel(appState: appState)

        let episode = Episode(
            id: "tmdb-100-s1e2",
            mediaId: "tmdb-100",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Episode 2",
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )
        viewModel.mediaItem = MediaItem(id: "tt1234567", type: .series, title: "Example Show", tmdbId: 100)
        viewModel.selectedEpisode = episode

        let primaryStream = makeStream(url: "https://cdn.example.com/main.mkv", name: "main.mkv")
        let secondaryStream = makeStream(url: "https://cdn.example.com/alt.mkv", name: "alt.mkv")
        viewModel.streams = [primaryStream, secondaryStream]

        let preview = MediaPreview(id: "series-tmdb-100", type: .series, title: "Preview Show", year: 2025, posterPath: nil, imdbRating: nil, tmdbId: 100)
        let request = viewModel.makePlayerSessionRequest(stream: primaryStream, preview: preview)

        #expect(request.mediaId == "tt1234567")
        #expect(request.mediaTitle == "Example Show")
        #expect(request.episodeId == episode.id)
        #expect(request.availableStreams == [primaryStream, secondaryStream])
    }

    @MainActor
    @Test func previewFallbackIsUsedWhenDetailItemUnavailable() {
        let appState = AppState(testHooks: .init())
        let viewModel = DetailViewModel(appState: appState)

        let stream = makeStream(url: "https://cdn.example.com/movie.mkv", name: "movie.mkv")
        let preview = MediaPreview(id: "movie-tmdb-90", type: .movie, title: "Preview Movie", year: 2024, posterPath: nil, imdbRating: nil, tmdbId: 90)

        let request = viewModel.makePlayerSessionRequest(stream: stream, preview: preview)

        #expect(request.mediaId == preview.id)
        #expect(request.mediaTitle == preview.title)
        #expect(request.episodeId == nil)
        #expect(request.availableStreams == [stream])
    }

    @MainActor
    @Test func streamPoolPinsSelectedPrimaryFirstAndDeduplicates() {
        let appState = AppState(testHooks: .init())
        let viewModel = DetailViewModel(appState: appState)

        let primary = makeStream(url: "https://cdn.example.com/primary.mkv", name: "primary.mkv")
        let alt = makeStream(url: "https://cdn.example.com/alt.mkv", name: "alt.mkv")
        viewModel.streams = [alt, primary, alt]

        let preview = MediaPreview(
            id: "movie-1",
            type: .movie,
            title: "Movie",
            year: 2026,
            posterPath: nil,
            imdbRating: nil,
            tmdbId: 1
        )

        let request = viewModel.makePlayerSessionRequest(stream: primary, preview: preview)

        #expect(request.availableStreams.first?.id == primary.id)
        #expect(request.availableStreams.count == 2)
    }

    private func makeStream(url: String, name: String) -> StreamInfo {
        StreamInfo(
            streamURL: URL(string: url)!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: name,
            sizeBytes: 1_000,
            debridService: DebridServiceType.realDebrid.rawValue
        )
    }
}
