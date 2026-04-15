import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct IndexerSettingsTests {
    private actor InMemorySecretStore: SecretStore {
        private var secrets: [String: String] = [:]

        func setSecret(_ secret: String, for key: String) async throws {
            secrets[key] = secret
        }

        func getSecret(for key: String) async throws -> String? {
            secrets[key]
        }

        func deleteSecret(for key: String) async throws {
            secrets[key] = nil
        }

        func deleteAllSecrets() async throws {
            secrets.removeAll()
        }
    }

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

    @Test func plaintextApiKeyMigratesToKeychainReferenceAndResolvesForRuntimeUse() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-settings-secret-migration.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let secretStore = InMemorySecretStore()
        let config = makeTorznab(id: "secret-migrate", name: "Secret", priority: 0, isActive: true)
        var plaintext = config
        plaintext.apiKey = "  super-secret-key  "

        try await database.saveIndexerConfig(plaintext)

        let manager = IndexerManager(database: database, secretStore: secretStore)
        try await manager.initialize()

        let stored = try await database.fetchAllIndexerConfigs()
        #expect(stored.first?.apiKey?.hasPrefix("keychain:") == true)

        let expectedKey = IndexerConfig.secretKey(for: config.id)
        let storedSecret = try await secretStore.getSecret(for: expectedKey)
        #expect(storedSecret == "super-secret-key")

        let storedConfig = try #require(stored.first)
        let runtimeKey = try await storedConfig.resolvedAPIKey(using: secretStore)
        #expect(runtimeKey == "super-secret-key")
    }

    @Test func persistedCopyClearsOrPersistsSecretBackedKeys() async throws {
        let secretStore = InMemorySecretStore()
        var config = makeTorznab(id: "persist-copy", name: "Persist", priority: 0, isActive: true)
        config.apiKey = "secret-value"

        let persisted = try await config.persistedCopy(using: secretStore)
        #expect(persisted.changed)
        #expect(persisted.config.apiKey?.hasPrefix("keychain:") == true)
        let persistedSecret = try await secretStore.getSecret(for: IndexerConfig.secretKey(for: config.id))
        #expect(persistedSecret == "secret-value")

        let resolved = try await persisted.config.resolvedCopy(using: secretStore)
        #expect(resolved.apiKey == "secret-value")
    }

    @Test func deleteStoredSecretRemovesSecretFromStore() async throws {
        let secretStore = InMemorySecretStore()
        let config = makeTorznab(id: "delete-secret", name: "Delete", priority: 0, isActive: true)
        let key = IndexerConfig.secretKey(for: config.id)
        try await secretStore.setSecret("secret-value", for: key)

        try await config.deleteStoredSecret(using: secretStore)

        let remaining = try await secretStore.getSecret(for: key)
        #expect(remaining == nil)
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
