import Foundation
import AVFoundation

struct AVPlayerEngine: PlayerEngine {
    let kind: PlayerEngineKind = .avPlayer

    func canHandle(stream: StreamInfo) -> Bool {
        URL(string: stream.streamURL.absoluteString) != nil
    }

    @MainActor
    func prepare(stream: StreamInfo) async throws -> PreparedPlaybackSession {
        guard URL(string: stream.streamURL.absoluteString) != nil else {
            throw PlayerEngineError.invalidStreamURL(stream.streamURL.absoluteString)
        }

        let item = AVPlayerItem(url: stream.streamURL)
        item.preferredForwardBufferDuration = preferredForwardBufferDuration(for: stream)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        let player = AVPlayer(playerItem: item)
        // Prefer faster first-frame start and lower memory pressure; fallback
        // logic handles streams that still need compatibility decoding.
        player.automaticallyWaitsToMinimizeStalling = false

        return PreparedPlaybackSession(
            engineKind: kind,
            streamURL: stream.streamURL,
            avPlayer: player,
            ksPlayerCoordinator: nil,
            ksOptions: nil
        )
    }

    private func preferredForwardBufferDuration(for stream: StreamInfo) -> TimeInterval {
        if stream.quality == .uhd4k || stream.hdr == .dolbyVision || stream.hdr == .hdr10Plus {
            return 3.0
        }
        return 1.5
    }

    @MainActor
    static func waitUntilReady(
        player: AVPlayer,
        timeout: TimeInterval = 12,
        pollInterval: Duration = .milliseconds(150),
        onState: ((PlayerPlaybackState, String?) -> Void)? = nil
    ) async throws {
        guard timeout > 0 else {
            throw PlayerEngineError.initializationFailed(.avPlayer, "Invalid readiness timeout.")
        }

        guard let item = player.currentItem else {
            throw PlayerEngineError.initializationFailed(.avPlayer, "Missing AVPlayerItem.")
        }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let itemError = item.error {
                throw PlayerEngineError.initializationFailed(.avPlayer, itemError.localizedDescription)
            }

            switch item.status {
            case .failed:
                let reason = item.error?.localizedDescription ?? "Unknown AVPlayer item error"
                throw PlayerEngineError.initializationFailed(.avPlayer, reason)

            case .readyToPlay:
                if player.rate > 0 || player.timeControlStatus == .playing {
                    onState?(.playing, "AVPlayer is rendering.")
                    return
                }

                if player.timeControlStatus == .waitingToPlayAtSpecifiedRate || item.isPlaybackBufferEmpty {
                    onState?(.buffering, "AVPlayer is buffering.")
                } else {
                    onState?(.buffering, "AVPlayer is ready; waiting for first frame.")
                }

            case .unknown:
                onState?(.preparing, "Loading stream metadata.")

            @unknown default:
                onState?(.buffering, "Waiting for AVPlayer readiness.")
            }

            try await Task.sleep(for: pollInterval)
        }

        throw PlayerEngineError.startupTimeout(.avPlayer)
    }
}
