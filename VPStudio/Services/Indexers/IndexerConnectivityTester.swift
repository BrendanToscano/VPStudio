import Foundation

enum IndexerConnectivityError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case invalidResponse
    case badStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid indexer base URL."
        case .missingAPIKey:
            return "API key is required for this indexer."
        case .invalidResponse:
            return "Indexer did not return a valid HTTP response."
        case .badStatusCode(let code):
            return "Indexer returned HTTP \(code)."
        }
    }
}

enum IndexerConnectivityTester {
    static func testConnection(for config: IndexerConfig, session: URLSession = .shared) async throws {
        let request = try makeRequest(for: config)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IndexerConnectivityError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw IndexerConnectivityError.badStatusCode(http.statusCode)
        }
    }

    static func makeRequest(for config: IndexerConfig) throws -> URLRequest {
        let url: URL

        switch config.indexerType {
        case .apiBay:
            let baseURL = config.baseURL ?? "https://apibay.org"
            url = try buildURL(baseURL: baseURL, path: "/q.php", queryItems: [
                URLQueryItem(name: "q", value: "test"),
                URLQueryItem(name: "cat", value: "0"),
            ])

        case .yts:
            url = try buildURL(baseURL: "https://yts.torrentbay.st", path: "/api/v2/list_movies.json", queryItems: [
                URLQueryItem(name: "limit", value: "1"),
            ])

        case .eztv:
            url = try buildURL(baseURL: "https://eztvx.to", path: "/api/get-torrents", queryItems: [
                URLQueryItem(name: "limit", value: "1"),
            ])

        case .jackett, .torznab:
            guard let baseURL = config.baseURL else {
                throw IndexerConnectivityError.invalidBaseURL
            }
            let endpointPath = config.endpointPath.isEmpty ? "/api" : config.endpointPath
            let apiKey = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw IndexerConnectivityError.missingAPIKey
            }
            var queryItems = [
                URLQueryItem(name: "t", value: "caps"),
            ]
            if config.apiKeyTransport == .query {
                queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
            }
            url = try buildURL(baseURL: baseURL, path: endpointPath, queryItems: queryItems)

        case .prowlarr:
            guard let baseURL = config.baseURL else {
                throw IndexerConnectivityError.invalidBaseURL
            }
            let endpointPath = config.endpointPath.isEmpty ? "/api/v1/search" : config.endpointPath
            let apiKey = (config.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw IndexerConnectivityError.missingAPIKey
            }
            url = try buildURL(baseURL: baseURL, path: endpointPath, queryItems: [
                URLQueryItem(name: "query", value: "test"),
            ])

        case .zilean:
            guard let baseURL = config.baseURL else {
                throw IndexerConnectivityError.invalidBaseURL
            }
            url = try buildURL(baseURL: baseURL, path: "/dmm/search", queryItems: [
                URLQueryItem(name: "query", value: "test"),
            ])

        case .stremio:
            guard let baseURL = config.baseURL else {
                throw IndexerConnectivityError.invalidBaseURL
            }
            let manifestPath = config.endpointPath.isEmpty ? "/manifest.json" : config.endpointPath
            url = try buildURL(baseURL: baseURL, path: manifestPath, queryItems: [])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.httpMethod = "GET"

        if (config.indexerType == .prowlarr || config.apiKeyTransport == .header),
           let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        }

        return request
    }

    private static func buildURL(baseURL: String, path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw IndexerConnectivityError.invalidBaseURL
        }

        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let appendPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch (normalizedPath.isEmpty, appendPath.isEmpty) {
        case (true, false):
            components.path = "/\(appendPath)"
        case (false, true):
            components.path = "/\(normalizedPath)"
        case (false, false):
            components.path = "/\(normalizedPath)/\(appendPath)"
        default:
            components.path = ""
        }

        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw IndexerConnectivityError.invalidBaseURL
        }
        return url
    }
}
