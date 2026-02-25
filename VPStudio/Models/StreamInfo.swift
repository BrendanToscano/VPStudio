import Foundation

struct StreamInfo: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id: String { "\(debridService)-\(fileName)-\(quality.rawValue)-\(codec.rawValue)" }

    var streamURL: URL
    var quality: VideoQuality
    var codec: VideoCodec
    var audio: AudioFormat
    var source: SourceType
    var hdr: HDRFormat
    var fileName: String
    var sizeBytes: Int64?
    var debridService: String

    var sizeString: String {
        guard let bytes = sizeBytes else { return "" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    var qualityBadge: String {
        var parts: [String] = []
        if quality != .unknown { parts.append(quality.rawValue) }
        if hdr != .sdr { parts.append(hdr.rawValue) }
        if codec != .unknown { parts.append(codec.rawValue) }
        if audio != .unknown { parts.append(audio.rawValue) }
        return parts.joined(separator: " / ")
    }
}
