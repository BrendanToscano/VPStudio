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
            return "Always uses KSPlayer first for maximum container and codec compatibility. Recommended for most users."
        }
    }
}

struct PlayerEngineSelector {
    func engineOrder(
        for stream: StreamInfo,
        strategy: PlayerEngineStrategy = .compatibility
    ) -> [PlayerEngineKind] {
        switch strategy {
        case .compatibility:
            // Always KSPlayer first for maximum codec/container compatibility.
            return [.ksPlayer, .avPlayer]
        case .performance:
            return [.avPlayer, .ksPlayer]
        case .adaptive:
            if shouldPreferNativePipeline(stream) {
                return [.avPlayer, .ksPlayer]
            }
            if streamNeedsCompatibilityDecodeAdaptive(stream) {
                return [.ksPlayer, .avPlayer]
            }
            return [.avPlayer, .ksPlayer]
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
