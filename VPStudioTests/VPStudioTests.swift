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
    let serviceType: DebridServiceType

    private let streamToReturn: StreamInfo
    private var calls: [String] = []

    init(serviceType: DebridServiceType, streamToReturn: StreamInfo) {
        self.serviceType = serviceType
        self.streamToReturn = streamToReturn
    }

    func validateToken() async throws -> Bool { true }

    func getAccountInfo() async throws -> DebridAccountInfo {
        DebridAccountInfo(username: "mock", email: nil, premiumExpiry: nil, isPremium: true)
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        hashes.reduce(into: [String: CacheStatus]()) { result, hash in
            result[hash] = .notCached
        }
    }

    func addMagnet(hash: String) async throws -> String {
        calls.append("add:\(hash)")
        return "torrent-\(hash)"
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        calls.append("select:\(torrentId)")
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        calls.append("stream:\(torrentId)")
        return streamToReturn
    }

    func unrestrict(link: String) async throws -> URL {
        streamToReturn.streamURL
    }

    func callSequence() -> [String] {
        calls
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

        let config = DebridConfig(
            id: "rd-config",
            serviceType: .realDebrid,
            apiTokenRef: "token",
            isActive: true,
            priority: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await database.saveDebridConfig(config)

        let manager = DebridManager(
            database: database,
            secretStore: TestSecretStore(),
            serviceFactory: { _, _ in mockService }
        )

        let stream = try await manager.resolveStream(hash: "abc123")
        let calls = await mockService.callSequence()

        #expect(stream.streamURL.absoluteString == expectedStream.streamURL.absoluteString)
        #expect(calls.count == 3, "Expected exactly 3 calls, no duplicates")
        #expect(calls == ["add:abc123", "select:torrent-abc123", "stream:torrent-abc123"])
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

        try await database.saveDebridConfig(
            DebridConfig(
                id: "rd",
                serviceType: .realDebrid,
                apiTokenRef: "rd-token",
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
                apiTokenRef: "ad-token",
                isActive: true,
                priority: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        let manager = DebridManager(
            database: database,
            secretStore: TestSecretStore(),
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

    @Test func debridLinkAddMagnetThrowsWhenAPIRejectsMagnet() async {
        let session = makeStubSession { request in
            let url = try #require(request.url)
            if url.path.hasSuffix("/seedbox/add") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                {
                  "success": false,
                  "error": "invalid magnet"
                }
                """
                return (response, Data(body.utf8))
            }

            let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (notFound, Data())
        }

        let service = DebridLinkService(apiToken: "token", session: session)

        do {
            _ = try await service.addMagnet(hash: "bad-hash")
            Issue.record("Expected DebridError.networkError")
        } catch let error as DebridError {
            if case .networkError(let message) = error {
                #expect(message.contains("invalid magnet"))
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
        let indexer = TorznabIndexer(name: "Test", baseURL: "https://indexer.example", apiKey: apiKey, session: session)
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

}
