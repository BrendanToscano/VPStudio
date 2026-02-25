import Foundation
import GRDB

struct UserTasteProfile: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "user_taste_profiles"

    var id: String
    var likedGenres: [String]
    var dislikedGenres: [String]
    var preferredDecades: [String]
    var preferredLanguages: [String]
    var eventCount: Int
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, likedGenres, dislikedGenres, preferredDecades
        case preferredLanguages, eventCount, updatedAt
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.likedGenres] = try? JSONEncoder().encode(likedGenres)
        container[Columns.dislikedGenres] = try? JSONEncoder().encode(dislikedGenres)
        container[Columns.preferredDecades] = try? JSONEncoder().encode(preferredDecades)
        container[Columns.preferredLanguages] = try? JSONEncoder().encode(preferredLanguages)
        container[Columns.eventCount] = eventCount
        container[Columns.updatedAt] = updatedAt
    }

    init(row: Row) throws {
        id = row[Columns.id]
        if let data = row[Columns.likedGenres] as Data? {
            likedGenres = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        } else { likedGenres = [] }
        if let data = row[Columns.dislikedGenres] as Data? {
            dislikedGenres = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        } else { dislikedGenres = [] }
        if let data = row[Columns.preferredDecades] as Data? {
            preferredDecades = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        } else { preferredDecades = [] }
        if let data = row[Columns.preferredLanguages] as Data? {
            preferredLanguages = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        } else { preferredLanguages = [] }
        eventCount = row[Columns.eventCount]
        updatedAt = row[Columns.updatedAt]
    }

    init(
        id: String = "default",
        likedGenres: [String] = [],
        dislikedGenres: [String] = [],
        preferredDecades: [String] = [],
        preferredLanguages: [String] = [],
        eventCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.likedGenres = likedGenres
        self.dislikedGenres = dislikedGenres
        self.preferredDecades = preferredDecades
        self.preferredLanguages = preferredLanguages
        self.eventCount = eventCount
        self.updatedAt = updatedAt
    }
}

struct TasteEvent: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "taste_events"

    var id: String
    var userId: String
    var mediaId: String?
    var episodeId: String?
    var eventType: EventType
    var signalStrength: Double
    var watchedState: WatchedState?
    var feedbackScale: FeedbackScaleMode?
    var feedbackValue: Double?
    var source: FeedbackSource?
    var metadata: [String: String]
    var createdAt: Date

    enum EventType: String, Codable, Sendable {
        case watched, rated, added, removed, searched, browsed, skipped
    }

    enum WatchedState: String, Codable, Sendable {
        case watching, completed, dropped, planToWatch = "plan_to_watch"
    }

    enum FeedbackSource: String, Codable, Sendable {
        case manual, automatic, ai
    }

    enum Columns: String, ColumnExpression {
        case id, userId, mediaId, episodeId, eventType, signalStrength
        case watchedState, feedbackScale, feedbackValue, source, metadata, createdAt
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.userId] = userId
        container[Columns.mediaId] = mediaId
        container[Columns.episodeId] = episodeId
        container[Columns.eventType] = eventType.rawValue
        container[Columns.signalStrength] = signalStrength
        container[Columns.watchedState] = watchedState?.rawValue
        container[Columns.feedbackScale] = feedbackScale?.rawValue
        container[Columns.feedbackValue] = feedbackValue
        container[Columns.source] = source?.rawValue
        container[Columns.metadata] = try? JSONEncoder().encode(metadata)
        container[Columns.createdAt] = createdAt
    }

    init(row: Row) throws {
        id = row[Columns.id]
        userId = row[Columns.userId]
        mediaId = row[Columns.mediaId]
        episodeId = row[Columns.episodeId]
        let eventRaw: String = row[Columns.eventType]
        eventType = EventType(rawValue: eventRaw) ?? .browsed
        signalStrength = row[Columns.signalStrength]
        let wsRaw: String? = row[Columns.watchedState]
        watchedState = wsRaw.flatMap(WatchedState.init(rawValue:))
        let fsRaw: String? = row[Columns.feedbackScale]
        if let fsRaw {
            feedbackScale = FeedbackScaleMode.fromStoredValue(fsRaw)
        } else {
            feedbackScale = nil
        }
        feedbackValue = row[Columns.feedbackValue]
        let srcRaw: String? = row[Columns.source]
        source = srcRaw.flatMap(FeedbackSource.init(rawValue:))
        if let data = row[Columns.metadata] as Data? {
            metadata = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        } else { metadata = [:] }
        createdAt = row[Columns.createdAt]
    }

    init(
        id: String = UUID().uuidString,
        userId: String = "default",
        mediaId: String? = nil,
        episodeId: String? = nil,
        eventType: EventType,
        signalStrength: Double = 1.0,
        watchedState: WatchedState? = nil,
        feedbackScale: FeedbackScaleMode? = nil,
        feedbackValue: Double? = nil,
        source: FeedbackSource? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.mediaId = mediaId
        self.episodeId = episodeId
        self.eventType = eventType
        self.signalStrength = signalStrength
        self.watchedState = watchedState
        self.feedbackScale = feedbackScale
        self.feedbackValue = feedbackValue
        self.source = source
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

enum FeedbackScaleMode: String, Codable, Sendable, CaseIterable {
    case likeDislike = "like_dislike"
    case oneToTen = "one_to_ten"
    case oneToHundred = "one_to_hundred"

    // Backward compatibility for earlier builds.
    case fiveStar = "five_star"
    case tenPoint = "ten_point"

    static var selectableCases: [Self] {
        [.likeDislike, .oneToTen, .oneToHundred]
    }

    static func fromStoredValue(_ rawValue: String?) -> Self {
        guard let rawValue, let mode = Self(rawValue: rawValue) else {
            return .oneToTen
        }
        return mode.canonicalMode
    }

    var canonicalMode: Self {
        switch self {
        case .likeDislike, .oneToTen, .oneToHundred:
            return self
        case .fiveStar:
            return .oneToTen
        case .tenPoint:
            return .oneToTen
        }
    }

    var displayName: String {
        switch canonicalMode {
        case .likeDislike:
            return "Like / Dislike"
        case .oneToTen:
            return "1-10"
        case .oneToHundred:
            return "1-100"
        case .fiveStar, .tenPoint:
            return "1-10"
        }
    }

    var minimumValue: Double {
        switch canonicalMode {
        case .likeDislike:
            return 0
        case .oneToTen:
            return 1
        case .oneToHundred:
            return 1
        case .fiveStar, .tenPoint:
            return 1
        }
    }

    var maximumValue: Double {
        switch canonicalMode {
        case .likeDislike:
            return 1
        case .oneToTen:
            return 10
        case .oneToHundred:
            return 100
        case .fiveStar:
            return 5
        case .tenPoint:
            return 10
        }
    }

    func clamp(_ value: Double) -> Double {
        min(max(value, minimumValue), maximumValue)
    }

    func normalizedValue(_ value: Double) -> Double {
        let clamped = clamp(value)
        switch canonicalMode {
        case .likeDislike:
            return clamped >= 0.5 ? 1.0 : 0.0
        case .oneToTen:
            return (clamped - 1.0) / 9.0
        case .oneToHundred:
            return (clamped - 1.0) / 99.0
        case .fiveStar:
            return (clamped - 1.0) / 4.0
        case .tenPoint:
            return (clamped - 1.0) / 9.0
        }
    }

    func value(fromNormalized normalized: Double) -> Double {
        let bounded = min(max(normalized, 0.0), 1.0)
        switch canonicalMode {
        case .likeDislike:
            return bounded >= 0.5 ? 1.0 : 0.0
        case .oneToTen:
            return round((bounded * 9.0) + 1.0)
        case .oneToHundred:
            return round((bounded * 99.0) + 1.0)
        case .fiveStar:
            return round((bounded * 4.0) + 1.0)
        case .tenPoint:
            return round((bounded * 9.0) + 1.0)
        }
    }

    func sentiment(for value: Double) -> FeedbackSentiment {
        let normalized = normalizedValue(value)
        if normalized >= 0.6 {
            return .liked
        }
        if normalized <= 0.4 {
            return .disliked
        }
        return .neutral
    }

    func format(_ value: Double) -> String {
        let clamped = clamp(value)
        switch canonicalMode {
        case .likeDislike:
            return clamped >= 0.5 ? "Liked" : "Disliked"
        case .oneToTen:
            return "\(Int(clamped))/10"
        case .oneToHundred:
            return "\(Int(clamped))/100"
        case .fiveStar:
            return "\(Int(clamped))/5"
        case .tenPoint:
            return "\(Int(clamped))/10"
        }
    }
}

enum FeedbackSentiment: String, Codable, Sendable {
    case liked
    case disliked
    case neutral
}
