import Foundation

/// Pure-value policy governing when transport controls auto-hide and reappear.
///
/// All timing and decision logic is testable through static functions.
enum PlayerControlVisibilityPolicy {

    // MARK: - Timing

    /// How long after the last interaction before controls auto-hide, in seconds.
    static let autoHideDelay: TimeInterval = 10.0

    /// The opacity-fade animation duration when controls hide, in seconds.
    static let fadeOutDuration: Double = 0.35

    /// The opacity-fade animation duration when controls reappear, in seconds.
    static let fadeInDuration: Double = 0.22

    // MARK: - Auto-Hide Guards

    /// Determines whether controls should auto-hide given the current state.
    ///
    /// Returns `true` only when playback is active, the player is actively
    /// playing (not paused), and no modal interactions (scrubbing, pickers,
    /// lock) are preventing dismissal.
    static func shouldAutoHide(
        playbackState: PlayerPlaybackState,
        isPlaying: Bool,
        isScrubbing: Bool,
        isShowingSubtitlePicker: Bool,
        isShowingAudioPicker: Bool,
        isControlsLocked: Bool
    ) -> Bool {
        guard playbackState == .playing else { return false }
        guard isPlaying else { return false }
        guard !isScrubbing else { return false }
        guard !isShowingSubtitlePicker && !isShowingAudioPicker else { return false }
        guard !isControlsLocked else { return false }
        return true
    }

    // MARK: - Reappear Triggers

    /// The set of events that should cause controls to reappear.
    enum ReappearTrigger: String, CaseIterable, Sendable {
        case tap
        case pointerMovement
        case keyboardShortcut
        case seekAction
    }

    /// Returns whether a given trigger should cause controls to show.
    /// Currently all triggers are valid; this exists to let us selectively
    /// disable triggers in the future (e.g., during a cinematic intro).
    static func shouldReappear(for trigger: ReappearTrigger) -> Bool {
        true
    }
}
