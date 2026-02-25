import Foundation
import GRDB

struct MediaItem: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "media_cache"

    var id: String
    var type: MediaType
    var title: String
    var year: Int?
    var posterPath: String?
    var backdropPath: String?
    var overview: String?
    var genres: [String]
    var imdbRating: Double?
    var runtime: Int?
    var status: String?
    var tmdbId: Int?
    var lastFetched: Date?

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/original\(path)")
    }

    var yearString: String {
        year.map(String.init) ?? ""
    }

    var ratingString: String {
        guard let rating = imdbRating else { return "" }
        return String(format: "%.1f", rating)
    }

    var runtimeString: String {
        guard let runtime = runtime else { return "" }
        let hours = runtime / 60
        let minutes = runtime % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    enum Columns: String, ColumnExpression {
        case id, type, title, year, posterPath, backdropPath
        case overview, genres, imdbRating, runtime, status, tmdbId, lastFetched
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.type] = type.rawValue
        container[Columns.title] = title
        container[Columns.year] = year
        container[Columns.posterPath] = posterPath
        container[Columns.backdropPath] = backdropPath
        container[Columns.overview] = overview
        container[Columns.genres] = try? JSONEncoder().encode(genres)
        container[Columns.imdbRating] = imdbRating
        container[Columns.runtime] = runtime
        container[Columns.status] = status
        container[Columns.tmdbId] = tmdbId
        container[Columns.lastFetched] = lastFetched
    }

    init(row: Row) throws {
        id = row[Columns.id]
        let typeRaw: String = row[Columns.type]
        type = MediaType(rawValue: typeRaw) ?? .movie
        title = row[Columns.title]
        year = row[Columns.year]
        posterPath = row[Columns.posterPath]
        backdropPath = row[Columns.backdropPath]
        overview = row[Columns.overview]
        if let genresData = row[Columns.genres] as Data? {
            genres = (try? JSONDecoder().decode([String].self, from: genresData)) ?? []
        } else {
            genres = []
        }
        imdbRating = row[Columns.imdbRating]
        runtime = row[Columns.runtime]
        status = row[Columns.status]
        tmdbId = row[Columns.tmdbId]
        lastFetched = row[Columns.lastFetched]
    }

    init(
        id: String,
        type: MediaType,
        title: String,
        year: Int? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        overview: String? = nil,
        genres: [String] = [],
        imdbRating: Double? = nil,
        runtime: Int? = nil,
        status: String? = nil,
        tmdbId: Int? = nil,
        lastFetched: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.year = year
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.overview = overview
        self.genres = genres
        self.imdbRating = imdbRating
        self.runtime = runtime
        self.status = status
        self.tmdbId = tmdbId
        self.lastFetched = lastFetched
    }
}

struct MediaPreview: Sendable, Identifiable, Equatable, Hashable {
    var id: String
    var type: MediaType
    var title: String
    var year: Int?
    var posterPath: String?
    var backdropPath: String?
    var imdbRating: Double?
    var tmdbId: Int?

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }

    var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(path)")
    }
}
