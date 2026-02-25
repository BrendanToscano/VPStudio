import Foundation

enum SpatialVideoTitleDetector {
    /// Infers the stereo/spatial mode from a media title or filename.
    static func stereoMode(fromTitle title: String) -> VPPlayerEngine.StereoMode {
        let lower = title.lowercased()

        // Side-by-side 3D
        if lower.contains("sbs")
            || lower.contains("side.by.side")
            || lower.contains("side-by-side")
            || lower.contains("half-sbs")
            || lower.containsStandaloneToken("hsbs") {
            return .sideBySide
        }

        // Over-under 3D
        if lower.contains("over.under")
            || lower.contains("over-under")
            || lower.containsStandaloneToken("ou")
            || lower.containsStandaloneToken("hou")
            || lower.containsStandaloneToken("tab") {
            return .overUnder
        }

        // Apple MV-HEVC / visionOS spatial video
        if lower.contains("mv-hevc") || lower.contains("spatial") {
            return .mvHevc
        }

        // 180° VR
        if lower.containsStandaloneToken("180"),
           lower.contains("vr") || lower.containsStandaloneToken("3d") {
            return .sphere180
        }

        // 360° VR
        if is360VideoTitle(lower) {
            return .sphere360
        }

        return .mono
    }

    private static func is360VideoTitle(_ loweredTitle: String) -> Bool {
        if loweredTitle.contains("360vr")
            || loweredTitle.contains("360 video")
            || loweredTitle.contains("360-video")
            || loweredTitle.contains("360°") {
            return true
        }

        guard loweredTitle.containsStandaloneToken("360") else { return false }
        return !loweredTitle.containsStandaloneToken("360p")
    }
}
