import Foundation

/// Pure-value policy for gesture-based interactions on the player surface.
///
/// Keeps all threshold magic numbers out of the view layer and makes
/// gesture decisions testable.
enum PlayerGesturePolicy {

    // MARK: - Double-Tap to Seek

    /// The maximum time between two taps to count as a double-tap, in seconds.
    static let doubleTapMaxInterval: TimeInterval = 0.35

    /// Seek offset applied when double-tapping the left half.
    static let doubleTapSeekBackSeconds: TimeInterval = -10

    /// Seek offset applied when double-tapping the right half.
    static let doubleTapSeekForwardSeconds: TimeInterval = 30

    /// The fraction of the player surface width that defines the
    /// left/right tap zones. The center dead zone is excluded.
    static let doubleTapZoneFraction: Double = 0.35

    /// Determines the seek offset for a double-tap at a given x position.
    ///
    /// - Parameters:
    ///   - tapX: The x-coordinate of the tap in the player surface.
    ///   - surfaceWidth: The total width of the player surface.
    /// - Returns: The seek offset, or `nil` if the tap is in the center dead zone.
    static func doubleTapSeekOffset(
        tapX: Double,
        surfaceWidth: Double
    ) -> TimeInterval? {
        guard surfaceWidth > 0 else { return nil }
        let fraction = tapX / surfaceWidth
        if fraction <= doubleTapZoneFraction {
            return doubleTapSeekBackSeconds
        } else if fraction >= (1 - doubleTapZoneFraction) {
            return doubleTapSeekForwardSeconds
        }
        return nil // Center dead zone
    }

    // MARK: - Seek Feedback Direction

    /// Indicates the visual direction for a seek animation.
    enum SeekDirection: Sendable, Equatable {
        case backward
        case forward
    }

    /// The direction implied by a seek offset.
    static func seekDirection(for offset: TimeInterval) -> SeekDirection {
        offset < 0 ? .backward : .forward
    }

    // MARK: - Swipe Gesture Thresholds

    /// Minimum vertical distance (in points) for a swipe gesture to register.
    static let swipeMinimumDistance: Double = 30.0

    /// Maximum horizontal distance allowed during a vertical swipe
    /// (prevents diagonal swipes from triggering volume/brightness).
    static let swipeMaxHorizontalDeviation: Double = 40.0
}
