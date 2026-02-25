import Foundation

struct TorrentResult: Codable, Sendable, Identifiable, Equatable {
    var id: String { "\(infoHash)-\(indexerName)" }

    var infoHash: String
    var title: String
    var sizeBytes: Int64
    var seeders: Int
    var leechers: Int
    var quality: VideoQuality
    var codec: VideoCodec
    var audio: AudioFormat
    var source: SourceType
    var hdr: HDRFormat
    var indexerName: String
    var magnetURI: String?

    var isCached: Bool = false
    var cachedOnService: String?

    var sizeString: String {
        let gb = Double(sizeBytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(sizeBytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    var qualityBadge: String {
        var parts: [String] = []
        if quality != .unknown { parts.append(quality.rawValue) }
        if hdr != .sdr { parts.append(hdr.rawValue) }
        if codec != .unknown { parts.append(codec.rawValue) }
        if audio != .unknown { parts.append(audio.rawValue) }
        if source != .unknown { parts.append(source.rawValue) }
        return parts.joined(separator: " / ")
    }

    static func fromSearch(
        infoHash: String,
        title: String,
        sizeBytes: Int64,
        seeders: Int,
        leechers: Int,
        indexerName: String,
        magnetURI: String? = nil
    ) -> TorrentResult {
        TorrentResult(
            infoHash: infoHash.lowercased(),
            title: title,
            sizeBytes: sizeBytes,
            seeders: seeders,
            leechers: leechers,
            quality: VideoQuality.parse(from: title),
            codec: VideoCodec.parse(from: title),
            audio: AudioFormat.parse(from: title),
            source: SourceType.parse(from: title),
            hdr: HDRFormat.parse(from: title),
            indexerName: indexerName,
            magnetURI: magnetURI
        )
    }
}
