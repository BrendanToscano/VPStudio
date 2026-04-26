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

    @Test func mvHevcStreamsUseOnlyAVPlayerForEveryStrategy() {
        let stream = makeStream(
            url: "https://cdn.example.com/spatial.mov",
            fileName: "Spatial.Movie.MV-HEVC.mov",
            codec: .h265
        )

        for strategy in PlayerEngineStrategy.allCases {
            #expect(selector.engineOrder(for: stream, strategy: strategy) == [.avPlayer])
        }
    }

    @Test func strategyLabelsAndSummariesAreStableForSettingsUI() {
        #expect(PlayerEngineStrategy.adaptive.id == "adaptive")
        #expect(PlayerEngineStrategy.performance.displayName == "Performance")
        #expect(PlayerEngineStrategy.compatibility.displayName == "Compatibility")
        #expect(PlayerEngineStrategy.adaptive.summary.contains("AVPlayer"))
        #expect(PlayerEngineStrategy.performance.summary.contains("AVPlayer"))
        #expect(PlayerEngineStrategy.compatibility.summary.contains("KSPlayer"))
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
        #expect(order == [.avPlayer])
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
    @Test func avPlayerReadinessRejectsNonPositiveTimeout() async {
        let item = AVPlayerItem(url: URL(string: "https://cdn.example.com/movie.mp4")!)
        let player = AVPlayer(playerItem: item)

        do {
            try await AVPlayerEngine.waitUntilReady(player: player, timeout: 0)
            Issue.record("Expected non-positive readiness timeout to fail.")
        } catch PlayerEngineError.initializationFailed(let kind, let message) {
            #expect(kind == .avPlayer)
            #expect(message.contains("Invalid readiness timeout"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test func avPlayerReadinessTimesOutForItemThatNeverStartsPlaying() async {
        let item = AVPlayerItem(url: URL(string: "https://cdn.example.com/movie.mp4")!)
        let player = AVPlayer(playerItem: item)
        var states: [PlayerPlaybackState] = []

        do {
            try await AVPlayerEngine.waitUntilReady(
                player: player,
                timeout: 0.05,
                pollInterval: .milliseconds(5),
                onState: { state, _ in states.append(state) }
            )
            Issue.record("Expected readiness wait to time out.")
        } catch PlayerEngineError.startupTimeout(let kind) {
            #expect(kind == .avPlayer)
            #expect(states.contains(.preparing) || states.contains(.buffering))
        } catch {
            Issue.record("Unexpected error: \(error)")
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

    @MainActor
    @Test func avPlayerEnginePrepareUsesLongerBufferForDemandingStreams() async throws {
        let engine = AVPlayerEngine()
        let stream = makeStream(
            url: "https://cdn.example.com/movie.mp4",
            fileName: "Movie.2025.2160p.DV.mp4",
            codec: .h265,
            hdr: .dolbyVision
        )

        let prepared = try await engine.prepare(stream: stream)

        #expect(engine.canHandle(stream: stream))
        #expect(prepared.engineKind == .avPlayer)
        #expect(prepared.ksPlayerCoordinator == nil)
        #expect(prepared.ksOptions == nil)
        #expect(prepared.avPlayer?.currentItem?.preferredForwardBufferDuration == 3.0)
    }

    @MainActor
    @Test func avPlayerEnginePrepareUsesLongerBufferForUHDAndHDR10Plus() async throws {
        let engine = AVPlayerEngine()
        let uhdStream = StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/movie-uhd.mp4")!,
            quality: .uhd4k,
            codec: .h265,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "Movie.2025.2160p.mp4",
            sizeBytes: 1_000,
            debridService: DebridServiceType.realDebrid.rawValue
        )
        let hdr10PlusStream = makeStream(
            url: "https://cdn.example.com/movie-hdr10plus.mp4",
            fileName: "Movie.2025.1080p.HDR10Plus.mp4",
            codec: .h265,
            hdr: .hdr10Plus
        )

        let uhdPrepared = try await engine.prepare(stream: uhdStream)
        let hdrPrepared = try await engine.prepare(stream: hdr10PlusStream)

        #expect(uhdPrepared.avPlayer?.currentItem?.preferredForwardBufferDuration == 3.0)
        #expect(hdrPrepared.avPlayer?.currentItem?.preferredForwardBufferDuration == 3.0)
    }

    @Test func streamFailoverPlannerReturnsNextStreamOnlyWhenAvailable() {
        let first = makeStream(url: "https://cdn.example.com/one.mp4", fileName: "one.mp4", codec: .h264)
        let second = makeStream(url: "https://cdn.example.com/two.mp4", fileName: "two.mp4", codec: .h264)
        let missing = makeStream(url: "https://cdn.example.com/missing.mp4", fileName: "missing.mp4", codec: .h264)

        #expect(PlayerStreamFailoverPlanner.nextStream(after: first, in: [first, second])?.id == second.id)
        #expect(PlayerStreamFailoverPlanner.nextStream(after: second, in: [first, second]) == nil)
        #expect(PlayerStreamFailoverPlanner.nextStream(after: missing, in: [first, second]) == nil)
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
