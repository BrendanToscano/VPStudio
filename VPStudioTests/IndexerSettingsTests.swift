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

    @Test func draftDefaultsNormalizeCustomIndexerFields() {
        var draft = IndexerSettingsView.IndexerDraft.new()

        #expect(draft.editingID == nil)
        #expect(draft.indexerType == .jackett)
        #expect(draft.isActive)
        #expect(draft.showsAPIKeyField)
        #expect(draft.showsAPIKeyTransportField)
        #expect(draft.showsEndpointPathField)
        #expect(draft.showsCategoryField)
        #expect(draft.providerSubtype == .jackett)
        #expect(draft.normalizedURL == nil)
        #expect(draft.normalizedAPIKey == nil)
        #expect(draft.normalizedEndpointPath == "/api/v2.0/indexers/all/results/torznab/api")
        #expect(draft.normalizedCategoryFilter == nil)
        #expect(draft.validationError == "Indexer name is required.")

        draft.name = "  Jackett  "
        draft.baseURL = "  https://jackett.example  "
        draft.apiKey = "  token  "
        draft.endpointPath = "api/custom"
        draft.categoryFilter = "  2000,5000  "

        #expect(draft.normalizedURL == "https://jackett.example")
        #expect(draft.normalizedAPIKey == "token")
        #expect(draft.normalizedEndpointPath == "/api/custom")
        #expect(draft.normalizedCategoryFilter == "2000,5000")
        #expect(draft.validationError == nil)
    }

    @Test func draftValidationCoversUrlApiKeyAndStremioManifestRules() {
        var draft = IndexerSettingsView.IndexerDraft.new()
        draft.name = "Custom"
        draft.baseURL = "http://insecure.example"
        draft.apiKey = "token"
        #expect(draft.validationError == "Enter a valid HTTPS base URL.")

        draft.baseURL = "https://secure.example"
        draft.apiKey = "   "
        #expect(draft.validationError == "API key is required for Jackett.")

        draft.indexerType = .stremio
        draft.applyDefaults(for: .stremio)
        draft.apiKey = ""
        draft.baseURL = "https://stremio.example"
        #expect(draft.showsAPIKeyField == false)
        #expect(draft.showsAPIKeyTransportField == false)
        #expect(draft.showsCategoryField == false)
        #expect(draft.providerSubtype == .stremioAddon)
        #expect(draft.normalizedEndpointPath == "/manifest.json")
        #expect(draft.validationError == nil)

        draft.endpointPath = "/catalog/movie/top.json"
        #expect(draft.validationError == "Stremio endpoint should usually point to /manifest.json.")
    }

    @Test func draftProviderMatrixAppliesDefaultsAndFieldVisibility() {
        var draft = IndexerSettingsView.IndexerDraft.new()

        let cases: [(IndexerConfig.IndexerType, String, IndexerConfig.APIKeyTransport, Bool, Bool, IndexerConfig.ProviderSubtype)] = [
            (.jackett, "/api/v2.0/indexers/all/results/torznab/api", .header, true, true, .jackett),
            (.prowlarr, "/api/v1/search", .header, true, false, .prowlarr),
            (.torznab, "/api", .header, true, true, .customTorznab),
            (.zilean, "/api", .query, false, false, .customTorznab),
            (.stremio, "/manifest.json", .query, false, false, .stremioAddon),
            (.apiBay, "", .query, false, false, .builtIn),
            (.yts, "", .query, false, false, .builtIn),
            (.eztv, "", .query, false, false, .builtIn),
        ]

        for (type, endpointPath, transport, showsKey, showsCategory, subtype) in cases {
            draft.indexerType = type
            draft.categoryFilter = "2000"
            draft.applyDefaults(for: type)

            #expect(draft.normalizedEndpointPath == endpointPath)
            #expect(draft.apiKeyTransport == transport)
            #expect(draft.showsAPIKeyField == showsKey)
            #expect(draft.showsAPIKeyTransportField == showsKey)
            #expect(draft.showsCategoryField == showsCategory)
            #expect(draft.providerSubtype == subtype)
            #expect(showsCategory ? draft.categoryFilter == "2000" : draft.categoryFilter.isEmpty)
        }
    }

    @Test func draftFromExistingConfigPreservesEditableFields() {
        var config = makeTorznab(id: "edit-me", name: "Editable", priority: 3, isActive: false)
        config.baseURL = "https://torznab.example"
        config.apiKey = "secret"
        config.endpointPath = "/torznab/api"
        config.categoryFilter = "5000"
        config.apiKeyTransport = .query

        let draft = IndexerSettingsView.IndexerDraft.from(config)

        #expect(draft.editingID == "edit-me")
        #expect(draft.name == "Editable")
        #expect(draft.indexerType == .torznab)
        #expect(draft.baseURL == "https://torznab.example")
        #expect(draft.apiKey == "secret")
        #expect(draft.isActive == false)
        #expect(draft.endpointPath == "/torznab/api")
        #expect(draft.categoryFilter == "5000")
        #expect(draft.apiKeyTransport == .query)
        #expect(draft.validationError == nil)
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
