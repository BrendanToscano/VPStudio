import Foundation

enum PlayerEngineStrategy: String, CaseIterable, Sendable, Identifiable {
    case adaptive
    case performance
    case compatibility

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adaptive:
            return "Adaptive"
        case .performance:
            return "Performance"
        case .compatibility:
            return "Compatibility"
        }
    }

    var summary: String {
        switch self {
        case .adaptive:
            return "Prefers AVPlayer and only uses KSPlayer first for clearly incompatible stream profiles."
        case .performance:
            return "Always try AVPlayer first for the lowest memory footprint and best system-level decoding."
        case .compatibility:
            #if os(visionOS)
            return "Uses AVPlayer first on visionOS for stability and power efficiency, with KSPlayer as fallback for edge formats."
            #else
            return "Always uses KSPlayer first for maximum container and codec compatibility. Recommended for most users."
            #endif
        }
    }
}

struct PlayerEngineSelector {
    func engineOrder(
        for stream: StreamInfo,
        strategy: PlayerEngineStrategy = .compatibility
    ) -> [PlayerEngineKind] {
        // MV-HEVC (native stereoscopic) must always use AVPlayer.
        // AVPlayer renders both eye views natively on visionOS; KSPlayer
        // cannot reproduce the stereoscopic presentation, so we return
        // AVPlayer as the sole engine with no fallback.
        if isMvHevc(stream) {
            return [.avPlayer]
        }

        switch strategy {
        case .compatibility:
            #if os(visionOS)
            // Keep AVPlayer first on visionOS for stability and power efficiency.
            // KSPlayer remains the fallback when AVPlayer cannot open the stream.
            return [.avPlayer, .ksPlayer]
            #else
            // Always KSPlayer first for maximum codec/container compatibility.
            return [.ksPlayer, .avPlayer]
            #endif
        case .performance:
            return [.avPlayer, .ksPlayer]
        case .adaptive:
            if shouldPreferNativePipeline(stream) {
                return [.avPlayer, .ksPlayer]
            }
            #if os(visionOS)
            return [.avPlayer, .ksPlayer]
            #else
            if streamNeedsCompatibilityDecodeAdaptive(stream) {
                return [.ksPlayer, .avPlayer]
            }
            return [.avPlayer, .ksPlayer]
            #endif
        }
    }

    private func streamNeedsCompatibilityDecodeLegacy(_ stream: StreamInfo) -> Bool {
        let ext = stream.streamURL.pathExtension.lowercased()
        let riskyExtensions: Set<String> = [
            "", "mkv", "avi", "wmv", "flv", "ts", "m2ts", "mpeg", "mpg", "webm"
        ]
        if riskyExtensions.contains(ext) {
            return true
        }

        if stream.codec == .av1 || stream.codec == .unknown {
            return true
        }

        let lower = stream.fileName.lowercased()
        let riskyTokens = ["remux", "truehd", "dts-hd", "dtshd", "dv", "dolby.vision", "hevc"]
        return riskyTokens.contains(where: { lower.contains($0) })
    }

    private func streamNeedsCompatibilityDecodeAdaptive(_ stream: StreamInfo) -> Bool {
        let ext = stream.streamURL.pathExtension.lowercased()
        let compatibilityExtensions: Set<String> = ["avi", "wmv", "flv", "ts", "m2ts", "mpeg", "mpg"]
        if compatibilityExtensions.contains(ext) {
            return true
        }

        if stream.codec == .unknown {
            return true
        }

        let lower = stream.fileName.lowercased()
        let highRiskTokens = ["xvid", "vc1", "realvideo", "rmvb"]
        return highRiskTokens.contains(where: { lower.contains($0) })
    }

    private func shouldPreferNativePipeline(_ stream: StreamInfo) -> Bool {
        if stream.hdr == .dolbyVision || stream.hdr == .hdr10Plus {
            return true
        }
        return isLikelySpatial(stream)
    }

    private func isLikelySpatial(_ stream: StreamInfo) -> Bool {
        SpatialVideoTitleDetector.stereoMode(fromTitle: stream.fileName) != .mono
    }

    /// Returns `true` when the stream has properties that AVPlayer on visionOS
    /// cannot handle natively, requiring KSPlayer (FFmpeg) as the primary engine.
    ///
    /// AVPlayer on visionOS handles: H.264, H.265/HEVC (all profiles incl. 10-bit),
    /// AV1 (visionOS 2.0+ / M2), AAC, AC3, EAC3 in MP4/MOV/fMP4/HLS containers.
    ///
    /// KSPlayer is needed for:
    /// - MKV container (AVPlayer cannot demux Matroska)
    /// - DTS / DTS-HD MA / TrueHD / Atmos-over-TrueHD audio
    /// - Legacy video codecs (MPEG-2, VP9, XviD/DivX)
    /// - Unknown codecs where we cannot predict AVPlayer compatibility
    private func streamRequiresKSPlayerOnVisionOS(_ stream: StreamInfo) -> Bool {
        // Container check: MKV, AVI, and other non-Apple containers need FFmpeg demuxing.
        let ext = stream.streamURL.pathExtension.lowercased()
        let ksPlayerContainers: Set<String> = ["mkv", "avi", "wmv", "flv", "webm"]
        if ksPlayerContainers.contains(ext) {
            return true
        }

        // Audio check: DTS variants and TrueHD require FFmpeg decoding.
        switch stream.audio {
        case .dts, .dtsHDMA, .trueHD, .atmos:
            return true
        default:
            break
        }

        // Codec check: legacy/unknown codecs need KSPlayer.
        switch stream.codec {
        case .xvid, .unknown:
            return true
        default:
            break
        }

        // Filename heuristics for codecs not captured by parsed metadata.
        let lower = stream.fileName.lowercased()
        let ksPlayerTokens = ["vc1", "mpeg2", "vp9", "realvideo", "rmvb", "xvid", "divx"]
        if ksPlayerTokens.contains(where: { lower.contains($0) }) {
            return true
        }

        return false
    }

    private func isMvHevc(_ stream: StreamInfo) -> Bool {
        SpatialVideoTitleDetector.stereoMode(
            fromTitle: stream.fileName,
            codecHint: stream.codec.rawValue
        ) == .mvHevc
    }
}

struct PlayerStreamFailoverPlanner {
    static func nextStream(after current: StreamInfo, in queue: [StreamInfo]) -> StreamInfo? {
        guard let currentIndex = queue.firstIndex(where: { $0.id == current.id }) else {
            return nil
        }
        let nextIndex = currentIndex + 1
        guard queue.indices.contains(nextIndex) else {
            return nil
        }
        return queue[nextIndex]
    }
}
