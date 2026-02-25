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
