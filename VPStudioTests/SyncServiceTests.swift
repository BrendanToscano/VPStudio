import Testing
import Foundation
@testable import VPStudio

// MARK: - URL Protocol Stub

private enum SyncStubError: Error {
    case missingHandler
}

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
            client?.urlProtocol(self, didFailWithError: SyncStubError.missingHandler)
            return
        }
        var sanitizedRequest = request
        sanitizedRequest.setValue(nil, forHTTPHeaderField: Self.handlerHeader)
        let requestForHandler = Self.materializeBodyIfNeeded(from: sanitizedRequest)
        do {
            let (response, data) = try handler(requestForHandler)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func materializeBodyIfNeeded(from request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let bodyStream = request.httpBodyStream else {
            return request
        }

        var copy = request
        copy.httpBody = readAllBytes(from: bodyStream)
        return copy
    }

    private static func readAllBytes(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 {
                break
            }
            output.append(buffer, count: read)
        }
        return output
    }
}

private func makeStubSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    let handlerID = URLProtocolStub.register(handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLProtocolStub.self]
    config.httpAdditionalHeaders = [URLProtocolStub.handlerHeader: handlerID]
    return URLSession(configuration: config)
}

// MARK: - TraktSyncService Tests

@Suite("TraktSyncService - OAuth")
struct TraktOAuthTests {

    @Test func getAuthorizationURLContainsClientId() async {
        let service = TraktSyncService(clientId: "my-client-id", clientSecret: "secret")
        let url = await service.getAuthorizationURL()
        #expect(url != nil)
        #expect(url!.absoluteString.contains("my-client-id"))
        #expect(url!.absoluteString.contains("response_type=code"))
        #expect(url!.absoluteString.contains("redirect_uri=urn"))
    }

    @Test func getAuthorizationURLHostIsTrakt() async {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret")
        let url = await service.getAuthorizationURL()
        #expect(url?.host == "trakt.tv")
    }

    @Test func exchangeCodeSetsTokens() async throws {
        let session = makeStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
                "access_token": "access-abc",
                "refresh_token": "refresh-xyz",
                "token_type": "Bearer",
                "expires_in": 7776000,
                "created_at": 1600000000
            }
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        try await service.exchangeCode("auth-code-123")
        let tokens = await service.currentTokens()
        #expect(tokens.access == "access-abc")
        #expect(tokens.refresh == "refresh-xyz")
    }

    @Test func setTokensUpdatesCurrentTokens() async {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret")
        await service.setTokens(access: "manual-access", refresh: "manual-refresh")
        let tokens = await service.currentTokens()
        #expect(tokens.access == "manual-access")
        #expect(tokens.refresh == "manual-refresh")
    }

    @Test func exchangeCodeSendsCorrectBody() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedBody: [String: Any]?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = request.url!
            if let body = request.httpBody {
                state.capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {"access_token":"t","refresh_token":"r","token_type":"Bearer","expires_in":100,"created_at":1}
            """
            return (response, Data(payload.utf8))
        }

        let service = TraktSyncService(clientId: "my-client", clientSecret: "my-secret", session: session)
        try await service.exchangeCode("the-code")

        #expect(state.capturedBody?["code"] as? String == "the-code")
        #expect(state.capturedBody?["client_id"] as? String == "my-client")
        #expect(state.capturedBody?["client_secret"] as? String == "my-secret")
        #expect(state.capturedBody?["grant_type"] as? String == "authorization_code")
    }
}

@Suite("TraktSyncService - API Calls", .serialized)
struct TraktAPICallTests {

    private func makeAuthedService(session: URLSession) -> TraktSyncService {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        return service
    }

    @Test func getWatchlistThrowsNotConnectedWithoutToken() async {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret")
        do {
            let _ = try await service.getWatchlist(type: .movie)
            Issue.record("Expected TraktError.notConnected")
        } catch let error as TraktError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected TraktError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func getHistoryThrowsNotConnectedWithoutToken() async {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret")
        do {
            let _ = try await service.getHistory(type: .movie)
            Issue.record("Expected TraktError.notConnected")
        } catch let error as TraktError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected TraktError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func getRatingsThrowsNotConnectedWithoutToken() async {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret")
        do {
            let _ = try await service.getRatings(type: .movie)
            Issue.record("Expected TraktError.notConnected")
        } catch let error as TraktError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected TraktError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func getWatchedThrowsNotConnectedWithoutToken() async {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret")
        do {
            let _ = try await service.getWatched(type: .series)
            Issue.record("Expected TraktError.notConnected")
        } catch let error as TraktError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected TraktError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func getWatchlistParsesMovieResponse() async throws {
        let session = makeStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {
                    "rank": 1,
                    "listed_at": "2025-01-15T10:30:00.000Z",
                    "movie": {
                        "title": "Dune: Part Two",
                        "year": 2024,
                        "ids": {
                            "trakt": 12345,
                            "slug": "dune-part-two-2024",
                            "imdb": "tt15239678",
                            "tmdb": 693134
                        }
                    }
                }
            ]
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "valid-token", refresh: "refresh")
        let items = try await service.getWatchlist(type: .movie)

        #expect(items.count == 1)
        #expect(items[0].movie?.title == "Dune: Part Two")
        #expect(items[0].movie?.year == 2024)
        #expect(items[0].movie?.ids.imdb == "tt15239678")
        #expect(items[0].rank == 1)
    }

    @Test func getWatchlistParsesShowResponse() async throws {
        let session = makeStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {
                    "rank": 1,
                    "show": {
                        "title": "The Last of Us",
                        "year": 2023,
                        "ids": {
                            "trakt": 1234,
                            "imdb": "tt3581920",
                            "tmdb": 100088
                        }
                    }
                }
            ]
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "valid-token", refresh: "refresh")
        let items = try await service.getWatchlist(type: .series)

        #expect(items.count == 1)
        #expect(items[0].show?.title == "The Last of Us")
        #expect(items[0].show?.ids.tmdb == 100088)
    }

    @Test func getHistoryParsesResponse() async throws {
        let session = makeStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {
                    "id": 9999,
                    "watched_at": "2025-02-01T20:00:00.000Z",
                    "action": "watch",
                    "movie": {
                        "title": "Oppenheimer",
                        "year": 2023,
                        "ids": {
                            "trakt": 555,
                            "imdb": "tt15398776"
                        }
                    }
                }
            ]
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: "refresh")
        let items = try await service.getHistory(type: .movie, page: 1)

        #expect(items.count == 1)
        #expect(items[0].id == 9999)
        #expect(items[0].action == "watch")
        #expect(items[0].movie?.title == "Oppenheimer")
    }

    @Test func getRatingsParsesResponse() async throws {
        let session = makeStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {
                    "rating": 9,
                    "rated_at": "2025-01-20T12:00:00.000Z",
                    "movie": {
                        "title": "Interstellar",
                        "year": 2014,
                        "ids": {"trakt": 111, "imdb": "tt0816692"}
                    }
                }
            ]
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: "refresh")
        let items = try await service.getRatings(type: .movie)

        #expect(items.count == 1)
        #expect(items[0].rating == 9)
        #expect(items[0].movie?.title == "Interstellar")
    }

    @Test func getWatchedParsesResponse() async throws {
        let session = makeStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {
                    "plays": 3,
                    "last_watched_at": "2025-02-10T20:00:00.000Z",
                    "show": {
                        "title": "Breaking Bad",
                        "year": 2008,
                        "ids": {"trakt": 1388, "imdb": "tt0903747"}
                    }
                }
            ]
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: "refresh")
        let items = try await service.getWatched(type: .series)

        #expect(items.count == 1)
        #expect(items[0].plays == 3)
        #expect(items[0].show?.title == "Breaking Bad")
    }

    @Test func getWatchlistUsesCorrectPathForMovies() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        let _ = try await service.getWatchlist(type: .movie)

        #expect(state.capturedPath?.hasSuffix("/sync/watchlist/movies") == true)
    }

    @Test func getWatchlistUsesCorrectPathForShows() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        let _ = try await service.getWatchlist(type: .series)

        #expect(state.capturedPath?.hasSuffix("/sync/watchlist/shows") == true)
    }

    @Test func requestIncludesCorrectHeaders() async throws {
        final class RequestState: @unchecked Sendable {
            var headers: [String: String] = [:]
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.headers = request.allHTTPHeaderFields ?? [:]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = TraktSyncService(clientId: "my-client-id", clientSecret: "secret", session: session)
        await service.setTokens(access: "my-access-token", refresh: nil)
        let _ = try await service.getWatchlist(type: .movie)

        #expect(state.headers["trakt-api-version"] == "2")
        #expect(state.headers["trakt-api-key"] == "my-client-id")
        #expect(state.headers["Authorization"] == "Bearer my-access-token")
        #expect(state.headers["Content-Type"] == "application/json")
    }

    @Test func httpErrorThrowsTraktError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)

        do {
            let _: [TraktItem] = try await service.getWatchlist(type: .movie)
            Issue.record("Expected TraktError.httpError")
        } catch let error as TraktError {
            if case .httpError(let code) = error {
                #expect(code == 500)
            } else { Issue.record("Unexpected TraktError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func addToWatchlistSendsPostWithImdbId() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
            var capturedMethod: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            state.capturedMethod = request.httpMethod
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"added":{"movies":1,"shows":0,"episodes":0}}
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.addToWatchlist(imdbId: "tt1234567", type: .movie)

        #expect(state.capturedPath?.hasSuffix("/sync/watchlist") == true)
        #expect(state.capturedMethod == "POST")
    }

    @Test func removeFromWatchlistSendsPostToRemovePath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"deleted":{"movies":1,"shows":0,"episodes":0}}
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.removeFromWatchlist(imdbId: "tt1234567", type: .movie)

        #expect(state.capturedPath?.hasSuffix("/sync/watchlist/remove") == true)
    }

    @Test func addToHistorySendsPostToHistoryPath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"added":{"movies":1,"shows":0,"episodes":0}}
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.addToHistory(imdbId: "tt1234567", type: .movie)

        #expect(state.capturedPath?.hasSuffix("/sync/history") == true)
    }

    @Test func startScrobbleSendsCorrectPath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"id":1,"action":"start"}
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.startScrobble(imdbId: "tt1234567", type: .movie, progress: 10.0)

        #expect(state.capturedPath?.hasSuffix("/scrobble/start") == true)
    }

    @Test func pauseScrobbleSendsCorrectPath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"id":1,"action":"pause"}
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.pauseScrobble(imdbId: "tt1234567", type: .movie, progress: 45.0)

        #expect(state.capturedPath?.hasSuffix("/scrobble/pause") == true)
    }

    @Test func stopScrobbleSendsCorrectPath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"id":1,"action":"scrobble"}
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.stopScrobble(imdbId: "tt1234567", type: .movie, progress: 95.0)

        #expect(state.capturedPath?.hasSuffix("/scrobble/stop") == true)
    }

    @Test func postRetriesToRefreshTokenOn401() async throws {
        final class RequestState: @unchecked Sendable {
            var scrobbleCallCount = 0
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = request.url!
            let path = url.path

            // Token refresh endpoint
            if request.httpMethod == "POST" && path.hasSuffix("/oauth/token") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {"access_token":"new-token","refresh_token":"new-refresh"}
                """
                return (response, Data(body.utf8))
            }

            // Scrobble endpoint
            if path.hasSuffix("/scrobble/start") {
                state.scrobbleCallCount += 1
                if state.scrobbleCallCount == 1 {
                    let unauthorized = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (unauthorized, Data())
                }
                let success = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (success, Data(#"{"id":1,"action":"start"}"#.utf8))
            }

            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "old-token", refresh: "refresh-token")
        try await service.startScrobble(imdbId: "tt1234567", type: .movie, progress: 10.0)

        #expect(state.scrobbleCallCount == 2)
    }

    @Test func refreshThrowsUnauthorizedWithNoRefreshToken() async {
        let session = makeStubSession { request in
            let url = request.url!
            let unauthorized = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (unauthorized, Data())
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)

        do {
            let _ = try await service.getWatchlist(type: .movie)
            Issue.record("Expected TraktError.unauthorized")
        } catch let error as TraktError {
            if case .unauthorized = error { /* OK */ }
            else { Issue.record("Unexpected TraktError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}

// MARK: - TraktError Tests

@Suite("TraktError")
struct TraktErrorTests {

    @Test func allErrorsHaveDescriptions() {
        let errors: [TraktError] = [
            .invalidURL,
            .httpError(500),
            .unauthorized,
            .notConnected,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func httpErrorIncludesStatusCode() {
        let error = TraktError.httpError(429)
        #expect(error.errorDescription?.contains("429") == true)
    }
}

// MARK: - TraktItem Model Tests

@Suite("Trakt Models")
struct TraktModelTests {

    @Test func traktItemDecodesMovieAndShow() throws {
        let json = """
        {"rank":1,"listed_at":"2025-01-01","movie":{"title":"Dune","year":2021,"ids":{"trakt":1,"imdb":"tt1160419","tmdb":438631}}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let item = try decoder.decode(TraktItem.self, from: Data(json.utf8))

        #expect(item.rank == 1)
        #expect(item.movie?.title == "Dune")
        #expect(item.movie?.ids.imdb == "tt1160419")
        #expect(item.show == nil)
    }

    @Test func traktHistoryItemDecodesWithEpisode() throws {
        let json = """
        {"id":1000,"watched_at":"2025-02-01","action":"watch","show":{"title":"Lost","year":2004,"ids":{"trakt":73}},"episode":{"season":1,"number":1,"title":"Pilot","ids":{"trakt":100}}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let item = try decoder.decode(TraktHistoryItem.self, from: Data(json.utf8))

        #expect(item.id == 1000)
        #expect(item.episode?.season == 1)
        #expect(item.episode?.number == 1)
        #expect(item.episode?.title == "Pilot")
        #expect(item.show?.title == "Lost")
    }

    @Test func traktRatingItemDecodes() throws {
        let json = """
        {"rating":8,"rated_at":"2025-01-20","movie":{"title":"Arrival","year":2016,"ids":{"trakt":50,"imdb":"tt2543164"}}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let item = try decoder.decode(TraktRatingItem.self, from: Data(json.utf8))

        #expect(item.rating == 8)
        #expect(item.movie?.title == "Arrival")
    }

    @Test func traktWatchedItemDecodes() throws {
        let json = """
        {"plays":5,"last_watched_at":"2025-02-10","last_updated_at":"2025-02-10","show":{"title":"Seinfeld","year":1989,"ids":{"trakt":200}}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let item = try decoder.decode(TraktWatchedItem.self, from: Data(json.utf8))

        #expect(item.plays == 5)
        #expect(item.show?.title == "Seinfeld")
    }

    @Test func traktIdsAllOptional() throws {
        let json = """
        {"trakt":null,"slug":null,"imdb":null,"tmdb":null}
        """
        let decoder = JSONDecoder()
        let ids = try decoder.decode(TraktIds.self, from: Data(json.utf8))

        #expect(ids.trakt == nil)
        #expect(ids.slug == nil)
        #expect(ids.imdb == nil)
        #expect(ids.tmdb == nil)
    }
}

// MARK: - SimklSyncService Tests

@Suite("SimklSyncService - OAuth")
struct SimklOAuthTests {

    @Test func getAuthorizationURLContainsClientId() async {
        let service = SimklSyncService(clientId: "simkl-client-id")
        let url = await service.getAuthorizationURL()
        #expect(url != nil)
        #expect(url!.absoluteString.contains("simkl-client-id"))
        #expect(url!.absoluteString.contains("response_type=code"))
    }

    @Test func getAuthorizationURLHostIsSimkl() async {
        let service = SimklSyncService(clientId: "client")
        let url = await service.getAuthorizationURL()
        #expect(url?.host == "simkl.com")
    }
}

@Suite("SimklSyncService - API Calls", .serialized)
struct SimklAPICallTests {

    @Test func getWatchlistThrowsNotConnectedWithoutToken() async {
        let service = SimklSyncService(clientId: "client")
        do {
            let _ = try await service.getWatchlist()
            Issue.record("Expected SimklError.notConnected")
        } catch let error as SimklError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func addToListThrowsNotConnectedWithoutToken() async {
        let service = SimklSyncService(clientId: "client")
        do {
            try await service.addToList(imdbId: "tt1234567", type: .movie)
            Issue.record("Expected SimklError.notConnected")
        } catch let error as SimklError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func markWatchedThrowsNotConnectedWithoutToken() async {
        let service = SimklSyncService(clientId: "client")
        do {
            try await service.markWatched(imdbId: "tt1234567", type: .movie)
            Issue.record("Expected SimklError.notConnected")
        } catch let error as SimklError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func getWatchlistParsesResponse() async throws {
        let session = makeStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
                "movies": [
                    {
                        "last_watched_at": "2025-02-01",
                        "status": "plantowatch",
                        "movie": {
                            "title": "Gladiator II",
                            "year": 2024,
                            "ids": {"simkl": 1, "imdb": "tt9218128", "tmdb": "558449"}
                        }
                    }
                ],
                "shows": []
            }
            """
            return (response, Data(body.utf8))
        }

        let service = SimklSyncService(clientId: "client", session: session)
        await service.setAccessToken("valid-token")
        let resp = try await service.getWatchlist()

        #expect(resp.movies?.count == 1)
        #expect(resp.movies?[0].movie?.title == "Gladiator II")
        #expect(resp.movies?[0].status == "plantowatch")
        #expect(resp.movies?[0].movie?.ids.imdb == "tt9218128")
        #expect(resp.shows?.isEmpty == true)
    }

    @Test func requestIncludesSimklApiKeyHeader() async throws {
        final class RequestState: @unchecked Sendable {
            var headers: [String: String] = [:]
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.headers = request.allHTTPHeaderFields ?? [:]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"movies":[],"shows":[]}"#.utf8))
        }

        let service = SimklSyncService(clientId: "my-simkl-key", session: session)
        await service.setAccessToken("token")
        let _ = try await service.getWatchlist()

        #expect(state.headers["simkl-api-key"] == "my-simkl-key")
        #expect(state.headers["Authorization"] == "Bearer token")
    }

    @Test func unauthorized401ThrowsSimklError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = SimklSyncService(clientId: "client", session: session)
        await service.setAccessToken("expired-token")

        do {
            let _ = try await service.getWatchlist()
            Issue.record("Expected SimklError.unauthorized")
        } catch let error as SimklError {
            if case .unauthorized = error { /* OK */ }
            else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func httpErrorThrowsSimklError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = SimklSyncService(clientId: "client", session: session)
        await service.setAccessToken("token")

        do {
            let _ = try await service.getWatchlist()
            Issue.record("Expected SimklError.httpError")
        } catch let error as SimklError {
            if case .httpError(let code) = error {
                #expect(code == 503)
            } else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func addToListSendsPostToCorrectPath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
            var capturedMethod: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            state.capturedMethod = request.httpMethod
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"added":{"movies":1}}"#
            return (response, Data(body.utf8))
        }

        let service = SimklSyncService(clientId: "client", session: session)
        await service.setAccessToken("token")
        try await service.addToList(imdbId: "tt1234567", type: .movie, list: "plantowatch")

        #expect(state.capturedPath?.hasSuffix("/sync/add-to-list") == true)
        #expect(state.capturedMethod == "POST")
    }

    @Test func markWatchedSendsPostToHistoryPath() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"added":{"movies":1}}"#
            return (response, Data(body.utf8))
        }

        let service = SimklSyncService(clientId: "client", session: session)
        await service.setAccessToken("token")
        try await service.markWatched(imdbId: "tt1234567", type: .movie)

        #expect(state.capturedPath?.hasSuffix("/sync/history") == true)
    }

    @Test func setAccessTokenEnablesAPIAccess() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"movies":[],"shows":[]}"#.utf8))
        }

        let service = SimklSyncService(clientId: "client", session: session)

        // Before setting token - should throw
        do {
            let _ = try await service.getWatchlist()
            Issue.record("Expected SimklError.notConnected")
        } catch is SimklError { /* expected */ }
        catch { Issue.record("Unexpected error: \(error)") }

        // After setting token - should work
        await service.setAccessToken("new-token")
        let resp = try await service.getWatchlist()
        #expect(resp.movies?.isEmpty == true)
    }
}

// MARK: - SimklError Tests

@Suite("SimklError")
struct SimklErrorTests {

    @Test func allErrorsHaveDescriptions() {
        let errors: [SimklError] = [
            .invalidURL,
            .httpError(500),
            .unauthorized,
            .notConnected,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func httpErrorIncludesStatusCode() {
        let error = SimklError.httpError(429)
        #expect(error.errorDescription?.contains("429") == true)
    }
}

// MARK: - Simkl Model Tests

@Suite("Simkl Models")
struct SimklModelTests {

    @Test func simklSyncResponseDecodes() throws {
        let json = """
        {
            "movies": [
                {"last_watched_at":"2025-01-01","status":"completed","movie":{"title":"Test","year":2025,"ids":{"simkl":1,"imdb":"tt1","tmdb":"2"}}}
            ],
            "shows": null
        }
        """
        let response = try JSONDecoder().decode(SimklSyncResponse.self, from: Data(json.utf8))
        #expect(response.movies?.count == 1)
        #expect(response.shows == nil)
    }

    @Test func simklItemDecodesWithCustomKeys() throws {
        let json = """
        {"last_watched_at":"2025-02-01","status":"watching","movie":{"title":"Movie","year":2025,"ids":{"simkl":1}}}
        """
        let item = try JSONDecoder().decode(SimklItem.self, from: Data(json.utf8))
        #expect(item.lastWatchedAt == "2025-02-01")
        #expect(item.status == "watching")
    }

    @Test func simklMediaDecodes() throws {
        let json = """
        {"title":"Example Show","year":2024,"ids":{"simkl":42,"imdb":"tt9999999","tmdb":"555"}}
        """
        let media = try JSONDecoder().decode(SimklMedia.self, from: Data(json.utf8))
        #expect(media.title == "Example Show")
        #expect(media.year == 2024)
        #expect(media.ids.simkl == 42)
        #expect(media.ids.imdb == "tt9999999")
        #expect(media.ids.tmdb == "555")
    }

    @Test func simklIdsAllOptional() throws {
        let json = """
        {"simkl":null,"imdb":null,"tmdb":null}
        """
        let ids = try JSONDecoder().decode(SimklIds.self, from: Data(json.utf8))
        #expect(ids.simkl == nil)
        #expect(ids.imdb == nil)
        #expect(ids.tmdb == nil)
    }

    @Test func simklActionResponseDecodes() throws {
        let json = """
        {"added":{"movies":1,"shows":0},"not_found":{"movies":0,"shows":0}}
        """
        let response = try JSONDecoder().decode(SimklActionResponse.self, from: Data(json.utf8))
        #expect(response.added?.movies == 1)
        #expect(response.notFound?.movies == 0)
    }
}
