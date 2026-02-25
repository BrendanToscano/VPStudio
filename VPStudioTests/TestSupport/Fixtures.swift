import Foundation
@testable import VPStudio

enum Fixtures {
    static func stream(
        url: String = "https://cdn.example.com/video.mkv",
        quality: VideoQuality = .hd1080p,
        codec: VideoCodec = .h264,
        audio: AudioFormat = .aac,
        source: SourceType = .webDL,
        hdr: HDRFormat = .sdr,
        fileName: String = "video.mkv",
        sizeBytes: Int64? = 1_000,
        debridService: String = DebridServiceType.realDebrid.rawValue
    ) -> StreamInfo {
        StreamInfo(
            streamURL: URL(string: url)!,
            quality: quality,
            codec: codec,
            audio: audio,
            source: source,
            hdr: hdr,
            fileName: fileName,
            sizeBytes: sizeBytes,
            debridService: debridService
        )
    }

    static func torrent(
        hash: String,
        title: String,
        quality: VideoQuality = .hd1080p,
        codec: VideoCodec = .h264,
        audio: AudioFormat = .aac,
        source: SourceType = .webDL,
        hdr: HDRFormat = .sdr,
        seeders: Int = 10,
        cached: Bool = false,
        indexerName: String = "TestIndexer",
        sizeBytes: Int64 = 2_000
    ) -> TorrentResult {
        TorrentResult(
            infoHash: hash,
            title: title,
            sizeBytes: sizeBytes,
            seeders: seeders,
            leechers: 0,
            quality: quality,
            codec: codec,
            audio: audio,
            source: source,
            hdr: hdr,
            indexerName: indexerName,
            magnetURI: "magnet:?xt=urn:btih:\(hash)",
            isCached: cached,
            cachedOnService: cached ? DebridServiceType.realDebrid.rawValue : nil
        )
    }

    static func watchHistory(
        mediaId: String = "tt123",
        episodeId: String? = nil,
        title: String = "Title",
        streamURL: String? = "https://cdn.example.com/stream.m3u8",
        quality: String? = VideoQuality.hd1080p.rawValue,
        progress: Double = 100,
        duration: Double = 1000
    ) -> WatchHistory {
        WatchHistory(
            id: UUID().uuidString,
            mediaId: mediaId,
            episodeId: episodeId,
            title: title,
            progress: progress,
            duration: duration,
            quality: quality,
            debridService: DebridServiceType.realDebrid.rawValue,
            streamURL: streamURL,
            watchedAt: Date(),
            isCompleted: false
        )
    }

    static func mediaPreview(
        id: String = "movie-tmdb-1",
        type: MediaType = .movie,
        title: String = "Sample",
        year: Int? = 2024,
        tmdbId: Int? = 1
    ) -> MediaPreview {
        MediaPreview(
            id: id,
            type: type,
            title: title,
            year: year,
            posterPath: nil,
            imdbRating: nil,
            tmdbId: tmdbId
        )
    }

    static func indexerConfig(
        id: String = UUID().uuidString,
        name: String = "Indexer",
        type: IndexerConfig.IndexerType = .torznab,
        baseURL: String? = "https://indexer.example",
        apiKey: String? = "key",
        endpointPath: String? = nil,
        transport: IndexerConfig.APIKeyTransport? = nil
    ) -> IndexerConfig {
        IndexerConfig(
            id: id,
            name: name,
            indexerType: type,
            baseURL: baseURL,
            apiKey: apiKey,
            isActive: true,
            priority: 0,
            providerSubtype: nil,
            endpointPath: endpointPath,
            categoryFilter: nil,
            apiKeyTransport: transport
        )
    }
}
