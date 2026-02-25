import Foundation
import Testing
@testable import VPStudio

// MARK: - URL Protocol Stub

private enum OrchestratorStubError: Error {
    case missingHandler
}

private final class OrchestratorURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    static let lock = NSLock()
    static let handlerHeader = "X-VPStudio-Orchestrator-Stub"

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
            client?.urlProtocol(self, didFailWithError: OrchestratorStubError.missingHandler)
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
            if read <= 0 { break }
            output.append(buffer, count: read)
        }
        return output
    }
}

private func makeStubSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    let handlerID = OrchestratorURLProtocolStub.register(handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [OrchestratorURLProtocolStub.self]
    config.httpAdditionalHeaders = [OrchestratorURLProtocolStub.handlerHeader: handlerID]
    return URLSession(configuration: config)
}

// MARK: - Test Helpers

private func makeTempDatabase() async throws -> DatabaseManager {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbPath = tempDir.appendingPathComponent("orchestrator-test.sqlite").path
    let database = try DatabaseManager(path: dbPath)
    try await database.migrate()
    return database
}

private func makeSettingsManager(database: DatabaseManager) -> SettingsManager {
    let secretStore = TestSecretStore()
    return SettingsManager(database: database, secretStore: secretStore)
}

private func makeOrchestrator(
    database: DatabaseManager,
    settingsManager: SettingsManager,
    session: URLSession
) -> (TraktSyncOrchestrator, TraktSyncService) {
    let service = TraktSyncService(clientId: "test-client", clientSecret: "test-secret", session: session)
    let orchestrator = TraktSyncOrchestrator(
        traktService: service,
        database: database,
        settingsManager: settingsManager
    )
    return (orchestrator, service)
}

/// Builds a stub session that returns path-matched JSON responses for Trakt API endpoints.
private func makeOrchestratorStubSession(
    watchlistMovies: String = "[]",
    watchlistShows: String = "[]",
    ratingsMovies: String = "[]",
    ratingsShows: String = "[]",
    historyMovies: String = "[]",
    historyShows: String = "[]",
    postResponder: ((URLRequest) -> (Int, String))? = nil
) -> URLSession {
    makeStubSession { request in
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let url = request.url!

        if method == "POST" {
            if let postResponder {
                let (statusCode, body) = postResponder(request)
                let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }
            // Default POST response
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"added":{"movies":1,"shows":0,"episodes":0}}"#
            return (response, Data(body.utf8))
        }

        // GET responses by path
        let body: String
        if path.hasSuffix("/sync/watchlist/movies") {
            body = watchlistMovies
        } else if path.hasSuffix("/sync/watchlist/shows") {
            body = watchlistShows
        } else if path.hasSuffix("/sync/ratings/movies") {
            body = ratingsMovies
        } else if path.hasSuffix("/sync/ratings/shows") {
            body = ratingsShows
        } else if path.contains("/sync/history/movies") {
            body = historyMovies
        } else if path.contains("/sync/history/shows") {
            body = historyShows
        } else {
            body = "[]"
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }
}

// MARK: - Pull Tests

@Suite("TraktSyncOrchestrator - Pull", .serialized)
struct TraktSyncOrchestratorPullTests {

    @Test("pull creates watchlist entries from remote")
    func pullCreatesWatchlistEntries() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            watchlistMovies: """
            [{"rank":1,"movie":{"title":"Dune","year":2021,"ids":{"trakt":1,"imdb":"tt1160419","tmdb":438631}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPulled == 1)
        let entries = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(entries.count == 1)
        #expect(entries[0].mediaId == "tt1160419")
    }

    @Test("pull skips duplicates that already exist in local watchlist")
    func pullSkipsDuplicateWatchlist() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Pre-add the item to the local watchlist
        let entry = UserLibraryEntry(
            id: UUID().uuidString,
            mediaId: "tt1160419",
            folderId: LibraryFolder.systemFolderID(for: .watchlist),
            listType: .watchlist,
            addedAt: Date()
        )
        try await database.addToLibrary(entry)

        let session = makeOrchestratorStubSession(
            watchlistMovies: """
            [{"rank":1,"movie":{"title":"Dune","year":2021,"ids":{"trakt":1,"imdb":"tt1160419","tmdb":438631}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPulled == 0)
        let entries = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(entries.count == 1)
    }

    @Test("pull creates taste events from remote ratings")
    func pullCreatesRatings() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: true)

        let session = makeOrchestratorStubSession(
            ratingsMovies: """
            [{"rating":9,"rated_at":"2025-01-20","movie":{"title":"Interstellar","year":2014,"ids":{"trakt":111,"imdb":"tt0816692"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.ratingsPulled == 1)
        let event = try await database.fetchLatestTasteRating(mediaId: "tt0816692")
        #expect(event != nil)
        #expect(event?.feedbackValue == 9)
        #expect(event?.feedbackScale == .oneToTen)
        #expect(event?.source == .automatic)
    }

    @Test("pull skips ratings that already exist locally")
    func pullSkipsDuplicateRatings() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: true)

        // Pre-add a local rating
        let event = TasteEvent(
            userId: "default",
            mediaId: "tt0816692",
            eventType: .rated,
            feedbackScale: .oneToTen,
            feedbackValue: 8,
            source: .manual
        )
        try await database.saveTasteEvent(event)

        let session = makeOrchestratorStubSession(
            ratingsMovies: """
            [{"rating":9,"rated_at":"2025-01-20","movie":{"title":"Interstellar","year":2014,"ids":{"trakt":111,"imdb":"tt0816692"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.ratingsPulled == 0)
    }

    @Test("pull creates history entries in both WatchHistory and UserLibrary tables")
    func pullCreatesHistoryEntries() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":9999,"watched_at":"2025-08-01T12:00:00.000Z","action":"watch","movie":{"title":"Oppenheimer","year":2023,"ids":{"trakt":555,"imdb":"tt15398776"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 1)

        // Verify WatchHistory record was created (the table the app actually displays)
        let watchHistory = try await database.fetchWatchHistory(mediaId: "tt15398776")
        #expect(watchHistory != nil)
        #expect(watchHistory?.title == "Oppenheimer")
        #expect(watchHistory?.isCompleted == true)
        #expect(watchHistory?.mediaId == "tt15398776")

        // Verify backwards-compatible UserLibraryEntry was also created
        let entries = try await database.fetchLibraryEntries(listType: .history)
        #expect(entries.count == 1)
        #expect(entries[0].mediaId == "tt15398776")
    }

    @Test("pull falls back to tmdb ID when IMDb ID is missing")
    func pullFallsBackToTmdbId() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            watchlistMovies: """
            [{"rank":1,"movie":{"title":"NoIMDb","year":2025,"ids":{"trakt":1,"tmdb":99999}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPulled == 1)
        let entries = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(entries[0].mediaId == "tmdb-99999")
    }

    @Test("pull handles both movies and shows in one sync")
    func pullHandlesMoviesAndShows() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            watchlistMovies: """
            [{"rank":1,"movie":{"title":"Dune","year":2021,"ids":{"trakt":1,"imdb":"tt1160419"}}}]
            """,
            watchlistShows: """
            [{"rank":1,"show":{"title":"The Last of Us","year":2023,"ids":{"trakt":2,"imdb":"tt3581920"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPulled == 2)
        let entries = try await database.fetchLibraryEntries(listType: .watchlist)
        let mediaIds = entries.map(\.mediaId)
        #expect(mediaIds.contains("tt1160419"))
        #expect(mediaIds.contains("tt3581920"))
    }
}

// MARK: - Push Tests

@Suite("TraktSyncOrchestrator - Push", .serialized)
struct TraktSyncOrchestratorPushTests {

    @Test("push sends local watchlist items with IMDb IDs to Trakt")
    func pushWatchlistSendsImdbIds() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Add local watchlist entry
        let entry = UserLibraryEntry(
            id: UUID().uuidString,
            mediaId: "tt9876543",
            folderId: LibraryFolder.systemFolderID(for: .watchlist),
            listType: .watchlist,
            addedAt: Date()
        )
        try await database.addToLibrary(entry)

        final class PostState: @unchecked Sendable {
            var capturedPaths: [String] = []
            let lock = NSLock()
            func record(_ path: String) { lock.lock(); capturedPaths.append(path); lock.unlock() }
            var paths: [String] { lock.lock(); defer { lock.unlock() }; return capturedPaths }
        }
        let postState = PostState()

        let session = makeOrchestratorStubSession(
            postResponder: { request in
                let path = request.url?.path ?? ""
                postState.record(path)
                return (200, #"{"added":{"movies":1,"shows":0,"episodes":0}}"#)
            }
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPushed == 1)
        #expect(postState.paths.contains { $0.hasSuffix("/sync/watchlist") })
    }

    @Test("push skips entries without IMDb IDs")
    func pushSkipsNonImdbEntries() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Add local entry with tmdb-style ID (no IMDb prefix)
        let entry = UserLibraryEntry(
            id: UUID().uuidString,
            mediaId: "tmdb-12345",
            folderId: LibraryFolder.systemFolderID(for: .watchlist),
            listType: .watchlist,
            addedAt: Date()
        )
        try await database.addToLibrary(entry)

        let session = makeOrchestratorStubSession()
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPushed == 0)
    }

    @Test("push ratings sends local rated events to Trakt")
    func pushRatingsSendsToTrakt() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: true)

        // Add a local rating
        let event = TasteEvent(
            userId: "default",
            mediaId: "tt1234567",
            eventType: .rated,
            feedbackScale: .oneToTen,
            feedbackValue: 8,
            source: .manual
        )
        try await database.saveTasteEvent(event)

        final class PostState: @unchecked Sendable {
            var capturedPaths: [String] = []
            let lock = NSLock()
            func record(_ path: String) { lock.lock(); capturedPaths.append(path); lock.unlock() }
            var paths: [String] { lock.lock(); defer { lock.unlock() }; return capturedPaths }
        }
        let postState = PostState()

        let session = makeOrchestratorStubSession(
            postResponder: { request in
                let path = request.url?.path ?? ""
                postState.record(path)
                return (200, #"{"added":{"movies":1,"shows":0,"episodes":0}}"#)
            }
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.ratingsPushed == 1)
        #expect(postState.paths.contains { $0.hasSuffix("/sync/ratings") })
    }
}

// MARK: - Toggle Settings Tests

@Suite("TraktSyncOrchestrator - Settings Toggles", .serialized)
struct TraktSyncOrchestratorToggleTests {

    @Test("sync respects watchlist toggle disabled")
    func syncRespectsWatchlistToggle() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            watchlistMovies: """
            [{"rank":1,"movie":{"title":"Dune","year":2021,"ids":{"trakt":1,"imdb":"tt1160419"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPulled == 0)
        #expect(result.watchlistPushed == 0)
        let entries = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(entries.isEmpty)
    }

    @Test("sync respects history toggle disabled")
    func syncRespectsHistoryToggle() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":1,"watched_at":"2025-08-01","action":"watch","movie":{"title":"Test","year":2025,"ids":{"trakt":1,"imdb":"tt1111111"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 0)
    }

    @Test("sync respects ratings toggle disabled")
    func syncRespectsRatingsToggle() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            ratingsMovies: """
            [{"rating":9,"rated_at":"2025-01-20","movie":{"title":"Test","year":2025,"ids":{"trakt":1,"imdb":"tt2222222"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.ratingsPulled == 0)
        #expect(result.ratingsPushed == 0)
    }

    @Test("sync with all toggles enabled syncs everything")
    func syncWithAllTogglesEnabled() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: true)

        let session = makeOrchestratorStubSession(
            watchlistMovies: """
            [{"rank":1,"movie":{"title":"Dune","year":2021,"ids":{"trakt":1,"imdb":"tt1160419"}}}]
            """,
            ratingsMovies: """
            [{"rating":8,"rated_at":"2025-01-20","movie":{"title":"Arrival","year":2016,"ids":{"trakt":50,"imdb":"tt2543164"}}}]
            """,
            historyMovies: """
            [{"id":1,"watched_at":"2025-08-01","action":"watch","movie":{"title":"Opp","year":2023,"ids":{"trakt":555,"imdb":"tt15398776"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPulled == 1)
        #expect(result.ratingsPulled == 1)
        #expect(result.historyPulled == 1)
    }
}

// MARK: - Error Resilience Tests

@Suite("TraktSyncOrchestrator - Error Resilience", .serialized)
struct TraktSyncOrchestratorErrorResilienceTests {

    @Test("partial API failure does not block other operations")
    func partialFailureDoesNotBlock() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Watchlist movies endpoint returns 500, but history works
        let session = makeStubSession { request in
            let path = request.url?.path ?? ""
            let url = request.url!

            if path.hasSuffix("/sync/watchlist/movies") {
                let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            if path.hasSuffix("/sync/watchlist/shows") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("[]".utf8))
            }
            if path.contains("/sync/history/movies") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = """
                [{"id":1,"watched_at":"2025-08-01","action":"watch","movie":{"title":"Test","year":2025,"ids":{"trakt":1,"imdb":"tt9999999"}}}]
                """
                return (response, Data(body.utf8))
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let defaultBody: String
            if request.httpMethod == "POST" {
                defaultBody = #"{"added":{"movies":1,"shows":0,"episodes":0}}"#
            } else {
                defaultBody = "[]"
            }
            return (response, Data(defaultBody.utf8))
        }

        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        // Watchlist pull should have an error for the movies endpoint
        #expect(result.hasErrors)
        // History should still have been pulled successfully
        #expect(result.historyPulled == 1)
        let historyEntries = try await database.fetchLibraryEntries(listType: .history)
        #expect(historyEntries.count == 1)
    }

    @Test("empty remote returns zero counts with no errors")
    func emptyRemoteReturnsZeroCounts() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: true)

        let session = makeOrchestratorStubSession()
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.watchlistPulled == 0)
        #expect(result.watchlistPushed == 0)
        #expect(result.ratingsPulled == 0)
        #expect(result.ratingsPushed == 0)
        #expect(result.historyPulled == 0)
        #expect(!result.hasErrors)
    }

    @Test("sync records last sync date in settings")
    func syncRecordsLastSyncDate() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession()
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        // Confirm no date before sync
        let before = try await settings.getString(key: SettingsKeys.traktLastSyncDate)
        #expect(before == nil)

        _ = await orchestrator.sync()

        let after = try await settings.getString(key: SettingsKeys.traktLastSyncDate)
        #expect(after != nil)
        // Should be a valid ISO 8601 date
        let formatter = ISO8601DateFormatter()
        #expect(formatter.date(from: after!) != nil)
    }
}

// MARK: - SyncResult Tests

@Suite("TraktSyncOrchestrator.SyncResult")
struct SyncResultTests {

    @Test("summary describes up to date when no changes and no errors")
    func summaryUpToDate() {
        let result = TraktSyncOrchestrator.SyncResult()
        #expect(result.summary == "Everything is up to date.")
    }

    @Test("summary lists pulled and pushed counts")
    func summaryListsCounts() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.watchlistPulled = 3
        result.ratingsPushed = 2
        #expect(result.summary.contains("3 watchlist pulled"))
        #expect(result.summary.contains("2 ratings pushed"))
    }

    @Test("summary includes error count")
    func summaryIncludesErrors() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.errors = ["error1", "error2"]
        #expect(result.summary.contains("2 error(s)"))
    }

    @Test("totalPulled aggregates all pull counts")
    func totalPulledAggregates() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.watchlistPulled = 1
        result.ratingsPulled = 2
        result.historyPulled = 3
        #expect(result.totalPulled == 6)
    }

    @Test("totalPushed aggregates all push counts")
    func totalPushedAggregates() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.watchlistPushed = 4
        result.ratingsPushed = 5
        result.historyPushed = 3
        #expect(result.totalPushed == 12)
    }

    @Test("hasErrors is false when errors array is empty")
    func hasErrorsFalseWhenEmpty() {
        let result = TraktSyncOrchestrator.SyncResult()
        #expect(!result.hasErrors)
    }

    @Test("hasErrors is true when errors array is non-empty")
    func hasErrorsTrueWhenNonEmpty() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.errors = ["something failed"]
        #expect(result.hasErrors)
    }

    @Test("summary includes history pushed count")
    func summaryIncludesHistoryPushed() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.historyPushed = 5
        #expect(result.summary.contains("5 history pushed"))
    }
}

// MARK: - History Pull -> WatchHistory Tests

@Suite("TraktSyncOrchestrator - History Pull WatchHistory", .serialized)
struct TraktSyncOrchestratorHistoryPullWatchHistoryTests {

    @Test("pull history creates WatchHistory records with correct fields")
    func pullHistoryCreatesWatchHistoryRecords() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":1001,"watched_at":"2025-06-15T20:30:00.000Z","action":"watch","movie":{"title":"Arrival","year":2016,"ids":{"trakt":50,"imdb":"tt2543164"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 1)

        let record = try await database.fetchWatchHistory(mediaId: "tt2543164")
        #expect(record != nil)
        #expect(record?.title == "Arrival")
        #expect(record?.isCompleted == true)
        #expect(record?.progress == 0)
        #expect(record?.duration == 0)
        #expect(record?.quality == nil)
        #expect(record?.debridService == nil)
        #expect(record?.streamURL == nil)
    }

    @Test("pull history skips items already in WatchHistory")
    func pullHistorySkipsExistingWatchHistory() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Pre-populate WatchHistory
        let existingHistory = WatchHistory(
            id: UUID().uuidString,
            mediaId: "tt2543164",
            title: "Arrival",
            progress: 7200,
            duration: 7200,
            watchedAt: Date(),
            isCompleted: true
        )
        try await database.saveWatchHistory(existingHistory)

        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":1001,"watched_at":"2025-06-15","action":"watch","movie":{"title":"Arrival","year":2016,"ids":{"trakt":50,"imdb":"tt2543164"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 0)
    }

    @Test("pull history handles shows as well as movies")
    func pullHistoryHandlesShows() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            historyShows: """
            [{"id":2001,"watched_at":"2025-03-10T14:00:00.000Z","action":"watch","show":{"title":"Breaking Bad","year":2008,"ids":{"trakt":10,"imdb":"tt0903747"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 1)
        let record = try await database.fetchWatchHistory(mediaId: "tt0903747")
        #expect(record?.title == "Breaking Bad")
        #expect(record?.isCompleted == true)
    }

    @Test("pull history items without IMDb or TMDB IDs are skipped")
    func pullHistorySkipsItemsWithoutIds() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Item with no imdb and no tmdb
        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":3001,"watched_at":"2025-08-01","action":"watch","movie":{"title":"NoIds","year":2025,"ids":{"trakt":999}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 0)
        let all = try await database.fetchWatchHistory(limit: 100)
        #expect(all.isEmpty)
    }

    @Test("pull history uses tmdb fallback ID when IMDb missing")
    func pullHistoryUsesTmdbFallback() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":4001,"watched_at":"2025-08-01","action":"watch","movie":{"title":"TmdbOnly","year":2025,"ids":{"trakt":1,"tmdb":77777}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 1)
        let record = try await database.fetchWatchHistory(mediaId: "tmdb-77777")
        #expect(record != nil)
        #expect(record?.title == "TmdbOnly")
    }
}

// MARK: - History Push Tests

@Suite("TraktSyncOrchestrator - History Push", .serialized)
struct TraktSyncOrchestratorHistoryPushTests {

    @Test("push sends completed local watch history to Trakt")
    func pushHistorySendsCompletedEntries() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Add completed local watch history with IMDb ID
        let history = WatchHistory(
            id: UUID().uuidString,
            mediaId: "tt1234567",
            title: "Test Movie",
            progress: 7200,
            duration: 7200,
            watchedAt: Date(),
            isCompleted: true
        )
        try await database.saveWatchHistory(history)

        final class PostState: @unchecked Sendable {
            var capturedPaths: [String] = []
            let lock = NSLock()
            func record(_ path: String) { lock.lock(); capturedPaths.append(path); lock.unlock() }
            var paths: [String] { lock.lock(); defer { lock.unlock() }; return capturedPaths }
        }
        let postState = PostState()

        let session = makeOrchestratorStubSession(
            postResponder: { request in
                let path = request.url?.path ?? ""
                postState.record(path)
                return (200, #"{"added":{"movies":1,"shows":0,"episodes":0}}"#)
            }
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPushed == 1)
        #expect(postState.paths.contains { $0.hasSuffix("/sync/history") })
    }

    @Test("push skips non-completed watch history entries")
    func pushHistorySkipsIncomplete() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Add incomplete local watch history (isCompleted = false)
        let history = WatchHistory(
            id: UUID().uuidString,
            mediaId: "tt1234567",
            title: "Test Movie",
            progress: 1800,
            duration: 7200,
            watchedAt: Date(),
            isCompleted: false
        )
        try await database.saveWatchHistory(history)

        let session = makeOrchestratorStubSession()
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        // fetchCompletedWatchHistory only returns completed entries
        #expect(result.historyPushed == 0)
    }

    @Test("push skips entries without IMDb IDs")
    func pushHistorySkipsNonImdbIds() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Add completed entry with tmdb-style ID (no IMDb prefix)
        let history = WatchHistory(
            id: UUID().uuidString,
            mediaId: "tmdb-99999",
            title: "TMDB Movie",
            progress: 7200,
            duration: 7200,
            watchedAt: Date(),
            isCompleted: true
        )
        try await database.saveWatchHistory(history)

        let session = makeOrchestratorStubSession()
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPushed == 0)
    }

    @Test("push deduplicates against remote Trakt history")
    func pushHistoryDeduplicatesAgainstRemote() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Add completed local history that already exists on Trakt
        let history = WatchHistory(
            id: UUID().uuidString,
            mediaId: "tt1234567",
            title: "Already On Trakt",
            progress: 7200,
            duration: 7200,
            watchedAt: Date(),
            isCompleted: true
        )
        try await database.saveWatchHistory(history)

        // Remote history already has this item
        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":5001,"watched_at":"2025-08-01","action":"watch","movie":{"title":"Already On Trakt","year":2025,"ids":{"trakt":1,"imdb":"tt1234567"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        // Pull should be 0 (already exists locally), push should be 0 (already on remote)
        #expect(result.historyPushed == 0)
    }

    @Test("push sends multiple completed entries")
    func pushHistorySendsMultipleEntries() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Add two completed local entries
        for imdb in ["tt1111111", "tt2222222"] {
            let history = WatchHistory(
                id: UUID().uuidString,
                mediaId: imdb,
                title: "Movie \(imdb)",
                progress: 7200,
                duration: 7200,
                watchedAt: Date(),
                isCompleted: true
            )
            try await database.saveWatchHistory(history)
        }

        let session = makeOrchestratorStubSession(
            postResponder: { _ in
                (200, #"{"added":{"movies":1,"shows":0,"episodes":0}}"#)
            }
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPushed == 2)
    }
}

// MARK: - History Pagination Tests

@Suite("TraktSyncOrchestrator - History Pagination", .serialized)
struct TraktSyncOrchestratorHistoryPaginationTests {

    /// Generates a JSON array of N Trakt history movie items with sequential IMDb IDs.
    private func generateHistoryMovieItems(count: Int, startIndex: Int = 0) -> String {
        let items = (0..<count).map { i in
            let index = startIndex + i
            let imdb = String(format: "tt%07d", index)
            return """
            {"id":\(index),"watched_at":"2025-08-01","action":"watch","movie":{"title":"Movie \(index)","year":2025,"ids":{"trakt":\(index),"imdb":"\(imdb)"}}}
            """
        }
        return "[\(items.joined(separator: ","))]"
    }

    @Test("pagination fetches multiple pages when first page is full")
    func paginationFetchesMultiplePages() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Page 1: 50 items (full page), Page 2: 10 items (partial, stops paging)
        let page1 = generateHistoryMovieItems(count: 50, startIndex: 0)
        let page2 = generateHistoryMovieItems(count: 10, startIndex: 50)

        final class PageTracker: @unchecked Sendable {
            var requestedPages: [Int] = []
            let lock = NSLock()
            func record(_ page: Int) { lock.lock(); requestedPages.append(page); lock.unlock() }
            var pages: [Int] { lock.lock(); defer { lock.unlock() }; return requestedPages }
        }
        let pageTracker = PageTracker()

        let session = makeStubSession { request in
            let url = request.url!
            let path = url.path
            let query = url.query ?? ""

            if request.httpMethod == "POST" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"added":{"movies":1,"shows":0,"episodes":0}}"#.utf8))
            }

            if path.contains("/sync/history/movies") {
                // Extract page number
                let pageParam = query.components(separatedBy: "&")
                    .first(where: { $0.hasPrefix("page=") })
                    .flatMap { $0.components(separatedBy: "=").last }
                    .flatMap { Int($0) } ?? 1
                pageTracker.record(pageParam)

                let body: String
                if pageParam == 1 { body = page1 }
                else if pageParam == 2 { body = page2 }
                else { body = "[]" }

                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        // Should have pulled 60 total items (50 from page 1 + 10 from page 2)
        #expect(result.historyPulled == 60)

        // Verify both pages were requested
        let moviePages = pageTracker.pages.sorted()
        #expect(moviePages.contains(1))
        #expect(moviePages.contains(2))

        // Verify WatchHistory records exist
        let allHistory = try await database.fetchWatchHistory(limit: 100)
        #expect(allHistory.count == 60)
    }

    @Test("pagination stops when page has fewer than 50 items")
    func paginationStopsOnPartialPage() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Only 10 items on page 1 — should NOT request page 2
        let page1 = generateHistoryMovieItems(count: 10, startIndex: 0)

        final class PageTracker: @unchecked Sendable {
            var requestedPages: [Int] = []
            let lock = NSLock()
            func record(_ page: Int) { lock.lock(); requestedPages.append(page); lock.unlock() }
            var pages: [Int] { lock.lock(); defer { lock.unlock() }; return requestedPages }
        }
        let pageTracker = PageTracker()

        let session = makeStubSession { request in
            let url = request.url!
            let path = url.path
            let query = url.query ?? ""

            if request.httpMethod == "POST" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"added":{"movies":1,"shows":0,"episodes":0}}"#.utf8))
            }

            if path.contains("/sync/history/movies") {
                let pageParam = query.components(separatedBy: "&")
                    .first(where: { $0.hasPrefix("page=") })
                    .flatMap { $0.components(separatedBy: "=").last }
                    .flatMap { Int($0) } ?? 1
                pageTracker.record(pageParam)

                let body = pageParam == 1 ? page1 : "[]"
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 10)
        // Should only have requested page 1 for movies (push dedup also requests page 1,
        // so we check that page 2 was never requested rather than counting exact requests)
        let moviePages = Set(pageTracker.pages)
        #expect(moviePages.contains(1))
        #expect(!moviePages.contains(2))
    }

    @Test("pagination respects max page limit")
    func paginationRespectsMaxPageLimit() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        final class PageTracker: @unchecked Sendable {
            var maxPageRequested = 0
            let lock = NSLock()
            func record(_ page: Int) { lock.lock(); maxPageRequested = max(maxPageRequested, page); lock.unlock() }
            var maxPage: Int { lock.lock(); defer { lock.unlock() }; return maxPageRequested }
        }
        let pageTracker = PageTracker()

        // Always return 50 items (simulating an infinitely large history)
        let session = makeStubSession { request in
            let url = request.url!
            let path = url.path
            let query = url.query ?? ""

            if request.httpMethod == "POST" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"added":{"movies":1,"shows":0,"episodes":0}}"#.utf8))
            }

            if path.contains("/sync/history/movies") {
                let pageParam = query.components(separatedBy: "&")
                    .first(where: { $0.hasPrefix("page=") })
                    .flatMap { $0.components(separatedBy: "=").last }
                    .flatMap { Int($0) } ?? 1
                pageTracker.record(pageParam)

                // Generate unique items per page so they don't get deduplicated
                let startIndex = (pageParam - 1) * 50
                let items = (0..<50).map { i in
                    let index = startIndex + i
                    let imdb = String(format: "tt%07d", index)
                    return """
                    {"id":\(index),"watched_at":"2025-08-01","action":"watch","movie":{"title":"Movie \(index)","year":2025,"ids":{"trakt":\(index),"imdb":"\(imdb)"}}}
                    """
                }
                let body = "[\(items.joined(separator: ","))]"
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        // Should stop at maxHistoryPages (20) even though each page returns 50 items
        #expect(pageTracker.maxPage <= TraktSyncOrchestrator.maxHistoryPages)
        // 20 pages * 50 items = 1000 items max for movies
        #expect(result.historyPulled == TraktSyncOrchestrator.maxHistoryPages * 50)
    }
}

// MARK: - Bi-directional History Sync Integration Tests

@Suite("TraktSyncOrchestrator - Bi-directional History", .serialized)
struct TraktSyncOrchestratorBidirectionalHistoryTests {

    @Test("full sync pulls remote history AND pushes local history")
    func fullSyncPullsAndPushes() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: true)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Local: completed watch of tt1111111 (not on remote)
        let localHistory = WatchHistory(
            id: UUID().uuidString,
            mediaId: "tt1111111",
            title: "Local Only Movie",
            progress: 7200,
            duration: 7200,
            watchedAt: Date(),
            isCompleted: true
        )
        try await database.saveWatchHistory(localHistory)

        // Remote: tt2222222 (not in local)
        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":6001,"watched_at":"2025-03-01T10:00:00.000Z","action":"watch","movie":{"title":"Remote Only Movie","year":2025,"ids":{"trakt":1,"imdb":"tt2222222"}}}]
            """,
            postResponder: { _ in
                (200, #"{"added":{"movies":1,"shows":0,"episodes":0}}"#)
            }
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        // Should pull the remote item
        #expect(result.historyPulled == 1)
        let remoteRecord = try await database.fetchWatchHistory(mediaId: "tt2222222")
        #expect(remoteRecord != nil)
        #expect(remoteRecord?.title == "Remote Only Movie")

        // Should push the local item
        #expect(result.historyPushed == 1)
    }

    @Test("sync with history toggle disabled skips both pull and push")
    func syncWithHistoryDisabledSkipsBoth() async throws {
        let database = try await makeTempDatabase()
        let settings = makeSettingsManager(database: database)
        try await settings.setBool(key: SettingsKeys.traktSyncWatchlist, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncHistory, value: false)
        try await settings.setBool(key: SettingsKeys.traktSyncRatings, value: false)

        // Local completed watch
        let history = WatchHistory(
            id: UUID().uuidString,
            mediaId: "tt9999999",
            title: "Should Not Push",
            progress: 7200,
            duration: 7200,
            watchedAt: Date(),
            isCompleted: true
        )
        try await database.saveWatchHistory(history)

        let session = makeOrchestratorStubSession(
            historyMovies: """
            [{"id":7001,"watched_at":"2025-08-01","action":"watch","movie":{"title":"Should Not Pull","year":2025,"ids":{"trakt":1,"imdb":"tt8888888"}}}]
            """
        )
        let (orchestrator, service) = makeOrchestrator(database: database, settingsManager: settings, session: session)
        await service.setTokens(access: "token", refresh: "refresh")

        let result = await orchestrator.sync()

        #expect(result.historyPulled == 0)
        #expect(result.historyPushed == 0)
    }
}
