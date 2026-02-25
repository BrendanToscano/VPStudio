import Foundation
import Testing
@testable import VPStudio

@Suite("Player Stream Failover")
struct PlayerStreamFailoverTests {
    @Test func sessionStreamsDeduplicatesAndPinsPrimaryFirst() {
        let primary = makeStream(
            fileName: "movie-1080-large.mkv",
            url: "https://cdn.example.com/a.mkv",
            quality: .hd1080p,
            sizeBytes: 3_000
        )
        let duplicatePrimary = primary
        let lowerQuality = makeStream(
            fileName: "movie-720.mkv",
            url: "https://cdn.example.com/b.mkv",
            quality: .hd720p,
            sizeBytes: 2_000
        )
        let higherQuality = makeStream(
            fileName: "movie-4k.mkv",
            url: "https://cdn.example.com/c.mkv",
            quality: .uhd4k,
            sizeBytes: 1_000
        )

        let queue = PlayerSessionRouting.sessionStreams(
            primary: primary,
            available: [duplicatePrimary, lowerQuality, higherQuality]
        )

        // Primary is pinned first, duplicate removed, other two follow
        #expect(queue.count == 3)
        #expect(queue.first?.id == primary.id)
        #expect(queue.contains(where: { $0.id == lowerQuality.id }))
        #expect(queue.contains(where: { $0.id == higherQuality.id }))
    }

    @Test func nextStreamReturnsFollowingCandidate() {
        let first = makeStream(
            fileName: "movie-4k.mkv",
            url: "https://cdn.example.com/4k.mkv",
            quality: .uhd4k,
            sizeBytes: 1_500
        )
        let second = makeStream(
            fileName: "movie-1080.mkv",
            url: "https://cdn.example.com/1080.mkv",
            quality: .hd1080p,
            sizeBytes: 1_200
        )

        let queue = PlayerSessionRouting.sessionStreams(primary: first, available: [second])
        let next = PlayerStreamFailoverPlanner.nextStream(after: first, in: queue)

        #expect(next?.id == second.id)
        #expect(PlayerStreamFailoverPlanner.nextStream(after: second, in: queue) == nil)
    }

    @Test func nextStreamReturnsNilForUnknownStream() {
        let queued = makeStream(
            fileName: "movie-1080.mkv",
            url: "https://cdn.example.com/1080.mkv",
            quality: .hd1080p,
            sizeBytes: 1_000
        )
        let unknown = makeStream(
            fileName: "movie-unknown.mkv",
            url: "https://cdn.example.com/unknown.mkv",
            quality: .hd720p,
            sizeBytes: 500
        )

        let queue = [queued]
        #expect(PlayerStreamFailoverPlanner.nextStream(after: unknown, in: queue) == nil)
    }

    @Test func nextStreamReturnsNilForEmptyQueue() {
        let stream = makeStream(
            fileName: "movie.mkv",
            url: "https://cdn.example.com/movie.mkv",
            quality: .hd1080p,
            sizeBytes: 1_000
        )

        #expect(PlayerStreamFailoverPlanner.nextStream(after: stream, in: []) == nil)
    }

    @Test func nextStreamWalksFullQueue() {
        let a = makeStream(fileName: "a.mkv", url: "https://cdn.example.com/a.mkv", quality: .uhd4k, sizeBytes: 3_000)
        let b = makeStream(fileName: "b.mkv", url: "https://cdn.example.com/b.mkv", quality: .hd1080p, sizeBytes: 2_000)
        let c = makeStream(fileName: "c.mkv", url: "https://cdn.example.com/c.mkv", quality: .hd720p, sizeBytes: 1_000)

        let queue = [a, b, c]

        #expect(PlayerStreamFailoverPlanner.nextStream(after: a, in: queue)?.id == b.id)
        #expect(PlayerStreamFailoverPlanner.nextStream(after: b, in: queue)?.id == c.id)
        #expect(PlayerStreamFailoverPlanner.nextStream(after: c, in: queue) == nil)
    }

    private func makeStream(
        fileName: String,
        url: String,
        quality: VideoQuality,
        sizeBytes: Int64
    ) -> StreamInfo {
        StreamInfo(
            streamURL: URL(string: url)!,
            quality: quality,
            codec: .h265,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: fileName,
            sizeBytes: sizeBytes,
            debridService: "rd"
        )
    }
}
