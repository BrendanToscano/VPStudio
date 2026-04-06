import AVFoundation
import CoreMedia
import Foundation

enum SpatialVideoTitleDetector {
    /// Infers the stereo/spatial mode from a media title or filename.
    static func stereoMode(fromTitle title: String) -> VPPlayerEngine.StereoMode {
        stereoMode(fromTitle: title, codecHint: nil)
    }

    /// Infers stereo/spatial mode using title/filename and optional codec metadata.
    /// A valid MV-HEVC codec hint always takes priority over title heuristics.
    static func stereoMode(fromTitle title: String, codecHint: String?) -> VPPlayerEngine.StereoMode {
        let lower = title.lowercased()

        if codecIndicatesMvHevc(codecHint) {
            return .mvHevc
        }

        // Side-by-side 3D
        if lower.contains("sbs")
            || lower.contains("side.by.side")
            || lower.contains("side-by-side")
            || lower.contains("sidebyside")
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

    private static func codecIndicatesMvHevc(_ codecHint: String?) -> Bool {
        guard let normalizedCodec = codecHint?.lowercased().replacingOccurrences(of: "_", with: "-") else {
            return false
        }
        let compacted = normalizedCodec.replacingOccurrences(of: "-", with: "")
        return compacted.contains("mv") && compacted.contains("hevc")
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

    // MARK: - AVAsset-based MV-HEVC Detection

    /// Inspects the video track's format descriptions for stereo eye view
    /// extensions, which are present in native MV-HEVC content. This is more
    /// reliable than title heuristics because it reads the actual container
    /// metadata written by Apple's spatial video pipeline.
    static func detectMVHEVC(from asset: AVAsset) async -> Bool {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return false
        }
        guard let descriptions = try? await videoTrack.load(.formatDescriptions) else {
            return false
        }
        for desc in descriptions {
            let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any]
            if let hasLeft = extensions?["HasLeftStereoEyeView"] as? Bool,
               let hasRight = extensions?["HasRightStereoEyeView"] as? Bool,
               hasLeft, hasRight {
                return true
            }
        }
        return false
    }
}
