import Foundation
import Testing
@testable import VPStudio

@Suite("Player Session Routing Concurrency")
struct PlayerSessionRoutingConcurrencyTests {
    @Test
    func playbackQueuePinsPrimaryAndSortsFallbacks() async {
        let primary = Fixtures.stream(
            url: "https://cdn.example.com/primary.mkv",
            quality: .hd1080p,
            codec: .h264,
            fileName: "primary.mkv",
            sizeBytes: 1_000
        )
        let fourK = Fixtures.stream(
            url: "https://cdn.example.com/4k.mkv",
            quality: .uhd4k,
            codec: .h265,
            hdr: .dolbyVision,
            fileName: "fourk.dv.mkv",
            sizeBytes: 1_500
        )
        let sevenTwenty = Fixtures.stream(
            url: "https://cdn.example.com/720.mkv",
            quality: .hd720p,
            codec: .h264,
            fileName: "seven-twenty.mkv",
            sizeBytes: 900
        )

        let queue = await PlayerSessionRouting.playbackQueue(
            primary: primary,
            available: [sevenTwenty, fourK]
        )

        #expect(queue.first?.id == primary.id)
        #expect(queue.dropFirst().first?.id == fourK.id)
    }

    @Test
    func sessionStreamsDeduplicateByIdentity() {
        let primary = Fixtures.stream(url: "https://cdn.example.com/primary.mkv", fileName: "primary.mkv")
        let duplicate = primary
        let alternate = Fixtures.stream(url: "https://cdn.example.com/alt.mkv", fileName: "alt.mkv")

        let routed = PlayerSessionRouting.sessionStreams(primary: primary, available: [duplicate, alternate, duplicate])

        #expect(routed.count == 2)
        #expect(routed.first?.id == primary.id)
    }
}
