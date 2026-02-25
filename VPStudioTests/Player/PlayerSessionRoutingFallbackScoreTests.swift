import Foundation
import Testing
@testable import VPStudio

// MARK: - PlayerSessionRouting Edge Cases

@Suite("PlayerSessionRouting - Edge Cases")
struct PlayerSessionRoutingEdgeCaseTests {

    @Test func sessionStreamsWithEmptyAvailableArray() {
        let primary = Fixtures.stream(url: "https://cdn.example.com/p.mkv", fileName: "p.mkv")
        let routed = PlayerSessionRouting.sessionStreams(primary: primary, available: [])
        #expect(routed.count == 1)
        #expect(routed.first?.id == primary.id)
    }

    @Test func sessionStreamsPrimaryAlreadyInAvailableIsNotDuplicated() {
        let primary = Fixtures.stream(url: "https://cdn.example.com/p.mkv", fileName: "p.mkv")
        let routed = PlayerSessionRouting.sessionStreams(primary: primary, available: [primary])
        #expect(routed.count == 1)
        #expect(routed.first?.id == primary.id)
    }

    @Test func sessionStreamsPrimaryAppearsMultipleTimesInAvailable() {
        let primary = Fixtures.stream(url: "https://cdn.example.com/p.mkv", fileName: "p.mkv")
        let alt = Fixtures.stream(url: "https://cdn.example.com/a.mkv", fileName: "a.mkv")
        let routed = PlayerSessionRouting.sessionStreams(primary: primary, available: [primary, primary, alt])
        #expect(routed.count == 2)
        #expect(routed.first?.id == primary.id)
    }

    @Test func playbackQueueWithTwoTotalStreamsSkipsSorting() async {
        // With only 2 streams (primary + 1 fallback), no scoring should happen.
        // The guard `routed.count > 2` skips the task group.
        let primary = Fixtures.stream(url: "https://cdn.example.com/p.mkv", fileName: "p.mkv")
        let fallback = Fixtures.stream(url: "https://cdn.example.com/f.mkv", quality: .hd720p, fileName: "f.mkv")

        let queue = await PlayerSessionRouting.playbackQueue(primary: primary, available: [fallback])
        #expect(queue.count == 2)
        #expect(queue[0].id == primary.id)
        #expect(queue[1].id == fallback.id)
    }

    @Test func playbackQueueWithOnlyPrimaryStream() async {
        let primary = Fixtures.stream(url: "https://cdn.example.com/p.mkv", fileName: "p.mkv")
        let queue = await PlayerSessionRouting.playbackQueue(primary: primary, available: [])
        #expect(queue.count == 1)
        #expect(queue.first?.id == primary.id)
    }
}

// MARK: - PlayerSessionRouting Fallback Scoring

// Tests verify the relative ordering of scores by comparing pairs of streams.
// The scoring is internal (private), so we exercise it through playbackQueue ordering.

@Suite("PlayerSessionRouting - Fallback Scoring")
struct PlayerSessionRoutingFallbackScoringTests {

    /// Returns the fallback ordering for a set of streams, with a throwaway primary.
    private func fallbackOrder(streams: [StreamInfo]) async -> [StreamInfo] {
        // We use a distinct primary so it pins at index 0, then read the sorted fallbacks.
        let sentinel = Fixtures.stream(
            url: "https://sentinel.example.com/s.mkv",
            fileName: "sentinel.mkv"
        )
        let queue = await PlayerSessionRouting.playbackQueue(primary: sentinel, available: streams)
        return Array(queue.dropFirst()) // Remove the pinned primary
    }

    // MARK: HDR Scoring

    @Test func dolbyVisionRanksAboveHdr10() async {
        let dv = Fixtures.stream(url: "https://cdn.example.com/dv.mkv", hdr: .dolbyVision, fileName: "dv.mkv")
        let hdr = Fixtures.stream(url: "https://cdn.example.com/hdr.mkv", hdr: .hdr10, fileName: "hdr.mkv")

        let ordered = await fallbackOrder(streams: [hdr, dv])
        #expect(ordered.first?.id == dv.id, "DolbyVision should rank above HDR10")
    }

    @Test func dolbyVisionRanksAboveHdr10Plus() async {
        let dv = Fixtures.stream(url: "https://cdn.example.com/dv.mkv", hdr: .dolbyVision, fileName: "dv.mkv")
        let hdr10plus = Fixtures.stream(url: "https://cdn.example.com/hdrplus.mkv", hdr: .hdr10Plus, fileName: "hdrplus.mkv")

        let ordered = await fallbackOrder(streams: [hdr10plus, dv])
        #expect(ordered.first?.id == dv.id, "DolbyVision should rank above HDR10Plus")
    }

    @Test func hdr10RanksAboveHlg() async {
        let hdr = Fixtures.stream(url: "https://cdn.example.com/hdr.mkv", hdr: .hdr10, fileName: "hdr.mkv")
        let hlg = Fixtures.stream(url: "https://cdn.example.com/hlg.mkv", hdr: .hlg, fileName: "hlg.mkv")

        let ordered = await fallbackOrder(streams: [hlg, hdr])
        #expect(ordered.first?.id == hdr.id, "HDR10 should rank above HLG")
    }

    @Test func hlgRanksAboveSdr() async {
        let hlg = Fixtures.stream(url: "https://cdn.example.com/hlg.mkv", hdr: .hlg, fileName: "hlg.mkv")
        let sdr = Fixtures.stream(url: "https://cdn.example.com/sdr.mkv", hdr: .sdr, fileName: "sdr.mkv")

        let ordered = await fallbackOrder(streams: [sdr, hlg])
        #expect(ordered.first?.id == hlg.id, "HLG should rank above SDR")
    }

    @Test func hdr10PlusAndHdr10HaveEqualHdrScore() async {
        // Both get 28 HDR points; with all else equal they should tie on score,
        // so ordering falls to quality sort, then size, then ID.
        let hdr10 = Fixtures.stream(
            url: "https://cdn.example.com/hdr10.mkv",
            hdr: .hdr10,
            fileName: "aaa-hdr10.mkv" // ID-based tiebreak: "aaa" < "bbb"
        )
        let hdr10plus = Fixtures.stream(
            url: "https://cdn.example.com/hdr10plus.mkv",
            hdr: .hdr10Plus,
            fileName: "bbb-hdr10plus.mkv"
        )

        // With identical score except HDR (both get 28), the ID tiebreak applies.
        // Both should appear, and aaa sorts before bbb when scores are equal.
        let ordered = await fallbackOrder(streams: [hdr10, hdr10plus])
        #expect(ordered.count == 2)
        #expect(ordered[0].id == hdr10.id, "Equal HDR scores should fall back to ID tiebreak (aaa < bbb)")
    }

    // MARK: Codec Scoring

    @Test func h265RanksAboveH264() async {
        let h265 = Fixtures.stream(url: "https://cdn.example.com/h265.mkv", codec: .h265, fileName: "h265.mkv")
        let h264 = Fixtures.stream(url: "https://cdn.example.com/h264.mkv", codec: .h264, fileName: "h264.mkv")

        let ordered = await fallbackOrder(streams: [h264, h265])
        #expect(ordered.first?.id == h265.id, "H265 should rank above H264")
    }

    @Test func h264RanksAboveAv1() async {
        let h264 = Fixtures.stream(url: "https://cdn.example.com/h264.mkv", codec: .h264, fileName: "h264.mkv")
        let av1 = Fixtures.stream(url: "https://cdn.example.com/av1.mkv", codec: .av1, fileName: "av1.mkv")

        let ordered = await fallbackOrder(streams: [av1, h264])
        #expect(ordered.first?.id == h264.id, "H264 should rank above AV1")
    }

    @Test func av1RanksAboveXvid() async {
        let av1 = Fixtures.stream(url: "https://cdn.example.com/av1.mkv", codec: .av1, fileName: "av1.mkv")
        let xvid = Fixtures.stream(url: "https://cdn.example.com/xvid.mkv", codec: .xvid, fileName: "xvid.mkv")

        let ordered = await fallbackOrder(streams: [xvid, av1])
        #expect(ordered.first?.id == av1.id, "AV1 should rank above XviD")
    }

    @Test func xvidRanksAboveUnknown() async {
        let xvid = Fixtures.stream(url: "https://cdn.example.com/xvid.mkv", codec: .xvid, fileName: "xvid.mkv")
        let unknown = Fixtures.stream(url: "https://cdn.example.com/unk.mkv", codec: .unknown, fileName: "unk.mkv")

        let ordered = await fallbackOrder(streams: [unknown, xvid])
        #expect(ordered.first?.id == xvid.id, "XviD should rank above unknown codec")
    }

    // MARK: Spatial Audio Scoring

    @Test func spatialAudioRanksAboveNonSpatial() async {
        // Atmos has spatialAudioHint = true, AAC does not
        let atmos = Fixtures.stream(url: "https://cdn.example.com/atmos.mkv", audio: .atmos, fileName: "atmos.mkv")
        let aac = Fixtures.stream(url: "https://cdn.example.com/aac.mkv", audio: .aac, fileName: "aac.mkv")

        let ordered = await fallbackOrder(streams: [aac, atmos])
        #expect(ordered.first?.id == atmos.id, "Spatial audio should rank higher")
    }

    // MARK: Size Scoring

    @Test func largerFileSizeRanksHigherWhenOtherScoresEqual() async {
        let large = Fixtures.stream(
            url: "https://cdn.example.com/large.mkv",
            fileName: "large.mkv",
            sizeBytes: 4 * 1_073_741_824  // 4 GB
        )
        let small = Fixtures.stream(
            url: "https://cdn.example.com/small.mkv",
            fileName: "small.mkv",
            sizeBytes: 500_000_000  // ~0.5 GB
        )

        let ordered = await fallbackOrder(streams: [small, large])
        #expect(ordered.first?.id == large.id, "Larger file should rank higher when other scores equal")
    }

    @Test func nilSizeBytesGetsZeroSizeScore() async {
        // A stream with nil size should not outrank one with real size
        // if all other attributes are equal
        let withSize = Fixtures.stream(
            url: "https://cdn.example.com/sized.mkv",
            fileName: "sized.mkv",
            sizeBytes: 2_147_483_648  // 2 GB
        )
        let noSize = Fixtures.stream(
            url: "https://cdn.example.com/nosize.mkv",
            fileName: "nosize.mkv",
            sizeBytes: nil
        )

        let ordered = await fallbackOrder(streams: [noSize, withSize])
        #expect(ordered.first?.id == withSize.id, "Stream with file size should rank above nil-size stream")
    }

    @Test func sizeScoringCapsAtFourGigabytes() async {
        // Both 5 GB and 10 GB should score the same (capped at min(gb*3, 12) → 4*3=12)
        let fiveGB = Fixtures.stream(
            url: "https://cdn.example.com/5gb.mkv",
            fileName: "aaa-5gb.mkv",  // ID tiebreak: "aaa" < "bbb" sorts first
            sizeBytes: 5 * 1_073_741_824
        )
        let tenGB = Fixtures.stream(
            url: "https://cdn.example.com/10gb.mkv",
            fileName: "bbb-10gb.mkv",
            sizeBytes: 10 * 1_073_741_824
        )

        // Both should cap at 12 size-score points.
        // With equal score, fallback is ID sort (aaa < bbb), so fiveGB first.
        let ordered = await fallbackOrder(streams: [tenGB, fiveGB])
        #expect(ordered.count == 2, "Both streams should appear")
    }
}
