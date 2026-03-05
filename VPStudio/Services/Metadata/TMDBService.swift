import Foundation

actor TMDBService: MetadataProvider {
    private let apiKey: String
    private let baseURL = "https://api.themoviedb.org/3"
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func search(query: String, type: MediaType?, page: Int = 1) async throws -> MetadataSearchResult {
        try await search(query: query, type: type, page: page, year: nil, language: nil)
    }

    func search(query: String, type: MediaType?, page: Int = 1, year: Int? = nil, language: String? = nil) async throws -> MetadataSearchResult {
        let path = type.map { "/search/\($0.tmdbPath)" } ?? "/search/multi"
        var params = ["query": query, "page": String(page), "include_adult": "false", "language": language ?? "en-US"]
        if let year {
            params["year"] = String(year)
        }
        let response: TMDBPagedResponse<TMDBSearchResult> = try await request(path: path, params: params)
        return MetadataSearchResult(
            items: response.results.compactMap { $0.toMediaPreview() },
            page: response.page, totalPages: response.totalPages, totalResults: response.totalResults
        )
    }

    func getDetail(id: String, type: MediaType) async throws -> MediaItem {
        let tmdbId: String
        if let extracted = extractTMDBID(from: id) { tmdbId = extracted }
        else if id.allSatisfy(\.isNumber) { tmdbId = id }
        else if let found = try await findByImdbId(id, type: type) { tmdbId = String(found) }
        else { throw TMDBError.notFound(id) }

        let response: TMDBDetailResponse = try await request(
            path: "/\(type.tmdbPath)/\(tmdbId)",
            params: ["append_to_response": "external_ids,credits", "language": "en-US"]
        )
        return response.toMediaItem(type: type)
    }

    func getTrending(type: MediaType, timeWindow: TrendingWindow = .week, page: Int = 1) async throws -> MetadataSearchResult {
        let response: TMDBPagedResponse<TMDBSearchResult> = try await request(
            path: "/trending/\(type.tmdbPath)/\(timeWindow.rawValue)",
            params: ["page": String(page), "language": "en-US"]
        )
        return MetadataSearchResult(
            items: response.results.compactMap { $0.toMediaPreview() },
            page: response.page, totalPages: response.totalPages, totalResults: response.totalResults
        )
    }

    func getCategory(_ category: MediaCategory, type: MediaType, page: Int = 1) async throws -> MetadataSearchResult {
        let response: TMDBPagedResponse<TMDBSearchResult> = try await request(
            path: "/\(type.tmdbPath)/\(category.rawValue)",
            params: ["page": String(page), "language": "en-US"]
        )
        return MetadataSearchResult(
            items: response.results.compactMap { $0.toMediaPreview() },
            page: response.page, totalPages: response.totalPages, totalResults: response.totalResults
        )
    }

    func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult {
        var params: [String: String] = [
            "page": String(filters.page), "sort_by": filters.sortBy.rawValue,
            "language": filters.language ?? "en-US", "include_adult": "false",
        ]
        if let g = filters.genreId { params["with_genres"] = String(g) }
        if let y = filters.year { params[type == .movie ? "primary_release_year" : "first_air_date_year"] = String(y) }
        if let r = filters.minRating { params["vote_average.gte"] = String(r); params["vote_count.gte"] = "100" }

        // Date range bounds
        let gteKey = type == .movie ? "release_date.gte" : "first_air_date.gte"
        let lteKey = type == .movie ? "release_date.lte" : "first_air_date.lte"
        if let gte = filters.releaseDateGte { params[gteKey] = gte }
        if let lte = filters.releaseDateLte { params[lteKey] = lte }

        // Original language filter (ISO 639-1)
        if let lang = filters.originalLanguage { params["with_original_language"] = lang }

        let response: TMDBPagedResponse<TMDBSearchResult> = try await request(path: "/discover/\(type.tmdbPath)", params: params)
        return MetadataSearchResult(
            items: response.results.compactMap { $0.toMediaPreview() },
            page: response.page, totalPages: response.totalPages, totalResults: response.totalResults
        )
    }

    func getGenres(type: MediaType) async throws -> [Genre] {
        let response: TMDBGenresResponse = try await request(path: "/genre/\(type.tmdbPath)/list", params: ["language": "en-US"])
        return response.genres.map { Genre(id: $0.id, name: $0.name) }
    }

    func getSeasons(tmdbId: Int) async throws -> [Season] {
        let response: TMDBTVDetailResponse = try await request(path: "/tv/\(tmdbId)", params: ["language": "en-US"])
        return response.seasons?.map { Season(
            id: $0.id, seasonNumber: $0.seasonNumber, name: $0.name,
            overview: $0.overview, posterPath: $0.posterPath,
            episodeCount: $0.episodeCount, airDate: $0.airDate
        ) } ?? []
    }

    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] {
        let response: TMDBSeasonResponse = try await request(path: "/tv/\(tmdbId)/season/\(season)", params: ["language": "en-US"])
        return response.episodes.map { Episode(
            id: "\(tmdbId)-s\(season)e\($0.episodeNumber)", mediaId: "tmdb-\(tmdbId)",
            seasonNumber: season, episodeNumber: $0.episodeNumber,
            title: $0.name, overview: $0.overview, airDate: $0.airDate,
            stillPath: $0.stillPath, runtime: $0.runtime
        ) }
    }

    func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds {
        try await request(path: "/\(type.tmdbPath)/\(tmdbId)/external_ids", params: [:])
    }

    func findByImdbId(_ imdbId: String, type: MediaType) async throws -> Int? {
        let response: TMDBFindResponse = try await request(path: "/find/\(imdbId)", params: ["external_source": "imdb_id"])
        return type == .movie ? response.movieResults.first?.id : response.tvResults.first?.id
    }

    private func request<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else { throw TMDBError.invalidURL(path) }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "api_key", value: apiKey)]

        guard let url = components.url else { throw TMDBError.invalidURL(path) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw TMDBError.invalidResponse }

        switch http.statusCode {
        case 200...299: break
        case 401: throw TMDBError.unauthorized
        case 404: throw TMDBError.notFound(path)
        case 429: throw TMDBError.rateLimited
        default: throw TMDBError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func extractTMDBID(from id: String) -> String? {
        if id.hasPrefix("tmdb-") {
            let suffix = String(id.dropFirst(5))
            if suffix.allSatisfy(\.isNumber) {
                return suffix
            }
        }

        // Supports typed identifiers like "movie-tmdb-123" and "series-tmdb-456".
        if id.contains("tmdb-"),
           let suffix = id.split(separator: "-").last,
           suffix.allSatisfy(\.isNumber) {
            return String(suffix)
        }

        return nil
    }
}

// MARK: - TMDB Response Models

struct TMDBPagedResponse<T: Decodable & Sendable>: Sendable {
    let page: Int; let results: [T]; let totalPages: Int; let totalResults: Int
}
extension TMDBPagedResponse: Decodable {}

struct TMDBSearchResult: Sendable {
    let id: Int; let title: String?; let name: String?; let mediaType: String?
    let overview: String?; let posterPath: String?; let backdropPath: String?
    let releaseDate: String?; let firstAirDate: String?; let voteAverage: Double?

    nonisolated func toMediaPreview() -> MediaPreview? {
        let displayTitle = title ?? name ?? ""
        guard !displayTitle.isEmpty else { return nil }
        let type: MediaType
        if let mt = mediaType {
            switch mt { case "movie": type = .movie; case "tv": type = .series; default: return nil }
        } else { type = title != nil ? .movie : .series }
        let year = (releaseDate ?? firstAirDate).flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil }
        return MediaPreview(
            id: "\(type.rawValue)-tmdb-\(id)",
            type: type,
            title: displayTitle,
            year: year,
            posterPath: posterPath,
            backdropPath: backdropPath,
            imdbRating: voteAverage,
            tmdbId: id
        )
    }
}
extension TMDBSearchResult: Decodable {}

struct TMDBDetailResponse: Sendable {
    let id: Int; let title: String?; let name: String?; let overview: String?
    let posterPath: String?; let backdropPath: String?; let releaseDate: String?
    let firstAirDate: String?; let voteAverage: Double?; let runtime: Int?
    let episodeRunTime: [Int]?; let status: String?; let genres: [TMDBGenre]?
    let externalIds: ExternalIds?

    nonisolated func toMediaItem(type: MediaType) -> MediaItem {
        let displayTitle = title ?? name ?? "Unknown"
        let year = (releaseDate ?? firstAirDate).flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil }
        let itemId = externalIds?.imdbId.flatMap { $0.isEmpty ? nil : $0 } ?? "tmdb-\(id)"
        let rt = (runtime ?? 0) > 0 ? runtime : episodeRunTime?.first
        return MediaItem(id: itemId, type: type, title: displayTitle, year: year, posterPath: posterPath,
                         backdropPath: backdropPath, overview: overview, genres: genres?.map(\.name) ?? [],
                         imdbRating: voteAverage, runtime: rt, status: status, tmdbId: id, lastFetched: Date())
    }
}
extension TMDBDetailResponse: Decodable {}

struct TMDBGenre: Sendable { let id: Int; let name: String }
extension TMDBGenre: Decodable {}

struct TMDBGenresResponse: Sendable { let genres: [TMDBGenre] }
extension TMDBGenresResponse: Decodable {}

struct TMDBTVDetailResponse: Sendable { let id: Int; let seasons: [TMDBSeason]? }
extension TMDBTVDetailResponse: Decodable {}

struct TMDBSeason: Sendable { let id: Int; let seasonNumber: Int; let name: String; let overview: String?; let posterPath: String?; let episodeCount: Int; let airDate: String? }
extension TMDBSeason: Decodable {}

struct TMDBSeasonResponse: Sendable { let episodes: [TMDBEpisode] }
extension TMDBSeasonResponse: Decodable {}

struct TMDBEpisode: Sendable { let id: Int; let episodeNumber: Int; let name: String?; let overview: String?; let airDate: String?; let stillPath: String?; let runtime: Int? }
extension TMDBEpisode: Decodable {}

struct TMDBFindResponse: Sendable { let movieResults: [TMDBSearchResult]; let tvResults: [TMDBSearchResult] }
extension TMDBFindResponse: Decodable {}

enum TMDBError: LocalizedError, Equatable, Sendable {
    case invalidURL(String), invalidResponse, unauthorized, notFound(String), rateLimited, httpError(Int, String)
    var errorDescription: String? {
        switch self {
        case .invalidURL(let p): return "Invalid TMDB URL: \(p)"
        case .invalidResponse: return "Invalid response"
        case .unauthorized: return "Invalid TMDB API key"
        case .notFound(let id): return "Not found: \(id)"
        case .rateLimited: return "Rate limited"
        case .httpError(let c, let m): return "HTTP \(c): \(m)"
        }
    }
}
