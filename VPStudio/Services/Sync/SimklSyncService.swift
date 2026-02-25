import Foundation

/// Simkl.com sync service
actor SimklSyncService {
    private let clientId: String
    private let baseURL = "https://api.simkl.com"
    private let session: URLSession
    private var accessToken: String?

    init(clientId: String, session: URLSession = .shared) {
        self.clientId = clientId
        self.session = session
    }

    func setAccessToken(_ token: String) {
        accessToken = token
    }

    // MARK: - OAuth

    func getAuthorizationURL() -> URL? {
        var components = URLComponents(string: "https://simkl.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: "urn:ietf:wg:oauth:2.0:oob"),
        ]
        return components?.url
    }

    // MARK: - Sync

    func getWatchlist() async throws -> SimklSyncResponse {
        guard accessToken?.isEmpty == false else { throw SimklError.notConnected }
        return try await get(path: "/sync/all-items/?episode_watched_at=yes")
    }

    func addToList(imdbId: String, type: MediaType, list: String = "plantowatch") async throws {
        guard accessToken?.isEmpty == false else { throw SimklError.notConnected }

        let key = type == .movie ? "movies" : "shows"
        let item = SimklAddItem(ids: SimklAddIds(imdb: imdbId), to: list)

        var dict: [String: [SimklAddItem]] = [:]
        dict[key] = [item]
        let wrappedData = try JSONEncoder().encode(dict)
        let _: SimklActionResponse = try await postData(path: "/sync/add-to-list", data: wrappedData)
    }

    func markWatched(imdbId: String, type: MediaType) async throws {
        guard accessToken?.isEmpty == false else { throw SimklError.notConnected }

        let key = type == .movie ? "movies" : "shows"
        let item = SimklAddItem(ids: SimklAddIds(imdb: imdbId), to: nil)
        var dict: [String: [SimklAddItem]] = [:]
        dict[key] = [item]
        let wrappedData = try JSONEncoder().encode(dict)
        let _: SimklActionResponse = try await postData(path: "/sync/history", data: wrappedData)
    }

    // MARK: - Networking

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw SimklError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "simkl-api-key")
        guard let token = accessToken, !token.isEmpty else { throw SimklError.notConnected }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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

    private func postData<T: Decodable>(path: String, data body: Data) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw SimklError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "simkl-api-key")
        guard let token = accessToken, !token.isEmpty else { throw SimklError.notConnected }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

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
}

// MARK: - Request Models

private struct SimklAddIds: Codable, Sendable {
    let imdb: String
}

private struct SimklAddItem: Codable, Sendable {
    let ids: SimklAddIds
    let to: String?
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

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Simkl URL"
        case .httpError(let code): return "Simkl API error: HTTP \(code)"
        case .unauthorized: return "Simkl authorization expired"
        case .notConnected: return "Not connected to Simkl"
        }
    }
}
