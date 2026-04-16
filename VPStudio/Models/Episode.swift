import Foundation
import GRDB

struct Episode: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "episodes"

    var id: String
    var mediaId: String
    var seasonNumber: Int
    var episodeNumber: Int
    var title: String?
    var overview: String?
    var airDate: String?
    var stillPath: String?
    var runtime: Int?

    var stillURL: URL? {
        guard let path = stillPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(path)")
    }

    var displayTitle: String {
        let epLabel = "S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber))"
        if let title = title, !title.isEmpty {
            return "\(epLabel) - \(title)"
        }
        return epLabel
    }

    var shortLabel: String {
        "S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber))"
    }

    enum Columns: String, ColumnExpression {
        case id, mediaId, seasonNumber, episodeNumber
        case title, overview, airDate, stillPath, runtime
    }
}

struct Season: Codable, Sendable, Identifiable, Equatable {
    var id: Int
    var seasonNumber: Int
    var name: String
    var overview: String?
    var posterPath: String?
    var episodeCount: Int
    var airDate: String?

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }
}
