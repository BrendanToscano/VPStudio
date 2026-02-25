import Foundation

// MARK: - Bundled Trakt App Credentials

/// Default Trakt OAuth app credentials bundled with VPStudio.
/// Users can override these in Settings > Trakt > Advanced.
enum TraktDefaults {
    static let clientId = "TRAKT_CLIENT_ID_PLACEHOLDER"
    static let clientSecret = "TRAKT_CLIENT_SECRET_PLACEHOLDER"

    /// Returns effective credentials: user-override if non-empty, otherwise bundled defaults.
    static func resolvedCredentials(
        userClientId: String?,
        userClientSecret: String?
    ) -> (clientId: String, clientSecret: String)? {
        let id = (userClientId?.isEmpty == false) ? userClientId! : clientId
        let secret = (userClientSecret?.isEmpty == false) ? userClientSecret! : clientSecret
        guard !id.isEmpty, id != "TRAKT_CLIENT_ID_PLACEHOLDER",
              !secret.isEmpty, secret != "TRAKT_CLIENT_SECRET_PLACEHOLDER"
        else { return nil }
        return (id, secret)
    }

    static var hasBundledCredentials: Bool {
        clientId != "TRAKT_CLIENT_ID_PLACEHOLDER" && clientSecret != "TRAKT_CLIENT_SECRET_PLACEHOLDER"
    }
}

/// Trakt.tv sync service for watchlist, history, and scrobbling
actor TraktSyncService {
    private let clientId: String
    private let clientSecret: String
    private let baseURL = "https://api.trakt.tv"
    private let session: URLSession
    private var accessToken: String?
    private var refreshToken: String?
    private let onTokensRefreshed: (@Sendable (String, String?) async -> Void)?

    init(
        clientId: String,
        clientSecret: String,
        session: URLSession = .shared,
        onTokensRefreshed: (@Sendable (String, String?) async -> Void)? = nil
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.session = session
        self.onTokensRefreshed = onTokensRefreshed
    }

    // MARK: - OAuth (legacy code exchange)

    func getAuthorizationURL() -> URL? {
        var components = URLComponents(string: "https://trakt.tv/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: "urn:ietf:wg:oauth:2.0:oob"),
        ]
        return components?.url
    }

    func exchangeCode(_ code: String) async throws {
        let body: [String: String] = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
            "grant_type": "authorization_code",
        ]

        let response: TokenResponse = try await post(path: "/oauth/token", body: body, auth: false)
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        await onTokensRefreshed?(response.accessToken, response.refreshToken)
    }

    // MARK: - OAuth (device code flow)

    /// Requests a device code from Trakt. The user visits the verification URL
    /// and enters the user code to authorize the app.
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        let body: [String: String] = ["client_id": clientId]
        return try await post(path: "/oauth/device/code", body: body, auth: false)
    }

    /// Polls Trakt for token exchange after the user has entered the device code.
    /// Returns `.pending` while waiting, `.success` when authorized, or throws on expiry/denial.
    func pollDeviceToken(deviceCode: String) async throws -> DevicePollResult {
        let body: [String: String] = [
            "code": deviceCode,
            "client_id": clientId,
            "client_secret": clientSecret,
        ]

        guard let url = URL(string: baseURL + "/oauth/device/token") else {
            throw TraktError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TraktError.httpError(0)
        }

        switch http.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let tokenResponse = try decoder.decode(TokenResponse.self, from: data)
            accessToken = tokenResponse.accessToken
            refreshToken = tokenResponse.refreshToken
            await onTokensRefreshed?(tokenResponse.accessToken, tokenResponse.refreshToken)
            return .success(access: tokenResponse.accessToken, refresh: tokenResponse.refreshToken)
        case 400:
            return .pending
        case 404:
            throw TraktError.deviceCodeInvalid
        case 409:
            throw TraktError.deviceCodeAlreadyUsed
        case 410:
            throw TraktError.deviceCodeExpired
        case 418:
            throw TraktError.deviceCodeDenied
        case 429:
            return .slowDown
        default:
            throw TraktError.httpError(http.statusCode)
        }
    }

    func setTokens(access: String, refresh: String?) {
        accessToken = access
        refreshToken = refresh
    }

    func currentTokens() -> (access: String?, refresh: String?) {
        (accessToken, refreshToken)
    }

    private func refreshAccessToken() async throws {
        guard let refreshToken, !refreshToken.isEmpty else {
            throw TraktError.unauthorized
        }

        let body: [String: String] = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
            "grant_type": "refresh_token",
        ]

        let response: TokenResponse = try await performPost(path: "/oauth/token", body: body, token: nil)
        accessToken = response.accessToken
        if let newRefresh = response.refreshToken, !newRefresh.isEmpty {
            self.refreshToken = newRefresh
        }
        await onTokensRefreshed?(accessToken!, self.refreshToken)
    }

    // MARK: - Sync

    func getWatchlist(type: MediaType) async throws -> [TraktItem] {
        let path = "/sync/watchlist/\(type == .movie ? "movies" : "shows")"
        return try await get(path: path)
    }

    func getHistory(type: MediaType, page: Int = 1) async throws -> [TraktHistoryItem] {
        var components = URLComponents()
        components.path = "/sync/history/\(type == .movie ? "movies" : "shows")"
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "50"),
        ]
        guard let path = components.string else { throw TraktError.invalidURL }
        return try await get(path: path)
    }

    func getRatings(type: MediaType) async throws -> [TraktRatingItem] {
        let path = "/sync/ratings/\(type == .movie ? "movies" : "shows")"
        return try await get(path: path)
    }

    func getWatched(type: MediaType) async throws -> [TraktWatchedItem] {
        let path = "/sync/watched/\(type == .movie ? "movies" : "shows")"
        return try await get(path: path)
    }

    // MARK: - Add/Remove

    func addToWatchlist(imdbId: String, type: MediaType) async throws {
        let body: [String: Any] = [
            type == .movie ? "movies" : "shows": [
                ["ids": ["imdb": imdbId]]
            ]
        ]
        let _: TraktSyncResponse = try await post(path: "/sync/watchlist", body: body, auth: true)
    }

    func removeFromWatchlist(imdbId: String, type: MediaType) async throws {
        let body: [String: Any] = [
            type == .movie ? "movies" : "shows": [
                ["ids": ["imdb": imdbId]]
            ]
        ]
        let _: TraktSyncResponse = try await post(path: "/sync/watchlist/remove", body: body, auth: true)
    }

    func addRating(imdbId: String, rating: Int, type: MediaType) async throws {
        let body: [String: Any] = [
            type == .movie ? "movies" : "shows": [
                ["ids": ["imdb": imdbId], "rating": rating]
            ]
        ]
        let _: TraktSyncResponse = try await post(path: "/sync/ratings", body: body, auth: true)
    }

    func addToHistory(imdbId: String, type: MediaType, watchedAt: Date = Date()) async throws {
        let formatter = ISO8601DateFormatter()
        let body: [String: Any] = [
            type == .movie ? "movies" : "shows": [
                ["ids": ["imdb": imdbId], "watched_at": formatter.string(from: watchedAt)]
            ]
        ]
        let _: TraktSyncResponse = try await post(path: "/sync/history", body: body, auth: true)
    }

    // MARK: - Custom Lists

    func getCustomLists() async throws -> [TraktCustomList] {
        try await get(path: "/users/me/lists")
    }

    func getListItems(listId: Int) async throws -> [TraktListItem] {
        try await get(path: "/users/me/lists/\(listId)/items")
    }

    func createCustomList(name: String, description: String? = nil) async throws -> TraktCustomList {
        var body: [String: Any] = ["name": name, "privacy": "private"]
        if let description { body["description"] = description }
        return try await post(path: "/users/me/lists", body: body, auth: true)
    }

    func addToCustomList(listId: Int, imdbIds: [(id: String, type: MediaType)]) async throws {
        var movies: [[String: Any]] = []
        var shows: [[String: Any]] = []
        for item in imdbIds {
            let entry: [String: Any] = ["ids": ["imdb": item.id]]
            if item.type == .movie { movies.append(entry) } else { shows.append(entry) }
        }
        var body: [String: Any] = [:]
        if !movies.isEmpty { body["movies"] = movies }
        if !shows.isEmpty { body["shows"] = shows }
        let _: TraktSyncResponse = try await post(path: "/users/me/lists/\(listId)/items", body: body, auth: true)
    }

    func removeFromCustomList(listId: Int, imdbIds: [(id: String, type: MediaType)]) async throws {
        var movies: [[String: Any]] = []
        var shows: [[String: Any]] = []
        for item in imdbIds {
            let entry: [String: Any] = ["ids": ["imdb": item.id]]
            if item.type == .movie { movies.append(entry) } else { shows.append(entry) }
        }
        var body: [String: Any] = [:]
        if !movies.isEmpty { body["movies"] = movies }
        if !shows.isEmpty { body["shows"] = shows }
        let _: TraktSyncResponse = try await post(path: "/users/me/lists/\(listId)/items/remove", body: body, auth: true)
    }

    func deleteCustomList(listId: Int) async throws {
        try await delete(path: "/users/me/lists/\(listId)")
    }

    // MARK: - Scrobbling

    func startScrobble(imdbId: String, type: MediaType, progress: Double) async throws {
        let body: [String: Any] = [
            type == .movie ? "movie" : "show": ["ids": ["imdb": imdbId]],
            "progress": progress,
        ]
        let _: ScrobbleResponse = try await post(path: "/scrobble/start", body: body, auth: true)
    }

    func pauseScrobble(imdbId: String, type: MediaType, progress: Double) async throws {
        let body: [String: Any] = [
            type == .movie ? "movie" : "show": ["ids": ["imdb": imdbId]],
            "progress": progress,
        ]
        let _: ScrobbleResponse = try await post(path: "/scrobble/pause", body: body, auth: true)
    }

    func stopScrobble(imdbId: String, type: MediaType, progress: Double) async throws {
        let body: [String: Any] = [
            type == .movie ? "movie" : "show": ["ids": ["imdb": imdbId]],
            "progress": progress,
        ]
        let _: ScrobbleResponse = try await post(path: "/scrobble/stop", body: body, auth: true)
    }

    // MARK: - Networking

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let token = accessToken, !token.isEmpty else {
            throw TraktError.notConnected
        }

        do {
            return try await performGet(path: path, token: token)
        } catch TraktError.unauthorized {
            try await refreshAccessToken()
            guard let refreshedToken = accessToken, !refreshedToken.isEmpty else {
                throw TraktError.unauthorized
            }
            return try await performGet(path: path, token: refreshedToken)
        }
    }

    private func performGet<T: Decodable>(path: String, token: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw TraktError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientId, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TraktError.httpError(0)
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw TraktError.unauthorized
        default:
            throw TraktError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(path: String, body: Any, auth: Bool) async throws -> T {
        if !auth {
            return try await performPost(path: path, body: body, token: nil)
        }

        guard let token = accessToken, !token.isEmpty else {
            throw TraktError.notConnected
        }

        do {
            return try await performPost(path: path, body: body, token: token)
        } catch TraktError.unauthorized {
            try await refreshAccessToken()
            guard let refreshedToken = accessToken, !refreshedToken.isEmpty else {
                throw TraktError.unauthorized
            }
            return try await performPost(path: path, body: body, token: refreshedToken)
        }
    }

    private func performPost<T: Decodable>(path: String, body: Any, token: String?) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw TraktError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientId, forHTTPHeaderField: "trakt-api-key")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TraktError.httpError(0)
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw TraktError.unauthorized
        default:
            throw TraktError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func delete(path: String) async throws {
        guard let token = accessToken, !token.isEmpty else {
            throw TraktError.notConnected
        }

        do {
            try await performDelete(path: path, token: token)
        } catch TraktError.unauthorized {
            try await refreshAccessToken()
            guard let refreshedToken = accessToken, !refreshedToken.isEmpty else {
                throw TraktError.unauthorized
            }
            try await performDelete(path: path, token: refreshedToken)
        }
    }

    private func performDelete(path: String, token: String) async throws {
        guard let url = URL(string: baseURL + path) else { throw TraktError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue(clientId, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TraktError.httpError(0)
        }

        switch http.statusCode {
        case 200...299, 204:
            break
        case 401:
            throw TraktError.unauthorized
        default:
            throw TraktError.httpError(http.statusCode)
        }
    }
}

// MARK: - Models

struct TraktItem: Sendable {
    let rank: Int?
    let listedAt: String?
    let movie: TraktMovie?
    let show: TraktShow?
}
extension TraktItem: Decodable {}

struct TraktMovie: Sendable {
    let title: String
    let year: Int?
    let ids: TraktIds
}
extension TraktMovie: Decodable {}

struct TraktShow: Sendable {
    let title: String
    let year: Int?
    let ids: TraktIds
}
extension TraktShow: Decodable {}

struct TraktIds: Sendable {
    let trakt: Int?
    let slug: String?
    let imdb: String?
    let tmdb: Int?
}
extension TraktIds: Decodable {}

struct TraktHistoryItem: Sendable {
    let id: Int
    let watchedAt: String?
    let action: String?
    let movie: TraktMovie?
    let show: TraktShow?
    let episode: TraktEpisode?
}
extension TraktHistoryItem: Decodable {}

struct TraktEpisode: Sendable {
    let season: Int
    let number: Int
    let title: String?
    let ids: TraktIds?
}
extension TraktEpisode: Decodable {}

struct TraktRatingItem: Sendable {
    let rating: Int
    let ratedAt: String?
    let movie: TraktMovie?
    let show: TraktShow?
}
extension TraktRatingItem: Decodable {}

struct TraktWatchedItem: Sendable {
    let plays: Int
    let lastWatchedAt: String?
    let lastUpdatedAt: String?
    let movie: TraktMovie?
    let show: TraktShow?
}
extension TraktWatchedItem: Decodable {}

struct TraktCustomList: Sendable {
    let ids: TraktListIds
    let name: String
    let description: String?
    let privacy: String?
    let itemCount: Int?
    let updatedAt: String?
}
extension TraktCustomList: Decodable {}

struct TraktListIds: Sendable {
    let trakt: Int
    let slug: String?
}
extension TraktListIds: Decodable {}

struct TraktListItem: Sendable {
    let rank: Int?
    let listedAt: String?
    let type: String?
    let movie: TraktMovie?
    let show: TraktShow?
}
extension TraktListItem: Decodable {}

private struct TokenResponse: Sendable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let createdAt: Int?
}
extension TokenResponse: Decodable {}

private struct TraktSyncResponse: Sendable {
    let added: SyncCounts?
    let deleted: SyncCounts?

    struct SyncCounts: Sendable {
        let movies: Int?
        let shows: Int?
        let episodes: Int?
    }
}
extension TraktSyncResponse: Decodable {}
extension TraktSyncResponse.SyncCounts: Decodable {}

private struct ScrobbleResponse: Sendable {
    let id: Int?
    let action: String?
}
extension ScrobbleResponse: Decodable {}

struct DeviceCodeResponse: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUrl: String
    let expiresIn: Int
    let interval: Int
}

enum DevicePollResult: Sendable {
    case pending
    case slowDown
    case success(access: String, refresh: String?)
}

enum TraktError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case unauthorized
    case notConnected
    case deviceCodeExpired
    case deviceCodeDenied
    case deviceCodeInvalid
    case deviceCodeAlreadyUsed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Trakt URL"
        case .httpError(let code): return "Trakt API error: HTTP \(code)"
        case .unauthorized: return "Trakt authorization expired"
        case .notConnected: return "Not connected to Trakt"
        case .deviceCodeExpired: return "Authorization code expired. Try again."
        case .deviceCodeDenied: return "Authorization was denied by the user."
        case .deviceCodeInvalid: return "Invalid device code. Try again."
        case .deviceCodeAlreadyUsed: return "This code has already been used."
        }
    }
}
