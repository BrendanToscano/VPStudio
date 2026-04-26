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

private actor DefaultOnlyDebridService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .realDebrid

    func validateToken() async throws -> Bool { true }
    func getAccountInfo() async throws -> DebridAccountInfo {
        DebridAccountInfo(username: "default", email: nil, premiumExpiry: nil, isPremium: nil)
    }
    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        hashes.reduce(into: [:]) { $0[$1] = .unknown }
    }
    func addMagnet(hash: String) async throws -> String {
        try DebridHashValidator.validatedInfoHash(hash)
    }
    func selectFiles(torrentId: String, fileIds: [Int]) async throws {}
    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        throw DebridError.torrentNotFound(torrentId)
    }
    func unrestrict(link: String) async throws -> URL {
        guard let url = URL(string: link) else {
            throw DebridError.networkError("Invalid URL")
        }
        return url
    }
}

@Suite("Debrid shared contracts")
struct DebridSharedContractTests {
    @Test func defaultEpisodeSelectionAndCleanupAreNoOps() async throws {
        let service = DefaultOnlyDebridService()

        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-1",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "Show.S01E02.mkv",
            resolvedFileSizeHint: 1024
        )
        try await service.cleanupRemoteTransfer(torrentId: "torrent-1")

        #expect(selected == false)
    }

    @Test func defaultEpisodeSelectionIgnoresRecoveryHintsAndReturnsFalse() async throws {
        let service = DefaultOnlyDebridService()

        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-2",
            seasonNumber: 3,
            episodeNumber: 4,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )

        #expect(selected == false)
    }

    @Test func defaultCleanupAcceptsEmptyTorrentIdentifier() async throws {
        let service = DefaultOnlyDebridService()

        try await service.cleanupRemoteTransfer(torrentId: "")
    }

    @Test func debridErrorDescriptionsIncludeActionableContext() {
        let errors: [DebridError] = [
            .unauthorized,
            .notPremium,
            .invalidHash("bad"),
            .torrentNotFound("id-1"),
            .fileNotReady("processing"),
            .rateLimited,
            .httpError(503, "maintenance"),
            .networkError("offline"),
            .timeout,
        ]

        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
        #expect(DebridError.invalidHash("bad").errorDescription?.contains("bad") == true)
        #expect(DebridError.torrentNotFound("id-1").errorDescription?.contains("id-1") == true)
        #expect(DebridError.httpError(503, "maintenance").errorDescription?.contains("503") == true)
    }

    @Test func httpExecutorHonorsHTTPDateRetryAfterFormats() async throws {
        let retryAfterValues = [
            "Sun, 06 Nov 1994 08:49:37 GMT",
            "Sunday, 06-Nov-94 08:49:37 GMT",
            "Sun Nov 6 08:49:37 1994",
        ]

        for retryAfter in retryAfterValues {
            final class State: @unchecked Sendable {
                private let lock = NSLock()
                private var count = 0

                func nextAttempt() -> Int {
                    lock.lock()
                    defer { lock.unlock() }
                    count += 1
                    return count
                }

                func attempts() -> Int {
                    lock.lock()
                    defer { lock.unlock() }
                    return count
                }
            }

            let state = State()
            let session = makeStubSession { request in
                let attempt = state.nextAttempt()
                if attempt == 1 {
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: ["Retry-After": retryAfter]
                    )!
                    return (response, Data("retry later".utf8))
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("ok".utf8))
            }
            let request = URLRequest(url: URL(string: "https://debrid.example.com/retry")!)

            let (data, response) = try await DebridHTTPExecutor.data(for: request, session: session)

            #expect(response.statusCode == 200)
            #expect(String(data: data, encoding: .utf8) == "ok")
            #expect(state.attempts() == 2)
        }
    }

    @Test func httpExecutorMapsNonRetryableTransportErrorsImmediately() async {
        let session = makeStubSession { _ in
            throw URLError(.badServerResponse)
        }
        let request = URLRequest(url: URL(string: "https://debrid.example.com/transport")!)

        do {
            _ = try await DebridHTTPExecutor.data(for: request, session: session)
            Issue.record("Expected nonretryable transport errors to map to DebridError.networkError")
        } catch DebridError.networkError(let message) {
            #expect(message.isEmpty == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func validatedInfoHashTrimsAndLowercasesValidHashes() throws {
        let hash = "  ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD  "
        #expect(try DebridHashValidator.validatedInfoHash(hash) == "abcdefabcdefabcdefabcdefabcdefabcdefabcd")
    }

    @Test func normalizedInfoHashAcceptsLowerAndUpperCaseSHA1AndSHA256() {
        #expect(
            DebridHashValidator.normalizedInfoHash("0123456789abcdef0123456789abcdef01234567")
            == "0123456789abcdef0123456789abcdef01234567"
        )
        #expect(
            DebridHashValidator.normalizedInfoHash("ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDABCDEFABCDEFABCDEFABCDEF")
            == "abcdefabcdefabcdefabcdefabcdefabcdefabcdabcdefabcdefabcdefabcdef"
        )
    }

    @Test func normalizedInfoHashRejectsWrongLengthAndNonHexCharacters() {
        #expect(DebridHashValidator.normalizedInfoHash("") == nil)
        #expect(DebridHashValidator.normalizedInfoHash("abc") == nil)
        #expect(DebridHashValidator.normalizedInfoHash("0123456789abcdef0123456789abcdef0123456z") == nil)
        #expect(DebridHashValidator.normalizedInfoHash("0123456789abcdef0123456789abcdef012345678") == nil)
    }

    @Test func validatedInfoHashThrowsInvalidHashWithOriginalInput() {
        do {
            _ = try DebridHashValidator.validatedInfoHash("not-a-hash")
            Issue.record("Expected invalid hash")
        } catch DebridError.invalidHash(let hash) {
            #expect(hash == "not-a-hash")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

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

    @Test func serverErrorRetriesAndEventuallySucceeds() async throws {
        final class State: @unchecked Sendable { var requestCount = 0 }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            let statusCode = state.requestCount < 3 ? 503 : 200
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: statusCode == 503 ? ["Retry-After": "0.001"] : nil
            )!
            let body = #"{"username":"sample-user","email":"sample@domain.test","type":"premium","expiration":"2026-12-31T00:00:00Z"}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let valid = try await service.validateToken()
        #expect(valid == true)
        #expect(state.requestCount == 3)
    }

    @Test func transportTimeoutRetriesAndEventuallySucceeds() async throws {
        final class State: @unchecked Sendable { var requestCount = 0 }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            if state.requestCount < 3 {
                throw URLError(.timedOut)
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
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

    @Test func getAccountInfoHandlesNonPremiumAndInvalidExpiry() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"username":"free-user","email":"free@example.test","type":"free","expiration":"not-a-date"}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()

        #expect(info.username == "free-user")
        #expect(info.email == "free@example.test")
        #expect(info.isPremium == false)
        #expect(info.premiumExpiry == nil)
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

    @Test func checkCacheMarksInvalidHashesUnknownWithoutNetworkRequest() async throws {
        let session = makeStubSession { _ in
            Issue.record("Should not make a request when every hash is invalid")
            let response = HTTPURLResponse(url: URL(string: "https://x.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: ["not-a-hash", "12345"])

        #expect(result["not-a-hash"] == .unknown)
        #expect(result["12345"] == .unknown)
    }

    @Test func checkCacheKeepsInvalidInputsWhileFetchingValidHashes() async throws {
        final class State: @unchecked Sendable {
            var requestPath: String?
        }
        let state = State()
        let validHash = "abc123abc123abc123abc123abc123abc123abc1"

        let session = makeStubSession { request in
            state.requestPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{\"\(validHash)\":[{}]}"
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: ["not-a-hash", validHash.uppercased()])

        #expect(state.requestPath?.contains(validHash) == true)
        #expect(result["not-a-hash"] == .unknown)
        #expect(result[validHash] == .cached(fileId: nil, fileName: nil, fileSize: nil))
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

    @Test func selectMatchingEpisodeFilePrefersResolvedExactSizeAndFallsBackToSingleVideo() async throws {
        final class State: @unchecked Sendable {
            var requestCount = 0
            var capturedBodies: [String] = []
        }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path.contains("/torrents/selectFiles/") == true {
                state.capturedBodies.append(request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")
                return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
            }

            state.requestCount += 1
            if state.requestCount == 1 {
                let body = #"{"id":"torrent-1","filename":"Season.Pack","status":"waiting_files_selection","links":[],"files":[{"id":1,"path":"/tmp/The.Show.S01E02.mkv","bytes":1000,"selected":0},{"id":2,"path":"/The.Show.S01E02.mkv","bytes":2000,"selected":0},{"id":3,"path":"/sample.txt","bytes":1,"selected":0}]}"#
                return (response, Data(body.utf8))
            }

            let body = #"{"id":"torrent-2","filename":"Single.Video","status":"waiting_files_selection","links":[],"files":[{"id":7,"path":"/Movie.Feature.mkv","bytes":4000,"selected":0},{"id":8,"path":"/poster.jpg","bytes":100,"selected":0}]}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let exact = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-1",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "The.Show.S01E02.mkv",
            resolvedFileSizeHint: 2000
        )
        let single = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-2",
            seasonNumber: 9,
            episodeNumber: 9,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )

        #expect(exact)
        #expect(single)
        #expect(state.capturedBodies == ["files=2", "files=7"])
    }

    @Test func selectMatchingEpisodeFileReturnsFalseWhenNoVideoMatchExists() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"id":"torrent-1","filename":"Docs","status":"waiting_files_selection","links":[],"files":[{"id":1,"path":"/readme.txt","bytes":100,"selected":0},{"id":2,"path":"/poster.jpg","bytes":200,"selected":0}]}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let matched = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-1",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )

        #expect(matched == false)
    }

    @Test func getStreamURLUnrestrictsFirstLinkAndParsesFilename() async throws {
        final class State: @unchecked Sendable {
            var unrestrictBody: String?
        }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path.contains("/torrents/info/") == true {
                let body = #"{"id":"torrent-1","filename":"Movie.2025.2160p.HDR10.WEB-DL.mkv","hash":"abc","bytes":4096,"status":"downloaded","links":["https://rd.example.com/link-one","https://rd.example.com/link-two"],"files":[]}"#
                return (response, Data(body.utf8))
            }

            state.unrestrictBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            let body = #"{"id":"dl-1","filename":"movie.mkv","download":"https://cdn.example.com/movie.mkv","filesize":4096}"#
            return (response, Data(body.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)
        let stream = try await service.getStreamURL(torrentId: "torrent-1")

        #expect(state.unrestrictBody?.contains("link=https") == true)
        #expect(state.unrestrictBody?.contains("&") == false)
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/movie.mkv")
        #expect(stream.quality == .uhd4k)
        #expect(stream.hdr == .hdr10)
        #expect(stream.source == .webDL)
        #expect(stream.sizeBytes == 4096)
    }

    @Test func getStreamURLThrowsForNotReadyMissingLinksAndInvalidUnrestrictURL() async {
        final class State: @unchecked Sendable { var requestCount = 0 }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url?.path.contains("/torrents/info/") == true {
                state.requestCount += 1
                if state.requestCount == 1 {
                    return (response, Data(#"{"id":"torrent-1","filename":"movie.mkv","status":"downloading","links":[]}"#.utf8))
                }
                if state.requestCount == 2 {
                    return (response, Data(#"{"id":"torrent-1","filename":"movie.mkv","status":"downloaded","links":[]}"#.utf8))
                }
                return (response, Data(#"{"id":"torrent-1","filename":"movie.mkv","status":"downloaded","links":["https://rd.example.com/link"]}"#.utf8))
            }

            return (response, Data(#"{"id":"dl-1","filename":"movie.mkv","download":"http://[bad","filesize":100}"#.utf8))
        }

        let service = RealDebridService(apiToken: "token", session: session)

        await #expect(throws: DebridError.fileNotReady("downloading")) {
            _ = try await service.getStreamURL(torrentId: "torrent-1")
        }
        await #expect(throws: DebridError.torrentNotFound("torrent-1")) {
            _ = try await service.getStreamURL(torrentId: "torrent-1")
        }
        do {
            _ = try await service.getStreamURL(torrentId: "torrent-1")
            Issue.record("Expected invalid unrestrict URL")
        } catch DebridError.networkError(let message) {
            #expect(message == "Invalid unrestrict URL")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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
    @Test func getAccountInfoParsesPremiumUser() async throws {
        final class State: @unchecked Sendable {
            var capturedPath: String?
            var capturedAuth: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            state.capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","data":{"user":{"username":"alldebrid-user","email":"ad@example.test","isPremium":true}}}"#
            return (response, Data(body.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()

        #expect(state.capturedPath == "/v4/user")
        #expect(state.capturedAuth == "Bearer token")
        #expect(info.username == "alldebrid-user")
        #expect(info.email == "ad@example.test")
        #expect(info.isPremium == true)
    }

    @Test func getAccountInfoFallsBackForMissingUserPayload() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"success","data":{}}"#.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()

        #expect(info.username == "Unknown")
        #expect(info.email == nil)
        #expect(info.isPremium == false)
    }

    @Test func validateTokenThrowsUnauthorizedOnForbiddenResponse() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"error","error":{"message":"bad token"}}"#.utf8))
        }

        let service = AllDebridService(apiToken: "bad-token", session: session)

        await #expect(throws: DebridError.unauthorized) {
            _ = try await service.validateToken()
        }
    }

    @Test func checkCacheReturnsEmptyWithoutNetworkForEmptyHashList() async throws {
        let service = AllDebridService(apiToken: "token", session: makeNoNetworkSession())

        let statuses = try await service.checkCache(hashes: [])

        #expect(statuses.isEmpty)
    }

    @Test func checkCacheDefaultsMissingMagnetsToNotCached() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","data":{"magnets":[{"hash":"ABC123","instant":true},{"hash":"def456","instant":false}]}}"#
            return (response, Data(body.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)
        let statuses = try await service.checkCache(hashes: ["abc123", "def456", "missing"])

        #expect(statuses["abc123"] == .cached(fileId: nil, fileName: nil, fileSize: nil))
        #expect(statuses["def456"] == .notCached)
        #expect(statuses["missing"] == .notCached)
    }

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

    @Test func addMagnetThrowsInvalidHashWhenUploadResponseHasNoMagnetId() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"success","data":{"magnets":[]}}"#.utf8))
        }
        let service = AllDebridService(apiToken: "token", session: session)

        await #expect(throws: DebridError.invalidHash(validInfoHash40)) {
            _ = try await service.addMagnet(hash: validInfoHash40)
        }
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

    @Test func selectMatchingEpisodeFileChoosesLargestEpisodeTokenMatch() async throws {
        final class State: @unchecked Sendable {
            var unlockLink: String?
        }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/v4/magnet/status":
                let body = """
                {"status":"success","data":{"id":42,"filename":"The.Show.S01.1080p.WEB-DL.mkv","size":4000,"status":"Ready","statusCode":4,"links":[
                    {"filename":"The.Show.S01E02.small.mkv","size":1000,"link":"https://alldebrid.example/small"},
                    {"filename":"The.Show.S01E02.large.mkv","size":2500,"link":"https://alldebrid.example/large"},
                    {"filename":"The.Show.S01E03.mkv","size":3000,"link":"https://alldebrid.example/wrong-episode"}
                ]}}
                """
                return (response, Data(body.utf8))
            case "/v4/link/unlock":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.unlockLink = components?.queryItems?.first(where: { $0.name == "link" })?.value
                return (response, Data(#"{"status":"success","data":{"link":"https://cdn.example.com/large.mkv"}}"#.utf8))
            default:
                return (response, Data(#"{"status":"success","data":{}}"#.utf8))
            }
        }

        let service = AllDebridService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "42",
            seasonNumber: 1,
            episodeNumber: 2
        )
        let stream = try await service.getStreamURL(torrentId: "42")

        #expect(selected)
        #expect(state.unlockLink == "https://alldebrid.example/large")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/large.mkv")
    }

    @Test func selectMatchingEpisodeFileFallsBackToSingleLink() async throws {
        final class State: @unchecked Sendable {
            var unlockLink: String?
        }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/v4/magnet/status":
                let body = """
                {"status":"success","data":{"id":42,"filename":"Archive.mkv","size":1000,"status":"Ready","statusCode":4,"links":[
                    {"filename":"Untokened.File.mkv","size":1000,"link":"https://alldebrid.example/only"}
                ]}}
                """
                return (response, Data(body.utf8))
            case "/v4/link/unlock":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.unlockLink = components?.queryItems?.first(where: { $0.name == "link" })?.value
                return (response, Data(#"{"status":"success","data":{"link":"https://cdn.example.com/only.mkv"}}"#.utf8))
            default:
                return (response, Data(#"{"status":"success","data":{}}"#.utf8))
            }
        }

        let service = AllDebridService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "42",
            seasonNumber: 9,
            episodeNumber: 9
        )
        let stream = try await service.getStreamURL(torrentId: "42")

        #expect(selected)
        #expect(state.unlockLink == "https://alldebrid.example/only")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/only.mkv")
    }

    @Test func selectFilesWithEmptyListClearsPriorSelection() async throws {
        final class State: @unchecked Sendable {
            var unlockLink: String?
        }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/v4/magnet/status":
                let body = """
                {"status":"success","data":{"id":42,"filename":"Movie.1080p.WEB-DL.mkv","size":3000,"status":"Ready","statusCode":4,"links":[
                    {"filename":"First.mkv","size":1000,"link":"https://alldebrid.example/first"},
                    {"filename":"Second.mkv","size":2000,"link":"https://alldebrid.example/second"}
                ]}}
                """
                return (response, Data(body.utf8))
            case "/v4/link/unlock":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.unlockLink = components?.queryItems?.first(where: { $0.name == "link" })?.value
                return (response, Data(#"{"status":"success","data":{"link":"https://cdn.example.com/default.mkv"}}"#.utf8))
            default:
                return (response, Data(#"{"status":"success","data":{}}"#.utf8))
            }
        }

        let service = AllDebridService(apiToken: "token", session: session)
        try await service.selectFiles(torrentId: "42", fileIds: [2])
        try await service.selectFiles(torrentId: "42", fileIds: [])
        _ = try await service.getStreamURL(torrentId: "42")

        #expect(state.unlockLink == "https://alldebrid.example/first")
    }

    @Test func selectMatchingEpisodeFileUsesResolvedBasenameAndSizeForStreamLink() async throws {
        final class State: @unchecked Sendable {
            var unlockLink: String?
        }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/v4/magnet/status":
                let body = """
                {"status":"success","data":{"id":42,"filename":"The.Show.S01.1080p.BluRay.mkv","size":3000,"status":"Ready","statusCode":4,"links":[
                    {"filename":"/downloads/The.Show.S01E02.mkv","size":1000,"link":"https://alldebrid.example/link-small"},
                    {"filename":"The.Show.S01E02.mkv","size":2000,"link":"https://alldebrid.example/link-exact"}
                ]}}
                """
                return (response, Data(body.utf8))
            case "/v4/link/unlock":
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.unlockLink = components?.queryItems?.first(where: { $0.name == "link" })?.value
                let body = #"{"status":"success","data":{"link":"https://cdn.example.com/exact.mkv"}}"#
                return (response, Data(body.utf8))
            default:
                return (response, Data(#"{"status":"success","data":{}}"#.utf8))
            }
        }

        let service = AllDebridService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "42",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "/tmp/The.Show.S01E02.mkv",
            resolvedFileSizeHint: 2000
        )
        #expect(selected)

        let stream = try await service.getStreamURL(torrentId: "42")
        #expect(state.unlockLink == "https://alldebrid.example/link-exact")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/exact.mkv")
        #expect(stream.quality == .hd1080p)
        #expect(stream.debridService == DebridServiceType.allDebrid.rawValue)
    }

    @Test func getStreamURLThrowsFileNotReadyForIncompleteMagnet() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","data":{"id":42,"filename":"movie.mkv","status":"Downloading","statusCode":2,"links":[{"filename":"movie.mkv","size":1000,"link":"https://alldebrid.example/link"}]}}"#
            return (response, Data(body.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)

        await #expect(throws: DebridError.fileNotReady("Downloading")) {
            _ = try await service.getStreamURL(torrentId: "42")
        }
    }

    @Test func getStreamURLThrowsTorrentNotFoundWhenReadyMagnetHasNoLinks() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","data":{"id":42,"filename":"movie.mkv","status":"Ready","statusCode":4,"links":[]}}"#
            return (response, Data(body.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)

        await #expect(throws: DebridError.torrentNotFound("42")) {
            _ = try await service.getStreamURL(torrentId: "42")
        }
    }

    @Test func unrestrictThrowsNetworkErrorForInvalidURLPayload() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"success","data":{"link":""}}"#.utf8))
        }

        let service = AllDebridService(apiToken: "token", session: session)

        await #expect(throws: DebridError.networkError("Invalid unrestrict URL")) {
            _ = try await service.unrestrict(link: "https://alldebrid.example/link")
        }
    }
}

// MARK: - TorBoxService Tests

@Suite("TorBoxService")
struct TorBoxServiceTests {
    @Test func addMagnetPostsFormBodyAndReturnsTorrentID() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
            var capturedAuth: String?
            var capturedContentType: String?
            var capturedBody: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            state.capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            state.capturedContentType = request.value(forHTTPHeaderField: "Content-Type")
            state.capturedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"data":{"torrent_id":42}}"#
            return (response, Data(body.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        let id = try await service.addMagnet(hash: "ABCDEF1234567890ABCDEF1234567890ABCDEF12")

        #expect(id == "42")
        #expect(state.capturedMethod == "POST")
        #expect(state.capturedPath == "/v1/api/torrents/createtorrent")
        #expect(state.capturedAuth == "Bearer token")
        #expect(state.capturedContentType == "application/x-www-form-urlencoded")
        #expect(state.capturedBody == "magnet=magnet:?xt%3Durn:btih:abcdef1234567890abcdef1234567890abcdef12")
    }

    @Test func addMagnetThrowsInvalidHashWhenProviderOmitsTorrentID() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true,"data":{}}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        await #expect(throws: DebridError.invalidHash("abcdef1234567890abcdef1234567890abcdef12")) {
            _ = try await service.addMagnet(hash: "abcdef1234567890abcdef1234567890abcdef12")
        }
    }

    @Test func addMagnetRejectsInvalidHashBeforeNetwork() async {
        let session = makeStubSession { request in
            Issue.record("Invalid hash should not issue request: \(request)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TorBoxService(apiToken: "token", session: session)

        await #expect(throws: DebridError.invalidHash("not-a-hash")) {
            _ = try await service.addMagnet(hash: "not-a-hash")
        }
    }

    @Test func getAccountInfoParsesPlanAndEmail() async throws {
        final class State: @unchecked Sendable {
            var capturedPath: String?
            var capturedAuth: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedPath = request.url?.path
            state.capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"data":{"email":"torbox@example.test","plan":2}}"#
            return (response, Data(body.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()

        #expect(state.capturedPath == "/v1/api/user/me")
        #expect(state.capturedAuth == "Bearer token")
        #expect(info.username == "torbox@example.test")
        #expect(info.email == "torbox@example.test")
        #expect(info.isPremium == true)
    }

    @Test func getAccountInfoUsesUnknownAndNonPremiumWhenUserPayloadIsSparse() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"data":{}}"#
            return (response, Data(body.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()

        #expect(info.username == "Unknown")
        #expect(info.email == nil)
        #expect(info.premiumExpiry == nil)
        #expect(info.isPremium == false)
    }

    @Test func validateTokenThrowsUnauthorizedOnHTTP401() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":false}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        await #expect(throws: DebridError.unauthorized) {
            _ = try await service.validateToken()
        }
    }

    @Test func validateTokenReturnsTrueForSuccessfulUserResponse() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true,"data":{"email":"torbox@example.test","plan":1}}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        #expect(try await service.validateToken())
    }

    @Test func validateTokenThrowsRateLimitedOnHTTP429() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":false,"error":"rate limited"}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        await #expect(throws: DebridError.rateLimited) {
            _ = try await service.validateToken()
        }
    }

    @Test func checkCacheLowercasesKnownAndMissingHashes() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"data":[{"hash":"ABC123","name":"cached.mkv"}]}"#
            return (response, Data(body.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        let statuses = try await service.checkCache(hashes: ["ABC123", "DEF456"])

        #expect(statuses["abc123"] == .cached(fileId: nil, fileName: nil, fileSize: nil))
        #expect(statuses["def456"] == .notCached)
    }

    @Test func checkCacheReturnsEmptyWithoutNetworkForEmptyInput() async throws {
        let session = makeStubSession { request in
            Issue.record("Empty cache check should not issue request: \(request)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TorBoxService(apiToken: "token", session: session)

        #expect(try await service.checkCache(hashes: []).isEmpty)
    }

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

    @Test func cleanupRemoteTransferUsesControlTorrentDeleteOperation() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
            var capturedBody: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            state.capturedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true,"data":null}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        try await service.cleanupRemoteTransfer(torrentId: "42")

        #expect(state.capturedMethod == "POST")
        #expect(state.capturedPath == "/v1/api/torrents/controltorrent")
        let body = try #require(state.capturedBody)
        #expect(body.contains("\"torrent_id\":\"42\""))
        #expect(body.contains("\"operation\":\"delete\""))
    }

    @Test func cleanupRemoteTransferMapsUnauthorizedRateLimitAndHTTPError() async {
        let unauthorizedSession = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":"forbidden"}"#.utf8))
        }
        let rateLimitedSession = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":"slow down"}"#.utf8))
        }
        let failingSession = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data("server exploded".utf8))
        }

        await #expect(throws: DebridError.unauthorized) {
            try await TorBoxService(apiToken: "token", session: unauthorizedSession)
                .cleanupRemoteTransfer(torrentId: "42")
        }
        await #expect(throws: DebridError.rateLimited) {
            try await TorBoxService(apiToken: "token", session: rateLimitedSession)
                .cleanupRemoteTransfer(torrentId: "42")
        }
        await #expect(throws: DebridError.httpError(500, "server exploded")) {
            try await TorBoxService(apiToken: "token", session: failingSession)
                .cleanupRemoteTransfer(torrentId: "42")
        }
    }

    @Test func selectMatchingEpisodeFilePrefersResolvedExactSizeForDownloadLink() async throws {
        final class State: @unchecked Sendable {
            var capturedFileId: String?
        }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                let body = """
                {"success":true,"data":{"name":"The.Show.S01.2160p.WEB-DL.DoVi.mkv","size":3000,"download_finished":true,"files":[
                    {"id":4,"name":"/remote/The.Show.S01E02.mkv","size":1000},
                    {"id":7,"name":"The.Show.S01E02.mkv","size":2000}
                ]}}
                """
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/requestdl") {
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.capturedFileId = components?.queryItems?.first(where: { $0.name == "file_id" })?.value
                let body = #"{"success":true,"data":{"data":"https://cdn.torbox.app/dl/exact.mkv"}}"#
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "42",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "/tmp/The.Show.S01E02.mkv",
            resolvedFileSizeHint: 2000
        )
        #expect(selected)

        let stream = try await service.getStreamURL(torrentId: "42")
        #expect(state.capturedFileId == "7")
        #expect(stream.streamURL.absoluteString == "https://cdn.torbox.app/dl/exact.mkv")
        #expect(stream.quality == .uhd4k)
        #expect(stream.hdr == .dolbyVision)
    }

    @Test func selectMatchingEpisodeFileUsesLargestNameMatchWhenExactSizeHintIsMissing() async throws {
        final class State: @unchecked Sendable { var capturedFileId: String? }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                let body = """
                {"success":true,"data":{"name":"The.Show.S01.1080p.WEB-DL.mkv","size":3000,"download_finished":true,"files":[
                    {"id":4,"name":"/remote/The.Show.S01E02.mkv","size":1000},
                    {"id":7,"name":"The.Show.S01E02.mkv","size":2000}
                ]}}
                """
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/requestdl") {
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.capturedFileId = components?.queryItems?.first(where: { $0.name == "file_id" })?.value
                let body = #"{"success":true,"data":{"data":"https://cdn.torbox.app/dl/largest-name.mkv"}}"#
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        #expect(try await service.selectMatchingEpisodeFile(
            torrentId: "42",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "The.Show.S01E02.mkv",
            resolvedFileSizeHint: nil
        ))

        _ = try await service.getStreamURL(torrentId: "42")
        #expect(state.capturedFileId == "7")
    }

    @Test func selectFilesWithEmptyIDsClearsPreviouslySelectedFile() async throws {
        final class State: @unchecked Sendable { var capturedFileId: String? }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                let body = """
                {"success":true,"data":{"name":"Movie.1080p.mkv","size":3000,"download_finished":true,"files":[
                    {"id":1,"name":"small.mkv","size":1000},
                    {"id":2,"name":"large.mkv","size":3000}
                ]}}
                """
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/requestdl") {
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.capturedFileId = components?.queryItems?.first(where: { $0.name == "file_id" })?.value
                let body = #"{"success":true,"data":{"data":"https://cdn.torbox.app/dl/large.mkv"}}"#
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        try await service.selectFiles(torrentId: "42", fileIds: [1])
        try await service.selectFiles(torrentId: "42", fileIds: [])

        _ = try await service.getStreamURL(torrentId: "42")
        #expect(state.capturedFileId == "2")
    }

    @Test func selectMatchingEpisodeFileReturnsFalseWhenTorrentPayloadHasNoFiles() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true,"data":{"name":"Season.Pack"}}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        #expect(try await service.selectMatchingEpisodeFile(
            torrentId: "42",
            seasonNumber: 1,
            episodeNumber: 2
        ) == false)
        #expect(try await service.selectMatchingEpisodeFile(
            torrentId: "42",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "The.Show.S01E02.mkv",
            resolvedFileSizeHint: 1000
        ) == false)
    }

    @Test func selectMatchingEpisodeFilePrefersLargestTokenMatch() async throws {
        final class State: @unchecked Sendable { var capturedFileId: String? }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                let body = """
                {"success":true,"data":{"name":"The.Show.S01.1080p.WEB-DL.mkv","size":3000,"download_finished":true,"files":[
                    {"id":2,"name":"The.Show.S01E02.720p.mkv","size":1000},
                    {"id":5,"name":"The.Show.S01E02.1080p.mkv","size":2500},
                    {"id":9,"name":"The.Show.S01E03.1080p.mkv","size":2600}
                ]}}
                """
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/requestdl") {
                let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
                state.capturedFileId = components?.queryItems?.first(where: { $0.name == "file_id" })?.value
                let body = #"{"success":true,"data":{"data":"https://cdn.torbox.app/dl/s01e02.mkv"}}"#
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "42",
            seasonNumber: 1,
            episodeNumber: 2
        )
        #expect(selected)

        _ = try await service.getStreamURL(torrentId: "42")
        #expect(state.capturedFileId == "5")
    }

    @Test func selectMatchingEpisodeFileFallsBackToSingleFileAndReturnsFalseForNoMatch() async throws {
        final class State: @unchecked Sendable {
            var useSingleFile = true
        }
        let state = State()

        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist"), state.useSingleFile {
                let body = """
                {"success":true,"data":{"name":"Single.File.Pack","size":1000,"download_finished":true,"files":[
                    {"id":11,"name":"Featurette.mkv","size":1000}
                ]}}
                """
                return (response, Data(body.utf8))
            }
            if request.url!.path.contains("/mylist") {
                let body = """
                {"success":true,"data":{"name":"Season.Pack","size":3000,"download_finished":true,"files":[
                    {"id":1,"name":"The.Show.S01E03.mkv","size":1000},
                    {"id":2,"name":"The.Show.S01E04.mkv","size":1000}
                ]}}
                """
                return (response, Data(body.utf8))
            }
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        #expect(try await service.selectMatchingEpisodeFile(
            torrentId: "single",
            seasonNumber: 1,
            episodeNumber: 2
        ))

        state.useSingleFile = false
        #expect(try await service.selectMatchingEpisodeFile(
            torrentId: "multi",
            seasonNumber: 1,
            episodeNumber: 2
        ) == false)
    }

    @Test func getStreamURLThrowsFileNotReadyUntilTorrentFinished() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"data":{"name":"movie.mkv","size":1000,"download_finished":false,"files":[{"id":1,"name":"movie.mkv","size":1000}]}}"#
            return (response, Data(body.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        await #expect(throws: DebridError.fileNotReady("downloading")) {
            _ = try await service.getStreamURL(torrentId: "42")
        }
    }

    @Test func getStreamURLThrowsWhenDownloadLinkPayloadIsMissingURL() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.contains("/mylist") {
                let body = #"{"success":true,"data":{"name":"movie.mkv","size":1000,"download_finished":true,"files":[{"id":1,"name":"movie.mkv","size":1000}]}}"#
                return (response, Data(body.utf8))
            }
            let body = #"{"success":true,"data":{}}"#
            return (response, Data(body.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        await #expect(throws: DebridError.networkError("No download link")) {
            _ = try await service.getStreamURL(torrentId: "42")
        }
    }

    @Test func getStreamURLThrowsTorrentNotFoundWhenMyListDataIsMissing() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true,"data":null}"#.utf8))
        }

        let service = TorBoxService(apiToken: "token", session: session)

        await #expect(throws: DebridError.torrentNotFound("42")) {
            _ = try await service.getStreamURL(torrentId: "42")
        }
    }

    @Test func unrestrictReturnsValidURLAndRejectsInvalidURL() async throws {
        let service = TorBoxService(apiToken: "token", session: .shared)

        #expect(try await service.unrestrict(link: "https://cdn.torbox.app/file.mkv").absoluteString == "https://cdn.torbox.app/file.mkv")
        await #expect(throws: DebridError.networkError("Invalid URL")) {
            _ = try await service.unrestrict(link: "http://[::1")
        }
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

    @Test func getAccountInfoMapsExpiryAndPremiumState() async throws {
        let expiry = 1_767_225_600
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","customer_id":"customer-42","premium_until":\#(expiry)}"#
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()

        #expect(info.username == "customer-42")
        #expect(info.email == nil)
        #expect(info.isPremium == true)
        #expect(info.premiumExpiry == Date(timeIntervalSince1970: TimeInterval(expiry)))
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

    @Test func checkCacheTreatsMissingResponseEntriesAsNotCached() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"success","response":[true]}"#.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: ["AAA", "BBB"])

        #expect(result["aaa"] == .cached(fileId: nil, fileName: nil, fileSize: nil))
        #expect(result["bbb"] == .notCached)
    }

    @Test func addMagnetFallsBackToNormalizedHashWhenResponseHasNoID() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
            var capturedBody: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            state.capturedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"success"}"#.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        let id = try await service.addMagnet(hash: "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")

        #expect(id == "abcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(state.capturedMethod == "POST")
        #expect(state.capturedPath == "/api/transfer/create")
        #expect(state.capturedBody?.contains("src=magnet") == true)
        #expect(state.capturedBody?.contains("&xt=") == false)
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

    @Test func cleanupRemoteTransferPostsTransferDeleteById() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
            var capturedBody: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            state.capturedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"success"}"#.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        try await service.cleanupRemoteTransfer(torrentId: "pm-123")

        #expect(state.capturedMethod == "POST")
        #expect(state.capturedPath == "/api/transfer/delete")
        #expect(state.capturedBody == "id=pm-123")
    }

    @Test func cleanupRemoteTransferThrowsWhenAPIRejectsDelete() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"error","message":"cannot delete"}"#.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)

        do {
            try await service.cleanupRemoteTransfer(torrentId: "pm-123")
            Issue.record("Expected cleanup rejection")
        } catch DebridError.networkError(let message) {
            #expect(message == "cannot delete")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func getStreamURLReturnsFinishedTransferAndClearsEpisodeSelection() async throws {
        final class State: @unchecked Sendable {
            var requestCount = 0
        }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"status":"success","transfers":[{"id":"pm-1","name":"The.Show.S01E02.2160p.WEB-DL.HDR10.mkv","status":"finished","link":"https://cdn.example.com/show-s01e02.mkv"}]}"#
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "pm-1",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )
        #expect(selected)

        let stream = try await service.getStreamURL(torrentId: "pm-1")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/show-s01e02.mkv")
        #expect(stream.quality == .uhd4k)
        #expect(stream.hdr == .hdr10)
        #expect(stream.debridService == DebridServiceType.premiumize.rawValue)

        let second = try await service.getStreamURL(torrentId: "pm-1")
        #expect(second.streamURL == stream.streamURL)
        #expect(state.requestCount == 3)
    }

    @Test func getStreamURLThrowsForMissingTransferInvalidLinkAndIncompleteStatus() async {
        let responses = [
            #"{"status":"success","transfers":[]}"#,
            #"{"status":"success","transfers":[{"id":"pm-1","name":"movie.mkv","status":"finished","link":"http://[bad"}]}"#,
            #"{"status":"success","transfers":[{"id":"pm-1","name":"movie.mkv","status":"waiting","link":null}]}"#,
        ]
        final class State: @unchecked Sendable { var index = 0 }
        let state = State()

        let session = makeStubSession { request in
            let body = responses[min(state.index, responses.count - 1)]
            state.index += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        let service = PremiumizeService(apiToken: "token", session: session)

        await #expect(throws: DebridError.torrentNotFound("pm-1")) {
            _ = try await service.getStreamURL(torrentId: "pm-1")
        }
        do {
            _ = try await service.getStreamURL(torrentId: "pm-1")
            Issue.record("Expected invalid URL")
        } catch DebridError.networkError(let message) {
            #expect(message == "Invalid URL")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        await #expect(throws: DebridError.fileNotReady("waiting")) {
            _ = try await service.getStreamURL(torrentId: "pm-1")
        }
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

    @Test func validateTokenReturnsFalseOnForbidden() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let service = EasyNewsService(apiToken: "bad-token", session: session)
        let valid = try await service.validateToken()
        #expect(valid == false)
    }

    @Test func validateTokenThrowsHTTPErrorForUnexpectedStatus() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data("maintenance".utf8))
        }
        let service = EasyNewsService(apiToken: "token", session: session)

        await #expect(throws: DebridError.httpError(503, "EasyNews validation failed")) {
            _ = try await service.validateToken()
        }
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
        let result = try await service.checkCache(hashes: ["HASH1", "hash2"])
        #expect(result["hash1"] == .unknown)
        #expect(result["hash2"] == .unknown)
    }

    @Test func selectFilesIsNoOpForSearchBasedFlow() async throws {
        let session = makeNoNetworkSession()
        let service = EasyNewsService(apiToken: "token", session: session)
        try await service.selectFiles(torrentId: "search-result", fileIds: [1, 2])
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

    @Test func unrestrictRejectsInvalidURL() async {
        let session = makeNoNetworkSession()
        let service = EasyNewsService(apiToken: "token", session: session)

        await #expect(throws: DebridError.networkError("Invalid URL")) {
            _ = try await service.unrestrict(link: "http://[bad")
        }
    }
}

// MARK: - DebridLinkService URL Encoding Tests

@Suite("DebridLinkService URL Encoding")
struct DebridLinkServiceURLEncodingTests {
    @Test func validateTokenAndAccountInfoParseAccountPayload() async throws {
        final class State: @unchecked Sendable {
            var capturedAuth: String?
            var capturedPath: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":{"pseudo":"dl-user","email":"dl@example.test","premiumLeft":1767225600}}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "dl-token", session: session)
        let valid = try await service.validateToken()
        let info = try await service.getAccountInfo()

        #expect(valid)
        #expect(state.capturedAuth == "Bearer dl-token")
        #expect(state.capturedPath == "/api/v2/account/infos")
        #expect(info.username == "dl-user")
        #expect(info.email == "dl@example.test")
        #expect(info.isPremium == true)
        #expect(info.premiumExpiry == Date(timeIntervalSince1970: 1_767_225_600))
    }

    @Test func getAccountInfoUsesSafeDefaultsForSparseAccountPayload() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true,"value":{}}"#.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        let info = try await service.getAccountInfo()

        #expect(info.username == "Unknown")
        #expect(info.email == nil)
        #expect(info.premiumExpiry == nil)
        #expect(info.isPremium == false)
    }

    @Test func checkCacheWithEmptyHashesSkipsNetwork() async throws {
        let service = DebridLinkService(apiToken: "token", session: makeNoNetworkSession())
        let result = try await service.checkCache(hashes: [])
        #expect(result.isEmpty)
    }

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

    @Test func checkCacheMapsCachedEntriesAndMissingHashes() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":{"abc123":{"files":[{"id":1,"name":"movie.mkv","size":1000,"downloadUrl":"https://cdn.example.com/movie.mkv"}]},"def456":{}}}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        let statuses = try await service.checkCache(hashes: ["ABC123", "def456", "missing"])

        #expect(statuses["abc123"] == .cached(fileId: nil, fileName: nil, fileSize: nil))
        #expect(statuses["def456"] == .notCached)
        #expect(statuses["missing"] == .notCached)
    }

    @Test func addMagnetPostsFormBodyAndReturnsTorrentID() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
            var capturedBody: String?
            var contentType: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            state.capturedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            state.contentType = request.value(forHTTPHeaderField: "Content-Type")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true,"value":{"id":"dl-123"}}"#.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        let id = try await service.addMagnet(hash: "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")

        #expect(id == "dl-123")
        #expect(state.capturedMethod == "POST")
        #expect(state.capturedPath == "/api/v2/seedbox/add")
        #expect(state.contentType == "application/x-www-form-urlencoded")
        #expect(state.capturedBody?.contains("async=true") == true)
        #expect(state.capturedBody?.contains("&xt=") == false)
        #expect(state.capturedBody?.contains("abcdefabcdefabcdefabcdefabcdefabcdefabcd") == true)
    }

    @Test func addMagnetSurfacesProviderRejectionAndMissingID() async {
        final class State: @unchecked Sendable { var requestCount = 0 }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if state.requestCount == 1 {
                return (response, Data(#"{"success":false,"error":"magnet rejected"}"#.utf8))
            }
            return (response, Data(#"{"success":true,"value":{}}"#.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)

        do {
            _ = try await service.addMagnet(hash: validInfoHash40)
            Issue.record("Expected provider rejection")
        } catch DebridError.networkError(let message) {
            #expect(message == "magnet rejected")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try await service.addMagnet(hash: validInfoHash40)
            Issue.record("Expected missing id error")
        } catch DebridError.networkError(let message) {
            #expect(message.contains("did not return"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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

    @Test func getStreamURLUsesExplicitSelectedFileAndClearsSelection() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"Season.Pack","totalSize":3000,"downloadPercent":100,"files":[{"id":1,"name":"subs.srt","size":10,"downloadUrl":"https://cdn.example.com/subs.srt"},{"id":2,"name":"The.Show.S01E02.1080p.WEB-DL.mkv","size":2000,"downloadUrl":"https://cdn.example.com/ep2.mkv"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        try await service.selectFiles(torrentId: "torrent-123", fileIds: [2])
        let selected = try await service.getStreamURL(torrentId: "torrent-123")
        let fallback = try await service.getStreamURL(torrentId: "torrent-123")

        #expect(selected.streamURL.absoluteString == "https://cdn.example.com/ep2.mkv")
        #expect(selected.quality == .hd1080p)
        #expect(fallback.streamURL.absoluteString == "https://cdn.example.com/subs.srt")
    }

    @Test func selectFilesWithEmptyListClearsSelectionsAndRestoresFallback() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"Season.Pack","totalSize":3000,"downloadPercent":100,"files":[{"id":1,"name":"The.Show.S01E01.mkv","size":1000,"downloadUrl":"https://cdn.example.com/ep1.mkv"},{"id":2,"name":"The.Show.S01E02.mkv","size":2000,"downloadUrl":"https://cdn.example.com/ep2.mkv"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        try await service.selectFiles(torrentId: "torrent-123", fileIds: [2])
        try await service.selectFiles(torrentId: "torrent-123", fileIds: [])

        let stream = try await service.getStreamURL(torrentId: "torrent-123")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/ep1.mkv")
        #expect(stream.fileName == "The.Show.S01E01.mkv")
    }

    @Test func getStreamURLUsesResolvedEpisodeHintAndSize() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"Season.Pack","totalSize":3000,"downloadPercent":100,"files":[{"id":1,"name":"/tmp/The.Show.S01E02.mkv","size":1000,"downloadUrl":"https://cdn.example.com/small.mkv"},{"id":2,"downloadUrl":"https://cdn.example.com/The.Show.S01E02.mkv","size":2000}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        let selected = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-123",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "The.Show.S01E02.mkv",
            resolvedFileSizeHint: 2000
        )
        #expect(selected)

        let stream = try await service.getStreamURL(torrentId: "torrent-123")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/The.Show.S01E02.mkv")
        #expect(stream.fileName == "The.Show.S01E02.mkv")
    }

    @Test func getStreamURLUsesLargestExactNameWhenSizeHintDoesNotMatch() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"Season.Pack","totalSize":5000,"downloadPercent":100,"files":[{"id":1,"name":"The.Show.S01E02.mkv","size":1000,"downloadUrl":"https://cdn.example.com/small.mkv"},{"id":2,"name":"/downloads/The.Show.S01E02.mkv","size":3000,"downloadUrl":"https://cdn.example.com/large.mkv"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        _ = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-123",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "The.Show.S01E02.mkv",
            resolvedFileSizeHint: 9_999
        )

        let stream = try await service.getStreamURL(torrentId: "torrent-123")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/large.mkv")
    }

    @Test func getStreamURLUsesLargestEpisodeTokenMatchWhenNoExactHintMatches() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"Season.Pack","totalSize":6000,"downloadPercent":100,"files":[{"id":1,"size":10},{"id":2,"name":"The.Show.S01E02.720p.mkv","size":1000,"downloadUrl":"https://cdn.example.com/720p.mkv"},{"id":3,"name":"The.Show.S01E02.2160p.mkv","size":4000,"downloadUrl":"https://cdn.example.com/2160p.mkv"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        _ = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-123",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "different-file.mkv",
            resolvedFileSizeHint: nil
        )

        let stream = try await service.getStreamURL(torrentId: "torrent-123")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/2160p.mkv")
        #expect(stream.quality == .uhd4k)
    }

    @Test func getStreamURLFallsBackToSingleFileForEpisodeSelectionWithoutTokenMatch() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"Season.Pack","totalSize":1000,"downloadPercent":100,"files":[{"id":1,"name":"Complete.Season.File.mkv","size":1000,"downloadUrl":"https://cdn.example.com/season.mkv"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        _ = try await service.selectMatchingEpisodeFile(
            torrentId: "torrent-123",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )

        let stream = try await service.getStreamURL(torrentId: "torrent-123")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/season.mkv")
    }

    @Test func getStreamURLThrowsForIncompleteTorrentAndInvalidDownloadURL() async {
        final class State: @unchecked Sendable { var requestCount = 0 }
        let state = State()

        let session = makeStubSession { request in
            state.requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if state.requestCount == 1 {
                let body = #"{"success":true,"value":[{"name":"movie.mkv","totalSize":1000,"downloadPercent":70,"files":[{"name":"movie.mkv","size":1000,"downloadUrl":"https://cdn.example.com/movie.mkv"}]}]}"#
                return (response, Data(body.utf8))
            }
            let body = #"{"success":true,"value":[{"name":"movie.mkv","totalSize":1000,"downloadPercent":100,"files":[{"name":"movie.mkv","size":1000,"downloadUrl":"http://[bad"}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)

        await #expect(throws: DebridError.fileNotReady("downloading")) {
            _ = try await service.getStreamURL(torrentId: "torrent-123")
        }
        do {
            _ = try await service.getStreamURL(torrentId: "torrent-123")
            Issue.record("Expected invalid URL")
        } catch DebridError.networkError(let message) {
            #expect(message == "Invalid URL")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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

    @Test func getStreamURLThrowsTorrentNotFoundWhenCompletedTorrentHasNoDownloadLink() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"success":true,"value":[{"name":"empty-pack","totalSize":1000,"downloadPercent":100,"files":[{"id":1,"name":"readme.txt","size":100}]}]}"#
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        await #expect(throws: DebridError.torrentNotFound("torrent-123")) {
            _ = try await service.getStreamURL(torrentId: "torrent-123")
        }
    }

    @Test func unrestrictReturnsValidURLsAndRejectsInvalidURLs() async throws {
        let service = DebridLinkService(apiToken: "token", session: makeNoNetworkSession())
        let url = try await service.unrestrict(link: "https://cdn.example.com/movie.mkv")
        #expect(url.absoluteString == "https://cdn.example.com/movie.mkv")

        await #expect(throws: DebridError.networkError("Invalid URL")) {
            _ = try await service.unrestrict(link: "http://[bad")
        }
    }

    @Test func validateTokenMapsRateLimitHTTPFailure() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data("slow down".utf8))
        }
        let service = DebridLinkService(apiToken: "token", session: session)

        await #expect(throws: DebridError.rateLimited) {
            _ = try await service.validateToken()
        }
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

    @Test func cleanupRemoteTransferUsesDocumentedDeleteRoute() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true,"value":{"removed":1}}"#.utf8))
        }

        let service = DebridLinkService(apiToken: "token", session: session)
        try await service.cleanupRemoteTransfer(torrentId: "torrent-123")

        #expect(state.capturedMethod == "DELETE")
        #expect(state.capturedPath == "/api/v2/seedbox/torrent-123/remove")
    }

    @Test(arguments: [
        (401, DebridError.unauthorized),
        (429, DebridError.rateLimited),
        (503, DebridError.httpError(503, "maintenance")),
    ])
    func validateTokenMapsHTTPFailures(statusCode: Int, expected: DebridError) async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (response, Data("maintenance".utf8))
        }
        let service = DebridLinkService(apiToken: "token", session: session)

        await #expect(throws: expected) {
            _ = try await service.validateToken()
        }
    }
}

@Suite("OffcloudService")
struct OffcloudServiceTests {
    @Test func validateTokenAndAccountInfoUseCloudHistory() async throws {
        final class State: @unchecked Sendable {
            var paths: [String] = []
            var authHeaders: [String?] = []
        }
        let state = State()

        let session = makeStubSession { request in
            state.paths.append(request.url?.path ?? "")
            state.authHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = OffcloudService(apiToken: "off-token", session: session)
        let valid = try await service.validateToken()
        let info = try await service.getAccountInfo()

        #expect(valid)
        #expect(info.username == "Offcloud User")
        #expect(info.isPremium == true)
        #expect(state.paths == ["/api/cloud/history", "/api/cloud/history"])
        #expect(state.authHeaders.allSatisfy { $0 == "Bearer off-token" })
    }

    @Test func checkCacheNormalizesHashesAndSendsJSONBody() async throws {
        final class State: @unchecked Sendable {
            var capturedBody: [String: Any]?
            var contentType: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.contentType = request.value(forHTTPHeaderField: "Content-Type")
            if let body = request.httpBody {
                state.capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"cached_items":["abc123"]}"#.utf8))
        }

        let service = OffcloudService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: ["ABC123", "DEF456"])

        #expect(state.contentType == "application/json")
        #expect(state.capturedBody?["hashes"] as? [String] == ["abc123", "def456"])
        #expect(result["abc123"] == .cached(fileId: nil, fileName: nil, fileSize: nil))
        #expect(result["def456"] == .notCached)
    }

    @Test func checkCacheWithEmptyHashListDoesNotSendRequest() async throws {
        let session = makeStubSession { request in
            Issue.record("Empty cache check should not send request: \(request)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = OffcloudService(apiToken: "token", session: session)
        let result = try await service.checkCache(hashes: [])

        #expect(result.isEmpty)
    }

    @Test func invalidOffcloudJSONIsSurfacedAsNetworkError() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"not":"a history array"}"#.utf8))
        }

        let service = OffcloudService(apiToken: "token", session: session)

        do {
            _ = try await service.validateToken()
            Issue.record("Expected invalid JSON response to throw")
        } catch DebridError.networkError(let message) {
            #expect(message.contains("Invalid Offcloud response"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func addMagnetFallsBackToNormalizedHashWhenRequestIDMissing() async throws {
        final class State: @unchecked Sendable {
            var capturedBody: [String: Any]?
        }
        let state = State()

        let session = makeStubSession { request in
            if let body = request.httpBody {
                state.capturedBody = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"status":"ok"}"#.utf8))
        }

        let service = OffcloudService(apiToken: "token", session: session)
        let id = try await service.addMagnet(hash: "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")

        #expect(id == "abcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(state.capturedBody?["url"] as? String == "magnet:?xt=urn:btih:abcdefabcdefabcdefabcdefabcdefabcdefabcd")
    }

    @Test func requestFallsBackToNonAPIPathAfterPrimary404() async throws {
        final class State: @unchecked Sendable {
            var paths: [String] = []
        }
        let state = State()

        let session = makeStubSession { request in
            let path = request.url?.path ?? ""
            state.paths.append(path)
            if path == "/api/cloud/history" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = OffcloudService(apiToken: "token", session: session)
        let valid = try await service.validateToken()

        #expect(valid)
        #expect(state.paths == ["/api/cloud/history", "/cloud/history"])
    }

    @Test func getStreamURLUsesSelectedFileIDAndResolvedDisplayName() async throws {
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://offcloud.com/api")!
            if url.path == "/api/cloud/status" {
                let body = #"{"requestId":"req-123","fileName":"The.Show.S01E02.1080p.WEB-DL.mkv","status":"downloaded","url":null}"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }
            if url.path == "/api/cloud/explore/req-123" {
                let body = #"["https://cdn.example.com/subtitles.srt","https://cdn.example.com/video.mp4"]"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = OffcloudService(apiToken: "token", session: session)
        try await service.selectFiles(torrentId: "req-123", fileIds: [2])
        let stream = try await service.getStreamURL(torrentId: "req-123")

        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/video.mp4")
        #expect(stream.fileName == "The.Show.S01E02.1080p.WEB-DL.mkv")
        #expect(stream.quality == .hd1080p)
    }

    @Test func directGenericURLUsesStatusFileNameForParsing() async throws {
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://offcloud.com/api")!
            let body = #"{"requestId":"req-123","fileName":"Movie.2025.2160p.HDR10.WEB-DL.mkv","status":"downloaded","url":"https://cdn.example.com/video.mp4"}"#
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        let service = OffcloudService(apiToken: "token", session: session)
        let stream = try await service.getStreamURL(torrentId: "req-123")

        #expect(stream.fileName == "Movie.2025.2160p.HDR10.WEB-DL.mkv")
        #expect(stream.quality == .uhd4k)
        #expect(stream.hdr == .hdr10)
        #expect(stream.source == .webDL)
    }

    @Test func getStreamURLThrowsForInvalidExploreLinkAndHTTPFailures() async {
        let responses = [
            (200, #"{"requestId":"req-1","fileName":"movie.mkv","status":"processing","url":null}"#),
            (200, #"{"requestId":"req-1","fileName":"movie.mkv","status":"downloaded","url":null}"#),
            (429, #"{"error":"slow"}"#),
        ]
        final class State: @unchecked Sendable { var index = 0 }
        let state = State()

        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://offcloud.com/api")!
            if url.path.contains("/cloud/explore/") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"["http://[bad"]"#.utf8))
            }
            let entry = responses[min(state.index, responses.count - 1)]
            state.index += 1
            let response = HTTPURLResponse(url: url, statusCode: entry.0, httpVersion: nil, headerFields: nil)!
            return (response, Data(entry.1.utf8))
        }

        let service = OffcloudService(apiToken: "token", session: session)

        await #expect(throws: DebridError.fileNotReady("processing")) {
            _ = try await service.getStreamURL(torrentId: "req-1")
        }
        do {
            _ = try await service.getStreamURL(torrentId: "req-1")
            Issue.record("Expected invalid URL")
        } catch DebridError.networkError(let message) {
            #expect(message == "Invalid URL")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        await #expect(throws: DebridError.rateLimited) {
            _ = try await service.getAccountInfo()
        }
    }

    @Test func getStreamURLThrowsNoDownloadLinkWhenExploreListIsEmpty() async throws {
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://offcloud.com/api")!
            if url.path == "/api/cloud/status" {
                let body = #"{"requestId":"req-empty","fileName":"movie.mkv","status":"downloaded","url":null}"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }
            if url.path == "/api/cloud/explore/req-empty" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("[]".utf8))
            }
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = OffcloudService(apiToken: "token", session: session)

        await #expect(throws: DebridError.networkError("No download link")) {
            _ = try await service.getStreamURL(torrentId: "req-empty")
        }
    }

    @Test func episodeSelectionUsesExactHintAndFileSizeWhenAvailable() async throws {
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://offcloud.com/api")!
            if url.path == "/api/cloud/status" {
                let body = #"{"requestId":"req-hint","fileName":"The.Show.Season.1.Pack","status":"downloaded","url":null}"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }
            if url.path == "/api/cloud/explore/req-hint" {
                let body = #"["https://cdn.example.com/The.Show.S01E02.mkv?size=100","https://cdn.example.com/path/The.Show.S01E02.mkv?size=200","https://cdn.example.com/The.Show.S01E03.mkv?size=300"]"#
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = OffcloudService(apiToken: "token", session: session)
        _ = try await service.selectMatchingEpisodeFile(
            torrentId: "req-hint",
            seasonNumber: 1,
            episodeNumber: 2,
            resolvedFileNameHint: "The.Show.S01E02.mkv",
            resolvedFileSizeHint: 200
        )

        let stream = try await service.getStreamURL(torrentId: "req-hint")

        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/path/The.Show.S01E02.mkv?size=200")
        #expect(stream.fileName == "The.Show.S01E02.mkv")
    }

    @Test func unrestrictReturnsValidURLAndRejectsInvalidURL() async throws {
        let service = OffcloudService(apiToken: "token")

        let url = try await service.unrestrict(link: "https://cdn.example.com/movie.mkv")
        #expect(url.absoluteString == "https://cdn.example.com/movie.mkv")

        await #expect(throws: DebridError.networkError("Invalid URL")) {
            _ = try await service.unrestrict(link: "http://[::1")
        }
    }

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

    @Test func cleanupRemoteTransferPostsCloudRemoveRequest() async throws {
        final class State: @unchecked Sendable {
            var capturedMethod: String?
            var capturedPath: String?
            var capturedBody: String?
        }
        let state = State()

        let session = makeStubSession { request in
            state.capturedMethod = request.httpMethod
            state.capturedPath = request.url?.path
            state.capturedBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"success":true}"#.utf8))
        }

        let service = OffcloudService(apiToken: "token", session: session)
        try await service.cleanupRemoteTransfer(torrentId: "req-123")

        #expect(state.capturedMethod == "POST")
        #expect(state.capturedPath == "/api/cloud/remove")
        let body = try #require(state.capturedBody)
        #expect(body.contains("\"requestId\":\"req-123\""))
    }

    @Test(arguments: [
        (401, DebridError.unauthorized),
        (429, DebridError.rateLimited),
        (500, DebridError.httpError(500, "remove failed")),
    ])
    func cleanupRemoteTransferMapsHTTPFailures(statusCode: Int, expected: DebridError) async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (response, Data("remove failed".utf8))
        }

        let service = OffcloudService(apiToken: "token", session: session)

        await #expect(throws: expected) {
            try await service.cleanupRemoteTransfer(torrentId: "req-123")
        }
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
