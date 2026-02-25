import Foundation

enum PlayerSessionRouting {
    nonisolated static func sessionStreams(primary: StreamInfo, available: [StreamInfo]) -> [StreamInfo] {
        var seen = Set<String>()
        var routed: [StreamInfo] = []
        routed.reserveCapacity(available.count + 1)

        routed.append(primary)
        seen.insert(primary.id)

        for stream in available where !seen.contains(stream.id) {
            routed.append(stream)
            seen.insert(stream.id)
        }

        return routed
    }

    nonisolated static func playbackQueue(primary: StreamInfo, available: [StreamInfo]) async -> [StreamInfo] {
        let routed = sessionStreams(primary: primary, available: available)
        guard routed.count > 2 else { return routed }

        let fallback = Array(routed.dropFirst())
        let scoredFallback: [(StreamInfo, Int)] = await withTaskGroup(of: (StreamInfo, Int).self) { group in
            for stream in fallback {
                group.addTask {
                    (stream, fallbackScore(for: stream))
                }
            }

            var results: [(StreamInfo, Int)] = []
            results.reserveCapacity(fallback.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        let sortedFallback = scoredFallback.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.quality != rhs.0.quality { return lhs.0.quality > rhs.0.quality }
            let lhsSize = lhs.0.sizeBytes ?? 0
            let rhsSize = rhs.0.sizeBytes ?? 0
            if lhsSize != rhsSize { return lhsSize > rhsSize }
            return lhs.0.id < rhs.0.id
        }.map(\.0)

        return [primary] + sortedFallback
    }

    nonisolated private static func fallbackScore(for stream: StreamInfo) -> Int {
        var score = 0
        score += stream.quality.sortOrder * 140
        score += stream.source.qualityTier * 24

        switch stream.hdr {
        case .dolbyVision:
            score += 40
        case .hdr10Plus, .hdr10:
            score += 28
        case .hlg:
            score += 18
        case .sdr:
            break
        }

        if stream.audio.spatialAudioHint {
            score += 22
        }

        switch stream.codec {
        case .h265:
            score += 14
        case .h264:
            score += 10
        case .av1:
            score += 8
        case .xvid:
            score += 4
        case .unknown:
            break
        }

        if let bytes = stream.sizeBytes {
            let gigabytes = max(0, Int(bytes / 1_073_741_824))
            score += min(gigabytes * 3, 12)
        }

        return score
    }
}
