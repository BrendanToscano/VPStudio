import CryptoKit
import Foundation
import Security

/// Simkl.com sync service
actor SimklSyncService {
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    private let clientId: String
    private let clientSecret: String
    private let baseURL = "https://api.simkl.com"
    private let redirectURI = "urn:ietf:wg:oauth:2.0:oob"
    private let session: URLSession
    private var accessToken: String?
    private var refreshToken: String?
    private let onTokensRefreshed: (@Sendable (String, String?) async -> Void)?

    init(
        clientId: String,
        clientSecret: String = "",
        accessToken: String? = nil,
        refreshToken: String? = nil,
        session: URLSession? = nil,
        onTokensRefreshed: (@Sendable (String, String?) async -> Void)? = nil
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.session = session ?? Self.defaultSession
        self.onTokensRefreshed = onTokensRefreshed
    }

    func setAccessToken(_ token: String) {
        accessToken = token
    }

    func setTokens(access: String, refresh: String?) {
        accessToken = access
        refreshToken = refresh
    }

    func currentTokens() -> (access: String?, refresh: String?) {
        (accessToken, refreshToken)
    }

    // MARK: - OAuth

    func getAuthorizationURL() -> URL? {
        beginAuthorization()?.url
    }

    func beginAuthorization() -> SimklAuthorizationSessionStart? {
        guard !self.clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let authorizationSession = beginAuthorizationSession()
        var components = URLComponents(string: "https://simkl.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: self.clientId),
            URLQueryItem(name: "redirect_uri", value: self.redirectURI),
            URLQueryItem(name: "state", value: authorizationSession.state),
            URLQueryItem(name: "code_challenge", value: authorizationSession.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: authorizationSession.codeChallengeMethod),
        ]
        guard let url = components?.url else { return nil }
        return SimklAuthorizationSessionStart(url: url, state: authorizationSession.state)
    }

    func exchangeAuthorizationCode(
        _ authorizationCode: String,
        returnedState: String? = nil
    ) async throws -> SimklOAuthTokenResponse {
        let trimmedCode = authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { throw SimklError.invalidAuthorizationCode }
        let authorizationSession = try validateAuthorizationSession(returnedState: returnedState)

        let trimmedClientSecret = self.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientSecret.isEmpty else { throw SimklError.missingClientSecret }

        let response: SimklOAuthTokenResponse = try await postForm(
            path: "/oauth/token",
            parameters: [
                ("grant_type", "authorization_code"),
                ("client_id", self.clientId),
                ("client_secret", trimmedClientSecret),
                ("code", trimmedCode),
                ("redirect_uri", self.redirectURI),
                ("code_verifier", authorizationSession.codeVerifier),
            ]
        )

        guard !response.accessToken.isEmpty else {
            throw SimklError.invalidAuthorizationResponse
        }

        accessToken = response.accessToken
        if let refreshToken = response.refreshToken, !refreshToken.isEmpty {
            self.refreshToken = refreshToken
        }
        clearAuthorizationSession()
        await onTokensRefreshed?(response.accessToken, self.refreshToken)
        return response
    }

    // MARK: - Sync

    func getWatchlist() async throws -> SimklSyncResponse {
        try await get(path: "/sync/all-items/?episode_watched_at=yes")
    }

    func addToList(imdbId: String, type: MediaType, list: String = "plantowatch") async throws {
        let key = type == .movie ? "movies" : "shows"
        let item = SimklAddItem(ids: SimklAddIds(imdb: imdbId), to: list, watchedAt: nil)

        var dict: [String: [SimklAddItem]] = [:]
        dict[key] = [item]
        let wrappedData = try JSONEncoder().encode(dict)
        let _: SimklActionResponse = try await postData(path: "/sync/add-to-list", data: wrappedData)
    }

    func markWatched(
        imdbId: String,
        type: MediaType,
        watchedAt: Date = Date()
    ) async throws {
        let key = type == .movie ? "movies" : "shows"
        let formatter = ISO8601DateFormatter()
        let item = SimklAddItem(
            ids: SimklAddIds(imdb: imdbId),
            to: nil,
            watchedAt: formatter.string(from: watchedAt)
        )
        var dict: [String: [SimklAddItem]] = [:]
        dict[key] = [item]
        let wrappedData = try JSONEncoder().encode(dict)
        let _: SimklActionResponse = try await postData(path: "/sync/history", data: wrappedData)
    }

    // MARK: - Networking

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw SimklError.invalidURL }
        let data = try await performAuthenticatedRequest {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(self.clientId, forHTTPHeaderField: "simkl-api-key")
            return request
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postData<T: Decodable>(path: String, data body: Data) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw SimklError.invalidURL }
        let data = try await performAuthenticatedRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(self.clientId, forHTTPHeaderField: "simkl-api-key")
            request.httpBody = body
            return request
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postForm<T: Decodable>(path: String, parameters: [(String, String)]) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw SimklError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(self.clientId, forHTTPHeaderField: "simkl-api-key")
        request.httpBody = encodedFormBody(parameters)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SimklError.httpError(0)
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw SimklError.unauthorized
        default:
            throw SimklError.httpError(http.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func performAuthenticatedRequest(
        buildRequest: @escaping () -> URLRequest,
        allowRefreshRetry: Bool = true
    ) async throws -> Data {
        if accessToken?.isEmpty != false {
            guard refreshToken?.isEmpty == false else {
                throw SimklError.notConnected
            }
            try await refreshAccessToken()
        }

        guard let token = accessToken, !token.isEmpty else {
            throw SimklError.notConnected
        }

        var request = buildRequest()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SimklError.httpError(0)
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401 where allowRefreshRetry:
            guard refreshToken?.isEmpty == false else {
                throw SimklError.unauthorized
            }
            try await refreshAccessToken()
            return try await performAuthenticatedRequest(buildRequest: buildRequest, allowRefreshRetry: false)
        case 401:
            throw SimklError.unauthorized
        default:
            throw SimklError.httpError(http.statusCode)
        }
    }

    private func refreshAccessToken() async throws {
        let trimmedClientSecret = self.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientSecret.isEmpty else { throw SimklError.missingClientSecret }

        let storedRefreshToken = self.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let storedRefreshToken, !storedRefreshToken.isEmpty else {
            throw SimklError.notConnected
        }

        let response: SimklOAuthTokenResponse = try await postForm(
            path: "/oauth/token",
            parameters: [
                ("grant_type", "refresh_token"),
                ("client_id", self.clientId),
                ("client_secret", trimmedClientSecret),
                ("redirect_uri", redirectURI),
                ("refresh_token", storedRefreshToken),
            ]
        )

        guard !response.accessToken.isEmpty else {
            throw SimklError.invalidAuthorizationResponse
        }

        accessToken = response.accessToken
        if let refreshedRefreshToken = response.refreshToken, !refreshedRefreshToken.isEmpty {
            refreshToken = refreshedRefreshToken
        }
        await onTokensRefreshed?(response.accessToken, refreshToken)
    }

    private func encodedFormBody(_ parameters: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func beginAuthorizationSession() -> PendingSimklAuthorizationSession {
        let authorizationSession = PendingSimklAuthorizationSession.make()
        SimklAuthorizationSessionStore.store(authorizationSession, for: self.clientId)
        return authorizationSession
    }

    private func validateAuthorizationSession(returnedState: String?) throws -> PendingSimklAuthorizationSession {
        guard let authorizationSession = SimklAuthorizationSessionStore.session(for: self.clientId) else {
            throw SimklError.authorizationSessionMissing
        }
        guard !authorizationSession.isExpired else {
            clearAuthorizationSession()
            throw SimklError.authorizationSessionExpired
        }
        guard let returnedState, !returnedState.isEmpty else {
            clearAuthorizationSession()
            throw SimklError.authorizationStateMissing
        }
        if returnedState != authorizationSession.state {
            clearAuthorizationSession()
            throw SimklError.authorizationStateMismatch
        }
        return authorizationSession
    }

    private func clearAuthorizationSession() {
        SimklAuthorizationSessionStore.remove(clientId: self.clientId)
    }
}

private struct PendingSimklAuthorizationSession: Sendable {
    private static let lifetime: TimeInterval = 15 * 60

    let state: String
    let codeVerifier: String
    let codeChallenge: String
    let codeChallengeMethod = "S256"
    let createdAt: Date

    var isExpired: Bool {
        createdAt.addingTimeInterval(Self.lifetime) < Date()
    }

    static func make() -> PendingSimklAuthorizationSession {
        let verifier = SimklOAuthSecurityRandom.urlSafeToken(byteCount: 32)
        return PendingSimklAuthorizationSession(
            state: SimklOAuthSecurityRandom.urlSafeToken(byteCount: 16),
            codeVerifier: verifier,
            codeChallenge: SimklOAuthPKCE.codeChallenge(for: verifier),
            createdAt: Date()
        )
    }
}

struct SimklAuthorizationSessionStart: Sendable {
    let url: URL
    let state: String
}

private enum SimklAuthorizationSessionStore {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sessions: [String: PendingSimklAuthorizationSession] = [:]

    static func store(_ session: PendingSimklAuthorizationSession, for clientId: String) {
        lock.lock()
        sessions[clientId] = session
        lock.unlock()
    }

    static func session(for clientId: String) -> PendingSimklAuthorizationSession? {
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

private enum SimklOAuthSecurityRandom {
    static func urlSafeToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: .min ... .max)
            }
        }
        return Data(bytes).simklBase64URLEncodedString()
    }
}

private enum SimklOAuthPKCE {
    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).simklBase64URLEncodedString()
    }
}

private extension Data {
    func simklBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Request Models

private struct SimklAddIds: Codable, Sendable {
    let imdb: String
}

private struct SimklAddItem: Codable, Sendable {
    let ids: SimklAddIds
    let to: String?
    let watchedAt: String?

    enum CodingKeys: String, CodingKey {
        case ids
        case to
        case watchedAt = "watched_at"
    }
}

struct SimklActionResponse: Sendable {
    let added: SimklActionCount?
    let notFound: SimklActionCount?

    enum CodingKeys: String, CodingKey {
        case added
        case notFound = "not_found"
    }
}
extension SimklActionResponse: Decodable {}

struct SimklActionCount: Sendable {
    let movies: Int?
    let shows: Int?
}
extension SimklActionCount: Decodable {}

struct SimklOAuthTokenResponse: Sendable {
    let accessToken: String
    let tokenType: String?
    let refreshToken: String?
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

extension SimklOAuthTokenResponse: Decodable {}

// MARK: - Response Models

struct SimklSyncResponse: Sendable {
    let movies: [SimklItem]?
    let shows: [SimklItem]?
}
extension SimklSyncResponse: Decodable {}

struct SimklItem: Sendable {
    let lastWatchedAt: String?
    let status: String?
    let movie: SimklMedia?
    let show: SimklMedia?

    enum CodingKeys: String, CodingKey {
        case lastWatchedAt = "last_watched_at"
        case status, movie, show
    }
}
extension SimklItem: Decodable {}

struct SimklMedia: Sendable {
    let title: String
    let year: Int?
    let ids: SimklIds
}
extension SimklMedia: Decodable {}

struct SimklIds: Sendable {
    let simkl: Int?
    let imdb: String?
    let tmdb: String?
}
extension SimklIds: Decodable {}

enum SimklError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case unauthorized
    case notConnected
    case authorizationSessionMissing
    case authorizationSessionExpired
    case authorizationStateMismatch
    case authorizationStateMissing
    case invalidAuthorizationCode
    case missingClientSecret
    case invalidAuthorizationResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Simkl URL"
        case .httpError(let code): return "Simkl API error: HTTP \(code)"
        case .unauthorized: return "Simkl authorization expired"
        case .notConnected: return "Not connected to Simkl"
        case .authorizationSessionMissing: return "Start Simkl authorization again before entering the code."
        case .authorizationSessionExpired: return "The Simkl authorization session expired. Start the login flow again."
        case .authorizationStateMismatch: return "The Simkl authorization response did not match the active login session."
        case .authorizationStateMissing: return "Simkl authorization state is required to complete the login flow."
        case .invalidAuthorizationCode: return "Invalid Simkl authorization code"
        case .missingClientSecret: return "Simkl client secret is required"
        case .invalidAuthorizationResponse: return "Simkl authorization response was invalid"
        }
    }
}
