#if os(visionOS)
import SwiftUI

/// Subtitle text view rendered as a RealityKit SwiftUI attachment in immersive cinema mode.
///
/// Designed to be used inside a `RealityView` `attachments` closure. The parent
/// is responsible for positioning the resulting entity below the cinema screen.
struct ImmersiveSubtitleRenderer: View {
    let text: String
    let fontSize: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.85), radius: 4, x: 0, y: 2)
            .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: maxWidth)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Subtitle Sizing by Preset

extension ScreenSizePreset {
    /// Font size for 3D subtitles, scaled by viewing distance.
    var subtitleFontSize: CGFloat {
        switch self {
        case .personal: 36
        case .cinema:   60
        case .imax:     80
        }
    }

    /// Maximum subtitle width (80% of screen width), in points for the SwiftUI
    /// attachment. Because attachments are rendered at 1 point ≈ 1mm at arm's
    /// length, distant presets need proportionally larger widths.
    var subtitleMaxWidth: CGFloat {
        switch self {
        case .personal: 1200   // 80% of 6m ≈ 4.8m → ~1200pt at scale
        case .cinema:   2000   // 80% of 10m
        case .imax:     3200   // 80% of 16m
        }
    }

    /// Vertical offset (meters) below the screen center for subtitle placement.
    /// Calculated as: (height / 2) + small gap so subtitles sit just below the
    /// bottom edge of the cinema screen.
    var subtitleVerticalOffset: Float {
        let halfHeight = height / 2
        let gap: Float = 0.15  // 15 cm below screen edge
        return halfHeight + gap
    }
}
#endif
