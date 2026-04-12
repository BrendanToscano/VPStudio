import Foundation

enum IndexerConnectivityError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case invalidResponse
    case badStatusCode(Int)
    case incompatibleManifest

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
        case .incompatibleManifest:
            return "Indexer manifest is not compatible with VPStudio search."
        }
    }
}

enum IndexerRequestError: LocalizedError {
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Indexer rate limit was exceeded."
        }
    }
}

enum IndexerConnectivityTester {
    static func testConnection(for config: IndexerConfig, session: URLSession = .shared) async throws {
        if config.indexerType == .stremio {
            try await validateStremioManifest(for: config, session: session)
            return
        }

        let request = try makeRequest(for: config)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IndexerConnectivityError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw IndexerConnectivityError.badStatusCode(http.statusCode)
        }
    }

    private static func validateStremioManifest(for config: IndexerConfig, session: URLSession) async throws {
        let request = try makeRequest(for: config)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IndexerConnectivityError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw IndexerConnectivityError.badStatusCode(http.statusCode)
        }

        let manifest = try JSONDecoder().decode(StremioManifestResponse.self, from: data)
        guard let catalogs = manifest.catalogs, !catalogs.isEmpty else {
            throw IndexerConnectivityError.incompatibleManifest
        }
        guard catalogs.contains(where: { $0.isCompatible }) else {
            throw IndexerConnectivityError.incompatibleManifest
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
            let endpointPath: String
            if config.endpointPath.isEmpty {
                endpointPath = "/dmm/search"
            } else if config.endpointPath.hasSuffix("/dmm/search") {
                endpointPath = config.endpointPath
            } else {
                endpointPath = "\(config.endpointPath)/dmm/search"
            }
            url = try buildURL(baseURL: baseURL, path: endpointPath, queryItems: [
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
              scheme == "https" else {
            throw IndexerConnectivityError.invalidBaseURL
        }
        return url
    }
}

actor IndexerRequestLimiter {
    private let minimumRequestInterval: TimeInterval
    private let maximumBackoffInterval: TimeInterval
    private let maximumAttempts: Int
    private var lastRequestDate: Date?
    private var nextAllowedRequestDate: Date?

    init(
        minimumRequestInterval: TimeInterval = 0.15,
        maximumBackoffInterval: TimeInterval = 5,
        maximumAttempts: Int = 3
    ) {
        self.minimumRequestInterval = minimumRequestInterval
        self.maximumBackoffInterval = maximumBackoffInterval
        self.maximumAttempts = max(1, maximumAttempts)
    }

    func data(from url: URL, session: URLSession) async throws -> (Data, URLResponse) {
        try await execute(request: URLRequest(url: url), session: session)
    }

    func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        try await execute(request: request, session: session)
    }

    private func execute(request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            try await waitForRequestSlot()

            let (data, response) = try await session.data(for: request)
            defer { lastRequestDate = Date() }

            guard let http = response as? HTTPURLResponse else {
                return (data, response)
            }

            guard http.statusCode == 429 else {
                return (data, response)
            }

            guard attempt < maximumAttempts else {
                throw IndexerRequestError.rateLimited
            }

            let delay = max(
                retryDelay(from: http) ?? 0,
                exponentialBackoffDelay(for: attempt)
            )
            nextAllowedRequestDate = Date().addingTimeInterval(max(delay, minimumRequestInterval))
        }
    }

    private func waitForRequestSlot() async throws {
        let now = Date()
        let earliestAllowed = max(
            nextAllowedRequestDate ?? now,
            lastRequestDate?.addingTimeInterval(minimumRequestInterval) ?? now
        )
        let delay = earliestAllowed.timeIntervalSince(now)
        if delay > 0 {
            try await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
        }
        try Task.checkCancellation()
    }

    private func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let seconds = TimeInterval(value),
              seconds > 0 else {
            return nil
        }

        return min(maximumBackoffInterval, seconds)
    }

    private func exponentialBackoffDelay(for attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let multiplier = pow(2.0, Double(min(exponent, 5)))
        return min(maximumBackoffInterval, minimumRequestInterval * multiplier)
    }

    private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64((max(interval, 0) * 1_000_000_000).rounded())
    }
}

private struct StremioManifestResponse: Decodable {
    let catalogs: [StremioManifestCatalog]?
}

private struct StremioManifestCatalog: Decodable {
    let type: String
    let extra: [StremioManifestExtra]?

    var isCompatible: Bool {
        let supportedType = type.caseInsensitiveCompare("movie") == .orderedSame
            || type.caseInsensitiveCompare("series") == .orderedSame
        return supportedType && (extra?.contains(where: { $0.name.caseInsensitiveCompare("search") == .orderedSame }) == true)
    }
}

private struct StremioManifestExtra: Decodable {
    let name: String
}
