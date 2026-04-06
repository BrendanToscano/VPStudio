import Foundation

struct StreamRecoveryContext: Codable, Sendable, Equatable, Hashable {
    var infoHash: String
    var preferredService: DebridServiceType?
    var seasonNumber: Int?
    var episodeNumber: Int?

    init?(
        infoHash: String,
        preferredService: DebridServiceType? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) {
        let normalizedHash = infoHash
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedHash.isEmpty else { return nil }

        self.infoHash = normalizedHash
        self.preferredService = preferredService
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}

struct StreamInfo: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id: String {
        "\(debridService)-\(fileName)-\(quality.rawValue)-\(codec.rawValue)-\(transportIdentity)"
    }

    var streamURL: URL
    var quality: VideoQuality
    var codec: VideoCodec
    var audio: AudioFormat
    var source: SourceType
    var hdr: HDRFormat
    var fileName: String
    var sizeBytes: Int64?
    var debridService: String
    var recoveryContext: StreamRecoveryContext?

    init(
        streamURL: URL,
        quality: VideoQuality,
        codec: VideoCodec,
        audio: AudioFormat,
        source: SourceType,
        hdr: HDRFormat,
        fileName: String,
        sizeBytes: Int64?,
        debridService: String,
        recoveryContext: StreamRecoveryContext? = nil
    ) {
        self.streamURL = streamURL
        self.quality = quality
        self.codec = codec
        self.audio = audio
        self.source = source
        self.hdr = hdr
        self.fileName = fileName
        self.sizeBytes = sizeBytes
        self.debridService = debridService
        self.recoveryContext = recoveryContext
    }

    func withRecoveryContext(_ recoveryContext: StreamRecoveryContext?) -> StreamInfo {
        var copy = self
        copy.recoveryContext = recoveryContext
        return copy
    }

    func withStreamURL(_ streamURL: URL) -> StreamInfo {
        var copy = self
        copy.streamURL = streamURL
        return copy
    }

    private var transportIdentity: String {
        guard var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else {
            return streamURL.absoluteString
        }

        components.query = nil
        components.fragment = nil

        if let normalizedURL = components.url {
            return normalizedURL.absoluteString
        }

        let normalizedString = components.string ?? ""
        return normalizedString.isEmpty ? streamURL.absoluteString : normalizedString
    }

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
