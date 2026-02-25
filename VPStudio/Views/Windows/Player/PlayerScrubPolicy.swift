import Foundation

/// Pure-value policy governing scrub/seek behavior in the progress bar.
///
/// All thresholds and formatting decisions are testable constants and
/// static functions — the SwiftUI views call these rather than embedding
/// magic numbers directly.
enum PlayerScrubPolicy {

    // MARK: - Chapter Snap

    /// How close (as a fraction of total duration) the scrub position must
    /// be to a chapter boundary before we show a snap indicator.
    static let chapterSnapThresholdFraction: Double = 0.008

    /// Minimum absolute distance in seconds for snap detection.
    /// Prevents false snaps on very long content.
    static let chapterSnapMinimumSeconds: TimeInterval = 2.0

    /// Maximum absolute distance in seconds for snap detection.
    /// Prevents false snaps on very short content.
    static let chapterSnapMaximumSeconds: TimeInterval = 12.0

    /// Returns the chapter boundary time the scrub position is near,
    /// or `nil` if it is not close enough to any.
    static func nearestChapterSnap(
        scrubTime: TimeInterval,
        chapters: [ChapterBoundary],
        duration: TimeInterval
    ) -> TimeInterval? {
        guard duration > 0 else { return nil }
        let threshold = chapterSnapDistance(duration: duration)
        for chapter in chapters where chapter.startTime > 0 {
            if abs(scrubTime - chapter.startTime) <= threshold {
                return chapter.startTime
            }
        }
        return nil
    }

    /// Computes the snap distance in seconds, clamped between the min/max.
    static func chapterSnapDistance(duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return chapterSnapMinimumSeconds }
        let proportional = duration * chapterSnapThresholdFraction
        return max(chapterSnapMinimumSeconds, min(chapterSnapMaximumSeconds, proportional))
    }

    // MARK: - Fine vs Coarse Scrubbing

    /// Points-per-second drag velocity below which scrubbing is "fine".
    static let fineScrubVelocityThreshold: Double = 80.0

    /// In fine mode, the drag delta is scaled by this factor.
    static let fineScrubScale: Double = 0.25

    /// Determines the effective percent delta for a drag translation,
    /// taking drag velocity into account.
    ///
    /// - Parameters:
    ///   - translationX: Horizontal drag translation in points.
    ///   - velocityX: Horizontal drag velocity in points/second.
    ///   - barWidth: Width of the progress bar in points.
    /// - Returns: A percent delta (may be negative) to apply to the scrub position.
    static func scrubPercentDelta(
        translationX: Double,
        velocityX: Double,
        barWidth: Double
    ) -> Double {
        guard barWidth > 0 else { return 0 }
        let rawDelta = translationX / barWidth
        if abs(velocityX) < fineScrubVelocityThreshold {
            return rawDelta * fineScrubScale
        }
        return rawDelta
    }

    // MARK: - Preview Label

    /// Format string for the floating scrub preview label.
    /// Delegates to the standard `formattedDuration` extension.
    static func previewLabel(for time: TimeInterval) -> String {
        time.formattedDuration
    }

    /// Returns the chapter title at the given time, if any.
    static func previewChapterTitle(
        at time: TimeInterval,
        chapters: [ChapterBoundary]
    ) -> String? {
        chapters.last(where: { $0.startTime <= time })?.title
    }

    // MARK: - Supporting Types

    /// A lightweight chapter boundary for policy calculations, avoiding
    /// a hard dependency on VPPlayerEngine.ChapterInfo in this file.
    struct ChapterBoundary: Sendable {
        let startTime: TimeInterval
        let title: String
    }
}
