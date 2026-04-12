import Foundation

struct StreamRecoveryContext: Codable, Sendable, Equatable, Hashable {
    var infoHash: String
    var preferredService: DebridServiceType?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var torrentId: String?
    var resolvedDebridService: String?
    var resolvedFileName: String?
    var resolvedFileSizeBytes: Int64?

    init?(
        infoHash: String,
        preferredService: DebridServiceType? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        torrentId: String? = nil,
        resolvedDebridService: String? = nil,
        resolvedFileName: String? = nil,
        resolvedFileSizeBytes: Int64? = nil
    ) {
        let normalizedHash = infoHash
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedHash.isEmpty else { return nil }

        self.infoHash = normalizedHash
        self.preferredService = preferredService
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.torrentId = Self.normalizedOptionalString(torrentId)
        self.resolvedDebridService = Self.normalizedOptionalString(resolvedDebridService)
        self.resolvedFileName = Self.normalizedOptionalString(resolvedFileName)
        self.resolvedFileSizeBytes = Self.normalizedByteCount(resolvedFileSizeBytes)
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedByteCount(_ value: Int64?) -> Int64? {
        guard let value, value > 0 else { return nil }
        return value
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
    var remoteTransferID: String? {
        recoveryContext?.torrentId
    }

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

extension StreamRecoveryContext {
    func enrichedForDownloadPersistence(
        fileName: String,
        sizeBytes: Int64?,
        debridService: String
    ) -> StreamRecoveryContext {
        StreamRecoveryContext(
            infoHash: infoHash,
            preferredService: preferredService,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            torrentId: torrentId,
            resolvedDebridService: debridService,
            resolvedFileName: fileName,
            resolvedFileSizeBytes: sizeBytes
        ) ?? self
    }
}
