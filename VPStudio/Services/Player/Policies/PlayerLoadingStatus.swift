import Foundation

/// Describes the current phase of the player loading lifecycle.
///
/// Each phase carries a user-friendly status message that the loading overlay
/// displays alongside the spinner. The phases progress linearly through
/// connection, buffering, and video preparation, with optional detours for
/// engine failover or stream retry before reaching `.ready` or `.failed`.
enum PlayerLoadingPhase: Sendable, Equatable {
    /// Initial connection to the stream server.
    case connecting

    /// Receiving data and building the playback buffer.
    case buffering

    /// Decoding first frames and preparing the video pipeline.
    case preparingVideo

    /// AVPlayer could not handle this stream; switching to KSPlayer.
    case switchingEngine

    /// Trying an alternate stream URL from the queue.
    case retryingStream

    /// Playback is about to start (briefly shown, then fades out).
    case ready

    /// Terminal failure with a user-facing message.
    case failed(String)

    // MARK: - Status Message

    /// A user-friendly status line for the loading overlay.
    var statusMessage: String {
        switch self {
        case .connecting:
            return "Connecting to stream\u{2026}"
        case .buffering:
            return "Buffering video data\u{2026}"
        case .preparingVideo:
            return "Preparing video\u{2026}"
        case .switchingEngine:
            return "Switching to alternate player engine\u{2026}"
        case .retryingStream:
            return "Trying next stream\u{2026}"
        case .ready:
            return "Starting playback"
        case .failed(let message):
            return message.isEmpty ? "Playback failed" : message
        }
    }

    // MARK: - Engine Failover Detail

    /// An extended explanation shown during engine failover so the user
    /// understands why the switch is happening. Returns `nil` for phases
    /// that don't need extra context.
    var failoverExplanation: String? {
        switch self {
        case .switchingEngine:
            return "The primary player could not handle this format. Switching to KSPlayer for better compatibility with this stream."
        default:
            return nil
        }
    }

    // MARK: - Phase Classification

    /// Whether this phase represents an active loading state (overlay visible).
    var isLoading: Bool {
        switch self {
        case .connecting, .buffering, .preparingVideo, .switchingEngine, .retryingStream:
            return true
        case .ready, .failed:
            return false
        }
    }

    /// Whether this phase is a terminal state.
    var isTerminal: Bool {
        switch self {
        case .ready, .failed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Phase Transition Validation

extension PlayerLoadingPhase {
    /// The set of phases that can legally follow this phase.
    ///
    /// Used by tests to verify the state machine doesn't make impossible jumps.
    var validNextPhases: Set<PlayerLoadingPhaseKind> {
        switch self {
        case .connecting:
            return [.buffering, .preparingVideo, .switchingEngine, .retryingStream, .failed]
        case .buffering:
            return [.preparingVideo, .switchingEngine, .retryingStream, .ready, .failed]
        case .preparingVideo:
            return [.ready, .switchingEngine, .failed]
        case .switchingEngine:
            return [.connecting, .buffering, .preparingVideo, .retryingStream, .ready, .failed]
        case .retryingStream:
            return [.connecting, .buffering, .preparingVideo, .switchingEngine, .ready, .failed]
        case .ready:
            return []
        case .failed:
            return [.connecting]
        }
    }

    /// Simplified kind for set-based transition checks (strips associated values).
    var kind: PlayerLoadingPhaseKind {
        switch self {
        case .connecting: return .connecting
        case .buffering: return .buffering
        case .preparingVideo: return .preparingVideo
        case .switchingEngine: return .switchingEngine
        case .retryingStream: return .retryingStream
        case .ready: return .ready
        case .failed: return .failed
        }
    }
}

/// Value-type mirror of `PlayerLoadingPhase` without associated values,
/// used for transition-table lookups.
enum PlayerLoadingPhaseKind: Hashable, Sendable {
    case connecting
    case buffering
    case preparingVideo
    case switchingEngine
    case retryingStream
    case ready
    case failed
}
