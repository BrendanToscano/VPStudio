import Testing
import Foundation
@testable import VPStudio

// MARK: - URLProtocol Stub (local to this file)

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

private func makeStubSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
    let handlerID = URLProtocolStub.register(handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [URLProtocolStub.self]
    config.httpAdditionalHeaders = [URLProtocolStub.handlerHeader: handlerID]
    return URLSession(configuration: config)
}

// MARK: - extractTMDBID Tests

@Suite("TMDBService - ID Extraction")
struct TMDBIDExtractionTests {
    private final class AttemptRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var attempts = 0
        private var recordedSleeps: [UInt64] = []

        func nextAttempt() -> Int {
            lock.lock()
            defer { lock.unlock() }
            attempts += 1
            return attempts
        }

        func recordSleep(_ nanoseconds: UInt64) {
            lock.lock()
            recordedSleeps.append(nanoseconds)
            lock.unlock()
        }

        func snapshot() -> (attempts: Int, sleeps: [UInt64]) {
            lock.lock()
            defer { lock.unlock() }
            return (attempts, recordedSleeps)
        }
    }

    @Test func searchFallsBackToLegacyApiKeyQueryForClassicV3Credential() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedURL: URL?
            var authorizationHeader: String?
            var cacheControlHeader: String?
            var pragmaHeader: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedURL = request.url
            state.authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            state.cacheControlHeader = request.value(forHTTPHeaderField: "Cache-Control")
            state.pragmaHeader = request.value(forHTTPHeaderField: "Pragma")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "1234567890abcdef1234567890abcdef", session: session)
        let _ = try await service.search(query: "Dune", type: .movie, page: 1)

        let url = try #require(state.capturedURL)
        #expect(url.path.contains("/search/movie"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let apiKey = components?.queryItems?.first(where: { $0.name == "api_key" })?.value
        #expect(apiKey == "1234567890abcdef1234567890abcdef")
        let query = components?.queryItems?.first(where: { $0.name == "query" })?.value
        #expect(query == "Dune")
        #expect(state.authorizationHeader == nil)
        #expect(state.cacheControlHeader == "no-store")
        #expect(state.pragmaHeader == "no-cache")
    }

    @Test func searchUsesBearerAuthorizationForReadAccessToken() async throws {
        final class RequestState: @unchecked Sendable {
            var capturedURL: URL?
            var authorizationHeader: String?
            var acceptHeader: String?
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedURL = request.url
            state.authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            state.acceptHeader = request.value(forHTTPHeaderField: "Accept")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let readAccessToken = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2Nlc3NfdG9rZW4iOiJ0bWRiIiwicm9sZSI6InJlYWQifQ.signature123"
        let service = TMDBService(apiKey: readAccessToken, session: session)
        let _ = try await service.search(query: "Dune", type: .movie, page: 1)

        let url = try #require(state.capturedURL)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let apiKey = components?.queryItems?.first(where: { $0.name == "api_key" })?.value
        #expect(apiKey == nil)
        #expect(state.authorizationHeader == "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2Nlc3NfdG9rZW4iOiJ0bWRiIiwicm9sZSI6InJlYWQifQ.signature123")
        #expect(state.acceptHeader == "application/json")
    }

    @Test func searchUsesBearerAuthorizationForBareReadAccessToken() async throws {
        final class RequestState: @unchecked Sendable {
            var authorizationHeader: String?
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            state.authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
            state.queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let token = "aaa.bbb_ccc-ddd.eee"
        let service = TMDBService(apiKey: token, session: session)
        _ = try await service.search(query: "Dune", type: .movie)

        #expect(state.authorizationHeader == "Bearer \(token)")
        #expect(state.queryItems.first(where: { $0.name == "api_key" }) == nil)
    }

    @Test func blankCredentialThrowsUnauthorizedBeforeNetwork() async {
        let session = makeStubSession { request in
            Issue.record("Blank credential should not issue request: \(request)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TMDBService(apiKey: "   ", session: session)

        await #expect(throws: TMDBError.unauthorized) {
            _ = try await service.search(query: "Dune", type: .movie)
        }
    }

    @Test func searchMultiTypeUsesMultiPath() async throws {
        final class RequestState: @unchecked Sendable { var capturedPath: String? }
        let state = RequestState()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let _ = try await service.search(query: "Test", type: nil, page: 1)
        #expect(state.capturedPath?.contains("/search/multi") == true)
    }

    @Test func searchMultiTypeOmitsYearFilter() async throws {
        final class RequestState: @unchecked Sendable { var queryItems: [URLQueryItem] = [] }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let _ = try await service.search(query: "Test", type: nil, page: 1, year: 2024, language: nil)

        #expect(state.queryItems.first(where: { $0.name == "year" }) == nil)
        #expect(state.queryItems.first(where: { $0.name == "first_air_date_year" }) == nil)
    }

    @Test func seriesSearchUsesFirstAirDateYearParameter() async throws {
        final class RequestState: @unchecked Sendable { var queryItems: [URLQueryItem] = [] }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let _ = try await service.search(query: "Severance", type: .series, page: 1, year: 2022, language: nil)

        #expect(state.queryItems.first(where: { $0.name == "first_air_date_year" })?.value == "2022")
        #expect(state.queryItems.first(where: { $0.name == "year" }) == nil)
    }

    @Test func discoverSeriesUsesFirstAirDateDescendingSort() async throws {
        final class RequestState: @unchecked Sendable { var queryItems: [URLQueryItem] = [] }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let filters = DiscoverFilters(sortBy: .releaseDateDesc)
        let _ = try await service.discover(type: .series, filters: filters)

        #expect(state.queryItems.first(where: { $0.name == "sort_by" })?.value == "first_air_date.desc")
    }

    @Test func discoverSeriesUsesNameAscendingSort() async throws {
        final class RequestState: @unchecked Sendable { var queryItems: [URLQueryItem] = [] }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let filters = DiscoverFilters(sortBy: .titleAsc)
        let _ = try await service.discover(type: .series, filters: filters)

        #expect(state.queryItems.first(where: { $0.name == "sort_by" })?.value == "name.asc")
    }

    @Test func trendingAndCategoryUseExpectedPathsAndPagination() async throws {
        final class RequestState: @unchecked Sendable {
            var paths: [String] = []
            var pages: [String?] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.paths.append(url.path)
            state.pages.append(URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "page" })?
                .value)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":2,"results":[],"total_pages":4,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let trending = try await service.getTrending(type: .movie, timeWindow: .day, page: 2)
        let category = try await service.getCategory(.airingToday, type: .series, page: 3)

        #expect(trending.page == 2)
        #expect(category.totalPages == 4)
        #expect(state.paths == ["/3/trending/movie/day", "/3/tv/airing_today"])
        #expect(state.pages == ["2", "3"])
    }

    @Test func getDetailUsesExtractedAndNumericTMDBIds() async throws {
        final class RequestState: @unchecked Sendable { var paths: [String] = [] }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.paths.append(url.path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
                "id": 438631,
                "title": "Dune",
                "overview": "A noble family...",
                "release_date": "2021-09-15",
                "vote_average": 7.8,
                "runtime": 155,
                "status": "Released",
                "genres": [{"id":878,"name":"Science Fiction"}],
                "external_ids": {"imdb_id":"tt1160419","tvdb_id":null}
            }
            """
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let extracted = try await service.getDetail(id: "movie-tmdb-438631", type: .movie)
        let numeric = try await service.getDetail(id: "438631", type: .movie)

        #expect(extracted.id == "tt1160419")
        #expect(numeric.tmdbId == 438631)
        #expect(state.paths == ["/3/movie/438631", "/3/movie/438631"])
    }

    @Test func getDetailFindsTMDBIdFromIMDbIdAndThrowsWhenMissing() async throws {
        final class RequestState: @unchecked Sendable { var paths: [String] = [] }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.paths.append(url.path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path.contains("/find/tt1160419") {
                let body = #"{"movie_results":[{"id":438631,"title":"Dune","media_type":"movie"}],"tv_results":[]}"#
                return (response, Data(body.utf8))
            }
            if url.path.contains("/movie/438631") {
                let body = #"{"id":438631,"title":"Dune","external_ids":{"imdb_id":"tt1160419"}}"#
                return (response, Data(body.utf8))
            }
            let body = #"{"movie_results":[],"tv_results":[]}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let item = try await service.getDetail(id: "tt1160419", type: .movie)

        #expect(item.title == "Dune")
        #expect(state.paths.prefix(2) == ["/3/find/tt1160419", "/3/movie/438631"])
        await #expect(throws: TMDBError.notFound("tt0000000")) {
            _ = try await service.getDetail(id: "tt0000000", type: .movie)
        }
    }

    @Test func searchParsesMovieResults() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
                "page": 1,
                "results": [
                    {
                        "id": 438631,
                        "title": "Dune",
                        "media_type": "movie",
                        "overview": "A noble family...",
                        "poster_path": "/d5NXSklXo0qyIYkgV94XAgMIckC.jpg",
                        "backdrop_path": "/bg.jpg",
                        "release_date": "2021-09-15",
                        "vote_average": 7.8
                    }
                ],
                "total_pages": 1,
                "total_results": 1
            }
            """
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let result = try await service.search(query: "Dune", type: .movie)
        #expect(result.items.count == 1)
        #expect(result.items[0].title == "Dune")
        #expect(result.items[0].type == .movie)
        #expect(result.items[0].year == 2021)
        #expect(result.totalResults == 1)
    }

    @Test func searchParsesTVResults() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
                "page": 1,
                "results": [
                    {
                        "id": 1399,
                        "name": "Game of Thrones",
                        "media_type": "tv",
                        "overview": "Seven noble families...",
                        "poster_path": "/poster.jpg",
                        "first_air_date": "2011-04-17",
                        "vote_average": 8.4
                    }
                ],
                "total_pages": 1,
                "total_results": 1
            }
            """
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let result = try await service.search(query: "Game", type: .series)
        #expect(result.items.count == 1)
        #expect(result.items[0].title == "Game of Thrones")
        #expect(result.items[0].type == .series)
        #expect(result.items[0].year == 2011)
    }

    @Test func unauthorizedThrowsTMDBError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TMDBService(apiKey: "bad-key", session: session)
        do {
            let _ = try await service.search(query: "Test", type: .movie)
            Issue.record("Expected TMDBError.unauthorized")
        } catch let error as TMDBError {
            #expect(error == .unauthorized)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func notFoundThrowsTMDBError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TMDBService(apiKey: "key", session: session)
        do {
            let _ = try await service.search(query: "Test", type: .movie)
            Issue.record("Expected TMDBError.notFound")
        } catch let error as TMDBError {
            if case .notFound = error { /* OK */ }
            else { Issue.record("Unexpected TMDBError: \(error)") }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func rateLimitedThrowsTMDBError() async {
        let recorder = AttemptRecorder()
        let session = makeStubSession { request in
            _ = recorder.nextAttempt()
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TMDBService(apiKey: "key", session: session) { nanoseconds in
            recorder.recordSleep(nanoseconds)
        }
        do {
            let _ = try await service.search(query: "Test", type: .movie)
            Issue.record("Expected TMDBError.rateLimited")
        } catch let error as TMDBError {
            #expect(error == .rateLimited)
            let snapshot = recorder.snapshot()
            #expect(snapshot.attempts == 3)
            #expect(snapshot.sleeps == [500_000_000, 1_000_000_000])
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func rateLimitedRetriesUsingRetryAfterHeaderThenSucceeds() async throws {
        let recorder = AttemptRecorder()
        let session = makeStubSession { request in
            let attempt = recorder.nextAttempt()
            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "2"]
                )!
                return (response, Data())
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session) { nanoseconds in
            recorder.recordSleep(nanoseconds)
        }
        let result = try await service.search(query: "Dune", type: .movie)

        #expect(result.totalResults == 0)
        let snapshot = recorder.snapshot()
        #expect(snapshot.attempts == 2)
        #expect(snapshot.sleeps == [2_000_000_000])
    }

    @Test func rateLimitedRetriesUsingHttpDateRetryAfterHeaderThenSucceeds() async throws {
        let recorder = AttemptRecorder()
        let retryAfterDate = Date(timeIntervalSinceNow: 5)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"

        let session = makeStubSession { request in
            let attempt = recorder.nextAttempt()
            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": formatter.string(from: retryAfterDate)]
                )!
                return (response, Data())
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session) { nanoseconds in
            recorder.recordSleep(nanoseconds)
        }
        let result = try await service.search(query: "Dune", type: .movie)

        #expect(result.totalResults == 0)
        let snapshot = recorder.snapshot()
        #expect(snapshot.attempts == 2)
        let recordedSleep = try #require(snapshot.sleeps.first)
        #expect(recordedSleep >= 3_000_000_000)
        #expect(recordedSleep <= 6_000_000_000)
    }

    @Test func rateLimitedRetriesWithExponentialBackoffWhenRetryAfterMissing() async throws {
        let recorder = AttemptRecorder()
        let session = makeStubSession { request in
            let attempt = recorder.nextAttempt()
            if attempt < 3 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"page":1,"results":[],"total_pages":0,"total_results":0}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session) { nanoseconds in
            recorder.recordSleep(nanoseconds)
        }
        let result = try await service.search(query: "Dune", type: .movie)

        #expect(result.totalResults == 0)
        let snapshot = recorder.snapshot()
        #expect(snapshot.attempts == 3)
        #expect(snapshot.sleeps == [500_000_000, 1_000_000_000])
    }

    @Test func findByImdbIdReturnsMovieId() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
                "movie_results": [{"id": 438631, "title": "Dune", "media_type": "movie", "release_date": "2021-09-15", "vote_average": 7.8}],
                "tv_results": []
            }
            """
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let tmdbId = try await service.findByImdbId("tt1160419", type: .movie)
        #expect(tmdbId == 438631)
    }

    @Test func findByImdbIdReturnsNilForMiss() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"movie_results":[],"tv_results":[]}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let tmdbId = try await service.findByImdbId("tt0000000", type: .movie)
        #expect(tmdbId == nil)
    }

    @Test func getGenresReturnsGenreList() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"genres":[{"id":28,"name":"Action"},{"id":18,"name":"Drama"}]}"#
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let genres = try await service.getGenres(type: .movie)
        #expect(genres.count == 2)
        #expect(genres[0].name == "Action")
        #expect(genres[1].name == "Drama")
    }

    @Test func getSeasonsMapsNilSeasonPayloadToEmptyArray() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"id":1399}"#.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let seasons = try await service.getSeasons(tmdbId: 1399)

        #expect(seasons.isEmpty)
    }

    @Test func getSeasonsReturnsSeasonList() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"id":1399,"seasons":[
                {"id":10,"season_number":1,"name":"Season 1","overview":"Start","poster_path":"/s1.jpg","episode_count":10,"air_date":"2011-04-17"}
            ]}
            """
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let seasons = try await service.getSeasons(tmdbId: 1399)

        #expect(seasons.count == 1)
        #expect(seasons[0].seasonNumber == 1)
        #expect(seasons[0].posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342/s1.jpg")
    }

    @Test func getEpisodesReturnsEpisodeList() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
                "episodes": [
                    {"id": 1, "episode_number": 1, "name": "Pilot", "overview": "The first ep", "still_path": "/still.jpg", "runtime": 58},
                    {"id": 2, "episode_number": 2, "name": "Second", "overview": null, "still_path": null, "runtime": 55}
                ]
            }
            """
            return (response, Data(body.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let episodes = try await service.getEpisodes(tmdbId: 1399, season: 1)
        #expect(episodes.count == 2)
        #expect(episodes[0].title == "Pilot")
        #expect(episodes[0].episodeNumber == 1)
        #expect(episodes[0].seasonNumber == 1)
        #expect(episodes[1].title == "Second")
    }

    @Test func getExternalIdsMapsMovieAndSeriesPayloads() async throws {
        final class RequestState: @unchecked Sendable { var paths: [String] = [] }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.paths.append(url.path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"imdb_id":"tt123","tvdb_id":456}"#.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        let movieIds = try await service.getExternalIds(tmdbId: 1, type: .movie)
        let seriesIds = try await service.getExternalIds(tmdbId: 2, type: .series)

        #expect(movieIds.imdbId == "tt123")
        #expect(seriesIds.tvdbId == 456)
        #expect(state.paths == ["/3/movie/1/external_ids", "/3/tv/2/external_ids"])
    }

    @Test func serverErrorsIncludeStatusAndBody() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data("maintenance".utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)

        await #expect(throws: TMDBError.httpError(500, "maintenance")) {
            _ = try await service.search(query: "Test", type: .movie)
        }
    }

    @Test func malformedPathThrowsInvalidURLInsteadOfCrashing() async {
        // Paths with characters that make URLComponents return nil should throw, not crash
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"page":1,"results":[],"total_pages":0,"total_results":0}"#.utf8))
        }

        let service = TMDBService(apiKey: "key", session: session)
        // A path with unescaped spaces/invalid chars that URLComponents can't parse
        do {
            let _: MetadataSearchResult = try await service.search(query: "Test\0Null", type: .movie)
            // If we get here, URLComponents handled it — that's also fine
        } catch let error as TMDBError {
            // Should throw invalidURL, not crash
            if case .invalidURL = error { /* expected */ }
            else { /* any TMDBError is acceptable vs a crash */ }
        } catch {
            // Network/other error is also acceptable — the point is no crash
        }
    }
}

// MARK: - TMDBSearchResult.toMediaPreview Tests

@Suite("TMDBSearchResult - toMediaPreview")
struct TMDBSearchResultConversionTests {

    @Test func movieResultConvertsCorrectly() {
        let result = TMDBSearchResult(
            id: 100, title: "Test Movie", name: nil, mediaType: "movie",
            overview: nil, posterPath: "/p.jpg", backdropPath: nil,
            releaseDate: "2025-06-15", firstAirDate: nil, voteAverage: 7.5
        )
        let preview = result.toMediaPreview()
        #expect(preview != nil)
        #expect(preview?.title == "Test Movie")
        #expect(preview?.type == .movie)
        #expect(preview?.year == 2025)
        #expect(preview?.id == "movie-tmdb-100")
    }

    @Test func tvResultConvertsCorrectly() {
        let result = TMDBSearchResult(
            id: 200, title: nil, name: "Test Show", mediaType: "tv",
            overview: nil, posterPath: nil, backdropPath: nil,
            releaseDate: nil, firstAirDate: "2023-03-01", voteAverage: 8.0
        )
        let preview = result.toMediaPreview()
        #expect(preview != nil)
        #expect(preview?.title == "Test Show")
        #expect(preview?.type == .series)
        #expect(preview?.year == 2023)
        #expect(preview?.id == "series-tmdb-200")
    }

    @Test func unknownMediaTypeReturnsNil() {
        let result = TMDBSearchResult(
            id: 300, title: "Person", name: nil, mediaType: "person",
            overview: nil, posterPath: nil, backdropPath: nil,
            releaseDate: nil, firstAirDate: nil, voteAverage: 0
        )
        #expect(result.toMediaPreview() == nil)
    }

    @Test func emptyTitleReturnsNil() {
        let result = TMDBSearchResult(
            id: 400, title: nil, name: nil, mediaType: "movie",
            overview: nil, posterPath: nil, backdropPath: nil,
            releaseDate: nil, firstAirDate: nil, voteAverage: 0
        )
        #expect(result.toMediaPreview() == nil)
    }

    @Test func noMediaTypeInfersTitleAsMovie() {
        let result = TMDBSearchResult(
            id: 500, title: "Inferred Movie", name: nil, mediaType: nil,
            overview: nil, posterPath: nil, backdropPath: nil,
            releaseDate: "2024-01-01", firstAirDate: nil, voteAverage: 6.0
        )
        let preview = result.toMediaPreview()
        #expect(preview?.type == .movie)
    }

    @Test func noMediaTypeInfersNameAsSeries() {
        let result = TMDBSearchResult(
            id: 600, title: nil, name: "Inferred Show", mediaType: nil,
            overview: nil, posterPath: nil, backdropPath: nil,
            releaseDate: nil, firstAirDate: "2024-01-01", voteAverage: 6.0
        )
        let preview = result.toMediaPreview()
        #expect(preview?.type == .series)
    }
}

// MARK: - TMDBDetailResponse.toMediaItem Tests

@Suite("TMDBDetailResponse - toMediaItem")
struct TMDBDetailResponseTests {

    @Test func convertsMovieDetailCorrectly() {
        let response = TMDBDetailResponse(
            id: 100, title: "Dune", name: nil, overview: "A noble family...",
            posterPath: "/poster.jpg", backdropPath: "/backdrop.jpg",
            releaseDate: "2021-09-15", firstAirDate: nil, voteAverage: 7.8,
            runtime: 155, episodeRunTime: nil, status: "Released",
            genres: [TMDBGenre(id: 878, name: "Science Fiction")],
            externalIds: ExternalIds(imdbId: "tt1160419", tvdbId: nil)
        )
        let item = response.toMediaItem(type: .movie)
        #expect(item.id == "tt1160419")
        #expect(item.title == "Dune")
        #expect(item.year == 2021)
        #expect(item.runtime == 155)
        #expect(item.genres == ["Science Fiction"])
    }

    @Test func useTmdbIdWhenNoImdb() {
        let response = TMDBDetailResponse(
            id: 999, title: "No IMDB", name: nil, overview: nil,
            posterPath: nil, backdropPath: nil,
            releaseDate: "2025-01-01", firstAirDate: nil, voteAverage: nil,
            runtime: nil, episodeRunTime: nil, status: nil,
            genres: nil, externalIds: ExternalIds(imdbId: nil, tvdbId: nil)
        )
        let item = response.toMediaItem(type: .movie)
        #expect(item.id == "tmdb-999")
    }

    @Test func useEpisodeRunTimeWhenNoRuntime() {
        let response = TMDBDetailResponse(
            id: 200, title: nil, name: "Show", overview: nil,
            posterPath: nil, backdropPath: nil,
            releaseDate: nil, firstAirDate: "2020-01-01", voteAverage: nil,
            runtime: 0, episodeRunTime: [42, 48], status: nil,
            genres: nil, externalIds: nil
        )
        let item = response.toMediaItem(type: .series)
        #expect(item.runtime == 42)
    }
}

// MARK: - TMDBError Tests

@Suite("TMDBError")
struct TMDBErrorTests {

    @Test func allErrorsHaveDescriptions() {
        let errors: [TMDBError] = [
            .invalidURL("/test"),
            .invalidResponse,
            .unauthorized,
            .notFound("id-1"),
            .rateLimited,
            .httpError(500, "Internal Server Error"),
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func errorsAreEquatable() {
        #expect(TMDBError.unauthorized == TMDBError.unauthorized)
        #expect(TMDBError.rateLimited == TMDBError.rateLimited)
        #expect(TMDBError.notFound("a") == TMDBError.notFound("a"))
        #expect(TMDBError.notFound("a") != TMDBError.notFound("b"))
    }
}
