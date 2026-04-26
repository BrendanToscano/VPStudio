import Foundation

struct PlayerControlPresentation: Equatable {
    let symbolName: String
    let label: String
    let accessibilityValue: String
}

enum PlayerPlayPauseControlState: Equatable, Sendable {
    case playing
    case paused
    case buffering
    case preparing
    case failed

    static func from(
        playbackState: PlayerPlaybackState,
        isCurrentlyPlaying: Bool
    ) -> PlayerPlayPauseControlState {
        switch playbackState {
        case .preparing:
            return .preparing
        case .buffering:
            return .buffering
        case .playing:
            return isCurrentlyPlaying ? .playing : .paused
        case .failed:
            return .failed
        }
    }
}

enum PlayerControlPresentationMapper {
    static func playPause(
        playbackState: PlayerPlaybackState,
        isCurrentlyPlaying: Bool
    ) -> PlayerControlPresentation {
        let state = PlayerPlayPauseControlState.from(
            playbackState: playbackState,
            isCurrentlyPlaying: isCurrentlyPlaying
        )
        return playPause(for: state)
    }

    static func playPause(for state: PlayerPlayPauseControlState) -> PlayerControlPresentation {
        switch state {
        case .playing:
            return PlayerControlPresentation(
                symbolName: "pause.fill",
                label: "Pause",
                accessibilityValue: "Playing"
            )
        case .paused:
            return PlayerControlPresentation(
                symbolName: "play.fill",
                label: "Play",
                accessibilityValue: "Paused"
            )
        case .buffering:
            return PlayerControlPresentation(
                symbolName: "play.fill",
                label: "Play",
                accessibilityValue: "Buffering"
            )
        case .preparing:
            return PlayerControlPresentation(
                symbolName: "play.fill",
                label: "Play",
                accessibilityValue: "Preparing"
            )
        case .failed:
            return PlayerControlPresentation(
                symbolName: "play.fill",
                label: "Play",
                accessibilityValue: "Failed"
            )
        }
    }
}
