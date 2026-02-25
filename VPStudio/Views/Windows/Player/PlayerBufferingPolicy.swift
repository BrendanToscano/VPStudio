import Foundation

/// Pure-value policy for buffering display and quality-change toasts.
///
/// Centralizes text formatting and timing decisions that would otherwise
/// be scattered across view code.
enum PlayerBufferingPolicy {

    // MARK: - Buffering Text

    /// Produces the display text for the mid-playback rebuffer pill.
    ///
    /// - Parameter bufferedPercent: The current buffered fraction (0...1).
    /// - Returns: A user-facing string like "Buffering... 60%" or "Rebuffering...".
    static func rebufferText(bufferedPercent: Double) -> String {
        if bufferedPercent > 0 && bufferedPercent < 1 {
            let pct = Int(bufferedPercent * 100)
            return "Buffering... \(pct)%"
        }
        return "Rebuffering\u{2026}"
    }

    // MARK: - Quality Change Toast

    /// Duration in seconds the quality-change toast remains visible.
    static let qualityToastDuration: TimeInterval = 3.0

    /// Formats the quality-change toast message.
    ///
    /// - Parameters:
    ///   - from: The previous quality string (e.g. "1080p").
    ///   - to: The new quality string (e.g. "4K").
    /// - Returns: A display string, or `nil` if the quality hasn't changed.
    static func qualityChangeMessage(from: String, to: String) -> String? {
        guard from != to else { return nil }
        return "Quality: \(from) \u{2192} \(to)"
    }

    // MARK: - Controls Lock

    /// Whether the controls-lock toggle should be shown.
    /// Always true on visionOS (accessibility); optional on macOS.
    static var showsControlsLock: Bool {
        #if os(visionOS)
        true
        #else
        true
        #endif
    }
}
