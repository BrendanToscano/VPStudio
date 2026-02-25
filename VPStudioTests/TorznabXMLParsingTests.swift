import Testing
import Foundation
@testable import VPStudio

@Suite("TorznabIndexer XML Parsing")
struct TorznabXMLParsingTests {

    private func makeIndexer(session: URLSession = .shared) -> TorznabIndexer {
        TorznabIndexer(name: "TestIndexer", baseURL: "https://indexer.example", apiKey: "key", session: session)
    }

    @Test func parsesAttributesInNameThenValueOrder() async throws {
        let xml = """
        <?xml version="1.0"?>
        <rss><channel>
        <item>
        <title>Movie.2025.1080p</title>
        <torznab:attr name="infohash" value="abc123def456"/>
        <torznab:attr name="seeders" value="50"/>
        <torznab:attr name="size" value="2000000000"/>
        </item>
        </channel></rss>
        """

        let session = makeStubSession(xml: xml)
        let indexer = makeIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "Movie", type: .movie)

        #expect(results.count == 1)
        #expect(results.first?.infoHash == "abc123def456")
        #expect(results.first?.seeders == 50)
    }

    @Test func parsesAttributesInValueThenNameOrder() async throws {
        let xml = """
        <?xml version="1.0"?>
        <rss><channel>
        <item>
        <title>Movie.2025.1080p</title>
        <torznab:attr value="abc123def456" name="infohash"/>
        <torznab:attr value="50" name="seeders"/>
        <torznab:attr value="2000000000" name="size"/>
        </item>
        </channel></rss>
        """

        let session = makeStubSession(xml: xml)
        let indexer = makeIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "Movie", type: .movie)

        #expect(results.count == 1)
        #expect(results.first?.infoHash == "abc123def456")
        #expect(results.first?.seeders == 50)
    }

    @Test func parsesAttributesInMixedOrder() async throws {
        let xml = """
        <?xml version="1.0"?>
        <rss><channel>
        <item>
        <title>Movie.2025.2160p.DV</title>
        <torznab:attr name="infohash" value="hash999"/>
        <torznab:attr value="120" name="seeders"/>
        <torznab:attr name="size" value="5000000000"/>
        <torznab:attr value="10" name="peers"/>
        </item>
        </channel></rss>
        """

        let session = makeStubSession(xml: xml)
        let indexer = makeIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "Movie", type: .movie)

        #expect(results.count == 1)
        #expect(results.first?.infoHash == "hash999")
        #expect(results.first?.seeders == 120)
        #expect(results.first?.leechers == 10)
    }
}

// MARK: - Helper

private enum StubError: Error { case missingHandler }

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    static let lock = NSLock()
    static let handlerHeader = "X-VPStudio-Stub-ID"

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
            client?.urlProtocol(self, didFailWithError: StubError.missingHandler); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    override func stopLoading() {}
}

private func makeStubSession(xml: String) -> URLSession {
    let handlerID = URLProtocolStub.register { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(xml.utf8))
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLProtocolStub.self]
    config.httpAdditionalHeaders = [URLProtocolStub.handlerHeader: handlerID]
    return URLSession(configuration: config)
}
