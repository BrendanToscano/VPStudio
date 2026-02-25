import Foundation
import AVFoundation
import Testing
@testable import VPStudio

@Suite("Player Engine Fallback")
struct PlayerEngineFallbackTests {
    private let selector = PlayerEngineSelector()

    @Test func selectorAdaptiveModePrefersAVPlayerForMkvRemuxProfile() {
        let stream = makeStream(
            url: "https://cdn.example.com/movie.remux.mkv",
            fileName: "Movie.2025.REMUX.2160p.DV.HEVC.mkv",
            codec: .h265
        )

        let order = selector.engineOrder(for: stream, strategy: .adaptive)
        #if os(visionOS)
        #expect(order == [.avPlayer, .ksPlayer])
        #else
        #expect(order == [.avPlayer, .ksPlayer])
        #endif
    }

    @Test func selectorCompatibilityModePrefersKSPlayerForRiskyStreamProfiles() {
        let stream = makeStream(
            url: "https://cdn.example.com/movie.remux.mkv",
            fileName: "Movie.2025.REMUX.2160p.DV.HEVC.mkv",
            codec: .h265
        )

        let order = selector.engineOrder(for: stream, strategy: .compatibility)
        #if os(visionOS)
        #expect(order == [.avPlayer, .ksPlayer])
        #else
        #expect(order == [.ksPlayer, .avPlayer])
        #endif
    }

    @Test func selectorAdaptiveModeUsesKSPlayerFirstForLegacyContainers() {
        let stream = makeStream(
            url: "https://cdn.example.com/movie.avi",
            fileName: "Movie.2025.avi",
            codec: .h264
        )

        let order = selector.engineOrder(for: stream, strategy: .adaptive)
        #if os(visionOS)
        #expect(order == [.avPlayer, .ksPlayer])
        #else
        #expect(order == [.ksPlayer, .avPlayer])
        #endif
    }

    @Test func selectorPerformanceModeAlwaysPrefersAVPlayer() {
        let stream = makeStream(
            url: "https://cdn.example.com/movie.remux.mkv",
            fileName: "Movie.2025.REMUX.2160p.DV.HEVC.mkv",
            codec: .h265
        )
        let order = selector.engineOrder(for: stream, strategy: .performance)
        #expect(order == [.avPlayer, .ksPlayer])
    }

    @Test func selectorPrefersAVPlayerForSimpleStreams() {
        let stream = makeStream(
            url: "https://cdn.example.com/movie.mp4",
            fileName: "Movie.2025.1080p.WEBDL.mp4",
            codec: .h264
        )

        let order = selector.engineOrder(for: stream, strategy: .adaptive)
        #expect(order == [.avPlayer, .ksPlayer])
    }

    @Test func selectorPrefersAVPlayerForSpatialProfiles() {
        let stream = makeStream(
            url: "https://cdn.example.com/movie.spatial.mkv",
            fileName: "Movie.2025.Spatial.MV-HEVC.2160p.mkv",
            codec: .h265,
            hdr: .dolbyVision
        )

        let order = selector.engineOrder(for: stream, strategy: .adaptive)
        #expect(order == [.avPlayer, .ksPlayer])
    }

    @Test func selectorPrefersAVPlayerForDolbyVisionPlusStreams() {
        let stream = makeStream(
            url: "https://cdn.example.com/movie-hdr10plus.mkv",
            fileName: "Movie.2025.2160p.HDR10Plus.mkv",
            codec: .h265,
            hdr: .hdr10Plus
        )

        let order = selector.engineOrder(for: stream, strategy: .adaptive)
        #expect(order == [.avPlayer, .ksPlayer])
    }

    @MainActor
    @Test func avPlayerReadinessFailureReturnsExplicitError() async {
        let player = AVPlayer()

        do {
            try await AVPlayerEngine.waitUntilReady(player: player, timeout: 0.2)
            Issue.record("Expected readiness wait to fail with missing AVPlayerItem.")
        } catch let error as PlayerEngineError {
            if case .initializationFailed(let kind, _) = error {
                #expect(kind == .avPlayer)
            } else {
                Issue.record("Unexpected PlayerEngineError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @MainActor
    @Test func avPlayerEnginePrepareReturnsAVSession() async throws {
        let engine = AVPlayerEngine()
        let stream = makeStream(
            url: "https://cdn.example.com/movie.mp4",
            fileName: "Movie.2025.1080p.mp4",
            codec: .h264
        )

        let prepared = try await engine.prepare(stream: stream)
        #expect(prepared.engineKind == .avPlayer)
        #expect(prepared.avPlayer != nil)
        #expect(prepared.avPlayer?.automaticallyWaitsToMinimizeStalling == false)
        #expect(prepared.avPlayer?.currentItem?.preferredForwardBufferDuration == 1.5)
    }

    private func makeStream(
        url: String,
        fileName: String,
        codec: VideoCodec,
        hdr: HDRFormat = .sdr
    ) -> StreamInfo {
        StreamInfo(
            streamURL: URL(string: url)!,
            quality: .hd1080p,
            codec: codec,
            audio: .aac,
            source: .webDL,
            hdr: hdr,
            fileName: fileName,
            sizeBytes: 1_000,
            debridService: DebridServiceType.realDebrid.rawValue
        )
    }
}
