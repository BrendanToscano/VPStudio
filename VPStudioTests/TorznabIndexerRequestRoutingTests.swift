import Foundation
import Testing
@testable import VPStudio

@Suite("TorznabIndexer Request Routing")
struct TorznabIndexerRequestRoutingTests {
    @Test func prowlarrSearchByQueryAddsTypeParameterForMovies() async throws {
        final class RequestState: @unchecked Sendable {
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let indexer = TorznabIndexer(
            name: "Prowlarr",
            baseURL: "https://prowlarr.example",
            endpointPath: "/api/v1/search",
            apiKey: "api-key",
            apiKeyTransport: .header,
            session: session
        )

        _ = try await indexer.searchByQuery(query: "Dune", type: .movie)

        #expect(state.queryItems.first(where: { $0.name == "type" })?.value == "moviesearch")
        #expect(state.queryItems.first(where: { $0.name == "query" })?.value == "Dune")
    }

    @Test func prowlarrImdbSearchUsesStructuredSeriesTokens() async throws {
        final class RequestState: @unchecked Sendable {
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let indexer = TorznabIndexer(
            name: "Prowlarr",
            baseURL: "https://prowlarr.example",
            endpointPath: "/api/v1/search",
            apiKey: "api-key",
            apiKeyTransport: .header,
            session: session
        )

        _ = try await indexer.search(imdbId: "tt0944947", type: .series, season: 1, episode: 2)

        #expect(state.queryItems.first(where: { $0.name == "type" })?.value == "tvsearch")
        #expect(
            state.queryItems.first(where: { $0.name == "query" })?.value
                == "{ImdbId:tt0944947} {Season:1} {Episode:2}"
        )
    }

    @Test func torznabIndexerRejectsHttpBaseURLs() async {
        let session = makeStubSession { request in
            Issue.record("Unexpected network request: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let indexer = TorznabIndexer(
            name: "HTTP Torznab",
            baseURL: "http://torznab.example",
            endpointPath: "/api",
            apiKey: "api-key",
            apiKeyTransport: .header,
            session: session
        )

        do {
            _ = try await indexer.searchByQuery(query: "Dune", type: .movie)
            Issue.record("Expected URLError.unsupportedURL")
        } catch let error as URLError {
            #expect(error.code == .unsupportedURL || error.code == .badURL)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func torznabQuerySearchFiltersSeriesResultsByEpisodeTokens() async throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <item>
              <title>Project Blue Book S01E02 1080p</title>
              <guid>aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</guid>
              <size>123456789</size>
              <torznab:attr xmlns:torznab="http://torznab.com/schemas/2015/feed" name="seeders" value="12" />
            </item>
            <item>
              <title>Project Blue Book S01E03 1080p</title>
              <guid>bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb</guid>
              <size>123456789</size>
              <torznab:attr xmlns:torznab="http://torznab.com/schemas/2015/feed" name="seeders" value="9" />
            </item>
          </channel>
        </rss>
        """

        let session = makeStubSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(xml.utf8))
        }

        let indexer = TorznabIndexer(
            name: "Torznab",
            baseURL: "https://torznab.example",
            endpointPath: "/api",
            apiKey: "api-key",
            apiKeyTransport: .header,
            session: session
        )

        let results = try await indexer.searchByQuery(query: "Project Blue Book S01E02", type: .series)

        #expect(results.map(\.infoHash) == ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
    }
}

private enum TorznabRequestStubError: Error {
    case missingHandler
}

private final class TorznabRequestURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    static let lock = NSLock()
    static let handlerHeader = "X-VPStudio-Torznab-Stub-ID"

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
            client?.urlProtocol(self, didFailWithError: TorznabRequestStubError.missingHandler)
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

private func makeStubSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    let handlerID = TorznabRequestURLProtocolStub.register(handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TorznabRequestURLProtocolStub.self]
    config.httpAdditionalHeaders = [TorznabRequestURLProtocolStub.handlerHeader: handlerID]
    return URLSession(configuration: config)
}
