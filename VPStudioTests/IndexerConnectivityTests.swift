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
    @Test func torznabConnectionSuccessIncludesApiKeyAndCapsQuery() async throws {
        final class RequestState: @unchecked Sendable {
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }

        let config = IndexerConfig(
            id: "torznab-1",
            name: "My Torznab",
            indexerType: .torznab,
            baseURL: "https://indexer.example",
            apiKey: "my-key",
            isActive: true,
            priority: 0
        )

        try await IndexerConnectivityTester.testConnection(for: config, session: session)

        #expect(state.queryItems.first(where: { $0.name == "apikey" })?.value == "my-key")
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
            return (response, Data("ok".utf8))
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
            return (response, Data("ok".utf8))
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

    @Test func stremioConnectionTargetsManifestEndpoint() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String = ""
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.capturedPath = url.path
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"id":"addon.test"}"#.utf8))
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

    private func makeStubSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let handlerID = IndexerConnectivityURLProtocolStub.register(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IndexerConnectivityURLProtocolStub.self]
        config.httpAdditionalHeaders = [IndexerConnectivityURLProtocolStub.handlerHeader: handlerID]
        return URLSession(configuration: config)
    }
}
