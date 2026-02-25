import Foundation
import Testing
@testable import VPStudio

// MARK: - URL Protocol Stub (same pattern as TraktSyncOrchestratorTests)

private enum FolderSyncStubError: Error {
    case missingHandler
}

private final class FolderSyncURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    static let lock = NSLock()
    static let handlerHeader = "X-VPStudio-FolderSync-Stub"

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
            client?.urlProtocol(self, didFailWithError: FolderSyncStubError.missingHandler)
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

// MARK: - Helpers

private func makeStubSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    let handlerID = FolderSyncURLProtocolStub.register(handler)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FolderSyncURLProtocolStub.self]
    config.httpAdditionalHeaders = [FolderSyncURLProtocolStub.handlerHeader: handlerID]
    return URLSession(configuration: config)
}

private func makeTempDatabase() async throws -> DatabaseManager {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbPath = tempDir.appendingPathComponent("folder-sync-test.sqlite").path
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

/// Builds a stub session that handles custom list + standard sync endpoints.
private func makeFolderSyncStubSession(
    customLists: String = "[]",
    listItems: [Int: String] = [:],
    createListResponse: String? = nil,
    watchlistMovies: String = "[]",
    watchlistShows: String = "[]"
) -> URLSession {
    makeStubSession { request in
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let url = request.url!

        // POST endpoints
        if method == "POST" {
            // Create custom list
            if path.hasSuffix("/users/me/lists") && !path.contains("/items") {
                let body = createListResponse ?? #"{"ids":{"trakt":999,"slug":"new-list"},"name":"New List","privacy":"private"}"#
                let response = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!
                return (response, Data(body.utf8))
            }
            // Add items to list
            if path.contains("/users/me/lists/") && path.hasSuffix("/items") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = #"{"added":{"movies":1,"shows":0,"episodes":0}}"#
                return (response, Data(body.utf8))
            }
            // Default POST (sync endpoints)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"added":{"movies":0,"shows":0,"episodes":0}}"#
            return (response, Data(body.utf8))
        }

        // DELETE
        if method == "DELETE" {
            let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        // GET responses
        let body: String
        if path.hasSuffix("/users/me/lists") {
            body = customLists
        } else if path.contains("/users/me/lists/") && path.hasSuffix("/items") {
            // Extract list ID from path: /users/me/lists/{id}/items
            let components = path.split(separator: "/")
            if let listIdIndex = components.firstIndex(of: "lists"),
               listIdIndex + 1 < components.count,
               let listId = Int(components[listIdIndex + 1]) {
                body = listItems[listId] ?? "[]"
            } else {
                body = "[]"
            }
        } else if path.hasSuffix("/sync/watchlist/movies") {
            body = watchlistMovies
        } else if path.hasSuffix("/sync/watchlist/shows") {
            body = watchlistShows
        } else {
            body = "[]"
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }
}

// MARK: - TraktListMapping Model Tests

@Suite("TraktListMapping Model")
struct TraktListMappingModelTests {

    @Test func initWithDefaults() {
        let mapping = TraktListMapping(traktListId: 42, localFolderId: "folder-1")
        #expect(mapping.traktListId == 42)
        #expect(mapping.localFolderId == "folder-1")
        #expect(mapping.listType == .watchlist)
        #expect(!mapping.id.isEmpty)
    }

    @Test func initWithAllParams() {
        let date = Date(timeIntervalSince1970: 1000)
        let mapping = TraktListMapping(
            id: "m1",
            traktListId: 100,
            traktListSlug: "my-list",
            localFolderId: "f1",
            listType: .favorites,
            lastSyncedAt: date
        )
        #expect(mapping.id == "m1")
        #expect(mapping.traktListId == 100)
        #expect(mapping.traktListSlug == "my-list")
        #expect(mapping.localFolderId == "f1")
        #expect(mapping.listType == .favorites)
        #expect(mapping.lastSyncedAt == date)
    }

    @Test func equatableConformance() {
        let a = TraktListMapping(id: "x", traktListId: 1, localFolderId: "f1")
        let b = TraktListMapping(id: "x", traktListId: 1, localFolderId: "f1")
        #expect(a == b)
    }

    @Test func sendableConformance() async {
        let mapping = TraktListMapping(traktListId: 5, localFolderId: "f2")
        let result = await Task.detached { mapping }.value
        #expect(result.traktListId == 5)
    }
}

// MARK: - Database CRUD Tests

@Suite("TraktListMapping DB Operations", .serialized)
struct TraktListMappingDBTests {

    @Test func saveAndFetchByTraktId() async throws {
        let db = try await makeTempDatabase()
        let mapping = TraktListMapping(traktListId: 42, traktListSlug: "horror", localFolderId: "f1")
        try await db.saveTraktListMapping(mapping)

        let fetched = try await db.fetchTraktListMapping(traktListId: 42)
        #expect(fetched != nil)
        #expect(fetched?.localFolderId == "f1")
        #expect(fetched?.traktListSlug == "horror")
    }

    @Test func fetchByLocalFolderId() async throws {
        let db = try await makeTempDatabase()
        let mapping = TraktListMapping(traktListId: 10, localFolderId: "folder-abc")
        try await db.saveTraktListMapping(mapping)

        let fetched = try await db.fetchTraktListMapping(localFolderId: "folder-abc")
        #expect(fetched != nil)
        #expect(fetched?.traktListId == 10)
    }

    @Test func fetchAllMappings() async throws {
        let db = try await makeTempDatabase()
        try await db.saveTraktListMapping(TraktListMapping(traktListId: 1, localFolderId: "f1"))
        try await db.saveTraktListMapping(TraktListMapping(traktListId: 2, localFolderId: "f2"))
        try await db.saveTraktListMapping(TraktListMapping(traktListId: 3, localFolderId: "f3"))

        let all = try await db.fetchAllTraktListMappings()
        #expect(all.count == 3)
    }

    @Test func deleteByTraktId() async throws {
        let db = try await makeTempDatabase()
        try await db.saveTraktListMapping(TraktListMapping(traktListId: 50, localFolderId: "f1"))

        try await db.deleteTraktListMapping(traktListId: 50)
        let fetched = try await db.fetchTraktListMapping(traktListId: 50)
        #expect(fetched == nil)
    }

    @Test func deleteById() async throws {
        let db = try await makeTempDatabase()
        let mapping = TraktListMapping(id: "del-me", traktListId: 60, localFolderId: "f2")
        try await db.saveTraktListMapping(mapping)

        try await db.deleteTraktListMapping(id: "del-me")
        let fetched = try await db.fetchTraktListMapping(traktListId: 60)
        #expect(fetched == nil)
    }

    @Test func upsertOverwritesExisting() async throws {
        let db = try await makeTempDatabase()
        let original = TraktListMapping(id: "m1", traktListId: 10, localFolderId: "f1")
        try await db.saveTraktListMapping(original)

        let updated = TraktListMapping(id: "m1", traktListId: 10, localFolderId: "f2-updated")
        try await db.saveTraktListMapping(updated)

        let fetched = try await db.fetchTraktListMapping(traktListId: 10)
        #expect(fetched?.localFolderId == "f2-updated")
    }

    @Test func fetchNonexistentReturnsNil() async throws {
        let db = try await makeTempDatabase()
        let fetched = try await db.fetchTraktListMapping(traktListId: 9999)
        #expect(fetched == nil)
    }
}

// MARK: - SyncResult Folder Fields Tests

@Suite("SyncResult Folder Fields")
struct SyncResultFolderFieldsTests {

    @Test func defaultsToZero() {
        let result = TraktSyncOrchestrator.SyncResult()
        #expect(result.foldersPulled == 0)
        #expect(result.foldersPushed == 0)
    }

    @Test func foldersIncludedInTotalPulled() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.watchlistPulled = 2
        result.foldersPulled = 5
        #expect(result.totalPulled == 7)
    }

    @Test func foldersIncludedInTotalPushed() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.watchlistPushed = 1
        result.foldersPushed = 3
        #expect(result.totalPushed == 4)
    }

    @Test func summaryIncludesFoldersPulled() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.foldersPulled = 4
        #expect(result.summary.contains("4 folder items pulled"))
    }

    @Test func summaryIncludesFoldersPushed() {
        var result = TraktSyncOrchestrator.SyncResult()
        result.foldersPushed = 2
        #expect(result.summary.contains("2 folder items pushed"))
    }
}

// MARK: - Orchestrator Folder Sync Integration Tests

@Suite("TraktSyncOrchestrator - Folder Sync", .serialized)
struct TraktFolderSyncIntegrationTests {

    @Test("pull creates local folder from Trakt custom list")
    func pullCreatesLocalFolder() async throws {
        let db = try await makeTempDatabase()
        let settings = makeSettingsManager(database: db)

        // Enable folder sync
        try await settings.setBool(key: SettingsKeys.traktSyncFolders, value: true)

        let customListsJSON = """
        [{"ids":{"trakt":42,"slug":"horror-picks"},"name":"Horror Picks","privacy":"private","item_count":1}]
        """
        let listItemsJSON = """
        [{"rank":1,"type":"movie","movie":{"title":"Hereditary","year":2018,"ids":{"trakt":1,"imdb":"tt7784604","tmdb":493922}}}]
        """

        let session = makeFolderSyncStubSession(
            customLists: customListsJSON,
            listItems: [42: listItemsJSON]
        )
        let (orchestrator, service) = makeOrchestrator(database: db, settingsManager: settings, session: session)
        await service.setTokens(access: "test-token", refresh: nil)

        let result = await orchestrator.sync()
        #expect(result.foldersPulled == 1)

        // Verify folder was created
        let folders = try await db.fetchAllLibraryFolders(listType: .watchlist)
        let horrorFolder = folders.first(where: { $0.name == "Horror Picks" })
        #expect(horrorFolder != nil)

        // Verify mapping was created
        let mapping = try await db.fetchTraktListMapping(traktListId: 42)
        #expect(mapping != nil)
        #expect(mapping?.localFolderId == horrorFolder?.id)
    }

    @Test("push creates Trakt list from local folder")
    func pushCreatesRemoteList() async throws {
        let db = try await makeTempDatabase()
        let settings = makeSettingsManager(database: db)

        try await settings.setBool(key: SettingsKeys.traktSyncFolders, value: true)

        // Create a local folder with an item
        let folder = try await db.createLibraryFolder(name: "My Favorites", listType: .watchlist)
        let entry = UserLibraryEntry(
            id: "tt1234567-watchlist",
            mediaId: "tt1234567",
            folderId: folder.id,
            listType: .watchlist,
            addedAt: Date()
        )
        try await db.addToLibrary(entry)

        let createResponse = """
        {"ids":{"trakt":999,"slug":"my-favorites"},"name":"My Favorites","privacy":"private"}
        """

        let session = makeFolderSyncStubSession(createListResponse: createResponse)
        let (orchestrator, service) = makeOrchestrator(database: db, settingsManager: settings, session: session)
        await service.setTokens(access: "test-token", refresh: nil)

        let result = await orchestrator.sync()
        #expect(result.foldersPushed == 1)

        // Verify mapping was created
        let mapping = try await db.fetchTraktListMapping(traktListId: 999)
        #expect(mapping != nil)
        #expect(mapping?.localFolderId == folder.id)
    }

    @Test("folder sync disabled by default")
    func folderSyncDisabledByDefault() async throws {
        let db = try await makeTempDatabase()
        let settings = makeSettingsManager(database: db)
        // Don't enable folder sync — it defaults to false

        // Create a local folder that would otherwise get pushed
        _ = try await db.createLibraryFolder(name: "Should Not Sync", listType: .watchlist)

        let session = makeFolderSyncStubSession()
        let (orchestrator, service) = makeOrchestrator(database: db, settingsManager: settings, session: session)
        await service.setTokens(access: "test-token", refresh: nil)

        let result = await orchestrator.sync()
        #expect(result.foldersPulled == 0)
        #expect(result.foldersPushed == 0)

        // No mapping should exist
        let mappings = try await db.fetchAllTraktListMappings()
        #expect(mappings.isEmpty)
    }

    @Test("pull syncs items into existing mapped folder")
    func pullSyncsItemsIntoExistingFolder() async throws {
        let db = try await makeTempDatabase()
        let settings = makeSettingsManager(database: db)
        try await settings.setBool(key: SettingsKeys.traktSyncFolders, value: true)

        // Pre-create folder and mapping
        let folder = try await db.createLibraryFolder(name: "Sci-Fi", listType: .watchlist)
        let mapping = TraktListMapping(traktListId: 55, traktListSlug: "sci-fi", localFolderId: folder.id)
        try await db.saveTraktListMapping(mapping)

        let customListsJSON = """
        [{"ids":{"trakt":55,"slug":"sci-fi"},"name":"Sci-Fi","privacy":"private","item_count":2}]
        """
        let listItemsJSON = """
        [{"rank":1,"type":"movie","movie":{"title":"Arrival","year":2016,"ids":{"trakt":1,"imdb":"tt2543164","tmdb":329865}}},
         {"rank":2,"type":"movie","movie":{"title":"Interstellar","year":2014,"ids":{"trakt":2,"imdb":"tt0816692","tmdb":157336}}}]
        """

        let session = makeFolderSyncStubSession(
            customLists: customListsJSON,
            listItems: [55: listItemsJSON]
        )
        let (orchestrator, service) = makeOrchestrator(database: db, settingsManager: settings, session: session)
        await service.setTokens(access: "test-token", refresh: nil)

        let result = await orchestrator.sync()
        #expect(result.foldersPulled == 2)

        // Verify entries were created in the correct folder
        let entries = try await db.fetchLibraryEntries(listType: .watchlist, folderId: folder.id)
        #expect(entries.count == 2)
        let mediaIds = Set(entries.map(\.mediaId))
        #expect(mediaIds.contains("tt2543164"))
        #expect(mediaIds.contains("tt0816692"))
    }

    @Test("push deduplicates against remote list items")
    func pushDeduplicatesAgainstRemote() async throws {
        let db = try await makeTempDatabase()
        let settings = makeSettingsManager(database: db)
        try await settings.setBool(key: SettingsKeys.traktSyncFolders, value: true)

        // Pre-create folder, mapping, and local entries
        let folder = try await db.createLibraryFolder(name: "Action", listType: .watchlist)
        let mapping = TraktListMapping(traktListId: 77, traktListSlug: "action", localFolderId: folder.id)
        try await db.saveTraktListMapping(mapping)

        // Two local entries
        try await db.addToLibrary(UserLibraryEntry(
            id: "tt1111111-watchlist", mediaId: "tt1111111", folderId: folder.id, listType: .watchlist, addedAt: Date()
        ))
        try await db.addToLibrary(UserLibraryEntry(
            id: "tt2222222-watchlist", mediaId: "tt2222222", folderId: folder.id, listType: .watchlist, addedAt: Date()
        ))

        // Remote list already has tt1111111
        let remoteItems = """
        [{"rank":1,"type":"movie","movie":{"title":"Already There","year":2020,"ids":{"trakt":1,"imdb":"tt1111111","tmdb":100}}}]
        """

        let session = makeFolderSyncStubSession(
            listItems: [77: remoteItems]
        )
        let (orchestrator, service) = makeOrchestrator(database: db, settingsManager: settings, session: session)
        await service.setTokens(access: "test-token", refresh: nil)

        let result = await orchestrator.sync()
        // Only tt2222222 should be pushed (tt1111111 already exists remotely)
        #expect(result.foldersPushed == 1)
    }

    @Test("system folders are not pushed")
    func systemFoldersNotPushed() async throws {
        let db = try await makeTempDatabase()
        let settings = makeSettingsManager(database: db)
        try await settings.setBool(key: SettingsKeys.traktSyncFolders, value: true)

        // System folder items should NOT create Trakt lists
        // (system folders have isSystem=true; only manual folders push)
        let session = makeFolderSyncStubSession()
        let (orchestrator, service) = makeOrchestrator(database: db, settingsManager: settings, session: session)
        await service.setTokens(access: "test-token", refresh: nil)

        let result = await orchestrator.sync()
        #expect(result.foldersPushed == 0)

        let mappings = try await db.fetchAllTraktListMappings()
        #expect(mappings.isEmpty)
    }
}
