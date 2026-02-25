import AVFoundation
import CoreGraphics
import Foundation

// MARK: - Aspect Ratio Selection

/// User-selectable aspect ratio presets for the player window.
///
/// - ``auto``: Locks the window to the video's native aspect ratio (detected
///   from the video track). Falls back to 16:9 until the ratio is detected.
/// - Fixed presets (``sixteenByNine``, ``twentyOneByNine``, ``fourByThree``):
///   Lock the window to the specified ratio.
/// - ``freeform``: Unlocks the window aspect ratio completely. The user can
///   drag the window to any shape.
///
/// Auto and fixed presets use `.resizeAspectFill` for edge-to-edge display.
/// Freeform uses `.resizeAspect` with letterboxing for the full frame.
enum AspectRatioSelection: String, CaseIterable, Sendable, Identifiable {
    case auto = "Auto (Native)"
    case sixteenByNine = "16:9"
    case twentyOneByNine = "21:9"
    case fourByThree = "4:3"
    case freeform = "Freeform"

    var id: String { rawValue }

    /// Human-readable label for display in menus.
    var label: String { rawValue }

    /// SF Symbol icon for each selection.
    var icon: String {
        switch self {
        case .auto: return "rectangle.arrowtriangle.2.inward"
        case .sixteenByNine: return "rectangle"
        case .twentyOneByNine: return "aspectratio"
        case .fourByThree: return "rectangle.portrait"
        case .freeform: return "rectangle.dashed"
        }
    }

    /// Whether this selection locks the window to a fixed aspect ratio.
    /// Only ``freeform`` allows arbitrary window shapes.
    var locksWindowRatio: Bool {
        self != .freeform
    }
}

// MARK: - Aspect Ratio Policy

/// Pure, testable logic for resolving aspect ratio values from user selection
/// and detected video dimensions.
enum PlayerAspectRatioPolicy {

    /// The canonical 16:9 fallback used when no video dimensions are detected.
    static let defaultRatio: CGFloat = 16.0 / 9.0

    /// Resolves a concrete aspect ratio (width / height) for the given selection.
    ///
    /// - Parameters:
    ///   - selection: The user's chosen aspect ratio preset.
    ///   - detectedRatio: The native video aspect ratio detected from the player,
    ///     expressed as width / height. Pass `nil` if not yet detected.
    /// - Returns: A positive `CGFloat` when the window should be locked to
    ///   that ratio, or `nil` when the window aspect ratio should be unlocked
    ///   (freeform mode).
    static func resolvedRatio(
        for selection: AspectRatioSelection,
        detectedRatio: CGFloat?
    ) -> CGFloat? {
        switch selection {
        case .auto:
            return detectedRatio ?? defaultRatio
        case .sixteenByNine:
            return 16.0 / 9.0
        case .twentyOneByNine:
            return 21.0 / 9.0
        case .fourByThree:
            return 4.0 / 3.0
        case .freeform:
            return nil
        }
    }

    /// Returns the appropriate `AVLayerVideoGravity` for the given selection.
    ///
    /// - Auto and fixed presets use `.resizeAspectFill` for edge-to-edge
    ///   presentation with no black bars.
    /// - Freeform uses `.resizeAspect` to show the full frame with
    ///   letterboxing/pillarboxing as needed.
    static func videoGravity(for selection: AspectRatioSelection) -> AVLayerVideoGravity {
        switch selection {
        case .freeform:
            return .resizeAspect
        case .auto, .sixteenByNine, .twentyOneByNine, .fourByThree:
            return .resizeAspectFill
        }
    }

    /// Converts a `CGSize` (video track natural size) into a width/height ratio.
    /// Returns `nil` if the size is zero or degenerate.
    static func ratio(from size: CGSize) -> CGFloat? {
        guard size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }

    /// Produces an `NSSize`-compatible (width, height) pair suitable for
    /// `NSWindow.contentAspectRatio`. The pair preserves the ratio at a
    /// convenient integer scale. Returns `nil` when the ratio is `nil`
    /// (freeform mode), meaning the window aspect ratio should be unlocked.
    static func windowAspectSize(for ratio: CGFloat?) -> (width: CGFloat, height: CGFloat)? {
        guard let ratio else { return nil }
        // Use a denominator of 9 as the base to get clean integer values
        // for common ratios (16:9, 21:9, etc.)
        let height: CGFloat = 9
        let width = ratio * height
        return (width: width, height: height)
    }
}
