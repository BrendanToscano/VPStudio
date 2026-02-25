import Testing
import Foundation
@testable import VPStudio

// MARK: - TorrentRanking Score Tests

@Suite("TorrentRanking - Scoring")
struct TorrentRankingScoringTests {

    private func makeTorrent(
        quality: VideoQuality = .hd1080p,
        codec: VideoCodec = .h264,
        audio: AudioFormat = .aac,
        source: SourceType = .webDL,
        hdr: HDRFormat = .sdr,
        seeders: Int = 50,
        isCached: Bool = false
    ) -> TorrentResult {
        TorrentResult(
            infoHash: UUID().uuidString, title: "", sizeBytes: 1_000_000_000,
            seeders: seeders, leechers: 0, quality: quality, codec: codec,
            audio: audio, source: source, hdr: hdr, indexerName: "test",
            isCached: isCached
        )
    }

    // -- Resolution dominance --

    @Test func higherResolutionAlwaysBeatsLower() {
        let uhd = makeTorrent(quality: .uhd4k, audio: .aac, source: .unknown, hdr: .sdr, seeders: 1)
        let hd = makeTorrent(quality: .hd1080p, audio: .atmos, source: .bluRay, hdr: .dolbyVision, seeders: 500, isCached: true)

        let uhdScore = TorrentRanking.score(uhd, preferredQuality: .hd1080p, preferCached: true, preferAtmos: true, hdrPreference: .dolbyVision)
        let hdScore = TorrentRanking.score(hd, preferredQuality: .hd1080p, preferCached: true, preferAtmos: true, hdrPreference: .dolbyVision)

        #expect(uhdScore > hdScore, "Bare 4K must beat a fully-loaded 1080p")
    }

    @Test func everyQualityTierBeatsTheOneBelow() {
        let tiers: [VideoQuality] = [.uhd4k, .hd1080p, .hd720p, .sd480p, .sd]
        for i in 0..<(tiers.count - 1) {
            let higher = makeTorrent(quality: tiers[i], seeders: 1)
            let lower = makeTorrent(quality: tiers[i + 1], audio: .atmos, source: .bluRay, hdr: .dolbyVision, seeders: 500, isCached: true)

            let hScore = TorrentRanking.score(higher, preferredQuality: .hd1080p, preferCached: true, preferAtmos: true, hdrPreference: .dolbyVision)
            let lScore = TorrentRanking.score(lower, preferredQuality: .hd1080p, preferCached: true, preferAtmos: true, hdrPreference: .dolbyVision)

            #expect(hScore > lScore, "\(tiers[i]) must beat \(tiers[i + 1])")
        }
    }

    // -- Within same resolution: features matter --

    @Test func dolbyVisionBeatsSDRWithinSameTier() {
        let dv = makeTorrent(hdr: .dolbyVision)
        let sdr = makeTorrent(hdr: .sdr)

        let dvScore = TorrentRanking.score(dv, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        let sdrScore = TorrentRanking.score(sdr, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(dvScore > sdrScore)
    }

    @Test func hdr10PlusBeatsHDR10() {
        let plus = makeTorrent(hdr: .hdr10Plus)
        let base = makeTorrent(hdr: .hdr10)

        let plusScore = TorrentRanking.score(plus, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        let baseScore = TorrentRanking.score(base, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(plusScore > baseScore)
    }

    @Test func atmosBeatsAACWithinSameTier() {
        let atmos = makeTorrent(audio: .atmos)
        let aac = makeTorrent(audio: .aac)

        let atmosScore = TorrentRanking.score(atmos, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        let aacScore = TorrentRanking.score(aac, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(atmosScore > aacScore)
    }

    @Test func h265BeatsH264WithinSameTier() {
        let h265 = makeTorrent(codec: .h265)
        let h264 = makeTorrent(codec: .h264)

        let h265Score = TorrentRanking.score(h265, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        let h264Score = TorrentRanking.score(h264, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(h265Score > h264Score)
    }

    @Test func bluRayBeatsWebDLWithinSameTier() {
        let bluray = makeTorrent(source: .bluRay)
        let webdl = makeTorrent(source: .webDL)

        let brScore = TorrentRanking.score(bluray, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        let wdScore = TorrentRanking.score(webdl, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(brScore > wdScore)
    }

    // -- User preferences are bonuses, not overrides --

    @Test func cachedBoostsWithinSameTier() {
        let cached = makeTorrent(isCached: true)
        let uncached = makeTorrent(isCached: false)

        let cachedScore = TorrentRanking.score(cached, preferredQuality: .hd1080p, preferCached: true, preferAtmos: false, hdrPreference: .auto)
        let uncachedScore = TorrentRanking.score(uncached, preferredQuality: .hd1080p, preferCached: true, preferAtmos: false, hdrPreference: .auto)

        #expect(cachedScore > uncachedScore)
    }

    @Test func cachedCannotOverrideResolution() {
        let cached720 = makeTorrent(quality: .hd720p, isCached: true)
        let uncached1080 = makeTorrent(quality: .hd1080p, isCached: false)

        let cachedScore = TorrentRanking.score(cached720, preferredQuality: .hd1080p, preferCached: true, preferAtmos: true, hdrPreference: .dolbyVision)
        let uncachedScore = TorrentRanking.score(uncached1080, preferredQuality: .hd1080p, preferCached: true, preferAtmos: true, hdrPreference: .dolbyVision)

        #expect(uncachedScore > cachedScore, "Uncached 1080p must still beat cached 720p")
    }

    @Test func atmosPreferenceAddsExtraBoost() {
        let atmos = makeTorrent(audio: .atmos)

        let withPref = TorrentRanking.score(atmos, preferredQuality: .hd1080p, preferCached: false, preferAtmos: true, hdrPreference: .auto)
        let withoutPref = TorrentRanking.score(atmos, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(withPref > withoutPref)
    }

    @Test func hdrPreferenceBoostsMatchingFormat() {
        let dv = makeTorrent(hdr: .dolbyVision)

        let withDVPref = TorrentRanking.score(dv, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .dolbyVision)
        let withAutoPref = TorrentRanking.score(dv, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(withDVPref > withAutoPref)
    }

    // -- Seeders --

    @Test func moreSeedersBreakTiesWithinSameTier() {
        let highSeeders = makeTorrent(seeders: 400)
        let lowSeeders = makeTorrent(seeders: 10)

        let highScore = TorrentRanking.score(highSeeders, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        let lowScore = TorrentRanking.score(lowSeeders, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(highScore > lowScore)
    }

    @Test func seedersCapAt500() {
        let cap = makeTorrent(seeders: 500)
        let over = makeTorrent(seeders: 10000)

        let capScore = TorrentRanking.score(cap, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        let overScore = TorrentRanking.score(over, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(capScore == overScore)
    }

    @Test func seedersCannotOverrideResolution() {
        let sd500 = makeTorrent(quality: .sd, seeders: 500)
        let hd1 = makeTorrent(quality: .hd720p, seeders: 1)

        let sdScore = TorrentRanking.score(sd500, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        let hdScore = TorrentRanking.score(hd1, preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)

        #expect(hdScore > sdScore)
    }
}

// MARK: - TorrentRanking Sort Tests

@Suite("TorrentRanking - Sorting")
struct TorrentRankingSortTests {

    @Test func sortPutsCachedFirstWithinSameResolution() {
        let cached = TorrentResult(
            infoHash: "cached", title: "", sizeBytes: 0,
            seeders: 10, leechers: 0, quality: .hd1080p, codec: .h264,
            audio: .aac, source: .webDL, hdr: .sdr, indexerName: "",
            isCached: true
        )
        let uncached = TorrentResult(
            infoHash: "uncached", title: "", sizeBytes: 0,
            seeders: 100, leechers: 0, quality: .hd1080p, codec: .h264,
            audio: .aac, source: .webDL, hdr: .sdr, indexerName: "",
            isCached: false
        )

        let sorted = TorrentRanking.sort([uncached, cached], preferredQuality: .hd1080p, preferCached: true, preferAtmos: false, hdrPreference: .auto)
        #expect(sorted[0].infoHash == "cached")
    }

    @Test func sortPutsHigherResolutionAboveCachedLowerResolution() {
        let cached720 = TorrentResult(
            infoHash: "cached720", title: "", sizeBytes: 0,
            seeders: 500, leechers: 0, quality: .hd720p, codec: .h265,
            audio: .atmos, source: .bluRay, hdr: .dolbyVision, indexerName: "",
            isCached: true
        )
        let uncached1080 = TorrentResult(
            infoHash: "uncached1080", title: "", sizeBytes: 0,
            seeders: 1, leechers: 0, quality: .hd1080p, codec: .h264,
            audio: .aac, source: .unknown, hdr: .sdr, indexerName: "",
            isCached: false
        )

        let sorted = TorrentRanking.sort([cached720, uncached1080], preferredQuality: .hd1080p, preferCached: true, preferAtmos: true, hdrPreference: .dolbyVision)
        #expect(sorted[0].infoHash == "uncached1080")
    }

    @Test func sortBreaksTiesBySeeders() {
        let high = TorrentResult(
            infoHash: "high", title: "", sizeBytes: 0,
            seeders: 200, leechers: 0, quality: .hd1080p, codec: .h264,
            audio: .aac, source: .webDL, hdr: .sdr, indexerName: ""
        )
        let low = TorrentResult(
            infoHash: "low", title: "", sizeBytes: 0,
            seeders: 10, leechers: 0, quality: .hd1080p, codec: .h264,
            audio: .aac, source: .webDL, hdr: .sdr, indexerName: ""
        )

        let sorted = TorrentRanking.sort([low, high], preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        #expect(sorted[0].infoHash == "high")
    }

    @Test func sortHandlesEmptyArray() {
        let sorted = TorrentRanking.sort([], preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        #expect(sorted.isEmpty)
    }

    @Test func sortHandlesSingleElement() {
        let single = TorrentResult(
            infoHash: "only", title: "", sizeBytes: 0,
            seeders: 50, leechers: 0, quality: .hd1080p, codec: .h264,
            audio: .aac, source: .webDL, hdr: .sdr, indexerName: ""
        )
        let sorted = TorrentRanking.sort([single], preferredQuality: .hd1080p, preferCached: false, preferAtmos: false, hdrPreference: .auto)
        #expect(sorted.count == 1)
        #expect(sorted[0].infoHash == "only")
    }

    @Test func concurrentSortMatchesSynchronousSort() async {
        var torrents: [TorrentResult] = []
        for index in 0..<32 {
            torrents.append(
                TorrentResult(
                    infoHash: "hash-\(index)",
                    title: "Movie.\(index).1080p",
                    sizeBytes: Int64(1_000 + index),
                    seeders: ((index * 37) % 499) + 1,
                    leechers: 0,
                    quality: index % 3 == 0 ? .uhd4k : (index % 2 == 0 ? .hd1080p : .hd720p),
                    codec: index % 4 == 0 ? .h265 : .h264,
                    audio: index % 5 == 0 ? .atmos : .aac,
                    source: .webDL,
                    hdr: index % 6 == 0 ? .dolbyVision : .sdr,
                    indexerName: "test",
                    isCached: index % 4 == 0
                )
            )
        }

        let sync = TorrentRanking.sort(
            torrents,
            preferredQuality: .uhd4k,
            preferCached: true,
            preferAtmos: true,
            hdrPreference: .dolbyVision
        )
        let concurrent = await TorrentRanking.sortConcurrently(
            torrents,
            preferredQuality: .uhd4k,
            preferCached: true,
            preferAtmos: true,
            hdrPreference: .dolbyVision
        )

        #expect(sync.map(\.id) == concurrent.map(\.id))
    }
}
