import Foundation

struct DiscoverFilters: Sendable {
    var genreId: Int?
    var year: Int?
    var minRating: Double?
    var sortBy: SortOption
    var page: Int
    var language: String?
    var releaseDateGte: String?
    var releaseDateLte: String?
    var originalLanguage: String?

    init(genreId: Int? = nil, year: Int? = nil, minRating: Double? = nil, sortBy: SortOption = .popularityDesc, page: Int = 1, language: String? = nil, releaseDateGte: String? = nil, releaseDateLte: String? = nil, originalLanguage: String? = nil) {
        self.genreId = genreId
        self.year = year
        self.minRating = minRating
        self.sortBy = sortBy
        self.page = page
        self.language = language
        self.releaseDateGte = releaseDateGte
        self.releaseDateLte = releaseDateLte
        self.originalLanguage = originalLanguage
    }

    enum SortOption: String, Sendable, CaseIterable {
        case popularityDesc = "popularity.desc"
        case popularityAsc = "popularity.asc"
        case ratingDesc = "vote_average.desc"
        case ratingAsc = "vote_average.asc"
        case releaseDateDesc = "primary_release_date.desc"
        case releaseDateAsc = "primary_release_date.asc"
        case titleAsc = "title.asc"

        var displayName: String {
            switch self {
            case .popularityDesc: return "Most Popular"
            case .popularityAsc: return "Least Popular"
            case .ratingDesc: return "Highest Rated"
            case .ratingAsc: return "Lowest Rated"
            case .releaseDateDesc: return "Newest"
            case .releaseDateAsc: return "Oldest"
            case .titleAsc: return "Title A-Z"
            }
        }
    }

    // MARK: - Date Helpers

    /// The current date formatted as yyyy-MM-dd, suitable for TMDB date parameters.
    static func todayString(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: now)
    }

    /// A date string offset by the given number of days from `now`.
    static func dateString(daysFromNow days: Int, now: Date = Date()) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: now)!
        return todayString(now: date)
    }

    /// Extracts the ISO 639-1 language code from a locale identifier (e.g. "en-US" -> "en", "ja-JP" -> "ja").
    static func iso639LanguageCode(from localeCode: String) -> String {
        let parts = localeCode.split(separator: "-")
        return String(parts.first ?? Substring(localeCode)).lowercased()
    }
}

struct Genre: Codable, Sendable, Identifiable, Hashable {
    var id: Int
    var name: String
}

protocol MetadataProvider: Sendable {
    func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult
    func search(query: String, type: MediaType?, page: Int, year: Int?, language: String?) async throws -> MetadataSearchResult
    func getDetail(id: String, type: MediaType) async throws -> MediaItem
    func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult
    func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult
    func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult
    func getGenres(type: MediaType) async throws -> [Genre]
    func getSeasons(tmdbId: Int) async throws -> [Season]
    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode]
    func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds
}

extension MetadataProvider {
    /// Default: delegates to the 3-param search (ignoring year/language) for backward compatibility.
    func search(query: String, type: MediaType?, page: Int, year: Int?, language: String?) async throws -> MetadataSearchResult {
        try await search(query: query, type: type, page: page)
    }
}

struct MetadataSearchResult: Sendable {
    var items: [MediaPreview]
    var page: Int
    var totalPages: Int
    var totalResults: Int
}

enum TrendingWindow: String, Sendable {
    case day, week
}

enum MediaCategory: String, Sendable, CaseIterable {
    case popular
    case topRated = "top_rated"
    case nowPlaying = "now_playing"
    case upcoming
    case airingToday = "airing_today"
    case onTheAir = "on_the_air"

    var displayName: String {
        switch self {
        case .popular: return "Popular"
        case .topRated: return "Top Rated"
        case .nowPlaying: return "Now Playing"
        case .upcoming: return "Upcoming"
        case .airingToday: return "Airing Today"
        case .onTheAir: return "On The Air"
        }
    }

    static func categories(for type: MediaType) -> [MediaCategory] {
        switch type {
        case .movie: return [.popular, .topRated, .nowPlaying, .upcoming]
        case .series: return [.popular, .topRated, .airingToday, .onTheAir]
        }
    }
}

struct ExternalIds: Sendable {
    var imdbId: String?
    var tvdbId: Int?
}
nonisolated extension ExternalIds: Codable {}
