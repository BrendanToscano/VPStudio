import Foundation
import Testing
@testable import VPStudio

@Suite("Player Capability And Ranking")
struct PlayerCapabilityTests {
    @Test func rankingPrefersCachedWhenEnabled() {
        var cached1080 = makeTorrent(
            hash: "cached",
            title: "Movie.1080p.WEB-DL.AAC",
            quality: .hd1080p,
            hdr: .sdr,
            audio: .aac,
            seeders: 50,
            cached: true
        )
        var uncached4K = makeTorrent(
            hash: "uncached",
            title: "Movie.2160p.DV.Atmos",
            quality: .uhd4k,
            hdr: .dolbyVision,
            audio: .atmos,
            seeders: 200,
            cached: false
        )

        let rankedCached = TorrentRanking.sort(
            [uncached4K, cached1080],
            preferredQuality: .uhd4k,
            preferCached: true,
            preferAtmos: true,
            hdrPreference: .dolbyVision
        )

        let rankedQuality = TorrentRanking.sort(
            [uncached4K, cached1080],
            preferredQuality: .uhd4k,
            preferCached: false,
            preferAtmos: true,
            hdrPreference: .dolbyVision
        )

        #expect(rankedCached.first?.infoHash == cached1080.infoHash)
        #expect(rankedQuality.first?.infoHash == uncached4K.infoHash)

        cached1080.isCached = true
        uncached4K.isCached = false
    }

    @Test func rankingHonorsAtmosAndHDRPreferences() {
        let atmosDV = makeTorrent(
            hash: "atmos-dv",
            title: "Movie.2160p.DV.Atmos",
            quality: .uhd4k,
            hdr: .dolbyVision,
            audio: .atmos,
            seeders: 40,
            cached: false
        )
        let standard = makeTorrent(
            hash: "standard",
            title: "Movie.2160p.HDR10.AAC",
            quality: .uhd4k,
            hdr: .hdr10,
            audio: .aac,
            seeders: 40,
            cached: false
        )

        let ranked = TorrentRanking.sort(
            [standard, atmosDV],
            preferredQuality: .uhd4k,
            preferCached: false,
            preferAtmos: true,
            hdrPreference: .dolbyVision
        )

        #expect(ranked.first?.infoHash == atmosDV.infoHash)
    }

    @Test func capabilityWarningsReflectStreamMetadata() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/movie.mkv")!,
            quality: .uhd4k,
            codec: .h265,
            audio: .atmos,
            source: .webDL,
            hdr: .dolbyVision,
            fileName: "Movie.2160p.DV.Atmos.mkv",
            sizeBytes: 2_000,
            debridService: DebridServiceType.realDebrid.rawValue
        )

        let warnings = PlayerCapabilityEvaluator.warnings(for: stream)

        #expect(warnings.count == 3)
        #expect(warnings.contains(where: { $0.contains("4K source") }))
        #expect(warnings.contains(where: { $0.contains("HDR source") }))
        #expect(warnings.contains(where: { $0.contains("Atmos") || $0.contains("Spatial") }))
    }

    private func makeTorrent(
        hash: String,
        title: String,
        quality: VideoQuality,
        hdr: HDRFormat,
        audio: AudioFormat,
        seeders: Int,
        cached: Bool
    ) -> TorrentResult {
        TorrentResult(
            infoHash: hash,
            title: title,
            sizeBytes: 10_000,
            seeders: seeders,
            leechers: 2,
            quality: quality,
            codec: .h265,
            audio: audio,
            source: .webDL,
            hdr: hdr,
            indexerName: "Test",
            magnetURI: nil,
            isCached: cached,
            cachedOnService: cached ? DebridServiceType.realDebrid.rawValue : nil
        )
    }
}
