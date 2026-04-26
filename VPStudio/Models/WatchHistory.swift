import Foundation
import GRDB

struct WatchHistory: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "watch_history"

    var id: String
    var mediaId: String
    var episodeId: String?
    var title: String
    var progress: Double
    var duration: Double
    var quality: String?
    var debridService: String?
    var streamURL: String?
    var watchedAt: Date
    var isCompleted: Bool

    var progressPercent: Double {
        guard duration > 0 else { return 0 }
        return min(progress / duration, 1.0)
    }

    var progressString: String {
        let progressMin = Int(progress) / 60
        let durationMin = Int(duration) / 60
        return "\(progressMin)m / \(durationMin)m"
    }

    var remainingString: String {
        let remaining = max(duration - progress, 0)
        let min = Int(remaining) / 60
        return "\(min)m remaining"
    }

    enum Columns: String, ColumnExpression {
        case id, mediaId, episodeId, title, progress, duration
        case quality, debridService, streamURL, watchedAt, isCompleted
    }

    init(
        id: String,
        mediaId: String,
        episodeId: String? = nil,
        title: String,
        progress: Double,
        duration: Double,
        quality: String? = nil,
        debridService: String? = nil,
        streamURL: String? = nil,
        watchedAt: Date,
        isCompleted: Bool
    ) {
        let normalizedDuration = Self.normalizedDuration(duration)
        let normalizedProgress = Self.normalizedProgress(progress, duration: normalizedDuration)

        self.id = id
        self.mediaId = mediaId
        self.episodeId = episodeId
        self.title = title
        self.progress = normalizedProgress
        self.duration = normalizedDuration
        self.quality = Self.normalizedOptionalString(quality)
        self.debridService = Self.normalizedOptionalString(debridService)
        self.streamURL = Self.normalizedOptionalString(streamURL)
        self.watchedAt = watchedAt
        self.isCompleted = isCompleted
    }

    init(row: Row) {
        let decodedDuration = (row[Columns.duration] as Double?) ?? 0

        id = (row[Columns.id] as String?) ?? UUID().uuidString
        mediaId = (row[Columns.mediaId] as String?) ?? ""
        episodeId = row[Columns.episodeId]
        title = (row[Columns.title] as String?) ?? ""
        duration = Self.normalizedDuration(decodedDuration)
        progress = Self.normalizedProgress((row[Columns.progress] as Double?) ?? 0, duration: duration)
        quality = Self.normalizedOptionalString(row[Columns.quality] as String?)
        debridService = Self.normalizedOptionalString(row[Columns.debridService] as String?)
        streamURL = Self.normalizedOptionalString(row[Columns.streamURL] as String?)
        watchedAt = Self.valueAsDate(row[Columns.watchedAt.rawValue])
        isCompleted = Self.valueAsBool(row[Columns.isCompleted.rawValue])
    }

    func encode(to container: inout PersistenceContainer) {
        let normalized = normalizedForPersistence
        container[Columns.id] = normalized.id
        container[Columns.mediaId] = normalized.mediaId
        container[Columns.episodeId] = normalized.episodeId
        container[Columns.title] = normalized.title
        container[Columns.progress] = normalized.progress
        container[Columns.duration] = normalized.duration
        container[Columns.quality] = normalized.quality
        container[Columns.debridService] = normalized.debridService
        container[Columns.streamURL] = normalized.streamURL
        container[Columns.watchedAt] = normalized.watchedAt
        container[Columns.isCompleted] = normalized.isCompleted
    }

    var normalizedForPersistence: WatchHistory {
        WatchHistory(
            id: id,
            mediaId: mediaId,
            episodeId: episodeId,
            title: title,
            progress: progress,
            duration: duration,
            quality: quality,
            debridService: debridService,
            streamURL: streamURL,
            watchedAt: watchedAt,
            isCompleted: isCompleted
        )
    }

    private static func normalizedDuration(_ duration: Double) -> Double {
        max(duration, 0)
    }

    private static func normalizedProgress(_ progress: Double, duration: Double) -> Double {
        let normalizedProgress = max(progress, 0)
        guard duration > 0 else { return normalizedProgress }
        return min(normalizedProgress, duration)
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func valueAsDate(_ value: (any DatabaseValueConvertible)?) -> Date {
        guard let value else { return Date() }
        return Date.fromDatabaseValue(value.databaseValue) ?? Date()
    }

    private static func valueAsBool(_ value: (any DatabaseValueConvertible)?) -> Bool {
        guard let value else { return false }
        return Bool.fromDatabaseValue(value.databaseValue) ?? false
    }
}
