import Foundation
import Testing
@testable import VPStudio

// MARK: - Timeout Tier Tests

@Suite("KSPlayerEngine - Timeout Tiers")
struct KSPlayerEngineTimeoutTests {

    // MARK: 24s — High-Demand Streams

    @Test func uhd4kStreamGets24sTimeout() {
        let stream = Fixtures.stream(quality: .uhd4k, fileName: "Movie.2160p.mkv")
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func av1CodecGets24sTimeout() {
        let stream = Fixtures.stream(codec: .av1, fileName: "Movie.AV1.1080p.mkv")
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func dolbyVisionGets24sTimeout() {
        let stream = Fixtures.stream(hdr: .dolbyVision, fileName: "Movie.DV.1080p.mkv")
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func hdr10PlusGets24sTimeout() {
        let stream = Fixtures.stream(hdr: .hdr10Plus, fileName: "Movie.HDR10Plus.1080p.mkv")
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func atmosAudioGets24sTimeout() {
        let stream = Fixtures.stream(audio: .atmos, fileName: "Movie.Atmos.1080p.mkv")
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func trueHDAudioGets24sTimeout() {
        let stream = Fixtures.stream(audio: .trueHD, fileName: "Movie.TrueHD.1080p.mkv")
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func dtsHDMAAudioGets24sTimeout() {
        let stream = Fixtures.stream(audio: .dtsHDMA, fileName: "Movie.DTS-HDMA.1080p.mkv")
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func remuxFilenameGets24sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mp4",
            fileName: "Movie.2025.Remux.1080p.mp4"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func bdremuxFilenameGets24sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mp4",
            fileName: "Movie.2025.BDRemux.1080p.mp4"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    // MARK: 18s — Complex Container Formats

    @Test func mkvContainerGets18sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mkv",
            fileName: "Movie.1080p.mkv"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 18)
    }

    @Test func tsContainerGets18sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.ts",
            fileName: "Movie.1080p.ts"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 18)
    }

    @Test func m2tsContainerGets18sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.m2ts",
            fileName: "Movie.1080p.m2ts"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 18)
    }

    @Test func aviContainerGets18sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.avi",
            fileName: "Movie.1080p.avi"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 18)
    }

    @Test func wmvContainerGets18sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.wmv",
            fileName: "Movie.1080p.wmv"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 18)
    }

    @Test func flvContainerGets18sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.flv",
            fileName: "Movie.1080p.flv"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 18)
    }

    @Test func webmContainerGets18sTimeout() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.webm",
            fileName: "Movie.1080p.webm"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 18)
    }

    // MARK: 12s — Standard Streams

    @Test func mp4StreamGets12sDefault() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mp4",
            fileName: "Movie.1080p.mp4"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 12)
    }

    @Test func movStreamGets12sDefault() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mov",
            fileName: "Movie.1080p.mov"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 12)
    }

    @Test func m4vStreamGets12sDefault() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.m4v",
            fileName: "Movie.1080p.m4v"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 12)
    }

    // MARK: Priority — High-demand overrides container tier

    @Test func highDemand4kMkvGets24sNotEighteen() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mkv",
            quality: .uhd4k,
            fileName: "Movie.4K.UHD.mkv"
        )
        // 4K triggers high-demand (24s), not the MKV container tier (18s)
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    @Test func atmosMkvGets24sNotEighteen() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mkv",
            audio: .atmos,
            fileName: "Movie.Atmos.1080p.mkv"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 24)
    }

    // MARK: Non-high-demand audio/HDR stay at container or default

    @Test func hdr10MkvGetsEighteen() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mkv",
            hdr: .hdr10,
            fileName: "Movie.HDR10.1080p.mkv"
        )
        // HDR10 is NOT high-demand (only DV and HDR10+ are), so MKV container tier applies
        #expect(KSPlayerEngine.timeout(for: stream) == 18)
    }

    @Test func aacMp4GetsDefault12s() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mp4",
            audio: .aac,
            fileName: "Movie.AAC.1080p.mp4"
        )
        #expect(KSPlayerEngine.timeout(for: stream) == 12)
    }
}

@Suite("KSPlayerEngine - Tuning Profiles")
struct KSPlayerEngineTuningProfileTests {
    @Test func highDemandProfileUsesBoundedBuffers() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mkv",
            quality: .uhd4k,
            hdr: .dolbyVision,
            fileName: "Movie.2160p.DV.Remux.mkv"
        )
        let profile = KSPlayerEngine.tuningProfile(for: stream)

        #expect(profile.preferredForwardBufferDuration == 3.0)
        #expect(profile.maxBufferDuration == 16.0)
        #expect(profile.probesize == 6_000_000)
        #expect(profile.maxAnalyzeDuration == 6_000_000)
        #expect(profile.autoSelectEmbedSubtitle == false)
    }

    @Test func defaultProfileUsesLowMemoryDefaults() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mp4",
            quality: .hd1080p,
            hdr: .sdr,
            fileName: "Movie.1080p.WEBDL.mp4"
        )
        let profile = KSPlayerEngine.tuningProfile(for: stream)

        #expect(profile.preferredForwardBufferDuration == 1.5)
        #expect(profile.maxBufferDuration == 8.0)
        #expect(profile.probesize == 2_000_000)
        #expect(profile.maxAnalyzeDuration == 2_500_000)
        #expect(profile.autoSelectEmbedSubtitle == true)
    }

    @Test func remuxTokenTriggersHighDemandProfile() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mp4",
            quality: .hd1080p,
            hdr: .sdr,
            fileName: "Movie.2025.BDRemux.1080p.mp4"
        )
        let profile = KSPlayerEngine.tuningProfile(for: stream)

        #expect(profile.maxBufferDuration == 16.0)
    }
}
