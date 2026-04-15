import Foundation

actor TMDBService: MetadataProvider {
    private static let maximumRateLimitAttempts = 3
    private static let initialBackoffNanoseconds: UInt64 = 500_000_000
    private static let maximumBackoffNanoseconds: UInt64 = 4_000_000_000

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    private let apiKey: String
    private let baseURL = "https://api.themoviedb.org/3"
    private let session: URLSession
    private let sleeper: @Sendable (UInt64) async throws -> Void

    private enum Authentication {
        case bearerToken(String)
        case apiKeyQuery(String)
    }

    init(
        apiKey: String,
        session: URLSession? = nil,
        sleeper: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.apiKey = apiKey
        self.session = session ?? Self.defaultSession
        self.sleeper = sleeper
    }

    func search(query: String, type: MediaType?, page: Int = 1) async throws -> MetadataSearchResult {
        try await search(query: query, type: type, page: page, year: nil, language: nil)
    }

    func search(query: String, type: MediaType?, page: Int = 1, year: Int? = nil, language: String? = nil) async throws -> MetadataSearchResult {
        let path = type.map { "/search/\($0.tmdbPath)" } ?? "/search/multi"
        var params = ["query": query, "page": String(page), "include_adult": "false", "language": language ?? "en-US"]
        if let year, let type {
            params[type.tmdbSearchYearParameterName] = String(year)
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
            "page": String(filters.page), "sort_by": filters.sortBy.tmdbValue(for: type),
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
        guard let authentication = authenticationMode() else { throw TMDBError.unauthorized }

        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        if case .apiKeyQuery(let apiKey) = authentication {
            components.queryItems?.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        guard let url = components.url else { throw TMDBError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if case .bearerToken(let token) = authentication {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            // Legacy v3 API keys must ride in the query string for compatibility.
            // Mark those requests as non-cacheable so local/remote intermediaries
            // are less likely to retain full URLs containing the credential.
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }

        let responseData = try await responseData(for: request, path: path)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: responseData)
    }

    private func responseData(for request: URLRequest, path: String, attempt: Int = 0) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TMDBError.invalidResponse }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw TMDBError.unauthorized
        case 404:
            throw TMDBError.notFound(path)
        case 429:
            guard attempt < Self.maximumRateLimitAttempts - 1 else {
                throw TMDBError.rateLimited
            }

            let delay = Self.retryDelayNanoseconds(
                from: http.value(forHTTPHeaderField: "Retry-After"),
                attempt: attempt
            )
            try await sleeper(delay)
            return try await responseData(for: request, path: path, attempt: attempt + 1)
        default:
            throw TMDBError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func authenticationMode() -> Authentication? {
        let trimmedCredential = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCredential.isEmpty else { return nil }

        if trimmedCredential.lowercased().hasPrefix("bearer ") {
            let token = trimmedCredential.dropFirst("bearer ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : .bearerToken(token)
        }

        if Self.looksLikeReadAccessToken(trimmedCredential) {
            return .bearerToken(trimmedCredential)
        }

        return .apiKeyQuery(trimmedCredential)
    }

    private static func looksLikeReadAccessToken(_ credential: String) -> Bool {
        let allowedJWTCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let segments = credential.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return false }

        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.unicodeScalars.allSatisfy { allowedJWTCharacters.contains($0) }
        }
    }

    private static func retryDelayNanoseconds(from retryAfter: String?, attempt: Int) -> UInt64 {
        let exponentialDelay = min(
            maximumBackoffNanoseconds,
            initialBackoffNanoseconds * UInt64(1 << min(attempt, 3))
        )

        guard let parsedDelay = retryAfterDelay(from: retryAfter) else {
            return exponentialDelay
        }

        let retryAfterNanoseconds = UInt64((parsedDelay * 1_000_000_000).rounded())
        return min(maximumBackoffNanoseconds, max(exponentialDelay, retryAfterNanoseconds))
    }

    private static func retryAfterDelay(from headerValue: String?) -> TimeInterval? {
        guard let rawHeader = headerValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawHeader.isEmpty else {
            return nil
        }

        if let retryAfterSeconds = TimeInterval(rawHeader), retryAfterSeconds > 0 {
            return retryAfterSeconds
        }

        for format in [
            "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
            "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
            "EEE MMM d HH':'mm':'ss yyyy",
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format

            if let date = formatter.date(from: rawHeader) {
                let delay = date.timeIntervalSinceNow
                if delay > 0 {
                    return delay
                }
                return nil
            }
        }

        return nil
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

enum TMDBError: LocalizedError, Equatable {
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
