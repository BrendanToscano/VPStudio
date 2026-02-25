import Foundation
@preconcurrency import KSPlayer

struct KSPlayerEngine: PlayerEngine {
    let kind: PlayerEngineKind = .ksPlayer

    struct TuningProfile: Equatable, Sendable {
        let preferredForwardBufferDuration: Double
        let maxBufferDuration: Double
        let probesize: Int64
        let maxAnalyzeDuration: Int64
        let autoSelectEmbedSubtitle: Bool
    }

    func canHandle(stream: StreamInfo) -> Bool {
        URL(string: stream.streamURL.absoluteString) != nil
    }

    @MainActor
    func prepare(stream: StreamInfo) async throws -> PreparedPlaybackSession {
        guard URL(string: stream.streamURL.absoluteString) != nil else {
            throw PlayerEngineError.invalidStreamURL(stream.streamURL.absoluteString)
        }

        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        KSOptions.isAutoPlay = true
        KSOptions.isSecondOpen = false
        KSOptions.logLevel = .error

        let options = KSOptions()

        // Always enable hardware decode and async decompression.
        // KSPlayer will fall back to software if the hardware decoder
        // can't handle the stream (e.g. interlaced content).
        options.hardwareDecode = true
        options.asynchronousDecompression = true

        // Per-stream buffer/probe tuning with a lower-RAM baseline.
        let profile = Self.tuningProfile(for: stream)
        options.preferredForwardBufferDuration = profile.preferredForwardBufferDuration
        options.maxBufferDuration = profile.maxBufferDuration
        options.probesize = profile.probesize
        options.maxAnalyzeDuration = profile.maxAnalyzeDuration
        options.autoSelectEmbedSubtitle = profile.autoSelectEmbedSubtitle

        // Hard read-timeout: if FFmpeg can't get data within 30 s it raises an
        // error rather than hanging the readiness poll indefinitely.
        options.formatContextOptions["rw_timeout"] = 30_000_000 // 30 s in µs

        return PreparedPlaybackSession(
            engineKind: kind,
            streamURL: stream.streamURL,
            avPlayer: nil,
            ksPlayerCoordinator: KSVideoPlayer.Coordinator(),
            ksOptions: options
        )
    }

    // MARK: - Readiness Timeout

    /// Returns a stream-aware readiness timeout for `waitUntilReady`.
    ///
    /// Demanding streams need more time for codec probing, hardware-decoder
    /// negotiation, and initial network buffering:
    /// - 4K / HDR / lossless audio / AV1 → 24 s
    /// - Container formats that require FFmpeg demuxing (MKV, TS, AVI…) → 18 s
    /// - Standard HTTP streams → 12 s (unchanged default)
    static func timeout(for stream: StreamInfo) -> TimeInterval {
        if isHighDemandStream(stream) { return 24 }
        let ext = stream.streamURL.pathExtension.lowercased()
        if ["mkv", "ts", "m2ts", "avi", "wmv", "flv", "webm"].contains(ext) { return 18 }
        return 12
    }

    // MARK: - Readiness Poll

    @MainActor
    static func waitUntilReady(
        coordinator: KSVideoPlayer.Coordinator,
        timeout: TimeInterval = 12,
        pollInterval: Duration = .milliseconds(150),
        onState: ((PlayerPlaybackState, String?) -> Void)? = nil,
        failureMessage: @escaping () -> String?
    ) async throws {
        guard timeout > 0 else {
            throw PlayerEngineError.initializationFailed(.ksPlayer, "Invalid readiness timeout.")
        }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            switch coordinator.state {
            case .initialized, .preparing:
                onState?(.preparing, "Initializing KSPlayer.")

            case .readyToPlay, .buffering:
                onState?(.buffering, "KSPlayer is buffering.")

            case .bufferFinished, .paused, .playedToTheEnd:
                onState?(.playing, "KSPlayer is rendering.")
                return

            case .error:
                let message = failureMessage() ?? "Unknown KSPlayer startup error"
                throw PlayerEngineError.initializationFailed(.ksPlayer, message)
            }

            try await Task.sleep(for: pollInterval)
        }

        throw PlayerEngineError.startupTimeout(.ksPlayer)
    }

    // MARK: - Private Helpers

    /// Returns `true` for streams where codec initialisation and buffering are
    /// meaningfully slower than standard 1080p H.264 content.
    private static func isHighDemandStream(_ stream: StreamInfo) -> Bool {
        if stream.quality == .uhd4k { return true }
        if stream.codec == .av1 { return true }
        if stream.hdr == .dolbyVision || stream.hdr == .hdr10Plus { return true }
        if stream.audio == .atmos || stream.audio == .trueHD || stream.audio == .dtsHDMA { return true }
        let lower = stream.fileName.lowercased()
        return lower.contains("remux") || lower.contains("bdremux")
    }

    nonisolated static func tuningProfile(for stream: StreamInfo) -> TuningProfile {
        if isHighDemandStream(stream) {
            return TuningProfile(
                preferredForwardBufferDuration: 5.0,
                maxBufferDuration: 30.0,
                probesize: 6_000_000,
                maxAnalyzeDuration: 6_000_000,
                autoSelectEmbedSubtitle: false
            )
        }

        return TuningProfile(
            preferredForwardBufferDuration: 3.0,
            maxBufferDuration: 15.0,
            probesize: 2_000_000,
            maxAnalyzeDuration: 2_500_000,
            autoSelectEmbedSubtitle: true
        )
    }
}
