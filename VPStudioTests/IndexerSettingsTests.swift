import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct IndexerSettingsTests {
    @Test func addEditDeleteToggleAndPriorityPersistence() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-settings-crud.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        var first = makeTorznab(id: "a", name: "First", priority: 0, isActive: true)
        var second = makeTorznab(id: "b", name: "Second", priority: 1, isActive: true)

        try await database.saveIndexerConfigs([first, second])

        var fetched = try await database.fetchAllIndexerConfigs()
        #expect(fetched.map(\.id) == ["a", "b"])

        first.baseURL = "https://first-updated.example"
        second.isActive = false
        first.priority = 1
        second.priority = 0

        try await database.saveIndexerConfigs([first, second])
        fetched = try await database.fetchAllIndexerConfigs()

        #expect(fetched.map(\.id) == ["b", "a"])
        #expect(fetched.first(where: { $0.id == "b" })?.isActive == false)
        #expect(fetched.first(where: { $0.id == "a" })?.baseURL == "https://first-updated.example")

        try await database.deleteIndexerConfig(id: "b")
        fetched = try await database.fetchAllIndexerConfigs()

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "a")
    }

    @Test func reorderNormalizationPreservesMovedOrderWithStalePriorities() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-settings-move-normalization.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let first = makeTorznab(id: "first", name: "First", priority: 0, isActive: true)
        let second = makeTorznab(id: "second", name: "Second", priority: 1, isActive: true)

        let movedOrder = [second, first]
        let normalized = IndexerSettingsView.normalizePrioritiesPreservingOrder(movedOrder)

        #expect(normalized.map(\.id) == ["second", "first"])
        #expect(normalized.map(\.priority) == [0, 1])

        try await database.saveIndexerConfigs(normalized)
        let fetched = try await database.fetchAllIndexerConfigs()

        #expect(fetched.map(\.id) == ["second", "first"])
    }

    @Test func managerInitializeUsesActiveIndexersInPriorityOrder() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-settings-manager-order.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let inactive = makeTorznab(id: "inactive", name: "Inactive", priority: 0, isActive: false)
        let second = makeTorznab(id: "second", name: "Second", priority: 2, isActive: true)
        let first = makeTorznab(id: "first", name: "First", priority: 1, isActive: true)

        try await database.saveIndexerConfigs([inactive, second, first])

        let manager = IndexerManager(database: database)
        try await manager.initialize()

        let names = await manager.configuredIndexerNames()
        // Only the active custom configs in priority order — no auto-added built-ins.
        #expect(names == ["First", "Second"])
    }

    @Test func managerDoesNotAutoEnableBuiltInsWhenConfigsExistButAllAreDisabled() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-settings-fallback.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let inactive = makeTorznab(id: "inactive", name: "Inactive", priority: 0, isActive: false)
        try await database.saveIndexerConfig(inactive)

        let manager = IndexerManager(database: database)
        try await manager.initialize()

        let names = await manager.configuredIndexerNames()
        #expect(names.isEmpty)
    }

    @Test func managerUsesBuiltInsWhenNoConfigsExist() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-settings-builtins-default.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = IndexerManager(database: database)
        try await manager.initialize()

        let names = await manager.configuredIndexerNames()
        // Only the 3 active-by-default indexers should be loaded
        #expect(names == ["Stremio Torrentio", "YTS", "APiBay"])
    }

    private func makeDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, rootDir)
    }

    private func makeTorznab(id: String, name: String, priority: Int, isActive: Bool) -> IndexerConfig {
        IndexerConfig(
            id: id,
            name: name,
            indexerType: .torznab,
            baseURL: "https://\(name.lowercased()).example",
            apiKey: "api-key",
            isActive: isActive,
            priority: priority
        )
    }
}
