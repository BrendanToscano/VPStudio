import Foundation
import AVFoundation
@preconcurrency import KSPlayer

enum PlayerEngineKind: String, Sendable, CaseIterable {
    case ksPlayer
    case avPlayer

    var displayName: String {
        switch self {
        case .ksPlayer:
            return "KSPlayer"
        case .avPlayer:
            return "AVPlayer"
        }
    }
}

enum PlayerPlaybackState: String, Sendable, Equatable {
    case preparing
    case buffering
    case playing
    case failed
}

enum PlayerEngineError: LocalizedError, Equatable {
    case invalidStreamURL(String)
    case startupTimeout(PlayerEngineKind)
    case initializationFailed(PlayerEngineKind, String)

    var errorDescription: String? {
        switch self {
        case .invalidStreamURL(let value):
            return "Invalid stream URL: \(value)"
        case .startupTimeout(let engine):
            return "\(engine.displayName) timed out before playback started."
        case .initializationFailed(let engine, let message):
            return "\(engine.displayName) failed: \(message)"
        }
    }
}

struct PreparedPlaybackSession {
    let engineKind: PlayerEngineKind
    let streamURL: URL
    let avPlayer: AVPlayer?
    let ksPlayerCoordinator: KSVideoPlayer.Coordinator?
    let ksOptions: KSOptions?
}

protocol PlayerEngine {
    var kind: PlayerEngineKind { get }
    func canHandle(stream: StreamInfo) -> Bool
    @MainActor func prepare(stream: StreamInfo) async throws -> PreparedPlaybackSession
}
