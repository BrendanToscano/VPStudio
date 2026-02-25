import Foundation
import GRDB

enum DownloadStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case resolving
    case downloading
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

struct DownloadTask: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "download_tasks"

    var id: String
    var mediaId: String
    var episodeId: String?
    var streamURL: String
    var fileName: String
    var status: DownloadStatus
    var progress: Double
    var bytesWritten: Int64
    var totalBytes: Int64?
    var destinationPath: String?
    var errorMessage: String?
    var mediaTitle: String
    var mediaType: String
    var posterPath: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var createdAt: Date
    var updatedAt: Date

    var destinationURL: URL? {
        guard let destinationPath else { return nil }
        return URL(fileURLWithPath: destinationPath)
    }

    var displayTitle: String {
        if let s = seasonNumber, let e = episodeNumber {
            let epLabel = "S\(String(format: "%02d", s))E\(String(format: "%02d", e))"
            if let epTitle = episodeTitle, !epTitle.isEmpty {
                return "\(epLabel) - \(epTitle)"
            }
            return epLabel
        }
        return mediaTitle.isEmpty ? fileName : mediaTitle
    }

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }

    var episodeSortKey: Int {
        (seasonNumber ?? 0) * 10000 + (episodeNumber ?? 0)
    }

    enum Columns: String, ColumnExpression {
        case id, mediaId, episodeId, streamURL, fileName
        case status, progress, bytesWritten, totalBytes
        case destinationPath, errorMessage
        case mediaTitle, mediaType, posterPath
        case seasonNumber, episodeNumber, episodeTitle
        case createdAt, updatedAt
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.mediaId] = mediaId
        container[Columns.episodeId] = episodeId
        container[Columns.streamURL] = streamURL
        container[Columns.fileName] = fileName
        container[Columns.status] = status.rawValue
        container[Columns.progress] = progress
        container[Columns.bytesWritten] = bytesWritten
        container[Columns.totalBytes] = totalBytes
        container[Columns.destinationPath] = destinationPath
        container[Columns.errorMessage] = errorMessage
        container[Columns.mediaTitle] = mediaTitle
        container[Columns.mediaType] = mediaType
        container[Columns.posterPath] = posterPath
        container[Columns.seasonNumber] = seasonNumber
        container[Columns.episodeNumber] = episodeNumber
        container[Columns.episodeTitle] = episodeTitle
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }

    init(row: Row) {
        id = row[Columns.id]
        mediaId = row[Columns.mediaId]
        episodeId = row[Columns.episodeId]
        streamURL = row[Columns.streamURL]
        fileName = row[Columns.fileName]
        status = DownloadStatus(rawValue: row[Columns.status]) ?? .queued
        progress = row[Columns.progress]
        bytesWritten = row[Columns.bytesWritten]
        totalBytes = row[Columns.totalBytes]
        destinationPath = row[Columns.destinationPath]
        errorMessage = row[Columns.errorMessage]
        mediaTitle = row[Columns.mediaTitle]
        mediaType = row[Columns.mediaType]
        posterPath = row[Columns.posterPath]
        seasonNumber = row[Columns.seasonNumber]
        episodeNumber = row[Columns.episodeNumber]
        episodeTitle = row[Columns.episodeTitle]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    init(
        id: String = UUID().uuidString,
        mediaId: String,
        episodeId: String? = nil,
        streamURL: String,
        fileName: String,
        status: DownloadStatus = .queued,
        progress: Double = 0,
        bytesWritten: Int64 = 0,
        totalBytes: Int64? = nil,
        destinationPath: String? = nil,
        errorMessage: String? = nil,
        mediaTitle: String = "",
        mediaType: String = "movie",
        posterPath: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mediaId = mediaId
        self.episodeId = episodeId
        self.streamURL = streamURL
        self.fileName = fileName
        self.status = status
        self.progress = progress
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
        self.destinationPath = destinationPath
        self.errorMessage = errorMessage
        self.mediaTitle = mediaTitle
        self.mediaType = mediaType
        self.posterPath = posterPath
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
