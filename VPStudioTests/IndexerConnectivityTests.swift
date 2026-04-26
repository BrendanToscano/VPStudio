import Foundation
import Testing
@testable import VPStudio

private enum IndexerConnectivityStubError: Error {
    case missingHandler
}

private final class IndexerConnectivityURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    static let lock = NSLock()
    static let handlerHeader = "X-VPStudio-Connectivity-Stub-ID"

    fileprivate static func register(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> String {
        let id = UUID().uuidString
        lock.lock()
        requestHandlers[id] = handler
        lock.unlock()
        return id
    }

    fileprivate static func handler(for id: String) -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        let handler = requestHandlers[id]
        lock.unlock()
        return handler
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: handlerHeader) != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handlerID = request.value(forHTTPHeaderField: Self.handlerHeader),
              let handler = Self.handler(for: handlerID) else {
            client?.urlProtocol(self, didFailWithError: IndexerConnectivityStubError.missingHandler)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite
struct IndexerConnectivityTests {
    @Test func connectivityErrorDescriptionsAreActionable() {
        let connectivityErrors: [IndexerConnectivityError] = [
            .invalidBaseURL,
            .missingAPIKey,
            .invalidResponse,
            .badStatusCode(503),
            .incompatibleManifest,
        ]

        for error in connectivityErrors {
            #expect(error.errorDescription?.isEmpty == false)
        }
        #expect(IndexerConnectivityError.badStatusCode(503).errorDescription?.contains("503") == true)
        #expect(IndexerRequestError.rateLimited.errorDescription?.contains("rate limit") == true)
    }

    @Test func torznabConnectionSuccessSendsHeaderApiKeyAndCapsQuery() async throws {
        final class RequestState: @unchecked Sendable {
            var headerValue: String?
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.headerValue = request.value(forHTTPHeaderField: "X-Api-Key")
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("<caps></caps>".utf8))
        }

        let config = IndexerConfig(
            id: "torznab-1",
            name: "My Torznab",
            indexerType: .torznab,
            baseURL: "https://indexer.example",
            apiKey: "my-key",
            isActive: true,
            priority: 0,
            apiKeyTransport: .header
        )

        try await IndexerConnectivityTester.testConnection(for: config, session: session)

        #expect(state.headerValue == "my-key")
        #expect(state.queryItems.first(where: { $0.name == "apikey" }) == nil)
        #expect(state.queryItems.first(where: { $0.name == "t" })?.value == "caps")
    }

    @Test func non2xxResponseIsReportedAsFailure() async {
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let config = IndexerConfig(
            id: "zilean-1",
            name: "Zilean",
            indexerType: .zilean,
            baseURL: "https://zilean.example",
            apiKey: nil,
            isActive: true,
            priority: 0
        )

        do {
            try await IndexerConnectivityTester.testConnection(for: config, session: session)
            Issue.record("Expected IndexerConnectivityError.badStatusCode")
        } catch let error as IndexerConnectivityError {
            if case .badStatusCode(let status) = error {
                #expect(status == 503)
            } else {
                Issue.record("Unexpected IndexerConnectivityError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func httpBaseURLsAreRejectedBeforeNetworkCall() async {
        let config = IndexerConfig(
            id: "torznab-http-1",
            name: "HTTP Torznab",
            indexerType: .torznab,
            baseURL: "http://indexer.example",
            apiKey: "key",
            isActive: true,
            priority: 0
        )

        do {
            _ = try IndexerConnectivityTester.makeRequest(for: config)
            Issue.record("Expected IndexerConnectivityError.invalidBaseURL")
        } catch let error as IndexerConnectivityError {
            if case .invalidBaseURL = error {
                return
            }
            Issue.record("Unexpected IndexerConnectivityError: \(error)")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func torznabMissingApiKeyIsRejectedBeforeNetworkCall() async {
        let config = IndexerConfig(
            id: "torznab-2",
            name: "Broken Torznab",
            indexerType: .torznab,
            baseURL: "https://indexer.example",
            apiKey: nil,
            isActive: true,
            priority: 0
        )

        do {
            try await IndexerConnectivityTester.testConnection(for: config)
            Issue.record("Expected IndexerConnectivityError.missingAPIKey")
        } catch let error as IndexerConnectivityError {
            if case .missingAPIKey = error {
                return
            }
            Issue.record("Unexpected IndexerConnectivityError: \(error)")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func prowlarrConnectionSendsApiKeyInHeader() async throws {
        final class RequestState: @unchecked Sendable {
            var headerValue: String?
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.headerValue = request.value(forHTTPHeaderField: "X-Api-Key")
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"records":[]}"#.utf8))
        }

        let config = IndexerConfig(
            id: "prowlarr-1",
            name: "Prowlarr",
            indexerType: .prowlarr,
            baseURL: "https://prowlarr.example",
            apiKey: "header-key",
            isActive: true,
            priority: 0,
            providerSubtype: .prowlarr,
            endpointPath: "/api/v1/search",
            categoryFilter: nil,
            apiKeyTransport: .header
        )

        try await IndexerConnectivityTester.testConnection(for: config, session: session)

        #expect(state.headerValue == "header-key")
        #expect(state.queryItems.first(where: { $0.name == "query" })?.value == "test")
    }

    @Test func jackettConnectionUsesConfiguredEndpointPath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String = ""
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.capturedPath = url.path
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("<caps></caps>".utf8))
        }

        let config = IndexerConfig(
            id: "jackett-1",
            name: "Jackett",
            indexerType: .jackett,
            baseURL: "https://jackett.example",
            apiKey: "query-key",
            isActive: true,
            priority: 0,
            providerSubtype: .jackett,
            endpointPath: "/api/v2.0/indexers/all/results/torznab/api",
            categoryFilter: nil,
            apiKeyTransport: .query
        )

        try await IndexerConnectivityTester.testConnection(for: config, session: session)
        #expect(state.capturedPath.hasSuffix("/api/v2.0/indexers/all/results/torznab/api"))
    }

    @Test func zileanConnectionUsesConfiguredEndpointPath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String = ""
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.capturedPath = url.path
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"results":[]}"#.utf8))
        }

        let config = IndexerConfig(
            id: "zilean-2",
            name: "Zilean",
            indexerType: .zilean,
            baseURL: "https://zilean.example",
            apiKey: nil,
            isActive: true,
            priority: 0,
            providerSubtype: .customTorznab,
            endpointPath: "/custom-api"
        )

        try await IndexerConnectivityTester.testConnection(for: config, session: session)
        #expect(state.capturedPath.hasSuffix("/custom-api/dmm/search"))
    }

    @Test func zileanRequestUsesDefaultPathAndPreservesAlreadyExpandedEndpoint() throws {
        let defaultRequest = try IndexerConnectivityTester.makeRequest(for: IndexerConfig(
            id: "zilean-default",
            name: "Zilean Default",
            indexerType: .zilean,
            baseURL: "https://zilean.example",
            apiKey: nil,
            isActive: true,
            priority: 0
        ))
        let expandedRequest = try IndexerConnectivityTester.makeRequest(for: IndexerConfig(
            id: "zilean-expanded",
            name: "Zilean Expanded",
            indexerType: .zilean,
            baseURL: "https://zilean.example/root",
            apiKey: nil,
            isActive: true,
            priority: 0,
            endpointPath: "/api/dmm/search"
        ))

        #expect(defaultRequest.url?.path == "/api/dmm/search")
        #expect(expandedRequest.url?.path == "/root/api/dmm/search")
    }

    @Test func stremioRequestUsesDefaultManifestPath() throws {
        let request = try IndexerConnectivityTester.makeRequest(for: IndexerConfig(
            id: "stremio-default",
            name: "Stremio Default",
            indexerType: .stremio,
            baseURL: "https://stremio-addon.example",
            apiKey: nil,
            isActive: true,
            priority: 0
        ))

        #expect(request.url?.path == "/manifest.json")
        #expect(request.url?.query == nil)
    }

    @Test func stremioConnectionTargetsManifestEndpoint() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String = ""
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.capturedPath = url.path
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"catalogs":[{"id":"search","type":"movie","extra":[{"name":"search"}]}]}"#
            return (response, Data(body.utf8))
        }

        let config = IndexerConfig(
            id: "stremio-1",
            name: "Stremio",
            indexerType: .stremio,
            baseURL: "https://stremio-addon.example",
            apiKey: nil,
            isActive: true,
            priority: 0,
            providerSubtype: .stremioAddon,
            endpointPath: "/manifest.json",
            categoryFilter: nil,
            apiKeyTransport: .query
        )

        try await IndexerConnectivityTester.testConnection(for: config, session: session)
        #expect(state.capturedPath.hasSuffix("/manifest.json"))
    }

    @Test func stremioConnectionRejectsIncompatibleManifest() async {
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"id":"addon.test"}"#.utf8))
        }

        let config = IndexerConfig(
            id: "stremio-2",
            name: "Stremio",
            indexerType: .stremio,
            baseURL: "https://stremio-addon.example",
            apiKey: nil,
            isActive: true,
            priority: 0,
            providerSubtype: .stremioAddon,
            endpointPath: "/manifest.json",
            categoryFilter: nil,
            apiKeyTransport: .query
        )

        do {
            try await IndexerConnectivityTester.testConnection(for: config, session: session)
            Issue.record("Expected IndexerConnectivityError.incompatibleManifest")
        } catch let error as IndexerConnectivityError {
            if case .incompatibleManifest = error {
                return
            }
            Issue.record("Unexpected IndexerConnectivityError: \(error)")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func stremioConnectionAcceptsSeriesSearchCatalogCaseInsensitively() async throws {
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"catalogs":[{"id":"series-search","type":"SERIES","extra":[{"name":"Search"}]}]}"#
            return (response, Data(body.utf8))
        }

        let config = IndexerConfig(
            id: "stremio-series",
            name: "Stremio Series",
            indexerType: .stremio,
            baseURL: "https://stremio-addon.example",
            apiKey: nil,
            isActive: true,
            priority: 0,
            providerSubtype: .stremioAddon,
            endpointPath: "/manifest.json",
            categoryFilter: nil,
            apiKeyTransport: .query
        )

        try await IndexerConnectivityTester.testConnection(for: config, session: session)
    }

    @Test func stremioConnectionRejectsCatalogsWithoutSearchExtra() async {
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"catalogs":[{"id":"movie","type":"movie","extra":[{"name":"genre"}]}]}"#
            return (response, Data(body.utf8))
        }

        let config = IndexerConfig(
            id: "stremio-no-search",
            name: "Stremio No Search",
            indexerType: .stremio,
            baseURL: "https://stremio-addon.example",
            apiKey: nil,
            isActive: true,
            priority: 0,
            providerSubtype: .stremioAddon,
            endpointPath: "/manifest.json",
            categoryFilter: nil,
            apiKeyTransport: .query
        )

        do {
            try await IndexerConnectivityTester.testConnection(for: config, session: session)
            Issue.record("Expected IndexerConnectivityError.incompatibleManifest")
        } catch IndexerConnectivityError.incompatibleManifest {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func ytsConnectionUsesReachableFallbackHost() throws {
        let config = IndexerConfig(
            id: "yts-1",
            name: "YTS",
            indexerType: .yts,
            baseURL: nil,
            apiKey: nil,
            isActive: true,
            priority: 0
        )

        let request = try IndexerConnectivityTester.makeRequest(for: config)
        let url = try #require(request.url)

        #expect(url.host == "yts.torrentbay.st")
        #expect(url.path.hasSuffix("/api/v2/list_movies.json"))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "limit" })?
            .value == "1")
    }

    @Test func builtInIndexerRequestsUseExpectedPathsAndJSONPayloads() async throws {
        final class RequestState: @unchecked Sendable {
            var paths: [String] = []
            var queries: [[URLQueryItem]] = []
        }
        let state = RequestState()
        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.paths.append(url.path)
            state.queries.append(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"[]"#.utf8))
        }

        try await IndexerConnectivityTester.testConnection(
            for: IndexerConfig(id: "apibay", name: "APIBay", indexerType: .apiBay, baseURL: nil, apiKey: nil, isActive: true, priority: 0),
            session: session
        )
        try await IndexerConnectivityTester.testConnection(
            for: IndexerConfig(id: "yts", name: "YTS", indexerType: .yts, baseURL: nil, apiKey: nil, isActive: true, priority: 0),
            session: session
        )
        try await IndexerConnectivityTester.testConnection(
            for: IndexerConfig(id: "eztv", name: "EZTV", indexerType: .eztv, baseURL: nil, apiKey: nil, isActive: true, priority: 0),
            session: session
        )

        #expect(state.paths.contains("/q.php"))
        #expect(state.paths.contains("/api/v2/list_movies.json"))
        #expect(state.paths.contains("/api/get-torrents"))
        #expect(state.queries.flatMap { $0 }.contains(URLQueryItem(name: "q", value: "test")))
        #expect(state.queries.flatMap { $0 }.contains(URLQueryItem(name: "limit", value: "1")))
    }

    @Test func jsonPayloadValidationRejectsNonJSONObjectPayloads() async {
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("not json".utf8))
        }

        let config = IndexerConfig(
            id: "zilean-invalid",
            name: "Zilean Invalid",
            indexerType: .zilean,
            baseURL: "https://zilean.example",
            apiKey: nil,
            isActive: true,
            priority: 0
        )

        do {
            try await IndexerConnectivityTester.testConnection(for: config, session: session)
            Issue.record("Expected IndexerConnectivityError.invalidResponse")
        } catch IndexerConnectivityError.invalidResponse {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func torznabCapsValidationAcceptsErrorRootAndRejectsUnexpectedRoot() async throws {
        let errorSession = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("<error code=\"100\" description=\"bad api key\" />".utf8))
        }
        let badRootSession = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("<rss></rss>".utf8))
        }
        let config = IndexerConfig(
            id: "torznab-caps",
            name: "Torznab Caps",
            indexerType: .torznab,
            baseURL: "https://indexer.example",
            apiKey: "key",
            isActive: true,
            priority: 0
        )

        try await IndexerConnectivityTester.testConnection(for: config, session: errorSession)
        do {
            try await IndexerConnectivityTester.testConnection(for: config, session: badRootSession)
            Issue.record("Expected IndexerConnectivityError.invalidResponse")
        } catch IndexerConnectivityError.invalidResponse {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func torznabCapsValidationRejectsMalformedXML() async {
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("<caps><broken></caps>".utf8))
        }
        let config = IndexerConfig(
            id: "torznab-malformed",
            name: "Torznab Malformed",
            indexerType: .torznab,
            baseURL: "https://indexer.example",
            apiKey: "key",
            isActive: true,
            priority: 0
        )

        do {
            try await IndexerConnectivityTester.testConnection(for: config, session: session)
            Issue.record("Expected malformed caps XML to be rejected")
        } catch IndexerConnectivityError.invalidResponse {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func requestLimiterRetriesRetryableStatusAndMapsPersistent429() async throws {
        final class RequestState: @unchecked Sendable { var count = 0 }
        let transient = RequestState()
        let transientSession = makeStubSession { request in
            transient.count += 1
            let url = try #require(request.url)
            let status = transient.count == 1 ? 503 : 200
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "0.001"])!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
        let rateLimitedSession = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0.001"])!
            return (response, Data())
        }
        let limiter = IndexerRequestLimiter(minimumRequestInterval: 0.001, maximumBackoffInterval: 0.001, maximumAttempts: 2)
        let request = URLRequest(url: URL(string: "https://indexer.example/api")!)

        let (_, response) = try await limiter.data(for: request, session: transientSession)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(transient.count == 2)

        do {
            _ = try await IndexerRequestLimiter(minimumRequestInterval: 0.001, maximumBackoffInterval: 0.001, maximumAttempts: 2)
                .data(for: request, session: rateLimitedSession)
            Issue.record("Expected IndexerRequestError.rateLimited")
        } catch IndexerRequestError.rateLimited {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func requestLimiterHonorsHTTPDateRetryAfterHeader() async throws {
        final class RequestState: @unchecked Sendable { var count = 0 }
        let state = RequestState()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        let retryAfter = formatter.string(from: Date(timeIntervalSinceNow: 60))

        let session = makeStubSession { request in
            state.count += 1
            let url = try #require(request.url)
            let status = state.count == 1 ? 503 : 200
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Retry-After": retryAfter]
            )!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
        let limiter = IndexerRequestLimiter(minimumRequestInterval: 0.001, maximumBackoffInterval: 0.001, maximumAttempts: 2)
        let request = URLRequest(url: URL(string: "https://indexer.example/api")!)

        let (_, response) = try await limiter.data(for: request, session: session)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(state.count == 2)
    }

    @Test func requestLimiterMapsTransportTimeoutAfterRetries() async {
        let session = makeThrowingStubSession { _ in
            throw URLError(.timedOut)
        }
        let limiter = IndexerRequestLimiter(minimumRequestInterval: 0.001, maximumBackoffInterval: 0.001, maximumAttempts: 2)
        let request = URLRequest(url: URL(string: "https://indexer.example/api")!)

        do {
            _ = try await limiter.data(for: request, session: session)
            Issue.record("Expected timeout URLError")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeStubSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let handlerID = IndexerConnectivityURLProtocolStub.register(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IndexerConnectivityURLProtocolStub.self]
        config.httpAdditionalHeaders = [IndexerConnectivityURLProtocolStub.handlerHeader: handlerID]
        return URLSession(configuration: config)
    }

    private func makeThrowingStubSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        makeStubSession(handler: handler)
    }
}
