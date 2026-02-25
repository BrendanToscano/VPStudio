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

    @Test func searchFallsBackToReleaseNameWhenNoFile() async throws {
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
                    "files": []
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
        #expect(results[0].fileName == "Movie.2024.BluRay.Release")
        #expect(results[0].fileId == nil)
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
            var capturedBody: [String: Any]?
        }
        let state = CapturedState()

        let session = makeSubtitleStubSession { request in
            if let body = request.httpBody {
                state.capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"link":"https://example.com/dl"}"#.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "key", session: session)
        _ = try await service.getDownloadURL(fileId: 42)

        #expect(state.capturedBody?["file_id"] as? Int == 42)
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
