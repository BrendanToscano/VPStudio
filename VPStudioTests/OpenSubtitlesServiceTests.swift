import Testing
import Foundation
@testable import VPStudio

// MARK: - Stub Session Helper

private func makeSubtitleStubSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    URLProtocolHarness.makeSession(handler: handler)
}

// MARK: - Search Tests

@Suite("OpenSubtitlesService - Search")
struct OpenSubtitlesSearchTests {

    private static let sampleSearchResponse = """
    {
        "data": [
            {
                "id": 100,
                "attributes": {
                    "language": "en",
                    "release": "Movie.2024.1080p.WEB-DL",
                    "ratings": 8.5,
                    "download_count": 1500,
                    "hearing_impaired": false,
                    "files": [
                        {"file_id": 200, "file_name": "Movie.2024.1080p.WEB-DL.srt"}
                    ]
                }
            },
            {
                "id": 101,
                "attributes": {
                    "language": "en",
                    "release": "Movie.2024.720p",
                    "ratings": 7.0,
                    "download_count": 800,
                    "hearing_impaired": true,
                    "files": [
                        {"file_id": 201, "file_name": "Movie.2024.720p.srt"}
                    ]
                }
            }
        ]
    }
    """

    @Test func searchMapsResponseToSubtitleArray() async throws {
        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.sampleSearchResponse.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "test-key", session: session)
        let results = try await service.search(query: "Movie 2024")

        #expect(results.count == 2)
        #expect(results[0].id == "100")
        #expect(results[0].language == "en")
        #expect(results[0].fileName == "Movie.2024.1080p.WEB-DL.srt")
        #expect(results[0].format == .srt)
        #expect(results[0].fileId == 200)
        #expect(results[0].rating == 8.5)
        #expect(results[0].downloadCount == 1500)
        #expect(results[0].isHearingImpaired == false)
    }

    @Test func searchWithIMDBIdIncludesParam() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedURL: URL?
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "test-key", session: session)
        let _ = try await service.search(imdbId: "tt1234567")

        let urlString = state.capturedURL?.absoluteString ?? ""
        // Should strip "tt" prefix
        #expect(urlString.contains("imdb_id=1234567"))
    }

    @Test func searchWithTMDBIdIncludesParam() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedURL: URL?
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "test-key", session: session)
        let _ = try await service.search(tmdbId: 693134)

        let urlString = state.capturedURL?.absoluteString ?? ""
        #expect(urlString.contains("tmdb_id=693134"))
    }

    @Test func searchWithQueryIncludesParam() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedURL: URL?
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "test-key", session: session)
        let _ = try await service.search(query: "Oppenheimer")

        let urlString = state.capturedURL?.absoluteString ?? ""
        #expect(urlString.contains("query=Oppenheimer"))
    }

    @Test func searchIncludesLanguageParam() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedURL: URL?
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "test-key", session: session)
        let _ = try await service.search(languages: ["en", "es"])

        let urlString = state.capturedURL?.absoluteString ?? ""
        #expect(urlString.contains("languages=en,es"))
    }

    @Test func searchIncludesSeasonAndEpisodeParams() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedURL: URL?
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "test-key", session: session)
        let _ = try await service.search(query: "Show", season: 2, episode: 5)

        let urlString = state.capturedURL?.absoluteString ?? ""
        #expect(urlString.contains("season_number=2"))
        #expect(urlString.contains("episode_number=5"))
    }

    @Test func searchSendsCorrectHeaders() async throws {
        final class CapturedState: @unchecked Sendable {
            var headers: [String: String] = [:]
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.headers = request.allHTTPHeaderFields ?? [:]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "my-api-key", session: session)
        let _ = try await service.search(query: "Test")

        #expect(state.headers["Api-Key"] == "my-api-key")
        #expect(state.headers["Content-Type"] == "application/json")
        #expect(state.headers["User-Agent"] == "VPStudio v1.0")
    }

    @Test func searchWithHearingImpairedFlag() async throws {
        let json = """
        {
            "data": [{
                "id": 300,
                "attributes": {
                    "language": "en",
                    "release": "Movie.HI.srt",
                    "ratings": 6.0,
                    "download_count": 50,
                    "hearing_impaired": true,
                    "files": [{"file_id": 301, "file_name": "Movie.HI.srt"}]
                }
            }]
        }
        """

        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        let results = try await service.search(query: "Movie")

        #expect(results.count == 1)
        #expect(results[0].isHearingImpaired == true)
    }

    @Test func searchSkipsUnsupportedSubtitleFormats() async throws {
        let json = """
        {
            "data": [{
                "id": 400,
                "attributes": {
                    "language": "en",
                    "release": "Movie.2024.BluRay.Release",
                    "ratings": 5.0,
                    "download_count": 10,
                    "hearing_impaired": false,
                    "files": [
                        {"file_id": 401, "file_name": "Movie.2024.BluRay.Release.txt"}
                    ]
                }
            }]
        }
        """

        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        let results = try await service.search(query: "Movie")

        #expect(results.isEmpty)
    }

    @Test func searchPrefersSupportedSubtitleFilesWhenMultipleArePresent() async throws {
        let json = """
        {
            "data": [{
                "id": 401,
                "attributes": {
                    "language": "en",
                    "release": "Movie.2024.Release",
                    "ratings": 6.5,
                    "download_count": 20,
                    "hearing_impaired": false,
                    "files": [
                        {"file_id": 402, "file_name": "Movie.2024.Release.txt"},
                        {"file_id": 403, "file_name": "Movie.2024.Release.srt"}
                    ]
                }
            }]
        }
        """

        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        let results = try await service.search(query: "Movie")

        #expect(results.count == 1)
        #expect(results[0].fileName == "Movie.2024.Release.srt")
        #expect(results[0].format == .srt)
        #expect(results[0].fileId == 403)
    }

    @Test func searchRetriesAfter429Response() async throws {
        final class CallState: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func increment() -> Int {
                lock.lock(); defer { lock.unlock() }
                value += 1
                return value
            }
            var currentValue: Int {
                lock.lock(); defer { lock.unlock() }
                return value
            }
        }
        let state = CallState()

        let session = makeSubtitleStubSession { request in
            let callCount = state.increment()
            let url = request.url!
            if callCount == 1 {
                let headers = ["Retry-After": "0"]
                let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers)!
                return (response, Data())
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.sampleSearchResponse.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "test-key", session: session)
        let results = try await service.search(query: "Movie 2024")

        #expect(state.currentValue == 2)
        #expect(results.count == 2)
    }

    @Test func searchByHashSendsMovieHashAndSizeParameters() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedURL: URL?
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        _ = try await service.searchByHash(movieHash: "abcdef1234567890", movieSize: 1_234_567_890)

        let components = URLComponents(url: try #require(state.capturedURL), resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        #expect(queryItems.first(where: { $0.name == "moviehash" })?.value == "abcdef1234567890")
        #expect(queryItems.first(where: { $0.name == "moviebytesize" })?.value == "1234567890")
    }
}

// MARK: - Authentication Tests

@Suite("OpenSubtitlesService - Authentication")
struct OpenSubtitlesAuthTests {

    @Test func loginSetsAuthToken() async throws {
        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"token":"session-token-abc"}"#
            return (response, Data(body.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        let token = try await service.login(username: "user", password: "pass")

        #expect(token == "session-token-abc")
    }

    @Test func loginSendsPostRequest() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"token":"t"}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        _ = try await service.login(username: "user", password: "pass")

        #expect(state.capturedMethod == "POST")
        #expect(state.capturedPath?.hasSuffix("/login") == true)
    }

    @Test func unauthorizedClearsAuthToken() async {
        var callCount = 0
        let session = makeSubtitleStubSession { request in
            callCount += 1
            if callCount == 1 {
                // First call: login succeeds
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"token":"valid-token"}"#.utf8))
            }
            // Second call: 401
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)

        // Login first
        _ = try? await service.login(username: "user", password: "pass")

        // Search should fail with 401
        do {
            let _ = try await service.search(query: "Movie")
            Issue.record("Expected SubtitleError.unauthorized")
        } catch let error as SubtitleError {
            if case .unauthorized = error { /* OK */ }
            else { Issue.record("Unexpected SubtitleError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func successfulLoginAddsBearerTokenToSubsequentRequests() async throws {
        final class CapturedState: @unchecked Sendable {
            private let lock = NSLock()
            private var _authorizationHeaders: [String?] = []

            func append(_ value: String?) {
                lock.lock()
                _authorizationHeaders.append(value)
                lock.unlock()
            }

            var authorizationHeaders: [String?] {
                lock.lock()
                defer { lock.unlock() }
                return _authorizationHeaders
            }
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            state.append(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path.hasSuffix("/login") == true {
                return (response, Data(#"{"token":"valid-token"}"#.utf8))
            }
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        _ = try await service.login(username: "user", password: "pass")
        _ = try await service.search(query: "Movie")

        #expect(state.authorizationHeaders == [nil, "Bearer valid-token"])
    }
}

// MARK: - Download Tests

@Suite("OpenSubtitlesService - Download")
struct OpenSubtitlesDownloadTests {

    @Test func getDownloadURLParsesLink() async throws {
        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"link":"https://dl.opensubtitles.com/file/abc123"}"#
            return (response, Data(body.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        let url = try await service.getDownloadURL(fileId: 999)

        #expect(url.absoluteString == "https://dl.opensubtitles.com/file/abc123")
    }

    @Test func getDownloadURLSendsFileIdInBody() async throws {
        final class CapturedState: @unchecked Sendable {
            private let lock = NSLock()
            private var _capturedBody: [String: Any]?
            func set(_ body: [String: Any]?) {
                lock.lock(); defer { lock.unlock() }
                _capturedBody = body
            }
            var capturedBody: [String: Any]? {
                lock.lock(); defer { lock.unlock() }
                return _capturedBody
            }
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            // Capture either httpBody or streamed body from httpBodyStream
            if let body = request.httpBody {
                let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                state.set(parsed)
            } else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data()
                let bufSize = 1024
                var buf = [UInt8](repeating: 0, count: bufSize)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buf, maxLength: bufSize)
                    if n > 0 { data.append(buf, count: n) }
                    else { break }
                }
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                state.set(parsed)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"link":"https://example.com/dl"}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        _ = try await service.getDownloadURL(fileId: 42)

        // URLProtocol callbacks can happen off the main task; give the stub a moment to capture.
        for _ in 0..<150 {
            if state.capturedBody?["file_id"] as? Int == 42 { break }
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        #expect(state.capturedBody?["file_id"] as? Int == 42)
    }

    @Test func downloadSubtitleFallsBackToUtf16WhenUtf8Fails() async throws {
        let subtitleBody = "1\n00:00:01,000 --> 00:00:02,000\nCafé\n"
        let utf16Data = subtitleBody.data(using: .utf16)!

        let session = makeSubtitleStubSession { request in
            let url = request.url!
            if url.path.hasSuffix("/download") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"link":"https://cdn.example.com/subtitle.srt"}"#.utf8))
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, utf16Data)
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        let content = try await service.downloadSubtitle(fileId: 7)

        #expect(content.contains("Café"))
    }

    @Test func getDownloadURLRejectsInvalidLink() async {
        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"link":"http://["}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)

        await #expect(throws: SubtitleError.self) {
            _ = try await service.getDownloadURL(fileId: 1)
        }
    }

    @Test func downloadSubtitleRejectsBinaryPayloads() async {
        let binaryData = Data(repeating: 0x00, count: 16)
        let session = makeSubtitleStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path.hasSuffix("/download") {
                return (response, Data(#"{"link":"https://cdn.example.com/subtitle.srt"}"#.utf8))
            }
            return (response, binaryData)
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)

        await #expect(throws: SubtitleError.self) {
            _ = try await service.downloadSubtitle(fileId: 7)
        }
    }

    @Test func downloadFirstMatchThrowsWhenOnlyUnsupportedMatchesAreReturned() async {
        let json = """
        {
            "data": [{
                "id": 500,
                "attributes": {
                    "language": "en",
                    "release": "Movie.2024.Release.txt",
                    "ratings": 5.0,
                    "download_count": 10,
                    "hearing_impaired": false,
                    "files": [
                        {"file_id": 501, "file_name": "Movie.2024.Release.txt"}
                    ]
                }
            }]
        }
        """

        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)

        await #expect(throws: SubtitleError.self) {
            _ = try await service.downloadFirstMatch(query: "Movie")
        }
    }
}

// MARK: - Error Tests

@Suite("OpenSubtitlesService - Errors")
struct OpenSubtitlesErrorTests {

    @Test func httpErrorThrowsSubtitleError() async {
        let session = makeSubtitleStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        do {
            let _ = try await service.search(query: "Movie")
            Issue.record("Expected SubtitleError.httpError")
        } catch let error as SubtitleError {
            if case .httpError(let code) = error {
                #expect(code == 503)
            } else { Issue.record("Unexpected SubtitleError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func allSubtitleErrorsHaveDescriptions() {
        let errors: [SubtitleError] = [
            .invalidURL,
            .httpError(500),
            .unauthorized,
            .decodingFailed,
            .invalidDownloadURL,
            .noSubtitlesFound,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func httpErrorIncludesStatusCode() {
        let error = SubtitleError.httpError(429)
        #expect(error.errorDescription?.contains("429") == true)
    }
}

// MARK: - Subtitle Model Tests

@Suite("Subtitle Model")
struct SubtitleModelTests {

    @Test func subtitleDisplayNameUppercasesLanguage() {
        let sub = Subtitle(
            id: "1", language: "en", fileName: "test.srt",
            url: "", format: .srt
        )
        #expect(sub.displayName == "EN")
    }

    @Test func subtitleDisplayNameAppendsHI() {
        let sub = Subtitle(
            id: "1", language: "en", fileName: "test.srt",
            url: "", format: .srt, isHearingImpaired: true
        )
        #expect(sub.displayName == "EN (HI)")
    }

    @Test func subtitleDisplayNameOmitsHIWhenFalse() {
        let sub = Subtitle(
            id: "1", language: "es", fileName: "test.srt",
            url: "", format: .srt, isHearingImpaired: false
        )
        #expect(sub.displayName == "ES")
    }

    @Test func subtitleDownloadURLParsesValidHTTPS() {
        let sub = Subtitle(
            id: "1", language: "en", fileName: "test.srt",
            url: "https://example.com/sub.srt", format: .srt
        )
        #expect(sub.downloadURL != nil)
        #expect(sub.downloadURL?.scheme == "https")
    }

    @Test func subtitleDownloadURLParsesFileURL() {
        let sub = Subtitle(
            id: "1", language: "en", fileName: "test.srt",
            url: "file:///tmp/sub.srt", format: .srt
        )
        #expect(sub.downloadURL != nil)
    }

    @Test func subtitleDownloadURLRejectsInvalidScheme() {
        let sub = Subtitle(
            id: "1", language: "en", fileName: "test.srt",
            url: "ftp://example.com/sub.srt", format: .srt
        )
        #expect(sub.downloadURL == nil)
    }

    @Test func subtitleDownloadURLRejectsEmptyString() {
        let sub = Subtitle(
            id: "1", language: "en", fileName: "test.srt",
            url: "", format: .srt
        )
        #expect(sub.downloadURL == nil)
    }
}

// MARK: - SubtitleFormat Tests

@Suite("SubtitleFormat - Parse")
struct SubtitleFormatParseTests {

    @Test func parsesSRTExtension() {
        #expect(SubtitleFormat.parse(from: "movie.srt") == .srt)
    }

    @Test func parsesVTTExtension() {
        #expect(SubtitleFormat.parse(from: "movie.vtt") == .vtt)
    }

    @Test func parsesWebVTTExtension() {
        #expect(SubtitleFormat.parse(from: "movie.webvtt") == .vtt)
    }

    @Test func parsesASSExtension() {
        #expect(SubtitleFormat.parse(from: "movie.ass") == .ass)
    }

    @Test func parsesSSAExtension() {
        #expect(SubtitleFormat.parse(from: "movie.ssa") == .ssa)
    }

    @Test func unknownExtensionReturnsUnknown() {
        #expect(SubtitleFormat.parse(from: "movie.txt") == .unknown)
        #expect(SubtitleFormat.parse(from: "movie") == .unknown)
        #expect(SubtitleFormat.parse(from: "movie.txt").isSupportedSubtitle == false)
    }

    @Test func caseInsensitiveParsing() {
        #expect(SubtitleFormat.parse(from: "movie.SRT") == .srt)
        #expect(SubtitleFormat.parse(from: "movie.VTT") == .vtt)
        #expect(SubtitleFormat.parse(from: "movie.ASS") == .ass)
    }

    @Test func fileExtensionRoundTrip() {
        for format in [SubtitleFormat.srt, .vtt, .ass, .ssa] {
            let filename = "test.\(format.fileExtension)"
            #expect(SubtitleFormat.parse(from: filename) == format)
        }
    }

    @Test func unknownFormatDefaultsToSRTExtension() {
        #expect(SubtitleFormat.unknown.fileExtension == "srt")
    }
}
