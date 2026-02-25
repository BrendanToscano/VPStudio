import Foundation
import Testing
@testable import VPStudio

@Suite("Indexer Manager Fallback", .serialized)
struct IndexerManagerFallbackTests {
    @Test func builtInsLoadWhenNoConfigsExist() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-fallback-none.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = IndexerManager(database: database)
        try await manager.initialize()
        let names = await manager.configuredIndexerNames()

        // Only the 3 active-by-default indexers should be loaded
        #expect(names == ["Stremio Torrentio", "YTS", "APiBay"])
    }

    @Test func legacyBuiltInSubsetDoesNotAutoAddMissingDefaults() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-fallback-legacy-subset.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        try await database.saveIndexerConfig(
            IndexerConfig(
                id: "legacy-apibay",
                name: "APiBay",
                indexerType: .apiBay,
                baseURL: nil,
                apiKey: nil,
                isActive: true,
                priority: 0
            )
        )

        let manager = IndexerManager(database: database)
        try await manager.initialize()
        let names = await manager.configuredIndexerNames()

        // With the new behavior, only the existing config is used — no auto-add of missing built-ins
        #expect(names == ["APiBay"])

        let stored = try await database.fetchAllIndexerConfigs()
        #expect(stored.count == 1)
        #expect(stored.first?.id == "legacy-apibay")
    }

    @Test func initializeCanonicalizesLegacyBuiltInDefinitionsEvenWithCustomConfigs() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-fallback-canonicalize.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        try await database.saveIndexerConfigs([
            IndexerConfig(
                id: "builtin-eztv",
                name: "EZTV",
                indexerType: .torznab,
                baseURL: "https://eztv.re",
                apiKey: nil,
                isActive: true,
                priority: 0,
                providerSubtype: .customTorznab,
                endpointPath: "/api",
                categoryFilter: nil,
                apiKeyTransport: .query
            ),
            IndexerConfig(
                id: "custom-jackett",
                name: "Jackett",
                indexerType: .jackett,
                baseURL: "https://jackett.example",
                apiKey: "key",
                isActive: true,
                priority: 1
            ),
        ])

        let manager = IndexerManager(database: database)
        try await manager.initialize()

        let stored = try await database.fetchAllIndexerConfigs()
        let rewritten = stored.first(where: { $0.id == "builtin-eztv" })
        let custom = stored.first(where: { $0.id == "custom-jackett" })

        #expect(rewritten?.indexerType == .eztv)
        #expect(rewritten?.baseURL == nil)
        #expect(rewritten?.endpointPath == "")
        #expect(rewritten?.providerSubtype == .builtIn)
        #expect(custom?.indexerType == .jackett)
        #expect(custom?.baseURL == "https://jackett.example")
    }

    @Test func disabledAllConfigsDoNotAutoEnableBuiltIns() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-fallback-disabled.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        try await database.saveIndexerConfig(
            IndexerConfig(
                id: "jackett-disabled",
                name: "Jackett Disabled",
                indexerType: .jackett,
                baseURL: "https://jackett.example.com",
                apiKey: "key",
                isActive: false,
                priority: 0
            )
        )

        let manager = IndexerManager(database: database)
        try await manager.initialize()
        let names = await manager.configuredIndexerNames()

        #expect(names.isEmpty)
    }

    private func makeDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, rootDir)
    }
}
