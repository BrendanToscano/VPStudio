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
    private var persistedStreamURLStorage: String?
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
    var recoveryContextJSON: String?
    var expectedBytes: Int64?
    var resumeDataBase64: String?
    var createdAt: Date
    var updatedAt: Date

    var streamURL: String {
        get { persistedStreamURLStorage ?? "" }
        set { persistedStreamURLStorage = Self.normalizedStreamURL(newValue, status: status) }
    }

    var persistedStreamURL: String? {
        persistedStreamURLStorage
    }

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

    var recoveryContext: StreamRecoveryContext? {
        get {
            guard let json = recoveryContextJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(StreamRecoveryContext.self, from: data)
        }
        set {
            guard let value = newValue,
                  let data = try? JSONEncoder().encode(value) else {
                recoveryContextJSON = nil
                return
            }
            recoveryContextJSON = String(data: data, encoding: .utf8)
        }
    }

    var resumeData: Data? {
        get {
            guard let resumeDataBase64,
                  let data = Data(base64Encoded: resumeDataBase64) else { return nil }
            return data
        }
        set {
            resumeDataBase64 = Self.normalizedResumeDataBase64(
                newValue?.base64EncodedString(),
                status: status
            )
        }
    }

    enum Columns: String, ColumnExpression {
        case id, mediaId, episodeId, streamURL, fileName
        case status, progress, bytesWritten, totalBytes
        case destinationPath, errorMessage
        case mediaTitle, mediaType, posterPath
        case seasonNumber, episodeNumber, episodeTitle
        case recoveryContextJSON, expectedBytes, resumeDataBase64
        case createdAt, updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mediaId
        case episodeId
        case streamURL
        case fileName
        case status
        case progress
        case bytesWritten
        case totalBytes
        case destinationPath
        case errorMessage
        case mediaTitle
        case mediaType
        case posterPath
        case seasonNumber
        case episodeNumber
        case episodeTitle
        case recoveryContextJSON
        case expectedBytes
        case resumeDataBase64
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStatus = try container.decode(DownloadStatus.self, forKey: .status)
        let decodedProgress = try container.decode(Double.self, forKey: .progress)
        let decodedBytesWritten = try container.decode(Int64.self, forKey: .bytesWritten)
        let decodedTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes)
        let decodedExpectedBytes = try container.decodeIfPresent(Int64.self, forKey: .expectedBytes)

        id = try container.decode(String.self, forKey: .id)
        mediaId = try container.decode(String.self, forKey: .mediaId)
        episodeId = try container.decodeIfPresent(String.self, forKey: .episodeId)
        status = decodedStatus
        persistedStreamURLStorage = Self.normalizedStreamURL(
            try container.decodeIfPresent(String.self, forKey: .streamURL),
            status: decodedStatus
        )
        fileName = try container.decode(String.self, forKey: .fileName)
        progress = Self.normalizedProgress(for: decodedProgress, status: decodedStatus)
        bytesWritten = Self.normalizedByteCount(decodedBytesWritten) ?? 0
        totalBytes = Self.normalizedByteCount(decodedTotalBytes)
        destinationPath = try container.decodeIfPresent(String.self, forKey: .destinationPath)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        mediaTitle = try container.decode(String.self, forKey: .mediaTitle)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        seasonNumber = try container.decodeIfPresent(Int.self, forKey: .seasonNumber)
        episodeNumber = try container.decodeIfPresent(Int.self, forKey: .episodeNumber)
        episodeTitle = try container.decodeIfPresent(String.self, forKey: .episodeTitle)
        recoveryContextJSON = try container.decodeIfPresent(String.self, forKey: .recoveryContextJSON)
        expectedBytes = Self.normalizedByteCount(decodedExpectedBytes)
        resumeDataBase64 = Self.normalizedResumeDataBase64(
            try container.decodeIfPresent(String.self, forKey: .resumeDataBase64),
            status: decodedStatus
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        let sanitized = sanitizedForPersistence
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sanitized.id, forKey: .id)
        try container.encode(sanitized.mediaId, forKey: .mediaId)
        try container.encodeIfPresent(sanitized.episodeId, forKey: .episodeId)
        try container.encodeIfPresent(sanitized.persistedStreamURLStorage, forKey: .streamURL)
        try container.encode(sanitized.fileName, forKey: .fileName)
        try container.encode(sanitized.status, forKey: .status)
        try container.encode(sanitized.progress, forKey: .progress)
        try container.encode(sanitized.bytesWritten, forKey: .bytesWritten)
        try container.encodeIfPresent(sanitized.totalBytes, forKey: .totalBytes)
        try container.encodeIfPresent(sanitized.destinationPath, forKey: .destinationPath)
        try container.encodeIfPresent(sanitized.errorMessage, forKey: .errorMessage)
        try container.encode(sanitized.mediaTitle, forKey: .mediaTitle)
        try container.encode(sanitized.mediaType, forKey: .mediaType)
        try container.encodeIfPresent(sanitized.posterPath, forKey: .posterPath)
        try container.encodeIfPresent(sanitized.seasonNumber, forKey: .seasonNumber)
        try container.encodeIfPresent(sanitized.episodeNumber, forKey: .episodeNumber)
        try container.encodeIfPresent(sanitized.episodeTitle, forKey: .episodeTitle)
        try container.encodeIfPresent(sanitized.recoveryContextJSON, forKey: .recoveryContextJSON)
        try container.encodeIfPresent(sanitized.expectedBytes, forKey: .expectedBytes)
        try container.encodeIfPresent(sanitized.resumeDataBase64, forKey: .resumeDataBase64)
        try container.encode(sanitized.createdAt, forKey: .createdAt)
        try container.encode(sanitized.updatedAt, forKey: .updatedAt)
    }

    func encode(to container: inout PersistenceContainer) {
        let sanitized = sanitizedForPersistence
        container[Columns.id] = sanitized.id
        container[Columns.mediaId] = sanitized.mediaId
        container[Columns.episodeId] = sanitized.episodeId
        container[Columns.streamURL] = sanitized.persistedStreamURLStorage
        container[Columns.fileName] = sanitized.fileName
        container[Columns.status] = sanitized.status.rawValue
        container[Columns.progress] = sanitized.progress
        container[Columns.bytesWritten] = sanitized.bytesWritten
        container[Columns.totalBytes] = sanitized.totalBytes
        container[Columns.destinationPath] = sanitized.destinationPath
        container[Columns.errorMessage] = sanitized.errorMessage
        container[Columns.mediaTitle] = sanitized.mediaTitle
        container[Columns.mediaType] = sanitized.mediaType
        container[Columns.posterPath] = sanitized.posterPath
        container[Columns.seasonNumber] = sanitized.seasonNumber
        container[Columns.episodeNumber] = sanitized.episodeNumber
        container[Columns.episodeTitle] = sanitized.episodeTitle
        container[Columns.recoveryContextJSON] = sanitized.recoveryContextJSON
        container[Columns.expectedBytes] = sanitized.expectedBytes
        container[Columns.resumeDataBase64] = sanitized.resumeDataBase64
        container[Columns.createdAt] = sanitized.createdAt
        container[Columns.updatedAt] = sanitized.updatedAt
    }

    init(row: Row) {
        let decodedID: String? = row[Columns.id]
        let decodedMediaId: String? = row[Columns.mediaId]
        let decodedFileName = (row[Columns.fileName] as String?)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedStatusValue = (row[Columns.status] as String?) ?? DownloadStatus.queued.rawValue
        let parsedStatus = DownloadStatus(rawValue: parsedStatusValue) ?? .queued
        let parsedProgress = Self.normalizedProgress(for: Self.valueAsDouble(row[Columns.progress]), status: parsedStatus)
        let parsedBytesWritten = max(0, Self.valueAsInt64(row[Columns.bytesWritten]))
        let parsedStreamURL = Self.normalizedStreamURL(row[Columns.streamURL] as String?, status: parsedStatus)
        let parsedMediaTitle = (row[Columns.mediaTitle] as String?) ?? ""
        let parsedMediaType = (row[Columns.mediaType] as String?) ?? "movie"
        let parsedFileName = {
            if let decodedFileName, !decodedFileName.isEmpty {
                return decodedFileName
            }
            return "download-\(decodedID ?? UUID().uuidString).mp4"
        }()
        let parsedResumeData = Self.normalizedResumeDataBase64(row[Columns.resumeDataBase64] as String?, status: parsedStatus)
        let parsedExpectedBytes = Self.normalizedByteCount(row[Columns.expectedBytes] as Int64?)
        let parsedTotalBytes = Self.normalizedByteCount(row[Columns.totalBytes] as Int64?)
        let parsedDestinationPath = row[Columns.destinationPath] as String?
        let parsedErrorMessage = row[Columns.errorMessage] as String?
        let parsedEpisodeID: String? = row[Columns.episodeId]
        let parsedPosterPath: String? = row[Columns.posterPath]
        let parsedSeasonNumber: Int? = row[Columns.seasonNumber]
        let parsedEpisodeNumber: Int? = row[Columns.episodeNumber]
        let parsedEpisodeTitle: String? = row[Columns.episodeTitle]
        let parsedRecoveryContext: String? = row[Columns.recoveryContextJSON]
        let parsedCreatedAt = (row[Columns.createdAt] as Date?) ?? Date()
        let parsedUpdatedAt = (row[Columns.updatedAt] as Date?) ?? parsedCreatedAt

        id = decodedID ?? UUID().uuidString
        mediaId = decodedMediaId ?? ""
        episodeId = parsedEpisodeID
        persistedStreamURLStorage = parsedStreamURL
        fileName = parsedFileName
        status = parsedStatus
        progress = parsedProgress
        bytesWritten = parsedBytesWritten
        totalBytes = parsedTotalBytes
        destinationPath = parsedDestinationPath
        errorMessage = parsedErrorMessage
        mediaTitle = parsedMediaTitle
        mediaType = parsedMediaType
        posterPath = parsedPosterPath
        seasonNumber = parsedSeasonNumber
        episodeNumber = parsedEpisodeNumber
        episodeTitle = parsedEpisodeTitle
        recoveryContextJSON = parsedRecoveryContext
        expectedBytes = parsedExpectedBytes
        resumeDataBase64 = parsedResumeData
        createdAt = parsedCreatedAt
        updatedAt = parsedUpdatedAt
    }

    private static func valueAsDouble(_ value: DatabaseValueConvertible?) -> Double {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int64 {
            return Double(value)
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? Float {
            return Double(value)
        }
        return 0
    }

    private static func valueAsInt64(_ value: DatabaseValueConvertible?) -> Int64 {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        return 0
    }

    init(
        id: String = UUID().uuidString,
        mediaId: String,
        episodeId: String? = nil,
        streamURL: String? = nil,
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
        recoveryContextJSON: String? = nil,
        expectedBytes: Int64? = nil,
        resumeDataBase64: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.mediaId = mediaId
        self.episodeId = episodeId
        self.persistedStreamURLStorage = Self.normalizedStreamURL(streamURL, status: status)
        self.fileName = fileName
        self.status = status
        self.progress = Self.normalizedProgress(for: progress, status: status)
        self.bytesWritten = Self.normalizedByteCount(bytesWritten) ?? 0
        self.totalBytes = Self.normalizedByteCount(totalBytes)
        self.destinationPath = destinationPath
        self.errorMessage = errorMessage
        self.mediaTitle = mediaTitle
        self.mediaType = mediaType
        self.posterPath = posterPath
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.recoveryContextJSON = recoveryContextJSON
        self.expectedBytes = Self.normalizedByteCount(expectedBytes)
        self.resumeDataBase64 = Self.normalizedResumeDataBase64(resumeDataBase64, status: status)
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    var sanitizedForPersistence: DownloadTask {
        DownloadTask(
            id: id,
            mediaId: mediaId,
            episodeId: episodeId,
            streamURL: persistedStreamURLStorage,
            fileName: fileName,
            status: status,
            progress: progress,
            bytesWritten: bytesWritten,
            totalBytes: totalBytes,
            destinationPath: destinationPath,
            errorMessage: errorMessage,
            mediaTitle: mediaTitle,
            mediaType: mediaType,
            posterPath: posterPath,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle,
            recoveryContextJSON: recoveryContextJSON,
            expectedBytes: expectedBytes,
            resumeDataBase64: resumeDataBase64,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    var redactedForRecoveryBackedPersistence: DownloadTask {
        var redacted = sanitizedForPersistence
        redacted.persistedStreamURLStorage = nil
        redacted.resumeDataBase64 = nil
        return redacted
    }

    private static func normalizedStreamURL(_ raw: String?, status: DownloadStatus) -> String? {
        guard status != .completed else { return nil }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedProgress(for value: Double, status: DownloadStatus) -> Double {
        if status == .completed {
            return 1
        }
        return min(max(value, 0), 1)
    }

    private static func normalizedResumeDataBase64(_ raw: String?, status: DownloadStatus) -> String? {
        guard status != .completed else { return nil }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        guard Data(base64Encoded: trimmed) != nil else {
            return nil
        }
        return trimmed
    }

    private static func normalizedByteCount(_ value: Int64?) -> Int64? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
