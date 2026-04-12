import Testing
import Foundation
@testable import VPStudio

// MARK: - URLProtocol Stub

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
        } catch { client?.urlProtocol(self, didFailWithError: error) }
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

/// Session that fails any real network request. Use for tests that exercise pure-logic paths
/// (no HTTP calls) so that accidental network access is caught immediately.
private func makeNoNetworkSession() -> URLSession {
    makeStubSession { request in
        Issue.record("Unexpected network request: \(request.url?.absoluteString ?? "nil")")
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        return (response, Data())
    }
}

private let validInfoHash40 = "0123456789abcdef0123456789abcdef01234567"
private let invalidInfoHash = "bad-hash"

// MARK: - RealDebridService Tests

@Suite("RealDebridService")
struct RealDebridServiceTests {

    @Test func validateTokenSendsAuthorizationHeader() async throws {
        final class State: @unchecked Sendable { var authHeader: String? }
        let state = State()

        let session = makeStubSession { request in
            state.authHeader = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"username":"sample-user","email":"sample@domain.test","type":"premium","expiration":"2026-12-31T00:00:00Z"}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "my-secret-token", session: session)
        let valid = try await service.validateToken()
        #expect(valid == true)
        #expect(state.authHeader == "Bearer my-secret-token")
    }

    @Test func unauthorizedThrowsDebridError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = RealDebridService(apiToken: "bad-token", session: session)
        do {
            let _ = try await service.validateToken()
            Issue.record("Expected DebridError.unauthorized")
        } catch let error as DebridError {
            if case .unauthorized = error { /* OK */ }
            else { Issue.record("Unexpected DebridError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func rateLimitedRetriesAndEventuallySucceeds() async throws {
        final class State: @unchecked Sendable { var requestCount = 0 }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            let statusCode = state.requestCount < 3 ? 429 : 200
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: statusCode == 429 ? ["Retry-After": "0.001"] : nil)!
            let body = #"{"username":"sample-user","email":"sample@domain.test","type":"premium","expiration":"2026-12-31T00:00:00Z"}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let valid = try await service.validateToken()
        #expect(valid == true)
        #expect(state.requestCount == 3)
    }

    @Test func getAccountInfoParsesResponse() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"username":"sample-user","email":"sample@domain.test","type":"premium","expiration":"2026-12-31T00:00:00Z"}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()
        #expect(info.username == "sample-user")
        #expect(info.email == "sample@domain.test")
        #expect(info.isPremium == true)
    }

    @Test func checkCacheReturnsStatusPerHash() async throws {
        let hash1 = "abc123abc123abc123abc123abc123abc123abc1"  // 40-char hex
        let hash2 = "def456def456def456def456def456def456def4"  // 40-char hex
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{\"\(hash1)\":[{}],\"\(hash2)\":[]}"
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: [hash1.uppercased(), hash2.uppercased()])

        #expect(result[hash1] == .cached(fileId: nil, fileName: nil, fileSize: nil))
        #expect(result[hash2] == .notCached)
    }

    @Test func checkCacheReturnsEmptyForEmptyInput() async throws {
        let session = makeStubSession { _ in
            Issue.record("Should not make a request for empty hashes")
            let response = HTTPURLResponse(url: URL(string: "https://x.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: [])
        #expect(result.isEmpty)
    }

    @Test func checkCacheBatchesLargeHashLists() async throws {
        final class State: @unchecked Sendable {
            var requestPaths: [String] = []
        }
        let state = State()

        let session = makeStubSession { request in
            state.requestPaths.append(request.url!.path)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // Return empty cache for all hashes
            return (response, Data("{}".utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        // 100 hashes should be split into batches of 48
        let hashes = (0 ..< 100).map { String(format: "%040x", $0) }
        let result = try await service.checkCache(hashes: hashes)

        #expect(result.count == 100)
        // Should make 3 requests: 48 + 48 + 4
        #expect(state.requestPaths.count == 3)
        // Each path should contain /torrents/instantAvailability/
        for path in state.requestPaths {
            #expect(path.contains("/torrents/instantAvailability/"))
        }
    }

    @Test func checkCacheSmallListMakesSingleRequest() async throws {
        final class State: @unchecked Sendable {
            var requestCount = 0
        }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let hashes = (0 ..< 10).map { String(format: "%040x", $0) }
        _ = try await service.checkCache(hashes: hashes)

        #expect(state.requestCount == 1)
    }

    @Test func checkCacheDisabledEndpointMemoizesUnsupportedState() async throws {
        final class State: @unchecked Sendable {
            var requestCount = 0
        }
        let state = State()
        let hash1 = "abc123abc123abc123abc123abc123abc123abc1"
        let hash2 = "def456def456def456def456def456def456def4"

        let session = makeStubSession { request in
            state.requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            let body = #"{"error":"disabled_endpoint","error_code":37}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let first = try await service.checkCache(hashes: [hash1, hash2])
        let second = try await service.checkCache(hashes: [hash1, hash2])

        #expect(state.requestCount == 1)
        #expect(first[hash1] == .unknown)
        #expect(first[hash2] == .unknown)
        #expect(second[hash1] == .unknown)
        #expect(second[hash2] == .unknown)
    }

    @Test func addMagnetPostsMagnetDirectly() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"id":"new-torrent-id","uri":"magnet:?xt=urn:btih:\#(validInfoHash40)"}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let id = try await service.addMagnet(hash: validInfoHash40)
        #expect(id == "new-torrent-id")
    }

    @Test func selectFilesPropagtesHTTPErrors() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = RealDebridService(apiToken: "token", session: session)
        do {
            try await service.selectFiles(torrentId: "torrent-1", fileIds: [])
            Issue.record("Expected DebridError.unauthorized")
        } catch let error as DebridError {
            if case .unauthorized = error { /* OK */ }
            else { Issue.record("Unexpected DebridError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func selectFilesSucceedsOn204NoContent() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = RealDebridService(apiToken: "token", session: session)
        // Should not throw — 204 No Content is valid for selectFiles
        try await service.selectFiles(torrentId: "torrent-1", fileIds: [1, 2])
    }

    @Test func cleanupRemoteTransferDeletesTorrent() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = RealDebridService(apiToken: "token", session: session)
        try await service.cleanupRemoteTransfer(torrentId: "torrent-1")

        #expect(state.capturedMethod == "DELETE")
        #expect(state.capturedPath == "/rest/1.0/torrents/delete/torrent-1")
    }

    @Test func selectMatchingEpisodeFileChoosesRequestedEpisodeFromSeasonPack() async throws {
        final class State: @unchecked Sendable { var capturedBody: String? }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case let path where path?.contains("/torrents/info/torrent-1") == true:
                let body = #"{"id":"torrent-1","filename":"The.Young.Pope.S01.Pack","status":"waiting_files_selection","links":[],"files":[{"id":1,"path":"/The.Young.Pope.S01E01.mkv","bytes":1000,"selected":0},{"id":2,"path":"/The.Young.Pope.S01E02.mkv","bytes":2000,"selected":0},{"id":3,"path":"/The.Young.Pope.S01E03.mkv","bytes":3000,"selected":0}]}"#
                return (response, Data(body.utf8))
            case let path where path?.contains("/torrents/selectFiles/torrent-1") == true:
                state.capturedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
                return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
            default:
                return (response, Data("{}".utf8))
            }
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let matched = try await service.selectMatchingEpisodeFile(torrentId: "torrent-1", seasonNumber: 1, episodeNumber: 2)

        #expect(matched)
        #expect(state.capturedBody == "files=2")
    }

    @Test func addMagnetIncludesHashInMagnetBody() async throws {
        final class State: @unchecked Sendable { var capturedBody: String? }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "POST", request.url!.path.hasSuffix("/addMagnet") {
                if let body = request.httpBody {
                    state.capturedBody = String(data: body, encoding: .utf8)
                }
                let body = #"{"id":"new-id","uri":"magnet:..."}"#
                return (response, Data(body.utf8))
            }
            return (response, Data("{}".utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let _ = try await service.addMagnet(hash: validInfoHash40)

        let captured = try #require(state.capturedBody)
        #expect(captured.contains(validInfoHash40))
    }

    @Test func unrestrictReturnsURL() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"id":"dl-1","filename":"movie.mkv","download":"https://cdn.example.com/movie.mkv","filesize":1000}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let url = try await service.unrestrict(link: "https://rd.example.com/link")
        #expect(url.absoluteString == "https://cdn.example.com/movie.mkv")
    }

    @Test func addMagnetFormEncodesAmpersandsInBody() async throws {
        final class State: @unchecked Sendable { var capturedBody: String? }
        let state = State()

        let session = makeStubSession { request in
            if let bodyData = request.httpBody {
                state.capturedBody = String(data: bodyData, encoding: .utf8)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.hasSuffix("/torrents") {
                return (response, Data("[]".utf8))
            }
            let addBody = #"{"id":"new-id","uri":"magnet:..."}"#
            return (response, Data(addBody.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let _ = try await service.addMagnet(hash: validInfoHash40)
        // The magnet URI contains ? and : which should be encoded in form body
        // & and = must be percent-encoded so they don't break form parsing
        let body = try #require(state.capturedBody)
        #expect(!body.contains("&xt="))  // & must be encoded, not literal
    }
}

@Suite("Debrid addMagnet hash validation")
struct DebridAddMagnetHashValidationTests {
    @Test func malformedHashesAreRejectedBeforeNetworkForAllProviders() async {
        let session = makeNoNetworkSession()

        let services: [(String, any DebridServiceProtocol)] = [
            ("RealDebrid", RealDebridService(apiToken: "token", session: session)),
            ("AllDebrid", AllDebridService(apiToken: "token", session: session)),
            ("Premiumize", PremiumizeService(apiToken: "token", session: session)),
            ("DebridLink", DebridLinkService(apiToken: "token", session: session)),
            ("TorBox", TorBoxService(apiToken: "token", session: session)),
            ("Offcloud", OffcloudService(apiToken: "token", session: session)),
        ]

        for (name, service) in services {
            do {
                _ = try await service.addMagnet(hash: invalidInfoHash)
                Issue.record("Expected DebridError.invalidHash for \(name)")
            } catch let error as DebridError {
                if case .invalidHash(let hash) = error {
                    #expect(hash == invalidInfoHash)
                } else {
                    Issue.record("Unexpected DebridError for \(name): \(error)")
                }
            } catch {
                Issue.record("Unexpected error for \(name): \(error)")
            }
        }
    }
}

// MARK: - AllDebridService Tests

@Suite("AllDebridService")
struct AllDebridServiceTests {

    @Test func addMagnetUsesIndexedArrayFormat() async throws {
        final class State: @unchecked Sendable { var capturedBody: String? }
        let state = State()

        let session = makeStubSession { request in
            if let bodyData = request.httpBody {
                state.capturedBody = String(data: bodyData, encoding: .utf8)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","data":{"magnets":[{"id":42}]}}"#
            return (response, Data(body.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)
        let _ = try await service.addMagnet(hash: validInfoHash40)

        let body = try #require(state.capturedBody)
        // Should use magnets[0] (indexed format) consistent with checkCache's magnets[\(offset)]
        #expect(body.contains("magnets%5B0%5D=") || body.contains("magnets[0]="))
    }

    @Test func checkCacheUsesIndexedArrayFormat() async throws {
        final class State: @unchecked Sendable { var capturedURL: URL? }
        let state = State()

        let session = makeStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","data":{"magnets":[{"hash":"abc123","instant":true}]}}"#
            return (response, Data(body.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)
        _ = try await service.checkCache(hashes: ["abc123", "def456"])

        let url = try #require(state.capturedURL)
        let query = url.query ?? ""
        // Should use magnets[0], magnets[1] (indexed) not magnets[]
        #expect(query.contains("magnets%5B0%5D=") || query.contains("magnets[0]="))
        #expect(query.contains("magnets%5B1%5D=") || query.contains("magnets[1]="))
    }

    @Test func cleanupRemoteTransferDeletesMagnetById() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
            var capturedBody: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            if let bodyData = request.httpBody {
                state.capturedBody = String(data: bodyData, encoding: .utf8)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","data":{"message":"Magnet was successfully deleted"}}"#
            return (response, Data(body.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)
        try await service.cleanupRemoteTransfer(torrentId: "123456")

        #expect(state.capturedMethod == "POST")
        #expect(state.capturedPath == "/v4/magnet/delete")
        #expect(state.capturedBody?.contains("id=123456") == true)
    }
}

// MARK: - TorBoxService Tests

@Suite("TorBoxService")
struct TorBoxServiceTests {

    @Test func requestdlDoesNotLeakTokenInURL() async throws {
        final class State: @unchecked Sendable { var capturedURL: URL? }
        let state = State()

        let session = makeStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                let body = #"{"success":true,"data":{"name":"movie.mkv","size":1000,"download_finished":true}}"#
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/requestdl") {
                let body = #"{"success":true,"data":{"data":"https://cdn.torbox.app/dl/movie.mkv"}}"#
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "secret-token-123", session: session)
        let _ = try await service.getStreamURL(torrentId: "42")

        let url = try #require(state.capturedURL)
        // Token must NOT appear as a query parameter
        #expect(url.absoluteString.contains("secret-token-123") == false)
    }

    @Test func authorizationHeaderUsedInsteadOfQueryToken() async throws {
        final class State: @unchecked Sendable { var capturedAuth: String? }
        let state = State()

        let session = makeStubSession { request in
            if request.url!.path.contains("/requestdl") {
                state.capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                let body = #"{"success":true,"data":{"name":"movie.mkv","size":1000,"download_finished":true}}"#
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/requestdl") {
                let body = #"{"success":true,"data":{"data":"https://cdn.torbox.app/dl/movie.mkv"}}"#
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "secret-token-123", session: session)
        let _ = try await service.getStreamURL(torrentId: "42")

        #expect(state.capturedAuth == "Bearer secret-token-123")
    }

    @Test func getStreamURLSelectsLargestFile() async throws {
        final class State: @unchecked Sendable { var capturedFileId: String? }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                // Multi-file torrent: file 0 is small (1KB subtitle), file 3 is the largest video (2GB)
                let body = """
                {"success":true,"data":{"name":"Season.Pack","size":2200000000,"download_finished":true,"files":[
                    {"id":0,"name":"subs.srt","size":1024},
                    {"id":1,"name":"episode01.mkv","size":700000000},
                    {"id":2,"name":"episode02.mkv","size":500000000},
                    {"id":3,"name":"episode03.mkv","size":2000000000}
                ]}}
                """
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/requestdl") {
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.capturedFileId = components?.queryItems?.first(where: { $0.name == "file_id" })?.value
                let body = #"{"success":true,"data":{"data":"https://cdn.torbox.app/dl/episode03.mkv"}}"#
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        _ = try await service.getStreamURL(torrentId: "42")

        // Should select file_id=3 (the largest file at 2GB), not hardcoded 0
        #expect(state.capturedFileId == "3")
    }

    @Test func getStreamURLFallsBackToZeroWithNoFiles() async throws {
        final class State: @unchecked Sendable { var capturedFileId: String? }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                // No files array in response
                let body = #"{"success":true,"data":{"name":"movie.mkv","size":1000,"download_finished":true}}"#
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/requestdl") {
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.capturedFileId = components?.queryItems?.first(where: { $0.name == "file_id" })?.value
                let body = #"{"success":true,"data":{"data":"https://cdn.torbox.app/dl/movie.mkv"}}"#
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        _ = try await service.getStreamURL(torrentId: "42")

        // Falls back to file_id=0 when no files array present
        #expect(state.capturedFileId == "0")
    }
}

// MARK: - PremiumizeService Tests

@Suite("PremiumizeService")
struct PremiumizeServiceTests {

    @Test func validateTokenChecksStatus() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","customer_id":"12345","premium_until":1767225600}"#
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        let valid = try await service.validateToken()
        #expect(valid == true)
    }

    @Test func apiKeyIsInAuthorizationHeader() async throws {
        final class State: @unchecked Sendable {
            var capturedAuth: String?
            var capturedURL: URL?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","customer_id":"1","premium_until":null}"#
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "my-key-123", session: session)
        let _ = try await service.validateToken()
        // Token must be in Authorization header, NOT in URL
        #expect(state.capturedAuth == "Bearer my-key-123")
        #expect(state.capturedURL?.absoluteString.contains("apikey") == false)
    }

    @Test func unauthorizedThrowsDebridError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = PremiumizeService(apiToken: "bad", session: session)
        do {
            let _ = try await service.validateToken()
            Issue.record("Expected DebridError.unauthorized")
        } catch let error as DebridError {
            if case .unauthorized = error { /* OK */ }
            else { Issue.record("Unexpected DebridError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func checkCacheReturnsCachedAndNotCached() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","response":[true,false,true]}"#
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: ["aaa", "bbb", "ccc"])
        #expect(result["aaa"] == .cached(fileId: nil, fileName: nil, fileSize: nil))
        #expect(result["bbb"] == .notCached)
        #expect(result["ccc"] == .cached(fileId: nil, fileName: nil, fileSize: nil))
    }

    @Test func selectFilesIsNoOp() async throws {
        let session = makeStubSession { _ in
            Issue.record("selectFiles should not make network requests for Premiumize")
            let response = HTTPURLResponse(url: URL(string: "https://x.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        // selectFiles is a no-op for Premiumize, should not throw or hit the network.
        try await service.selectFiles(torrentId: "123", fileIds: [1, 2])
    }

    @Test func unrestrictReturnsURLDirectly() async throws {
        let session = makeNoNetworkSession()
        let service = PremiumizeService(apiToken: "token", session: session)
        let url = try await service.unrestrict(link: "https://cdn.premiumize.me/video.mkv")
        #expect(url.absoluteString == "https://cdn.premiumize.me/video.mkv")
    }

    @Test func unrestrictThrowsForInvalidURL() async {
        let session = makeNoNetworkSession()
        let service = PremiumizeService(apiToken: "token", session: session)
        do {
            let _ = try await service.unrestrict(link: "")
            Issue.record("Expected DebridError")
        } catch let error as DebridError {
            if case .networkError = error { /* OK */ }
            else { Issue.record("Unexpected DebridError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func seasonPackSelectionFailsWhenTransferNameCannotIdentifyEpisode() async throws {
        final class State: @unchecked Sendable { var requestCount = 0 }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if state.requestCount == 1 {
                return (response, Data(#"{"status":"success","transfers":[]}"#.utf8))
            }
            let body = #"{"status":"success","transfers":[{"id":"torrent-1","name":"The.Show.Season.1.Pack","status":"finished","link":"https://cdn.example.com/pack.mkv"}]}"#
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-1",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )
        #expect(selected)

        do {
            _ = try await service.getStreamURL(torrentId: "torrent-1")
            Issue.record("Expected Premiumize deterministic episode-selection failure")
        } catch let error as DebridError {
            if case .networkError(let message) = error {
                #expect(message.contains("deterministically select"))
            } else {
                Issue.record("Unexpected DebridError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func seasonPackSelectionPersistsResolvedHintForLaterValidation() async throws {
        final class State: @unchecked Sendable { var requestCount = 0 }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if state.requestCount == 1 {
                let body = #"{"status":"success","transfers":[{"id":"torrent-1","name":"The.Show.S01E02.mkv","status":"waiting","link":null}]}"#
                return (response, Data(body.utf8))
            }

            let body = #"{"status":"success","transfers":[{"id":"torrent-1","name":"The.Show.Season.1.Pack","status":"finished","link":"https://cdn.example.com/pack.mkv"}]}"#
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-1",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "The.Show.S01E02.mkv",
            resolvedFileSizeHint: nil
        )
        #expect(selected)

        do {
            _ = try await service.getStreamURL(torrentId: "torrent-1")
            Issue.record("Expected Premiumize to revalidate the resolved file hint before returning a finished pack link")
        } catch let error as DebridError {
            if case .networkError(let message) = error {
                #expect(message.contains("deterministically select"))
            } else {
                Issue.record("Unexpected DebridError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - EasyNewsService Tests

@Suite("EasyNewsService")
struct EasyNewsServiceTests {

    @Test func validateTokenReturnsTrueOnSuccess() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let service = EasyNewsService(apiToken: "valid-token", session: session)
        let valid = try await service.validateToken()
        #expect(valid == true)
    }

    @Test func validateTokenReturnsFalseOnUnauthorized() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let service = EasyNewsService(apiToken: "bad-token", session: session)
        let valid = try await service.validateToken()
        #expect(valid == false)
    }

    @Test func validateTokenSendsBasicAuthHeader() async throws {
        final class State: @unchecked Sendable { var authHeader: String? }
        let state = State()

        let session = makeStubSession { request in
            state.authHeader = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let service = EasyNewsService(apiToken: "dXNlcjpwYXNz", session: session)
        _ = try await service.validateToken()
        #expect(state.authHeader == "Basic dXNlcjpwYXNz")
    }

    @Test func getAccountInfoReturnsUnknownPremiumState() async throws {
        let session = makeNoNetworkSession()
        let service = EasyNewsService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()
        #expect(info.isPremium == nil)
        #expect(info.username == "EasyNews")
    }

    @Test func checkCacheReturnsUnknownForAllHashes() async throws {
        let session = makeNoNetworkSession()
        let service = EasyNewsService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: ["hash1", "hash2"])
        #expect(result["hash1"] == .unknown)
        #expect(result["hash2"] == .unknown)
    }

    @Test func addMagnetThrowsBecauseUsenetBased() async {
        let session = makeNoNetworkSession()
        let service = EasyNewsService(apiToken: "token", session: session)
        do {
            let _ = try await service.addMagnet(hash: validInfoHash40)
            Issue.record("Expected DebridError.networkError")
        } catch let error as DebridError {
            if case .networkError(let msg) = error {
                #expect(msg.contains("Usenet"))
            } else { Issue.record("Unexpected DebridError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func getStreamURLThrowsForNonSearchFlow() async {
        let session = makeNoNetworkSession()
        let service = EasyNewsService(apiToken: "token", session: session)
        do {
            let _ = try await service.getStreamURL(torrentId: "some-id")
            Issue.record("Expected DebridError.fileNotReady")
        } catch let error as DebridError {
            if case .fileNotReady = error { /* OK */ }
            else { Issue.record("Unexpected DebridError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func unrestrictReturnsURLDirectly() async throws {
        let session = makeNoNetworkSession()
        let service = EasyNewsService(apiToken: "token", session: session)
        let url = try await service.unrestrict(link: "https://members.easynews.com/file.mkv")
        #expect(url.absoluteString == "https://members.easynews.com/file.mkv")
    }
}

// MARK: - DebridLinkService URL Encoding Tests

@Suite("DebridLinkService URL Encoding")
struct DebridLinkServiceURLEncodingTests {

    @Test func checkCacheEncodesHashesInQuery() async throws {
        final class State: @unchecked Sendable { var capturedURL: URL? }
        let state = State()

        let session = makeStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":{}}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        _ = try await service.checkCache(hashes: ["abc123", "def456"])

        let url = try #require(state.capturedURL)
        // Query should be properly encoded via URLComponents
        #expect(url.absoluteString.contains("/seedbox/cached?"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let urlParam = components?.queryItems?.first(where: { $0.name == "url" })
        #expect(urlParam?.value == "abc123,def456")
    }

    @Test func getStreamURLEncodesTorrentIdInQuery() async throws {
        final class State: @unchecked Sendable { var capturedURL: URL? }
        let state = State()

        let session = makeStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"movie.mkv","totalSize":1000,"downloadPercent":100,"files":[{"name":"movie.mkv","size":1000,"downloadUrl":"https://cdn.example.com/movie.mkv"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        _ = try await service.getStreamURL(torrentId: "torrent-123")

        let url = try #require(state.capturedURL)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let idsParam = components?.queryItems?.first(where: { $0.name == "ids" })
        #expect(idsParam?.value == "torrent-123")
    }

    @Test func getStreamURLSelectsFirstFromArray() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // API returns array with multiple torrents — should use the first
            let body = #"{"success":true,"value":[{"name":"movie.mkv","totalSize":2000,"downloadPercent":100,"files":[{"name":"movie.mkv","size":2000,"downloadUrl":"https://cdn.example.com/first.mkv"}]},{"name":"other.mkv","totalSize":1000,"downloadPercent":100,"files":[{"name":"other.mkv","size":1000,"downloadUrl":"https://cdn.example.com/second.mkv"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        let stream = try await service.getStreamURL(torrentId: "torrent-123")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/first.mkv")
        #expect(stream.fileName == "movie.mkv")
    }

    @Test func getStreamURLThrowsNotFoundOnEmptyArray() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        do {
            _ = try await service.getStreamURL(torrentId: "missing-id")
            Issue.record("Expected DebridError.torrentNotFound")
        } catch let error as DebridError {
            if case .torrentNotFound = error { /* OK */ }
            else { Issue.record("Unexpected DebridError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func seasonPackSelectionFailsDeterministicallyWhenNoMatchingFileExists() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"The.Show.S01.Pack","totalSize":2000,"downloadPercent":100,"files":[{"id":1,"name":"The.Show.S01E01.mkv","size":1000,"downloadUrl":"https://cdn.example.com/ep1.mkv"},{"id":2,"name":"The.Show.S01E03.mkv","size":1200,"downloadUrl":"https://cdn.example.com/ep3.mkv"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-123",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )
        #expect(selected)

        do {
            _ = try await service.getStreamURL(torrentId: "torrent-123")
            Issue.record("Expected deterministic Debrid-Link episode-selection failure")
        } catch let error as DebridError {
            if case .networkError(let message) = error {
                #expect(message.contains("deterministically select"))
            } else {
                Issue.record("Unexpected DebridError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@Suite("OffcloudService")
struct OffcloudServiceTests {

    @Test func directStatusURLFailsWhenRequestedEpisodeCannotBeVerified() async throws {
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://offcloud.com/api")!
            if url.path == "/api/cloud/status" || url.path == "/cloud/status" {
                let body = #"{"requestId":"req-123","fileName":"The.Show.Season.1.Pack","status":"downloaded","url":"https://cdn.example.com/season-pack.mkv"}"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            let bad = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (bad, Data())
        }

        let service = OffcloudService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "req-123",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )
        #expect(selected)

        do {
            _ = try await service.getStreamURL(torrentId: "req-123")
            Issue.record("Expected Offcloud deterministic episode-selection failure")
        } catch let error as DebridError {
            if case .networkError(let message) = error {
                #expect(message.contains("deterministically select"))
            } else {
                Issue.record("Unexpected DebridError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func failedEpisodeSelectionClearsStateForLaterGenericFetch() async throws {
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://offcloud.com/api")!
            if url.path == "/api/cloud/status" || url.path == "/cloud/status" {
                let body = #"{"requestId":"req-123","fileName":"The.Show.Season.1.Pack","status":"downloaded","url":null}"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            if url.path == "/api/cloud/explore/req-123" || url.path == "/cloud/explore/req-123" {
                let body = #"["https://cdn.example.com/The.Show.S01E01.mkv","https://cdn.example.com/The.Show.S01E03.mkv"]"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            let bad = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (bad, Data())
        }

        let service = OffcloudService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "req-123",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )
        #expect(selected)

        await #expect(throws: DebridError.networkError("Offcloud could not deterministically select the requested episode file.")) {
            _ = try await service.getStreamURL(torrentId: "req-123")
        }

        let stream = try await service.getStreamURL(torrentId: "req-123")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/The.Show.S01E01.mkv")
    }
}

@Suite("Debrid settings source contracts")
struct DebridSettingsSourceContractTests {
    @Test func easyNewsIsExcludedFromSharedStreamingAddFlow() throws {
        let source = try normalizedContents(of: "VPStudio/Views/Windows/Settings/Destinations/DebridSettingsView.swift")
        #expect(source.contains("sharedStreamingServiceTypes"))
        #expect(source.contains("type!=.easyNews"))
        #expect(source.contains("UnsupportedinSharedStreaming"))
    }

    private func contents(of relativePath: String) throws -> String {
        let absolutePath = repoRootURL().appendingPathComponent(relativePath).path
        return try String(contentsOfFile: absolutePath, encoding: .utf8)
    }

    private func normalizedContents(of relativePath: String) throws -> String {
        let source = try contents(of: relativePath)
        return source.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    private func repoRootURL() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return url
    }
}

// MARK: - PremiumizeService URL Encoding Tests

@Suite("PremiumizeService URL Encoding")
struct PremiumizeServiceURLEncodingTests {

    @Test func checkCacheEncodesHashesWithURLComponents() async throws {
        final class State: @unchecked Sendable { var capturedURL: URL? }
        let state = State()

        let session = makeStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","response":[true,false]}"#
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        _ = try await service.checkCache(hashes: ["abc123", "def456"])

        let url = try #require(state.capturedURL)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Should have two items[] params properly encoded
        let itemParams = components?.queryItems?.filter { $0.name == "items[]" } ?? []
        #expect(itemParams.count == 2)
        #expect(itemParams[0].value == "abc123")
        #expect(itemParams[1].value == "def456")
    }
}

// MARK: - DebridError Tests

@Suite("DebridError")
struct DebridErrorTests {

    @Test func allErrorsHaveDescriptions() {
        let errors: [DebridError] = [
            .unauthorized, .notPremium, .invalidHash("abc"),
            .torrentNotFound("xyz"), .fileNotReady("pending"),
            .rateLimited, .httpError(500, "Server Error"),
            .networkError("timeout"), .timeout,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func errorsAreEquatable() {
        #expect(DebridError.unauthorized == DebridError.unauthorized)
        #expect(DebridError.rateLimited == DebridError.rateLimited)
        #expect(DebridError.timeout == DebridError.timeout)
        #expect(DebridError.invalidHash("a") == DebridError.invalidHash("a"))
        #expect(DebridError.invalidHash("a") != DebridError.invalidHash("b"))
    }
}

// MARK: - CacheStatus Tests

@Suite("CacheStatus")
struct CacheStatusTests {

    @Test func cachedWithDetailsIsEquatable() {
        let a = CacheStatus.cached(fileId: "1", fileName: "a.mkv", fileSize: 1000)
        let b = CacheStatus.cached(fileId: "1", fileName: "a.mkv", fileSize: 1000)
        #expect(a == b)
    }

    @Test func cachedDifferentFileIdNotEqual() {
        let a = CacheStatus.cached(fileId: "1", fileName: "a.mkv", fileSize: 1000)
        let b = CacheStatus.cached(fileId: "2", fileName: "a.mkv", fileSize: 1000)
        #expect(a != b)
    }

    @Test func notCachedEqualsNotCached() {
        #expect(CacheStatus.notCached == CacheStatus.notCached)
    }

    @Test func unknownEqualsUnknown() {
        #expect(CacheStatus.unknown == CacheStatus.unknown)
    }

    @Test func differentStatusesAreNotEqual() {
        #expect(CacheStatus.notCached != CacheStatus.unknown)
        #expect(CacheStatus.cached(fileId: nil, fileName: nil, fileSize: nil) != CacheStatus.notCached)
    }
}
