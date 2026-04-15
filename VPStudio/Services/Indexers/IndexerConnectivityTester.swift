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
        let request = try makeRequest(for: config)
        let limiter = IndexerRequestLimiter()
        let (data, response) = try await limiter.data(for: request, session: session)
        guard let http = response as? HTTPURLResponse else {
            throw IndexerConnectivityError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw IndexerConnectivityError.badStatusCode(http.statusCode)
        }
        try validatePayload(data, for: config)
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

    private static func validatePayload(_ data: Data, for config: IndexerConfig) throws {
        switch config.indexerType {
        case .stremio:
            let manifest = try JSONDecoder().decode(StremioManifestResponse.self, from: data)
            guard let catalogs = manifest.catalogs, !catalogs.isEmpty else {
                throw IndexerConnectivityError.incompatibleManifest
            }
            guard catalogs.contains(where: { $0.isCompatible }) else {
                throw IndexerConnectivityError.incompatibleManifest
            }

        case .jackett, .torznab:
            try validateTorznabCapsPayload(data)

        case .prowlarr, .apiBay, .yts, .eztv, .zilean:
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  object is [String: Any] || object is [[String: Any]] || object is [Any] else {
                throw IndexerConnectivityError.invalidResponse
            }
        }
    }

    private static func validateTorznabCapsPayload(_ data: Data) throws {
        let parser = XMLParser(data: data)
        let delegate = ConnectivityTorznabCapsParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw IndexerConnectivityError.invalidResponse
        }

        guard let root = delegate.rootElement?.lowercased(),
              root == "caps" || root == "error" else {
            throw IndexerConnectivityError.invalidResponse
        }
    }
}

actor IndexerRequestLimiter {
    private let minimumRequestInterval: TimeInterval
    private let maximumBackoffInterval: TimeInterval
    private let maximumAttempts: Int
    private var lastRequestDate: Date?
    private var nextAllowedRequestDate: Date?
    private let retryableStatusCodes: Set<Int> = [408, 425, 429, 500, 502, 503, 504]
    private let retryableTransportErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .networkConnectionLost,
        .notConnectedToInternet,
        .resourceUnavailable
    ]

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

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where retryableTransportErrorCodes.contains(urlError.code) && attempt < maximumAttempts {
                let delay = exponentialBackoffDelay(for: attempt)
                nextAllowedRequestDate = Date().addingTimeInterval(max(delay, minimumRequestInterval))
                continue
            }
            defer { lastRequestDate = Date() }

            guard let http = response as? HTTPURLResponse else {
                return (data, response)
            }

            guard retryableStatusCodes.contains(http.statusCode) else {
                return (data, response)
            }

            guard attempt < maximumAttempts else {
                if http.statusCode == 429 {
                    throw IndexerRequestError.rateLimited
                }
                return (data, response)
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
              !value.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(value), seconds > 0 {
            return min(maximumBackoffInterval, seconds)
        }

        guard let date = IndexerRetryHeaderDateParser.date(from: value) else {
            return nil
        }

        let interval = date.timeIntervalSinceNow
        guard interval > 0 else {
            return nil
        }

        return min(maximumBackoffInterval, interval)
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

private final class ConnectivityTorznabCapsParserDelegate: NSObject, XMLParserDelegate {
    private(set) var rootElement: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        if rootElement == nil {
            rootElement = elementName
        }
    }
}

private enum IndexerRetryHeaderDateParser {
    private static let formatters: [DateFormatter] = {
        let formatter1 = DateFormatter()
        formatter1.locale = Locale(identifier: "en_US_POSIX")
        formatter1.timeZone = TimeZone(secondsFromGMT: 0)
        formatter1.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"

        let formatter2 = DateFormatter()
        formatter2.locale = Locale(identifier: "en_US_POSIX")
        formatter2.timeZone = TimeZone(secondsFromGMT: 0)
        formatter2.dateFormat = "EEEE',' dd-MMM-yy HH':'mm':'ss zzz"

        let formatter3 = DateFormatter()
        formatter3.locale = Locale(identifier: "en_US_POSIX")
        formatter3.timeZone = TimeZone(secondsFromGMT: 0)
        formatter3.dateFormat = "EEE MMM d HH':'mm':'ss yyyy"

        return [formatter1, formatter2, formatter3]
    }()

    static func date(from value: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
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
