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
}
