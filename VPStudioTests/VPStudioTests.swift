import Testing
import Foundation
@testable import VPStudio

private enum URLProtocolStubError: Error {
    case missingHandler
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    static let lock = NSLock()
    static let handlerHeader = "X-VPStudio-Main-Stub-ID"

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
            client?.urlProtocol(self, didFailWithError: URLProtocolStubError.missingHandler)
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

private actor MockDebridService: DebridServiceProtocol {
    private enum MockFailure: Error, Sendable {
        case streamResolutionFailed
    }

    let serviceType: DebridServiceType

    private let streamToReturn: StreamInfo
    private let shouldFailAddMagnet: Bool
    private let shouldFailGetStreamURL: Bool
    private let cachedHashes: Set<String>
    private var calls: [String] = []
    private var cacheRequestBatches: [[String]] = []

    init(
        serviceType: DebridServiceType,
        streamToReturn: StreamInfo,
        shouldFailAddMagnet: Bool = false,
        shouldFailGetStreamURL: Bool = false,
        cachedHashes: Set<String> = []
    ) {
        self.serviceType = serviceType
        self.streamToReturn = streamToReturn
        self.shouldFailAddMagnet = shouldFailAddMagnet
        self.shouldFailGetStreamURL = shouldFailGetStreamURL
        self.cachedHashes = cachedHashes
    }

    func validateToken() async throws -> Bool { true }

    func getAccountInfo() async throws -> DebridAccountInfo {
        DebridAccountInfo(username: "mock", email: nil, premiumExpiry: nil, isPremium: true)
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        cacheRequestBatches.append(hashes)
        return hashes.reduce(into: [String: CacheStatus]()) { result, hash in
            result[hash] = cachedHashes.contains(hash)
                ? .cached(fileId: nil, fileName: nil, fileSize: nil)
                : .notCached
        }
    }

    func addMagnet(hash: String) async throws -> String {
        calls.append("add:\(hash)")
        if shouldFailAddMagnet {
            throw DebridError.networkError("forced addMagnet failure")
        }
        return "torrent-\(hash)"
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        calls.append("select:\(torrentId)")
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        calls.append("stream:\(torrentId)")
        if shouldFailGetStreamURL {
            throw MockFailure.streamResolutionFailed
        }
        return streamToReturn
    }

    func unrestrict(link: String) async throws -> URL {
        streamToReturn.streamURL
    }

    func cleanupRemoteTransfer(torrentId: String) async throws {
        calls.append("cleanup:\(torrentId)")
    }

    func callSequence() -> [String] {
        calls
    }

    func cacheBatchSizes() -> [Int] {
        cacheRequestBatches.map(\.count)
    }
}

private actor FailingCacheDebridService: DebridServiceProtocol {
    struct Failure: Error {}

    let serviceType: DebridServiceType

    init(serviceType: DebridServiceType) {
        self.serviceType = serviceType
    }

    func validateToken() async throws -> Bool { true }

    func getAccountInfo() async throws -> DebridAccountInfo {
        DebridAccountInfo(username: "mock", email: nil, premiumExpiry: nil, isPremium: true)
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        throw Failure()
    }

    func addMagnet(hash: String) async throws -> String {
        throw Failure()
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        throw Failure()
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        throw Failure()
    }

    func unrestrict(link: String) async throws -> URL {
        throw Failure()
    }
}

@Suite(.serialized)
struct VPStudioTests {
    private func makeStubSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let handlerID = URLProtocolStub.register(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        config.httpAdditionalHeaders = [URLProtocolStub.handlerHeader: handlerID]
        return URLSession(configuration: config)
    }

    private func makeTemporaryDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, tempDir)
    }

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: bufferSize)
            if readCount < 0 { return nil }
            if readCount == 0 { break }
            data.append(buffer, count: readCount)
        }

        return data.isEmpty ? nil : data
    }

    @Test func sourceTypeDoesNotClassifyDTSAsCam() {
        let source = SourceType.parse(from: "Example.Movie.2024.1080p.DTS.x264")
        #expect(source == .unknown)
    }

    @Test func sourceTypeClassifiesStandaloneTSAsCam() {
        let source = SourceType.parse(from: "Example.Movie.2024.720p.TS.x264")
        #expect(source == .cam)
    }

    @Test func hdrFormatDoesNotClassifyDVDRipAsDolbyVision() {
        let hdr = HDRFormat.parse(from: "Classic.Movie.2001.DVDRip.XviD")
        #expect(hdr == .sdr)
    }

    @Test func hdrFormatClassifiesStandaloneDVAsDolbyVision() {
        let hdr = HDRFormat.parse(from: "Modern.Movie.2025.2160p.DV.HDR10")
        #expect(hdr == .dolbyVision)
    }

    @Test func parseSRTSupportsCRLFLineEndings() {
        let content = "1\r\n00:00:01,000 --> 00:00:02,000\r\nFirst line\r\n\r\n2\r\n00:00:03,500 --> 00:00:04,500\r\nSecond line\r\n"

        let cues = SubtitleParser.parseSRT(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "First line")
        #expect(abs(cues[1].startTime - 3.5) < 0.000_1)
    }

    @Test func parseVTTSupportsCRLFLineEndings() {
        let content = "WEBVTT\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nFirst cue\r\n\r\n00:00:02.500 --> 00:00:04.000\r\nSecond cue\r\n"

        let cues = SubtitleParser.parseVTT(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "First cue")
        #expect(abs(cues[1].endTime - 4.0) < 0.000_1)
    }

    @Test func debridSecretKeyIsUniquePerConfig() {
        let keyA = SecretKey.debridToken(service: .realDebrid, configId: "config-a")
        let keyB = SecretKey.debridToken(service: .realDebrid, configId: "config-b")

        #expect(keyA != keyB)
        #expect(keyA.contains("config-a"))
        #expect(keyB.contains("config-b"))
    }

    @Test func debridManagerSelectsFilesBeforePollingStream() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-select-files.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectedStream = StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/stream.mkv")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "Example.Movie.1080p.mkv",
            sizeBytes: 2_000_000_000,
            debridService: DebridServiceType.realDebrid.rawValue
        )
        let mockService = MockDebridService(serviceType: .realDebrid, streamToReturn: expectedStream)
        let secretStore = TestSecretStore()
        let secretKey = SecretKey.debridToken(service: .realDebrid, configId: "rd-config")
        try await secretStore.setSecret("token", for: secretKey)

        let config = DebridConfig(
            id: "rd-config",
            serviceType: .realDebrid,
            apiTokenRef: SecretReference.encode(key: secretKey),
            isActive: true,
            priority: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await database.saveDebridConfig(config)

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { _, _ in mockService }
        )

        let stream = try await manager.resolveStream(hash: "abc123")
        let calls = await mockService.callSequence()

        #expect(stream.streamURL.absoluteString == expectedStream.streamURL.absoluteString)
        #expect(calls.count == 3, "Expected exactly 3 calls, no duplicates")
        #expect(calls == ["add:abc123", "select:torrent-abc123", "stream:torrent-abc123"])
    }

    @Test func debridManagerFallsBackWhenFirstProviderResolveFails() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-failover.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fallbackStream = StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/fallback.mkv")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "Fallback.Release.mkv",
            sizeBytes: 2_000_000_000,
            debridService: DebridServiceType.allDebrid.rawValue
        )

        let failingService = MockDebridService(
            serviceType: .realDebrid,
            streamToReturn: Fixtures.stream(),
            shouldFailAddMagnet: true
        )
        let fallbackService = MockDebridService(
            serviceType: .allDebrid,
            streamToReturn: fallbackStream
        )
        let secretStore = TestSecretStore()
        let rdSecretKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        let adSecretKey = SecretKey.debridToken(service: .allDebrid, configId: "ad")
        try await secretStore.setSecret("rd-token", for: rdSecretKey)
        try await secretStore.setSecret("ad-token", for: adSecretKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: rdSecretKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        try await database.saveDebridConfig(
            DebridConfig(
                id: "ad",
                serviceType: .allDebrid,
                apiTokenRef: SecretReference.encode(key: adSecretKey),
                isActive: true,
                priority: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { type, _ in
                switch type {
                case .realDebrid:
                    return failingService
                case .allDebrid:
                    return fallbackService
                default:
                    return failingService
                }
            }
        )
        try await manager.initialize()

        let stream = try await manager.resolveStream(hash: "abc123")

        #expect(stream.streamURL.absoluteString == fallbackStream.streamURL.absoluteString)
        #expect(await failingService.callSequence() == ["add:abc123"])
        #expect(await fallbackService.callSequence() == ["add:abc123", "select:torrent-abc123", "stream:torrent-abc123"])
    }

    @Test func debridManagerAttachesRecoveryTorrentIdentityAndCleansUpOnRetry() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-recovery-cleanup.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stream = StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/retry.mkv")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "Retry.Release.mkv",
            sizeBytes: 2_000_000_000,
            debridService: DebridServiceType.realDebrid.rawValue
        )
        let service = MockDebridService(serviceType: .realDebrid, streamToReturn: stream)
        let secretStore = TestSecretStore()
        let secretKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        try await secretStore.setSecret("rd-token", for: secretKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: secretKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { _, _ in service }
        )
        try await manager.initialize()

        let resolved = try await manager.resolveStream(hash: "abc123")
        let initialCalls = await service.callSequence()
        let recoveryContext = try #require(resolved.recoveryContext)

        #expect(recoveryContext.infoHash == "abc123")
        #expect(recoveryContext.torrentId == "torrent-abc123")
        #expect(recoveryContext.resolvedDebridService == DebridServiceType.realDebrid.rawValue)
        #expect(resolved.remoteTransferID == "torrent-abc123")

        let retried = try await manager.resolveStream(from: recoveryContext)
        let retriedCalls = await service.callSequence()

        #expect(retried.remoteTransferID == "torrent-abc123")
        #expect(initialCalls == ["add:abc123", "select:torrent-abc123", "stream:torrent-abc123"])
        #expect(retriedCalls.contains("cleanup:torrent-abc123"))
        #expect(retriedCalls.last == "stream:torrent-abc123")
    }

    @Test func debridManagerCleansUpAbandonedRemoteTransferBeforeFailover() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-failover-cleanup.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstStream = Fixtures.stream(url: "https://cdn.example.com/first.mkv", debridService: DebridServiceType.realDebrid.rawValue)
        let fallbackStream = Fixtures.stream(url: "https://cdn.example.com/fallback.mkv", debridService: DebridServiceType.allDebrid.rawValue)

        let failingService = MockDebridService(
            serviceType: .realDebrid,
            streamToReturn: firstStream,
            shouldFailGetStreamURL: true
        )
        let fallbackService = MockDebridService(
            serviceType: .allDebrid,
            streamToReturn: fallbackStream
        )
        let secretStore = TestSecretStore()
        let rdSecretKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        let adSecretKey = SecretKey.debridToken(service: .allDebrid, configId: "ad")
        try await secretStore.setSecret("rd-token", for: rdSecretKey)
        try await secretStore.setSecret("ad-token", for: adSecretKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: rdSecretKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        try await database.saveDebridConfig(
            DebridConfig(
                id: "ad",
                serviceType: .allDebrid,
                apiTokenRef: SecretReference.encode(key: adSecretKey),
                isActive: true,
                priority: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { type, _ in
                switch type {
                case .realDebrid:
                    return failingService
                case .allDebrid:
                    return fallbackService
                default:
                    return fallbackService
                }
            }
        )
        try await manager.initialize()

        let resolved = try await manager.resolveStream(hash: "abc123")

        #expect(resolved.remoteTransferID == "torrent-abc123")
        #expect(await failingService.callSequence() == [
            "add:abc123",
            "select:torrent-abc123",
            "stream:torrent-abc123",
            "cleanup:torrent-abc123"
        ])
        #expect(await fallbackService.callSequence() == ["add:abc123", "select:torrent-abc123", "stream:torrent-abc123"])
    }

    @Test func debridManagerUsesPreferredServiceWhenProvided() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-preferred-service.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rdStream = StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/rd.mkv")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "RD.Release.mkv",
            sizeBytes: 1_000,
            debridService: DebridServiceType.realDebrid.rawValue
        )
        let adStream = StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/ad.mkv")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "AD.Release.mkv",
            sizeBytes: 1_000,
            debridService: DebridServiceType.allDebrid.rawValue
        )

        let rdService = MockDebridService(serviceType: .realDebrid, streamToReturn: rdStream)
        let adService = MockDebridService(serviceType: .allDebrid, streamToReturn: adStream)
        let secretStore = TestSecretStore()
        let rdSecretKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        let adSecretKey = SecretKey.debridToken(service: .allDebrid, configId: "ad")
        try await secretStore.setSecret("rd-token", for: rdSecretKey)
        try await secretStore.setSecret("ad-token", for: adSecretKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: rdSecretKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        try await database.saveDebridConfig(
            DebridConfig(
                id: "ad",
                serviceType: .allDebrid,
                apiTokenRef: SecretReference.encode(key: adSecretKey),
                isActive: true,
                priority: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { type, _ in
                switch type {
                case .realDebrid:
                    return rdService
                case .allDebrid:
                    return adService
                default:
                    return rdService
                }
            }
        )
        try await manager.initialize()

        let stream = try await manager.resolveStream(hash: "hash-1", preferredService: .allDebrid)
        let rdCalls = await rdService.callSequence()
        let adCalls = await adService.callSequence()

        #expect(stream.streamURL.absoluteString == adStream.streamURL.absoluteString)
        #expect(rdCalls.isEmpty)
        #expect(adCalls == ["add:hash-1", "select:torrent-hash-1", "stream:torrent-hash-1"])
    }

    @Test func debridManagerResolveStreamThrowsWhenNoSharedMagnetServicesAreConfigured() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-no-services.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = DebridManager(
            database: database,
            secretStore: TestSecretStore(),
            serviceFactory: { _, _ in
                MockDebridService(serviceType: .realDebrid, streamToReturn: Fixtures.stream())
            }
        )

        do {
            _ = try await manager.resolveStream(hash: "0123456789abcdef0123456789abcdef01234567")
            Issue.record("Expected no-service debrid error")
        } catch let error as DebridError {
            #expect(error == .networkError("No debrid services configured. Add one in Settings > Debrid Services."))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func debridManagerDoesNotFailOverInvalidHashErrors() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-invalid-hash-no-failover.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let rdSecretKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        let adSecretKey = SecretKey.debridToken(service: .allDebrid, configId: "ad")
        try await secretStore.setSecret("rd-token", for: rdSecretKey)
        try await secretStore.setSecret("ad-token", for: adSecretKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: rdSecretKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        try await database.saveDebridConfig(
            DebridConfig(
                id: "ad",
                serviceType: .allDebrid,
                apiTokenRef: SecretReference.encode(key: adSecretKey),
                isActive: true,
                priority: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let fallbackService = MockDebridService(serviceType: .allDebrid, streamToReturn: Fixtures.stream())
        let fixture = QADebridFixture(
            hash: "0123456789abcdef0123456789abcdef01234567",
            serviceType: .realDebrid,
            streamURLs: [URL(string: "https://fixtures.example/rd.mkv")!],
            fileName: "Fixture.Release.mkv"
        )
        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { type, _ in
                switch type {
                case .realDebrid:
                    return QADebridService(fixture: fixture)
                case .allDebrid:
                    return fallbackService
                default:
                    return fallbackService
                }
            }
        )
        try await manager.initialize()

        do {
            _ = try await manager.resolveStream(hash: "not-a-valid-infohash")
            Issue.record("Expected invalid hash error")
        } catch let error as DebridError {
            #expect(error == .invalidHash("not-a-valid-infohash"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        #expect(await fallbackService.callSequence().isEmpty)
    }

    @Test func debridManagerCleanupRemoteTransferFromContextUsesResolvedService() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-cleanup-context.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let adSecretKey = SecretKey.debridToken(service: .allDebrid, configId: "ad")
        try await secretStore.setSecret("ad-token", for: adSecretKey)
        try await database.saveDebridConfig(
            DebridConfig(
                id: "ad",
                serviceType: .allDebrid,
                apiTokenRef: SecretReference.encode(key: adSecretKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let service = MockDebridService(serviceType: .allDebrid, streamToReturn: Fixtures.stream())
        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { _, _ in service }
        )
        try await manager.initialize()

        let context = StreamRecoveryContext(
            infoHash: "0123456789abcdef0123456789abcdef01234567",
            preferredService: .realDebrid,
            torrentId: "remote-transfer-1",
            resolvedDebridService: DebridServiceType.allDebrid.rawValue
        )!

        await manager.cleanupRemoteTransfer(from: context)

        #expect(await service.callSequence() == ["cleanup:remote-transfer-1"])
    }

    @Test func debridManagerFailsEpisodeResolveWhenServiceCannotSelectMatchingFile() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-episode-select-failure.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let rdSecretKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        try await secretStore.setSecret("rd-token", for: rdSecretKey)
        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: rdSecretKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let service = MockDebridService(serviceType: .realDebrid, streamToReturn: Fixtures.stream())
        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { _, _ in service }
        )
        try await manager.initialize()

        do {
            _ = try await manager.resolveStream(
                hash: "0123456789abcdef0123456789abcdef01234567",
                seasonNumber: 1,
                episodeNumber: 2
            )
            Issue.record("Expected deterministic episode selection failure")
        } catch let error as DebridError {
            #expect(error == .networkError("Could not deterministically select the requested episode file."))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(await service.callSequence() == [
            "add:0123456789abcdef0123456789abcdef01234567",
            "cleanup:torrent-0123456789abcdef0123456789abcdef01234567",
        ])
    }

    @Test func debridManagerMigratesPlaintextTokensToSecretStore() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-migrate-token.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        final class State: @unchecked Sendable {
            var tokens: [String] = []
        }
        let secretStore = TestSecretStore()
        let captured = State()
        let mockService = MockDebridService(
            serviceType: .realDebrid,
            streamToReturn: Fixtures.stream()
        )

        try await database.saveDebridConfig(
            DebridConfig(
                id: "legacy",
                serviceType: .realDebrid,
                apiTokenRef: "plaintext-token",
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { _, token in
                captured.tokens.append(token)
                return mockService
            }
        )

        try await manager.initialize()

        let migratedKey = SecretKey.debridToken(service: .realDebrid, configId: "legacy")
        let storedSecret = try await secretStore.getSecret(for: migratedKey)
        let migratedConfig = try await database.fetchAllDebridConfigs().first

        #expect(captured.tokens == ["plaintext-token"])
        #expect(storedSecret == "plaintext-token")
        #expect(migratedConfig?.apiTokenRef == SecretReference.encode(key: migratedKey))
    }

    @Test func debridManagerSkipsEasyNewsInSharedMagnetFlow() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-skip-easynews.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        final class State: @unchecked Sendable {
            var factoryCalls = 0
        }
        let state = State()
        let secretStore = TestSecretStore()
        let easyNewsKey = SecretKey.debridToken(service: .easyNews, configId: "en")
        try await secretStore.setSecret("easynews-token", for: easyNewsKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "en",
                serviceType: .easyNews,
                apiTokenRef: SecretReference.encode(key: easyNewsKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { _, _ in
                state.factoryCalls += 1
                return MockDebridService(
                    serviceType: .realDebrid,
                    streamToReturn: Fixtures.stream()
                )
            }
        )

        try await manager.initialize()

        #expect(state.factoryCalls == 0)
        let services = await manager.availableServices()
        #expect(services.isEmpty)
    }

    @Test func debridManagerCacheChecksContinueAfterSingleServiceFailure() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-cache-failure-recovery.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let allDebridKey = SecretKey.debridToken(service: .allDebrid, configId: "ad")
        let realDebridKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        try await secretStore.setSecret("ad-token", for: allDebridKey)
        try await secretStore.setSecret("rd-token", for: realDebridKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "ad",
                serviceType: .allDebrid,
                apiTokenRef: SecretReference.encode(key: allDebridKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: realDebridKey),
                isActive: true,
                priority: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let cachedHash = "0123456789abcdef0123456789abcdef01234567"
        let fallbackFixture = QADebridFixture(
            hash: cachedHash,
            serviceType: .realDebrid,
            streamURLs: [URL(string: "https://fixtures.example/rd.mkv")!],
            fileName: "Cached.Release.mkv"
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { type, _ in
                switch type {
                case .allDebrid:
                    return FailingCacheDebridService(serviceType: .allDebrid)
                case .realDebrid:
                    return QADebridService(fixture: fallbackFixture)
                default:
                    return FailingCacheDebridService(serviceType: type)
                }
            }
        )
        try await manager.initialize()

        let result = try await manager.checkCacheAcrossServices(hashes: [cachedHash])
        let resolved = result[cachedHash]

        #expect(resolved?.1 == .realDebrid)
        if case .cached = resolved?.0 {
            #expect(Bool(true))
        } else {
            Issue.record("Expected cached result from fallback debrid service")
        }
    }

    @Test func debridManagerCacheChecksThrowWhenAllServicesFail() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-cache-all-fail.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let realDebridKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        try await secretStore.setSecret("rd-token", for: realDebridKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: realDebridKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { type, _ in
                FailingCacheDebridService(serviceType: type)
            }
        )
        try await manager.initialize()

        await #expect(throws: FailingCacheDebridService.Failure.self) {
            _ = try await manager.checkCacheAcrossServices(hashes: ["0123456789abcdef0123456789abcdef01234567"])
        }
    }

    @Test func debridManagerBatchesCacheChecksAndSkipsResolvedHashes() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-cache-batching.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let realDebridKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        let allDebridKey = SecretKey.debridToken(service: .allDebrid, configId: "ad")
        try await secretStore.setSecret("rd-token", for: realDebridKey)
        try await secretStore.setSecret("ad-token", for: allDebridKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: realDebridKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        try await database.saveDebridConfig(
            DebridConfig(
                id: "ad",
                serviceType: .allDebrid,
                apiTokenRef: SecretReference.encode(key: allDebridKey),
                isActive: true,
                priority: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let hashes = (0 ..< 100).map { String(format: "%040x", $0) }
        let cachedHash = hashes[0]
        let firstService = MockDebridService(
            serviceType: .realDebrid,
            streamToReturn: Fixtures.stream(),
            cachedHashes: [cachedHash]
        )
        let secondService = MockDebridService(
            serviceType: .allDebrid,
            streamToReturn: Fixtures.stream()
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { type, _ in
                switch type {
                case .realDebrid:
                    return firstService
                case .allDebrid:
                    return secondService
                default:
                    return firstService
                }
            }
        )
        try await manager.initialize()

        let result = try await manager.checkCacheAcrossServices(hashes: hashes)

        #expect(result[cachedHash]?.1 == .realDebrid)
        if case .cached = result[cachedHash]?.0 {
            #expect(Bool(true))
        } else {
            Issue.record("Expected cached result from first provider")
        }

        #expect(await firstService.cacheBatchSizes() == [48, 48, 4])
        #expect(await secondService.cacheBatchSizes() == [48, 48, 3])
    }

    @Test func debridManagerMarksUnresolvedHashesUnknownAfterPartialCacheFailure() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-debrid-cache-partial-failure.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let rdSecretKey = SecretKey.debridToken(service: .realDebrid, configId: "rd")
        let adSecretKey = SecretKey.debridToken(service: .allDebrid, configId: "ad")
        try await secretStore.setSecret("rd-token", for: rdSecretKey)
        try await secretStore.setSecret("ad-token", for: adSecretKey)

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: SecretReference.encode(key: rdSecretKey),
                isActive: true,
                priority: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        try await database.saveDebridConfig(
            DebridConfig(
                id: "ad",
                serviceType: .allDebrid,
                apiTokenRef: SecretReference.encode(key: adSecretKey),
                isActive: true,
                priority: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let cachedHash = "0123456789abcdef0123456789abcdef01234567"
        let unresolvedHash = "fedcba9876543210fedcba9876543210fedcba98"
        let fallbackFixture = QADebridFixture(
            hash: cachedHash,
            serviceType: .allDebrid,
            streamURLs: [URL(string: "https://fixtures.example/ad.mkv")!],
            fileName: "Cached.Release.mkv"
        )

        let manager = DebridManager(
            database: database,
            secretStore: secretStore,
            serviceFactory: { type, _ in
                switch type {
                case .realDebrid:
                    return FailingCacheDebridService(serviceType: .realDebrid)
                case .allDebrid:
                    return QADebridService(fixture: fallbackFixture)
                default:
                    return FailingCacheDebridService(serviceType: type)
                }
            }
        )
        try await manager.initialize()

        let result = try await manager.checkCacheAcrossServices(hashes: [cachedHash, unresolvedHash])

        if case .cached = result[cachedHash]?.0 {
            #expect(Bool(true))
        } else {
            Issue.record("Expected cached result for resolved hash")
        }
        #expect(result[cachedHash]?.1 == .allDebrid)
        #expect(result[unresolvedHash]?.0 == .unknown)
        #expect(result[unresolvedHash]?.1 == .allDebrid)
    }

    @Test func qaDebridServiceReturnsSequentialFixtureURLsForRepeatedRequests() async throws {
        let fixture = QADebridFixture(
            hash: "0123456789abcdef0123456789abcdef01234567",
            serviceType: .realDebrid,
            streamURLs: [
                URL(string: "https://fixtures.example/stream.mp4?token=expired")!,
                URL(string: "https://fixtures.example/stream.mp4?token=fresh")!,
            ],
            fileName: "Example.Movie.2025.720p.WEB-DL.x264.AAC.mp4"
        )
        let service = QADebridService(fixture: fixture)

        #expect(try await service.validateToken())
        let account = try await service.getAccountInfo()
        #expect(account.username == "qa-fixture")
        #expect(account.isPremium == true)

        let torrentId = try await service.addMagnet(hash: fixture.hash)
        try await service.selectFiles(torrentId: torrentId, fileIds: [])

        let first = try await service.getStreamURL(torrentId: torrentId)
        let second = try await service.getStreamURL(torrentId: torrentId)
        let cache = try await service.checkCache(hashes: [fixture.hash, "deadbeef"])
        let unrestricted = try await service.unrestrict(link: fixture.streamURLs[0].absoluteString)

        #expect(first.streamURL.absoluteString == fixture.streamURLs[0].absoluteString)
        #expect(second.streamURL.absoluteString == fixture.streamURLs[1].absoluteString)
        #expect(unrestricted.absoluteString == fixture.streamURLs[0].absoluteString)
        #expect(first.debridService == DebridServiceType.realDebrid.rawValue)
        #expect(second.fileName == fixture.fileName)

        await #expect(throws: DebridError.self) {
            _ = try await service.addMagnet(hash: "invalid")
        }
        await #expect(throws: DebridError.self) {
            _ = try await service.getStreamURL(torrentId: "missing")
        }
        await #expect(throws: DebridError.self) {
            _ = try await service.unrestrict(link: "http://[")
        }

        guard let cachedEntry = cache[fixture.hash] else {
            Issue.record("Expected cached QA fixture entry")
            return
        }
        if case .cached(_, let cachedFileName, _) = cachedEntry {
            #expect(cachedFileName == fixture.fileName)
        } else {
            Issue.record("Expected fixture hash to be reported as cached")
        }

        guard let missEntry = cache["deadbeef"] else {
            Issue.record("Expected non-fixture hash to be present")
            return
        }
        if case .notCached = missEntry {
            // expected
        } else {
            Issue.record("Expected non-fixture hash to be reported as not cached")
        }
    }

    @Test func streamInfoIdIsStableAcrossTokenChanges() {
        let streamA = StreamInfo(
            streamURL: URL(string: "https://example.com/stream.mkv?token=abc")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "Same.Release.Name.1080p.mkv",
            sizeBytes: 1_000,
            debridService: "realdebrid"
        )
        let streamB = StreamInfo(
            streamURL: URL(string: "https://example.com/stream.mkv?token=xyz")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "Same.Release.Name.1080p.mkv",
            sizeBytes: 1_000,
            debridService: "realdebrid"
        )

        // Same logical stream with different tokens should have the same ID
        #expect(streamA.id == streamB.id)
    }

    @Test func tmdbPreviewIDIsTypedToAvoidMovieShowCollisions() {
        let movieResult = TMDBSearchResult(
            id: 101,
            title: "Example Movie",
            name: nil,
            mediaType: "movie",
            overview: nil,
            posterPath: "/movie.jpg",
            backdropPath: nil,
            releaseDate: "2025-01-01",
            firstAirDate: nil,
            voteAverage: 7.5
        )
        let showResult = TMDBSearchResult(
            id: 101,
            title: nil,
            name: "Example Show",
            mediaType: "tv",
            overview: nil,
            posterPath: "/show.jpg",
            backdropPath: nil,
            releaseDate: nil,
            firstAirDate: "2025-01-01",
            voteAverage: 8.1
        )

        let moviePreview = movieResult.toMediaPreview()
        let showPreview = showResult.toMediaPreview()

        #expect(moviePreview?.id == "movie-tmdb-101")
        #expect(showPreview?.id == "series-tmdb-101")
        #expect(moviePreview?.id != showPreview?.id)
    }

    @Test func loadingExternalSubtitlesPopulatesSubtitleTracks() async {
        let subtitles = [
            Subtitle(
                id: "sub-1",
                language: "en",
                fileName: "Example.en.srt",
                url: "https://example.com/sub.srt",
                format: .srt
            ),
        ]

        let (trackCount, selectedTrack, trackName): (Int, Int, String?) = await MainActor.run {
            let engine = VPPlayerEngine()
            engine.loadExternalSubtitles(subtitles)
            return (engine.subtitleTracks.count, engine.selectedSubtitleTrack, engine.subtitleTracks.first?.name)
        }

        #expect(trackCount == 1)
        #expect(selectedTrack == 0)
        #expect(trackName == "Example.en.srt")
    }

    @Test func localExternalSubtitleCuesUpdateCurrentSubtitleText() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subtitleFileURL = tempDir.appendingPathComponent("example.srt")
        let subtitleContent = """
        1
        00:00:01,000 --> 00:00:02,000
        Hello world
        """
        try subtitleContent.write(to: subtitleFileURL, atomically: true, encoding: .utf8)

        let subtitle = Subtitle(
            id: "local-sub",
            language: "en",
            fileName: "example.srt",
            url: subtitleFileURL.absoluteString,
            format: .srt
        )

        let cueText: String? = await MainActor.run {
            let engine = VPPlayerEngine()
            engine.loadExternalSubtitles([subtitle])
            engine.selectSubtitleTrack(0)
            engine.updateSubtitleText(at: 1.5)
            return engine.currentSubtitleText
        }

        #expect(cueText == "Hello world")
    }

    @Test func traktSyncRequiresConnection() async {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret")

        do {
            let _: [TraktItem] = try await service.getWatchlist(type: .movie)
            Issue.record("Expected TraktError.notConnected")
        } catch let error as TraktError {
            if case .notConnected = error {
                return
            } else {
                Issue.record("Unexpected TraktError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func simklSyncRequiresConnection() async {
        let service = SimklSyncService(clientId: "client")

        do {
            let _: SimklSyncResponse = try await service.getWatchlist()
            Issue.record("Expected SimklError.notConnected")
        } catch let error as SimklError {
            if case .notConnected = error {
                return
            } else {
                Issue.record("Unexpected SimklError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func indexerManagerThrowsWhenAllIndexersFail() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("vpstudio-tests.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()

        // Insert all known defaults as inactive so hydration doesn't add live built-ins.
        var inactiveDefaults = IndexerDefaultRanking.defaultConfigs()
        for i in inactiveDefaults.indices {
            inactiveDefaults[i].isActive = false
            inactiveDefaults[i].priority = i + 1
        }
        let brokenConfig = IndexerConfig(
            id: UUID().uuidString,
            name: "Broken Torznab",
            indexerType: .torznab,
            baseURL: "://invalid-url",
            apiKey: "api-key",
            isActive: true,
            priority: 0
        )
        try await database.saveIndexerConfigs([brokenConfig] + inactiveDefaults)

        let manager = IndexerManager(database: database)
        try await manager.initialize()

        do {
            let _ = try await manager.searchByQuery(query: "anything", type: .movie)
            Issue.record("Expected IndexerManagerError.allIndexersFailed")
        } catch let error as IndexerManagerError {
            if case .allIndexersFailed = error {
                return
            } else {
                Issue.record("Unexpected IndexerManagerError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func databaseLibraryAddAndRemoveWatchlistEntry() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("vpstudio-library-tests.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()

        let folderId = try await database.fetchSystemLibraryFolderID(listType: .watchlist)
        let entry = UserLibraryEntry(
            id: "tt1234567-\(folderId)",
            mediaId: "tt1234567",
            folderId: folderId,
            listType: .watchlist,
            addedAt: Date()
        )

        try await database.addToLibrary(entry)

        let added = try await database.isInLibrary(mediaId: "tt1234567", listType: .watchlist)
        #expect(added)

        let entries = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(entries.contains(where: { $0.mediaId == "tt1234567" }))

        try await database.removeFromLibrary(mediaId: "tt1234567", listType: .watchlist)

        let removed = try await database.isInLibrary(mediaId: "tt1234567", listType: .watchlist)
        #expect(!removed)
    }

    @Test func ytsIndexerThrowsOnHTTPFailure() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://yts.mx/api/v2/list_movies.json")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let indexer = YTSIndexer(session: session)

        do {
            let _ = try await indexer.searchByQuery(query: "Dune", type: .movie)
            Issue.record("Expected URLError.badServerResponse")
        } catch let error as URLError {
            #expect(error.code == .badServerResponse)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func ytsIndexerEncodesQueryParametersSafely() async throws {
        final class RequestState: @unchecked Sendable {
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"data":{"movies":[]}}"#
            return (response, Data(body.utf8))
        }

        let indexer = YTSIndexer(session: session)
        let query = "Spider-Man & Venom=2"
        let _ = try await indexer.searchByQuery(query: query, type: .movie)

        let capturedQuery = state.queryItems.first(where: { $0.name == "query_term" })?.value
        let capturedLimit = state.queryItems.first(where: { $0.name == "limit" })?.value
        #expect(capturedQuery == query)
        #expect(capturedLimit == "20")
    }

    @Test func apiBayIndexerThrowsOnHTTPFailure() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://apibay.org/q.php")!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let indexer = APIBayIndexer(session: session)

        do {
            let _ = try await indexer.searchByQuery(query: "Dune", type: .movie)
            Issue.record("Expected URLError.badServerResponse")
        } catch let error as URLError {
            #expect(error.code == .badServerResponse)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func apiBayIndexerEncodesQueryParametersSafely() async throws {
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

        let indexer = APIBayIndexer(session: session)
        let query = "Spider-Man & Venom=2"
        let _ = try await indexer.searchByQuery(query: query, type: .movie)

        let capturedQuery = state.queryItems.first(where: { $0.name == "q" })?.value
        let capturedCategory = state.queryItems.first(where: { $0.name == "cat" })?.value
        #expect(capturedQuery == query)
        #expect(capturedCategory == "0")
    }

    @Test func eztvIndexerEncodesQueryParametersSafely() async throws {
        final class RequestState: @unchecked Sendable {
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"torrents":[]}"#
            return (response, Data(body.utf8))
        }

        let indexer = EZTVIndexer(session: session)
        let query = "Halo & S01E01=Pilot"
        let _ = try await indexer.searchByQuery(query: query, type: .series)

        let capturedQuery = state.queryItems.first(where: { $0.name == "search" })?.value
        let capturedLimit = state.queryItems.first(where: { $0.name == "limit" })?.value
        #expect(capturedQuery == query)
        #expect(capturedLimit == "100")
    }

    @Test func zileanIndexerEncodesQueryParametersSafely() async throws {
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

        let indexer = ZileanIndexer(baseURL: "https://zilean.example", session: session)
        let query = "Dune & Part=Two"
        let _ = try await indexer.searchByQuery(query: query, type: .movie)

        let capturedQuery = state.queryItems.first(where: { $0.name == "query" })?.value
        #expect(capturedQuery == query)
    }

    @Test func debridLinkAddMagnetRejectsMalformedHashBeforeNetwork() async {
        let session = makeStubSession { request in
            Issue.record("Unexpected network request: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = DebridLinkService(apiToken: "token", session: session)

        do {
            _ = try await service.addMagnet(hash: "bad-hash")
            Issue.record("Expected DebridError.invalidHash")
        } catch let error as DebridError {
            if case .invalidHash(let hash) = error {
                #expect(hash == "bad-hash")
            } else {
                Issue.record("Unexpected DebridError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func openSubtitlesSearchParsesFormatFromFilename() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.opensubtitles.com/api/v1/subtitles")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
              "data": [
                {
                  "id": 123,
                  "attributes": {
                    "language": "en",
                    "release": "Example Release",
                    "ratings": 8.2,
                    "download_count": 42,
                    "hearing_impaired": false,
                    "files": [
                      { "file_id": 777, "file_name": "example.vtt" }
                    ]
                  }
                }
              ]
            }
            """
            return (response, Data(body.utf8))
        }

        let service = OpenSubtitlesService(apiKey: "api-key", session: session)
        let subtitles = try await service.search(query: "Example")

        #expect(subtitles.count == 1)
        #expect(subtitles.first?.format == .vtt)
    }

    @Test func torznabIndexerPreservesApiKeyAndQueryValues() async throws {
        final class RequestState: @unchecked Sendable {
            var queryItems: [URLQueryItem] = []
        }
        let state = RequestState()
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            state.queryItems = components?.queryItems ?? []

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            <rss><channel><item>
              <title>Example Release</title>
              <torznab:attr name="infohash" value="ABCDEF123456"/>
              <torznab:attr name="size" value="123456"/>
              <torznab:attr name="seeders" value="12"/>
              <torznab:attr name="peers" value="3"/>
            </item></channel></rss>
            """
            return (response, Data(body.utf8))
        }

        let apiKey = "key+with&symbols=="
        let query = "Dune & Part+Two"
        let indexer = TorznabIndexer(
            name: "Test",
            baseURL: "https://indexer.example",
            apiKey: apiKey,
            apiKeyTransport: .query,
            session: session
        )
        let results = try await indexer.searchByQuery(query: query, type: .movie)

        #expect(results.count == 1)
        let capturedApiKey = state.queryItems.first(where: { $0.name == "apikey" })?.value
        let capturedQuery = state.queryItems.first(where: { $0.name == "q" })?.value
        #expect(capturedApiKey == apiKey)
        #expect(capturedQuery == query)
    }

    @Test func torBoxRequestDownloadUsesAuthHeaderNotQueryToken() async throws {
        final class RequestState: @unchecked Sendable {
            var requestAuthHeader: String?
            var requestTorrentId: String?
            var tokenInQuery: Bool = false
        }
        let state = RequestState()
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let path = url.path

            if path.hasSuffix("/torrents/mylist") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "success": true,
                  "data": {
                    "name": "Example.Movie.2025.1080p",
                    "size": 123456789,
                    "download_finished": true
                  }
                }
                """
                return (response, Data(body.utf8))
            }

            if path.hasSuffix("/torrents/requestdl") {
                let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                state.tokenInQuery = queryItems.contains(where: { $0.name == "token" })
                state.requestTorrentId = queryItems.first(where: { $0.name == "torrent_id" })?.value
                state.requestAuthHeader = request.value(forHTTPHeaderField: "Authorization")

                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "success": true,
                  "data": {
                    "data": "https://cdn.example.com/video.mkv"
                  }
                }
                """
                return (response, Data(body.utf8))
            }

            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())
        }

        let token = "abc+def/ghi=="
        let service = TorBoxService(apiToken: token, session: session)
        let stream = try await service.getStreamURL(torrentId: "42")

        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/video.mkv")
        #expect(state.tokenInQuery == false) // Token must NOT be in URL
        #expect(state.requestAuthHeader == "Bearer \(token)")
        #expect(state.requestTorrentId == "42")
    }

    @Test func offcloudResolvesDownloadedStreamFromExploreLinks() async throws {
        let session = makeStubSession { request in
            let url = try #require(request.url)
            let path = url.path

            if path.hasSuffix("/api/cloud/status") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "request_id": "req-123",
                  "file_name": "Example.Movie.2025.1080p.mkv",
                  "status": "downloaded"
                }
                """
                return (response, Data(body.utf8))
            }

            if path.hasSuffix("/api/cloud/explore/req-123") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                [
                  "https://cdn.example.com/readme.txt",
                  "https://cdn.example.com/video.mkv"
                ]
                """
                return (response, Data(body.utf8))
            }

            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())
        }

        let service = OffcloudService(apiToken: "token", session: session)
        let stream = try await service.getStreamURL(torrentId: "req-123")

        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/video.mkv")
        #expect(stream.fileName == "Example.Movie.2025.1080p.mkv")
    }

    @Test func openSubtitlesDownloadFirstMatchReturnsLocalSubtitleFile() async throws {
        final class RequestState: @unchecked Sendable {
            var didCallDownloadEndpoint = false
        }
        let state = RequestState()

        let session = makeStubSession { request in
            let url = try #require(request.url)
            let path = url.path

            if path.hasSuffix("/api/v1/subtitles") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "data": [
                    {
                      "id": 123,
                      "attributes": {
                        "language": "en",
                        "release": "Example",
                        "ratings": 8.5,
                        "download_count": 1,
                        "hearing_impaired": false,
                        "files": [
                          { "file_id": 777, "file_name": "example.srt" }
                        ]
                      }
                    }
                  ]
                }
                """
                return (response, Data(body.utf8))
            }

            if path.hasSuffix("/api/v1/download") {
                state.didCallDownloadEndpoint = true
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = #"{"link":"https://cdn.example.com/example.srt"}"#
                return (response, Data(body.utf8))
            }

            if url.host == "cdn.example.com" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                1
                00:00:01,000 --> 00:00:02,000
                Downloaded subtitle
                """
                return (response, Data(body.utf8))
            }

            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())
        }

        let service = OpenSubtitlesService(apiKey: "api-key", session: session)
        let subtitle = try await service.downloadFirstMatch(query: "Example")

        let fileURL = try #require(subtitle.downloadURL)
        #expect(fileURL.isFileURL)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("Downloaded subtitle"))
        #expect(state.didCallDownloadEndpoint)
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test func subtitleAutoSearchSettingPersists() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("vpstudio-settings-tests.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()

        let settings = SettingsManager(database: database, secretStore: TestSecretStore())
        try await settings.setBool(key: SettingsKeys.subtitleAutoSearch, value: false)
        let persisted = try await settings.getBool(key: SettingsKeys.subtitleAutoSearch, default: true)

        #expect(persisted == false)
    }

    @Test func preferredEnvironmentSettingPersists() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("vpstudio-environment-settings-tests.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()

        let settings = SettingsManager(database: database, secretStore: TestSecretStore())
        try await settings.setString(key: SettingsKeys.preferredEnvironment, value: EnvironmentType.hdriSkybox.rawValue)
        let persisted = try await settings.getString(key: SettingsKeys.preferredEnvironment)

        #expect(persisted == EnvironmentType.hdriSkybox.rawValue)
    }

    @Test func allDebridUnauthorizedMapsToUnauthorizedError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.alldebrid.com/v4/user")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let service = AllDebridService(apiToken: "token", session: session)

        do {
            _ = try await service.validateToken()
            Issue.record("Expected DebridError.unauthorized")
        } catch let error as DebridError {
            if case .unauthorized = error {
                return
            } else {
                Issue.record("Unexpected DebridError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func allDebridCacheIncludesNotCachedForMissingHashes() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.alldebrid.com/v4/magnet/instant")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = """
            {
              "status": "success",
              "data": {
                "magnets": [
                  { "hash": "abc", "instant": true }
                ]
              }
            }
            """
            return (response, Data(body.utf8))
        }
        let service = AllDebridService(apiToken: "token", session: session)
        let cache = try await service.checkCache(hashes: ["abc", "def"])

        guard let abc = cache["abc"] else {
            Issue.record("Expected cache entry for hash abc")
            return
        }
        guard let def = cache["def"] else {
            Issue.record("Expected cache entry for hash def")
            return
        }

        if case .cached = abc {} else {
            Issue.record("Expected hash abc to be cached")
        }
        if case .notCached = def {} else {
            Issue.record("Expected hash def to be notCached")
        }
    }

    @Test func openSubtitlesUnauthorizedStatusReturnsUnauthorizedError() async {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.opensubtitles.com/api/v1/subtitles")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let service = OpenSubtitlesService(apiKey: "api-key", session: session)

        do {
            _ = try await service.search(query: "Dune")
            Issue.record("Expected SubtitleError.unauthorized")
        } catch let error as SubtitleError {
            if case .unauthorized = error {
                return
            } else {
                Issue.record("Unexpected SubtitleError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func traktRefreshesTokenOnUnauthorizedAndRetries() async throws {
        final class RequestState: @unchecked Sendable {
            var watchlistRequestCount = 0
            var secondAuthHeader: String?
        }

        let state = RequestState()
        let session = makeStubSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if request.httpMethod == "POST" {
                let success = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let payload = """
                {
                  "access_token": "new-access-token",
                  "refresh_token": "new-refresh-token"
                }
                """
                return (success, Data(payload.utf8))
            }

            switch url.path {
            case let path where path.hasSuffix("/sync/watchlist/movies"):
                state.watchlistRequestCount += 1
                if state.watchlistRequestCount == 1 {
                    let unauthorized = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (unauthorized, Data())
                }

                state.secondAuthHeader = request.value(forHTTPHeaderField: "Authorization")
                let success = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (success, Data("[]".utf8))

            default:
                let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (notFound, Data())
            }
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "old-access-token", refresh: "refresh-token")
        let items = try await service.getWatchlist(type: .movie)

        #expect(items.isEmpty)
        #expect(state.watchlistRequestCount == 2)
        #expect(state.secondAuthHeader == "Bearer new-access-token")
    }

    @Test func episodeTokenMatcherExtractsEpisodeContextFromCommonPatterns() {
        let contextA = EpisodeTokenMatcher.context(fromQuery: "Some.Show.s03e14.2025.REPACK")
        #expect(contextA?.season == 3)
        #expect(contextA?.episode == 14)

        let contextB = EpisodeTokenMatcher.context(fromQuery: "Some.Show - 2x07")
        #expect(contextB?.season == 2)
        #expect(contextB?.episode == 7)

        let contextC = EpisodeTokenMatcher.context(fromQuery: "season 5 episode 09")
        #expect(contextC?.season == 5)
        #expect(contextC?.episode == 9)

        #expect(EpisodeTokenMatcher.matches(title: "Pilot (S01E01)", season: 1, episode: 1))
        #expect(EpisodeTokenMatcher.matches(title: "The Show 2x3", season: 2, episode: 3))
        #expect(!EpisodeTokenMatcher.matches(title: "Movie 2019", season: 1, episode: 1))
    }

    @Test func eztvIndexerFiltersByEpisodeContextFromQuery() async throws {
        let session = makeStubSession { request in
            let responseURL = request.url ?? URL(string: "https://eztvx.to/api/get-torrents")!
            let components = URLComponents(url: responseURL, resolvingAgainstBaseURL: false)
            let page = components?.queryItems?.first(where: { $0.name == "page" })?.value

            let body: String
            if page == "1" {
                body = """
                {
                  "torrents": [
                    { "hash": "hash-0101", "title": "Wrong.Episode", "season": "1", "episode": "1", "size_bytes": "1234" },
                    { "hash": "hash-0102", "title": "Correct Episode S01E02", "season": "1", "episode": "2", "size_bytes": "4321" }
                  ]
                }
                """
            } else {
                body = "{ \"torrents\": [] }"
            }

            let response = HTTPURLResponse(url: responseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        let indexer = EZTVIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "My.Show S01E02", type: .series)

        #expect(results.count == 1)
        #expect(results.first?.infoHash == "hash-0102")
    }

    @Test func eztvIndexerThrowsWhenLaterPageFails() async {
        final class RequestState: @unchecked Sendable {
            var requestCount: Int = 0
        }
        let state = RequestState()

        let pageOneTorrents = (0..<100).map { index -> String in
            """
            { "hash": "hash-\(index)", "title": "Correct Episode S01E02", "season": "1", "episode": "2", "size_bytes": "4321" }
            """
        }.joined(separator: ",")

        let session = makeStubSession { request in
            let responseURL = request.url ?? URL(string: "https://eztvx.to/api/get-torrents")!
            let page = URLComponents(url: responseURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "page" })?
                .value

            state.requestCount += 1
            if page == "1" {
                let body = #"{"torrents":["# + pageOneTorrents + "]}"
                let response = HTTPURLResponse(url: responseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            let response = HTTPURLResponse(url: responseURL, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let indexer = EZTVIndexer(session: session)

        do {
            _ = try await indexer.searchByQuery(query: "My.Show S01E02", type: .series)
            Issue.record("Expected URLError.badServerResponse")
        } catch let error as URLError {
            #expect(error.code == .badServerResponse)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(state.requestCount >= 2)
    }

    @Test func zileanIndexerFiltersByEpisodeContextFromQuery() async throws {
        let session = makeStubSession { request in
            let responseURL = request.url ?? URL(string: "https://zilean.example/dmm/search")!
            let payload = """
            [
                { "info_hash": "z-mismatch", "raw_title": "Show 1x01", "size": 1000 },
                { "info_hash": "z-match", "raw_title": "Show S01E02", "size": 2000 }
            ]
            """
            let response = HTTPURLResponse(url: responseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let indexer = ZileanIndexer(baseURL: "https://zilean.example", session: session)
        let results = try await indexer.searchByQuery(query: "Some.Show s01e02", type: .series)

        #expect(results.count == 1)
        #expect(results.first?.infoHash == "z-match")
    }

    @Test func stremioSearchByQueryUsesSeriesEpisodeIDForStreamURL() async throws {
        final class StreamState: @unchecked Sendable { var streamPath: String? }
        let state = StreamState()

        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://stremio.example/stream/series/tt1234567:1:2.json")!
            state.streamPath = url.path

            if url.path.contains("/stream/series/tt1234567:1:2.json") {
                let body = """
                {
                  "streams": [
                    {
                      "title": "Source",
                      "url": "magnet:?xt=urn:btih:abc",
                      "infoHash": "abc",
                      "behaviorHints": { "videoSize": 12345, "seeders": 9, "leechers": 0 }
                    }
                  ]
                }
                """
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            throw URLError(.unsupportedURL)
        }

        let indexer = StremioIndexer(name: "stremio", baseURL: "https://stremio.example", session: session)
        let results = try await indexer.searchByQuery(query: "Movie: tt1234567 s01e02", type: .series)

        #expect(results.count == 1)
        #expect(state.streamPath == "/stream/series/tt1234567:1:2.json")
    }

    @Test func offcloudValidateTokenReturnsFalseWhenUnauthorized() async throws {
        let session = makeStubSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://offcloud.com/api/cloud/history")!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = OffcloudService(apiToken: "offcloud-token", session: session)
        let isValid = try await service.validateToken()

        #expect(isValid == false)
    }

    @Test func offcloudSelectFilesUsesRequestedFileId() async throws {
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://offcloud.com/api")!
            if url.path == "/cloud/status" {
                let body = """
                {"requestId":"req-123","fileName":"show.mkv","status":"downloaded"}
                """
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            if url.path == "/cloud/explore/req-123" {
                let body = """
                [
                  "https://cdn.example.com/first.mkv",
                  "https://cdn.example.com/second.mkv",
                  "https://cdn.example.com/third.mp4"
                ]
                """
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            let bad = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (bad, Data())
        }

        let service = OffcloudService(apiToken: "offcloud-token", session: session)
        try await service.selectFiles(torrentId: "req-123", fileIds: [2])
        let stream = try await service.getStreamURL(torrentId: "req-123")

        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/second.mkv")
    }

    @Test func allDebridGetsExplicitlySelectedLinkWhenAvailable() async throws {
        final class RequestState: @unchecked Sendable {
            var unlockedLink: String?
        }

        let state = RequestState()
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://api.alldebrid.com/v4")!

            if url.path == "/v4/magnet/status" {
                let body = """
                {
                  "status": "success",
                  "data": {
                    "id": 55,
                    "filename": "Show.S01E02.mkv",
                    "status": "finished",
                    "statusCode": 4,
                    "size": 2048,
                    "links": [
                      {"link": "https://cdn.example.com/ep1.mkv", "filename": "S01E01", "size": 100},
                      {"link": "https://cdn.example.com/ep2.mkv", "filename": "S01E02", "size": 200}
                    ]
                  }
                }
                """
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            if url.path == "/v4/link/unlock" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                state.unlockedLink = components?.queryItems?.first(where: { $0.name == "link" })?.value
                let linkValue = state.unlockedLink ?? ""
                let body = """
                {
                  "status": "success",
                  "data": { "link": "\(linkValue)", "filename": "selected", "filesize": 200 }
                }
                """
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())
        }

        let service = AllDebridService(apiToken: "ad-token", session: session)
        try await service.selectFiles(torrentId: "55", fileIds: [2])
        let stream = try await service.getStreamURL(torrentId: "55")

        #expect(state.unlockedLink == "https://cdn.example.com/ep2.mkv")
        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/ep2.mkv")
    }

    @Test func debridLinkUsesRequestedFileIdWhenSelectingFiles() async throws {
        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://debrid-link.com/api/v2/seedbox/list")!
            let body = """
            {
              "success": true,
              "value": [
                {
                  "name": "Show.S01",
                  "totalSize": 4000,
                  "downloadPercent": 100,
                  "files": [
                    { "id": 1, "name": "eps1", "size": 100, "download_url": "https://cdn.example.com/eps1.mkv" },
                    { "id": 2, "name": "eps2", "size": 120, "download_url": "https://cdn.example.com/eps2.mkv" }
                  ]
                }
              ]
            }
            """
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        let service = DebridLinkService(apiToken: "dl-token", session: session)
        try await service.selectFiles(torrentId: "req-55", fileIds: [2])
        let stream = try await service.getStreamURL(torrentId: "req-55")

        #expect(stream.streamURL.absoluteString == "https://cdn.example.com/eps2.mkv")
    }

    @Test func traktAddToHistorySendsEpisodePayloadWhenEpisodeIdProvided() async throws {
        final class State: @unchecked Sendable {
            var sawEpisodePayload = false
            var requestBody: [String: Any]?
        }

        let state = State()
        let expectedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedWatchedAt = ISO8601DateFormatter().string(from: expectedDate)

        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://api.trakt.tv/sync/history")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if request.httpMethod == "POST", url.path.contains("/sync/history"), let bodyData = requestBodyData(from: request) {
                let parsed = (try JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any])
                state.requestBody = parsed

                if let episodes = parsed?["episodes"] as? [[String: Any]],
                   let first = episodes.first,
                   let ids = first["ids"] as? [String: Any],
                   let episodeId = ids["imdb"] as? String,
                   episodeId == "tt9999999",
                   let watchedAt = first["watched_at"] as? String,
                   watchedAt == expectedWatchedAt {
                    state.sawEpisodePayload = true
                }
            }

            return (response, Data("{}".utf8))
        }

        let service = TraktSyncService(clientId: TraktDefaults.clientId, clientSecret: TraktDefaults.clientSecret, session: session)
        await service.setTokens(access: "token", refresh: "refresh")
        try await service.addToHistory(imdbId: "tt1234567", type: .series, episodeId: "tt9999999", watchedAt: expectedDate)

        #expect(state.sawEpisodePayload)
        #expect(state.requestBody != nil)
        #expect(state.requestBody?["episodes"] != nil)
    }

    @Test func traktAddToHistoryBuildsSeasonEpisodePayloadWhenEpisodeCodeIsAvailable() async throws {
        final class State: @unchecked Sendable {
            var requestBody: [String: Any]?
        }

        let state = State()
        let expectedDate = Date(timeIntervalSince1970: 1_700_000_100)
        let expectedWatchedAt = ISO8601DateFormatter().string(from: expectedDate)

        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://api.trakt.tv/sync/history")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if request.httpMethod == "POST", url.path.contains("/sync/history"), let bodyData = requestBodyData(from: request) {
                state.requestBody = try JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any]
            }

            return (response, Data("{}".utf8))
        }

        let service = TraktSyncService(clientId: TraktDefaults.clientId, clientSecret: TraktDefaults.clientSecret, session: session)
        await service.setTokens(access: "token", refresh: "refresh")
        try await service.addToHistory(
            imdbId: "tt1234567",
            type: .series,
            episodeId: "tmdb-999-s2e5",
            watchedAt: expectedDate
        )

        let shows = try #require(state.requestBody?["shows"] as? [[String: Any]])
        let firstShow = try #require(shows.first)
        let seasons = try #require(firstShow["seasons"] as? [[String: Any]])
        let firstSeason = try #require(seasons.first)
        let episodes = try #require(firstSeason["episodes"] as? [[String: Any]])
        let firstEpisode = try #require(episodes.first)

        #expect(firstSeason["number"] as? Int == 2)
        #expect(firstEpisode["number"] as? Int == 5)
        #expect(firstEpisode["watched_at"] as? String == expectedWatchedAt)
    }

    @Test func databaseFetchCompletedHistorySupportsPagination() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-completed-history.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for index in 0..<3 {
            try await database.saveWatchHistory(WatchHistory(
                id: UUID().uuidString,
                mediaId: "tt100\(index)",
                episodeId: nil,
                title: "Episode \(index)",
                progress: 0,
                duration: 0,
                quality: nil,
                debridService: nil,
                streamURL: nil,
                watchedAt: Date(timeIntervalSinceNow: Double(-index * 10)),
                isCompleted: true
            ))
        }

        let firstPage = try await database.fetchCompletedWatchHistory(limit: 2, offset: 0)
        let secondPage = try await database.fetchCompletedWatchHistory(limit: 2, offset: 2)

        #expect(firstPage.count == 2)
        #expect(secondPage.count == 1)

        let allIds = firstPage.map(\.id) + secondPage.map(\.id)
        #expect(Set(allIds).count == 3)
    }

    @Test func simklMarkWatchedIncludesWatchedAtTimestamp() async throws {
        final class State: @unchecked Sendable { var sawWatchedAt = false }
        let state = State()
        let expectedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedWatchedAt = ISO8601DateFormatter().string(from: expectedDate)

        let session = makeStubSession { request in
            let url = request.url ?? URL(string: "https://api.simkl.com/sync/history")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!

            if request.httpMethod == "POST",
               request.url?.path.contains("/sync/history") == true,
               let bodyData = requestBodyData(from: request),
               let bodyString = String(data: bodyData, encoding: .utf8),
               bodyString.contains(expectedWatchedAt) {
                state.sawWatchedAt = true
            }

            let payload = "{\"added\":{\"movies\":1},\"not_found\":{}}"
            return (response, Data(payload.utf8))
        }

        let service = SimklSyncService(clientId: "simkl-client-id", session: session)
        await service.setAccessToken("simkl-token")
        try await service.markWatched(imdbId: "tt9876543", type: .movie, watchedAt: expectedDate)

        #expect(state.sawWatchedAt)
    }

    @Test @MainActor func appStateResetClearsCachedServiceActors() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-appstate-reset.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appState = AppState(database: database, secretStore: TestSecretStore())
        let beforeDebridManager = appState.debridManager
        let beforeScrobble = appState.scrobbleCoordinator

        try await appState.resetAllData()

        let afterDebridManager = appState.debridManager
        let afterScrobble = appState.scrobbleCoordinator

        #expect(beforeDebridManager !== afterDebridManager)
        #expect(beforeScrobble !== afterScrobble)
    }

    @Test func libraryCSVExportHistoryReturnsAllRowsIncludingEpisodeDuplicatesAndLatestRating() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-export-history.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await database.saveWatchHistory(WatchHistory(
            id: UUID().uuidString,
            mediaId: "tt1234567",
            episodeId: "s01e01",
            title: "Episode 1",
            progress: 0,
            duration: 0,
            quality: nil,
            debridService: nil,
            streamURL: nil,
            watchedAt: Date(timeIntervalSinceNow: -300),
            isCompleted: true
        ))
        try await database.saveWatchHistory(WatchHistory(
            id: UUID().uuidString,
            mediaId: "tt1234567",
            episodeId: "s01e02",
            title: "Episode 2",
            progress: 0,
            duration: 0,
            quality: nil,
            debridService: nil,
            streamURL: nil,
            watchedAt: Date(),
            isCompleted: true
        ))

        try await database.saveTasteEvent(TasteEvent(
            id: UUID().uuidString,
            mediaId: "tt1234567",
            eventType: .rated,
            feedbackScale: .oneToTen,
            feedbackValue: 10,
            createdAt: Date(timeIntervalSinceNow: -120)
        ))
        try await database.saveTasteEvent(TasteEvent(
            id: UUID().uuidString,
            mediaId: "tt1234567",
            eventType: .rated,
            feedbackScale: .oneToTen,
            feedbackValue: 5,
            createdAt: Date(timeIntervalSinceNow: -600)
        ))

        let exportService = LibraryCSVExportService(database: database)
        let (csv, itemCount) = try await exportService.exportFolder(listType: .history, folderId: nil)

        #expect(itemCount == 2)

        let lines = csv.split(whereSeparator: \.isNewline)
        #expect(lines.count == 3)

        let mediaRows = lines.dropFirst().filter { $0.hasPrefix("tt1234567,") }
        #expect(mediaRows.count == 2)
        #expect(mediaRows.allSatisfy { $0.split(separator: ",")[1] == "10" })

        _ = csv
    }

    @Test func libraryCSVExportHistorySupportsPaginationBeyondSinglePage() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "vpstudio-export-history-pagination.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for index in 0..<1_050 {
            try await database.saveWatchHistory(WatchHistory(
                id: UUID().uuidString,
                mediaId: "tt\(index)",
                episodeId: nil,
                title: "Episode \(index)",
                progress: 0,
                duration: 0,
                quality: nil,
                debridService: nil,
                streamURL: nil,
                watchedAt: Date(timeIntervalSinceNow: Double(-index * 10)),
                isCompleted: true
            ))
        }

        let exportService = LibraryCSVExportService(database: database)
        let (csv, itemCount) = try await exportService.exportFolder(listType: .history, folderId: nil)

        #expect(itemCount == 1_050)
        let lines = csv.split(whereSeparator: \.isNewline)
        #expect(lines.count == 1_051)
    }

    @Test func laneC_environmentCatalog_resolvesNilYawOffsets() {
        #expect(EnvironmentCatalogManager.resolveHdriYawOffset(from: nil) == 0)
        #expect(EnvironmentCatalogManager.resolveHdriYawOffset(from: 17.75) == 17.75)
    }

    @Test func laneC_assistantManager_usesCanonicalFallbackModels() {
        #expect(AIAssistantManager.fallbackModelID(for: .openAI) == AIModelCatalog.gpt54.id)
        #expect(AIAssistantManager.fallbackModelID(for: .anthropic) == AIModelCatalog.defaultModel(for: .anthropic)?.id)
        #expect(AIAssistantManager.fallbackModelID(for: .gemini) == AIModelCatalog.gemini25Flash.id)

        #expect(
            AIAssistantManager.resolvedModelID(
                provider: .openAI,
                catalogDefault: AIModelCatalog.gpt54.id,
                configuredModel: nil
            ) == AIModelCatalog.gpt54.id
        )
    }

    @Test @MainActor func laneC_spatialModeDetection_prefersCodecMetadataOverFilename() {
        let engine = VPPlayerEngine()
        engine.updateStereoMode(from: "A regular movie file", codecHint: "hevc_mv")
        #expect(engine.stereoMode == .mvHevc)

        engine.updateStereoMode(from: "movie_sidebyside.mkv", codecHint: nil)
        #expect(engine.stereoMode == .sideBySide)
    }

    @Test func laneC_externalPlayerRouting_appendsEncodedStreamToCustomTemplate() {
        let streamURL = URL(string: "https://cdn.example.com/video.mp4?foo=bar&baz=1")!

        let placeholderTemplate = ExternalPlayerPreference(app: .custom, customURLTemplate: "videoplayer://play?url={url}")
        let placeholderURL = ExternalPlayerRouting.launchURL(for: streamURL, preference: placeholderTemplate)
        #expect(placeholderURL != nil)
        if let placeholderURL,
           let components = URLComponents(url: placeholderURL, resolvingAgainstBaseURL: false),
           let streamParam = components.queryItems?.first(where: { $0.name == "url" })?.value {
            #expect(streamParam == streamURL.absoluteString)
        } else {
            Issue.record("Expected url query param when launching with placeholder template")
        }

        let noPlaceholderTemplate = ExternalPlayerPreference(app: .custom, customURLTemplate: "videoplayer://play")
        let noPlaceholderURL = ExternalPlayerRouting.launchURL(for: streamURL, preference: noPlaceholderTemplate)
        #expect(noPlaceholderURL != nil)
        if let noPlaceholderURL,
           let components = URLComponents(url: noPlaceholderURL, resolvingAgainstBaseURL: false),
           let streamParam = components.queryItems?.first(where: { $0.name == "url" })?.value {
            #expect(streamParam == streamURL.absoluteString)
        } else {
            Issue.record("Expected appended url query param when template has no placeholder")
        }

        let noApp = ExternalPlayerPreference(app: .builtIn, customURLTemplate: nil)
        #expect(ExternalPlayerRouting.launchURL(for: streamURL, preference: noApp) == nil)
    }

    @Test func laneC_playerView_refreshGuardProtectsOldStream() {
        #expect(PlayerView.audioTrackRefreshShouldRun(requestedStreamID: "current", currentStreamID: "current"))
        #expect(!PlayerView.audioTrackRefreshShouldRun(requestedStreamID: "current", currentStreamID: "next"))
    }

    @Test func laneC_playerView_subtitleGuardProtectsOldStream() {
        #expect(PlayerView.subtitleMutationShouldRun(requestedStreamID: "current", currentStreamID: "current"))
        #expect(!PlayerView.subtitleMutationShouldRun(requestedStreamID: "current", currentStreamID: "next"))
        #expect(!PlayerView.subtitleMutationShouldRun(requestedStreamID: "current", currentStreamID: nil))
    }

    #if os(visionOS)
    @Test func laneC_apmpInjector_reportsModeSpecificMetadata() {
        let sbs = APMPInjector.stereoMetadataExtensions(for: .sideBySide)
        let ou = APMPInjector.stereoMetadataExtensions(for: .overUnder)

        #expect(sbs["ViewPackingKind"] as? String == "SideBySide")
        #expect(ou["ViewPackingKind"] as? String == "OverUnder")
        #expect((sbs["ViewPackingKind"] as? String) != (ou["ViewPackingKind"] as? String))
    }

    @Test func laneC_headTracker_pollingIntervalHonorsIdleMode() {
        #expect(HeadTracker.pollingInterval(isIdle: true, activeInterval: .milliseconds(100)) == .milliseconds(500))
        #expect(HeadTracker.pollingInterval(isIdle: false, activeInterval: .milliseconds(100)) == .milliseconds(100))
    }
    #endif

}
