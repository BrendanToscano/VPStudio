import CryptoKit
import Foundation
import Security

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
        let id: String
        if let userClientId, !userClientId.isEmpty {
            id = userClientId
        } else {
            id = clientId
        }

        let secret: String
        if let userClientSecret, !userClientSecret.isEmpty {
            secret = userClientSecret
        } else {
            secret = clientSecret
        }

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
    private static let authorizationRedirectURI = "urn:ietf:wg:oauth:2.0:oob"
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

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
        session: URLSession? = nil,
        onTokensRefreshed: (@Sendable (String, String?) async -> Void)? = nil
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.session = session ?? Self.defaultSession
        self.onTokensRefreshed = onTokensRefreshed
    }

    // MARK: - OAuth (legacy code exchange)

    func getAuthorizationURL() -> URL? {
        let authorizationSession = beginAuthorizationSession()
        var components = URLComponents(string: "https://trakt.tv/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.authorizationRedirectURI),
            URLQueryItem(name: "state", value: authorizationSession.state),
            URLQueryItem(name: "code_challenge", value: authorizationSession.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: authorizationSession.codeChallengeMethod),
        ]
        return components?.url
    }

    func exchangeCode(_ code: String, returnedState: String? = nil) async throws {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorizationSession = try validateAuthorizationSession(returnedState: returnedState)
        let body: [String: String] = [
            "code": trimmedCode,
            "client_id": self.clientId,
            "client_secret": self.clientSecret,
            "redirect_uri": Self.authorizationRedirectURI,
            "grant_type": "authorization_code",
            "code_verifier": authorizationSession.codeVerifier,
        ]

        let response: TokenResponse = try await post(path: "/oauth/token", body: body, auth: false)
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        clearAuthorizationSession()
        await onTokensRefreshed?(response.accessToken, response.refreshToken)
    }

    // MARK: - OAuth (device code flow)

    /// Requests a device code from Trakt. The user visits the verification URL
    /// and enters the user code to authorize the app.
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        let body: [String: String] = ["client_id": self.clientId]
        return try await post(path: "/oauth/device/code", body: body, auth: false)
    }

    /// Polls Trakt for token exchange after the user has entered the device code.
    /// Returns `.pending` while waiting, `.success` when authorized, or throws on expiry/denial.
    func pollDeviceToken(deviceCode: String) async throws -> DevicePollResult {
        let body: [String: String] = [
            "code": deviceCode,
            "client_id": self.clientId,
            "client_secret": self.clientSecret,
        ]

        guard let url = URL(string: self.baseURL + "/oauth/device/token") else {
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
            "client_id": self.clientId,
            "client_secret": self.clientSecret,
            "redirect_uri": Self.authorizationRedirectURI,
            "grant_type": "refresh_token",
        ]

        let response: TokenResponse = try await performPost(path: "/oauth/token", body: body, token: nil)
        accessToken = response.accessToken
        if let newRefresh = response.refreshToken, !newRefresh.isEmpty {
            self.refreshToken = newRefresh
        }
        await onTokensRefreshed?(response.accessToken, self.refreshToken)
    }

    // MARK: - Sync

    func getWatchlist(type: MediaType, page: Int = 1) async throws -> [TraktItem] {
        let resourcePath = "/sync/watchlist/\(type == .movie ? "movies" : "shows")"
        return try await pagedGet(resourcePath: resourcePath, page: page)
    }

    func getHistory(type: MediaType, page: Int = 1) async throws -> [TraktHistoryItem] {
        let resourcePath = "/sync/history/\(type == .movie ? "movies" : "shows")"
        return try await pagedGet(resourcePath: resourcePath, page: page)
    }

    func getRatings(type: MediaType, page: Int = 1) async throws -> [TraktRatingItem] {
        let resourcePath = "/sync/ratings/\(type == .movie ? "movies" : "shows")"
        return try await pagedGet(resourcePath: resourcePath, page: page)
    }

    func getWatched(type: MediaType) async throws -> [TraktWatchedItem] {
        let path = "/sync/watched/\(type == .movie ? "movies" : "shows")"
        return try await get(path: path)
    }

    private func pagedGet<T: Decodable>(resourcePath: String, page: Int) async throws -> T {
        let path = "\(resourcePath)?page=\(page)&limit=50"
        do {
            return try await get(path: path)
        } catch let error as TraktError {
            if case .httpError = error, page == 1 {
                // Compatibility fallback for stubs/servers that only expose the base path.
                return try await get(path: resourcePath)
            }
            throw error
        }
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

    func addToHistory(
        imdbId: String,
        type: MediaType,
        episodeId: String? = nil,
        watchedAt: Date = Date()
    ) async throws {
        let formatter = ISO8601DateFormatter()
        let watchedAtString = formatter.string(from: watchedAt)

        let body: [String: Any]
        if type == .series,
           let episodeId,
           episodeId.hasPrefix("tt") {
            body = [
                "episodes": [
                    ["ids": ["imdb": episodeId], "watched_at": watchedAtString]
                ]
            ]
        } else {
            body = [
                type == .movie ? "movies" : "shows": [
                    ["ids": ["imdb": imdbId], "watched_at": watchedAtString]
                ]
            ]
        }

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
        request.setValue(self.clientId, forHTTPHeaderField: "trakt-api-key")
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
        request.setValue(self.clientId, forHTTPHeaderField: "trakt-api-key")
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
        request.setValue(self.clientId, forHTTPHeaderField: "trakt-api-key")
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

    private func beginAuthorizationSession() -> PendingOAuthAuthorizationSession {
        let authorizationSession = PendingOAuthAuthorizationSession.make()
        TraktAuthorizationSessionStore.store(authorizationSession, for: self.clientId)
        return authorizationSession
    }

    private func validateAuthorizationSession(returnedState: String?) throws -> PendingOAuthAuthorizationSession {
        guard let authorizationSession = TraktAuthorizationSessionStore.session(for: self.clientId) else {
            throw TraktError.authorizationSessionMissing
        }
        guard !authorizationSession.isExpired else {
            clearAuthorizationSession()
            throw TraktError.authorizationSessionExpired
        }
        if let returnedState, returnedState != authorizationSession.state {
            clearAuthorizationSession()
            throw TraktError.authorizationStateMismatch
        }
        return authorizationSession
    }

    private func clearAuthorizationSession() {
        TraktAuthorizationSessionStore.remove(clientId: self.clientId)
    }
}

private struct PendingOAuthAuthorizationSession: Sendable {
    private static let lifetime: TimeInterval = 15 * 60

    let state: String
    let codeVerifier: String
    let codeChallenge: String
    let codeChallengeMethod = "S256"
    let createdAt: Date

    var isExpired: Bool {
        createdAt.addingTimeInterval(Self.lifetime) < Date()
    }

    static func make() -> PendingOAuthAuthorizationSession {
        let verifier = OAuthSecurityRandom.urlSafeToken(byteCount: 32)
        return PendingOAuthAuthorizationSession(
            state: OAuthSecurityRandom.urlSafeToken(byteCount: 16),
            codeVerifier: verifier,
            codeChallenge: OAuthPKCE.codeChallenge(for: verifier),
            createdAt: Date()
        )
    }
}

private enum TraktAuthorizationSessionStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sessions: [String: PendingOAuthAuthorizationSession] = [:]

    static func store(_ session: PendingOAuthAuthorizationSession, for clientId: String) {
        lock.lock()
        sessions[clientId] = session
        lock.unlock()
    }

    static func session(for clientId: String) -> PendingOAuthAuthorizationSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[clientId]
    }

    static func remove(clientId: String) {
        lock.lock()
        sessions.removeValue(forKey: clientId)
        lock.unlock()
    }
}

private enum OAuthSecurityRandom {
    static func urlSafeToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: .min ... .max)
            }
        }
        return Data(bytes).base64URLEncodedString()
    }
}

private enum OAuthPKCE {
    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
extension TraktMovie: Decodable {
    private enum CodingKeys: String, CodingKey {
        case title, year, ids
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Unknown"
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        ids = try container.decodeIfPresent(TraktIds.self, forKey: .ids)
            ?? TraktIds(trakt: nil, slug: nil, imdb: nil, tmdb: nil)
    }
}

struct TraktShow: Sendable {
    let title: String
    let year: Int?
    let ids: TraktIds
}
extension TraktShow: Decodable {
    private enum CodingKeys: String, CodingKey {
        case title, name, year, ids
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? "Unknown"
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        ids = try container.decodeIfPresent(TraktIds.self, forKey: .ids)
            ?? TraktIds(trakt: nil, slug: nil, imdb: nil, tmdb: nil)
    }
}

struct TraktIds: Sendable {
    let trakt: Int?
    let slug: String?
    let imdb: String?
    let tmdb: Int?
}
extension TraktIds: Decodable {}

struct TraktHistoryItem: Sendable {
    let id: Int?
    let watchedAt: String?
    let action: String?
    let movie: TraktMovie?
    let show: TraktShow?
    let episode: TraktEpisode?
}
extension TraktHistoryItem: Decodable {}

struct TraktEpisode: Sendable {
    let season: Int?
    let number: Int?
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
    case authorizationSessionMissing
    case authorizationSessionExpired
    case authorizationStateMismatch
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
        case .authorizationSessionMissing: return "Start Trakt authorization again before entering the code."
        case .authorizationSessionExpired: return "The Trakt authorization session expired. Start the login flow again."
        case .authorizationStateMismatch: return "The Trakt authorization response did not match the active login session."
        case .deviceCodeExpired: return "Authorization code expired. Try again."
        case .deviceCodeDenied: return "Authorization was denied by the user."
        case .deviceCodeInvalid: return "Invalid device code. Try again."
        case .deviceCodeAlreadyUsed: return "This code has already been used."
        }
    }
}
