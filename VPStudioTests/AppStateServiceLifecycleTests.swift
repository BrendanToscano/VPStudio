import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct AppStateServiceLifecycleTests {
    private actor ThrowingDeleteAllSecretStore: SecretStore {
        struct Failure: Error {}

        func setSecret(_ value: String, for key: String) async throws {}
        func getSecret(for key: String) async throws -> String? { nil }
        func deleteSecret(for key: String) async throws {}
        func deleteAllSecrets() async throws { throw Failure() }
    }

    private func makeTemporaryDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, tempDir)
    }

    private func makeLocalModel(
        id: String = "apple/SmolLM2-360M-Instruct-CoreML",
        displayName: String = "SmolLM2 360M",
        repo: String? = nil,
        localPath: String? = nil,
        partialDownloadPath: String? = nil,
        status: LocalModelStatus = .downloaded
    ) -> LocalModelDescriptor {
        let now = Date()
        return LocalModelDescriptor(
            id: id,
            displayName: displayName,
            huggingFaceRepo: repo ?? id,
            revision: "main",
            parameterCount: "360M",
            quantization: "float16",
            diskSizeMB: 700,
            minMemoryMB: 800,
            expectedFileCount: 5,
            maxContextTokens: 2_048,
            effectivePromptCap: 2_048,
            effectiveOutputCap: 1_024,
            status: status,
            downloadProgress: status == .downloaded ? 1 : 0,
            downloadedBytes: 0,
            totalBytes: 0,
            lastProgressAt: nil,
            checksumSHA256: nil,
            validationState: .pending,
            localPath: localPath,
            partialDownloadPath: partialDownloadPath,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
    }

    private final class NotificationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func markPosted() {
            lock.lock()
            value = true
            lock.unlock()
        }

        func didPost() -> Bool {
            lock.lock()
            let posted = value
            lock.unlock()
            return posted
        }
    }

    private final class CleanupCapture: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var models: [LocalModelDescriptor] = []

        func record(_ models: [LocalModelDescriptor]) {
            lock.lock()
            self.models = models
            lock.unlock()
        }
    }

    private static let cases = ExhaustiveMode.choose(
        fast: Array(0..<8),
        full: Array(0..<24)
    )

    private static func contents(of relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    @Test(arguments: cases)
    @MainActor
    func serviceIdentityIsStable(_: Int) async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "appstate-service-identity.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appState = AppState(database: database, secretStore: TestSecretStore())

        let db1 = appState.database
        let db2 = appState.database
        #expect(ObjectIdentifier(db1) == ObjectIdentifier(db2))

        let debrid1 = appState.debridManager
        let debrid2 = appState.debridManager
        #expect(ObjectIdentifier(debrid1) == ObjectIdentifier(debrid2))

        let indexer1 = appState.indexerManager
        let indexer2 = appState.indexerManager
        #expect(ObjectIdentifier(indexer1) == ObjectIdentifier(indexer2))

        let downloads1 = appState.downloadManager
        let downloads2 = appState.downloadManager
        #expect(ObjectIdentifier(downloads1) == ObjectIdentifier(downloads2))

        let env1 = appState.environmentCatalogManager
        let env2 = appState.environmentCatalogManager
        #expect(ObjectIdentifier(env1) == ObjectIdentifier(env2))
    }

    @Test
    @MainActor
    func databaseFallsBackWhenInjectedFactoryFails() async throws {
        struct InjectedFailure: Error {}

        let appState = AppState(
            testHooks: .init(
                databaseFactory: {
                    throw InjectedFailure()
                }
            )
        )

        let database = appState.database
        try await database.migrate()
        #expect(ObjectIdentifier(database) == ObjectIdentifier(appState.database))
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<8), full: Array(0..<16)))
    @MainActor
    func reloadIndexersPostsNotification(index: Int) async {
        let _ = index
        let appState = AppState(
            testHooks: .init(
                initializeIndexers: {
                    // no-op success path
                }
            )
        )

        let flag = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .indexersDidChange,
            object: nil,
            queue: nil
        ) { _ in
            flag.markPosted()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await appState.reloadIndexers()
        #expect(flag.didPost())
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<8), full: Array(0..<16)))
    @MainActor
    func traktSyncRefreshHelperPostsLibraryAndTasteNotifications(index: Int) async {
        let _ = index
        let appState = AppState(testHooks: .init())

        let libraryFlag = NotificationFlag()
        let tasteFlag = NotificationFlag()
        let libraryToken = NotificationCenter.default.addObserver(
            forName: .libraryDidChange,
            object: nil,
            queue: nil
        ) { _ in
            libraryFlag.markPosted()
        }
        let tasteToken = NotificationCenter.default.addObserver(
            forName: .tasteProfileDidChange,
            object: nil,
            queue: nil
        ) { _ in
            tasteFlag.markPosted()
        }
        defer {
            NotificationCenter.default.removeObserver(libraryToken)
            NotificationCenter.default.removeObserver(tasteToken)
        }

        appState.applyTraktSyncLocalRefresh(
            for: .init(localRefreshTargets: [.library, .tasteProfile])
        )

        #expect(libraryFlag.didPost())
        #expect(tasteFlag.didPost())
    }

    @Test
    @MainActor
    func resetAllDataRebuildsCachedServicesThatTrackAppState() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "appstate-service-reset.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appState = AppState(database: database, secretStore: TestSecretStore())

        let beforeSettings = appState.settingsManager
        let beforeDebrid = appState.debridManager
        let beforeIndexer = appState.indexerManager
        let beforeDownloads = appState.downloadManager
        let beforeEnvironmentCatalog = appState.environmentCatalogManager
        let beforeAI = appState.aiAssistantManager
        let beforeLocalCatalog = appState.localCatalogStore
        let beforeLocalDownload = appState.localDownloadService
        let beforeLocalInference = appState.localInferenceEngine
        let beforeLibraryCSV = appState.libraryCSVImportService
        let beforeScrobble = appState.scrobbleCoordinator

        try await appState.resetAllData()

        #expect(appState.settingsManager !== beforeSettings)
        #expect(appState.debridManager !== beforeDebrid)
        #expect(appState.indexerManager !== beforeIndexer)
        #expect(appState.downloadManager !== beforeDownloads)
        #expect(appState.environmentCatalogManager !== beforeEnvironmentCatalog)
        #expect(appState.aiAssistantManager !== beforeAI)
        #expect(appState.localCatalogStore !== beforeLocalCatalog)
        #expect(appState.localDownloadService !== beforeLocalDownload)
        #expect(appState.localInferenceEngine !== beforeLocalInference)
        #expect(appState.libraryCSVImportService !== beforeLibraryCSV)
        #expect(appState.scrobbleCoordinator !== beforeScrobble)
    }

    @Test
    func cleanupPersistentArtifactsRemovesModelArtifactsWithoutTouchingUnrelatedCaches() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appSupport = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let downloadsDir = appSupport.appendingPathComponent("VPStudio/Downloads", isDirectory: true)
        let environmentsDir = appSupport.appendingPathComponent("VPStudio/Environments", isDirectory: true)
        let modelsDir = appSupport.appendingPathComponent("VPStudio/Models", isDirectory: true)
        let hubRoot = caches.appendingPathComponent("huggingface/hub", isDirectory: true)
        let repoDir = hubRoot.appendingPathComponent("models--apple--SmolLM2-360M-Instruct-CoreML", isDirectory: true)
        let snapshotDir = repoDir.appendingPathComponent("snapshots/123", isDirectory: true)
        let unrelatedRepoDir = hubRoot.appendingPathComponent("models--other--shared", isDirectory: true)

        for directory in [downloadsDir, environmentsDir, modelsDir, snapshotDir, unrelatedRepoDir] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let localModel = makeLocalModel(localPath: snapshotDir.path)
        try AppState.cleanupPersistentArtifacts(
            using: fileManager,
            localModels: [localModel],
            appSupportDirectory: appSupport,
            cachesDirectory: caches
        )

        #expect(!fileManager.fileExists(atPath: downloadsDir.path))
        #expect(!fileManager.fileExists(atPath: environmentsDir.path))
        #expect(!fileManager.fileExists(atPath: modelsDir.path))
        #expect(!fileManager.fileExists(atPath: repoDir.path))
        #expect(fileManager.fileExists(atPath: unrelatedRepoDir.path))
    }

    @Test
    @MainActor
    func resetAllDataPassesPersistedLocalModelsToCleanupHook() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "appstate-local-model-reset.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let localModel = makeLocalModel()
        try await database.saveLocalModel(localModel)

        let capture = CleanupCapture()
        let appState = AppState(
            database: database,
            secretStore: TestSecretStore(),
            testHooks: .init(
                cleanupPersistentArtifacts: { models in
                    capture.record(models)
                }
            )
        )

        try await appState.resetAllData()

        #expect(capture.models.count == 1)
        #expect(capture.models.first?.id == localModel.id)
        let remainingModels = try await database.fetchLocalModels()
        #expect(remainingModels.isEmpty)
    }

    @Test
    @MainActor
    func resetAllDataThrowsAndSkipsSuccessNotificationsWhenInjectedSecretDeletionFails() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "appstate-reset-secret-failure.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await database.setSetting(key: "sample-setting", value: "keep-me")
        let existingHistory = WatchHistory(
            id: "progress-entry",
            mediaId: "tt1234567",
            title: "Existing Progress",
            progress: 120,
            duration: 300,
            watchedAt: Date(),
            isCompleted: false
        )
        try await database.saveWatchHistory(existingHistory)

        let appState = AppState(database: database, secretStore: ThrowingDeleteAllSecretStore())
        appState.selectedTab = .library

        let flag = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .appDidResetAllData,
            object: nil,
            queue: nil
        ) { _ in
            flag.markPosted()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        do {
            try await appState.resetAllData()
            Issue.record("Expected resetAllData to throw when deleteAllSecrets fails")
        } catch is ThrowingDeleteAllSecretStore.Failure {
            // expected
        }

        #expect(appState.selectedTab == .library)
        #expect(flag.didPost() == false)
    }

    @Test
    @MainActor
    func resetAllDataStopsBeforeDatabaseWipeWhenArtifactCleanupFails() async throws {
        enum CleanupFailure: Error {
            case diskFailure
        }

        let (database, tempDir) = try await makeTemporaryDatabase(named: "appstate-reset-cleanup-failure.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await database.setSetting(key: "sample-setting", value: "keep-me")
        let existingHistory = WatchHistory(
            id: "cleanup-failure-history",
            mediaId: "tt7654321",
            title: "Existing Progress",
            progress: 120,
            duration: 300,
            watchedAt: Date(),
            isCompleted: false
        )
        try await database.saveWatchHistory(existingHistory)

        let appState = AppState(
            database: database,
            secretStore: TestSecretStore(),
            testHooks: .init(
                cleanupPersistentArtifacts: { _ in
                    throw CleanupFailure.diskFailure
                }
            )
        )
        appState.selectedTab = .library

        let flag = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .appDidResetAllData,
            object: nil,
            queue: nil
        ) { _ in
            flag.markPosted()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        do {
            try await appState.resetAllData()
            Issue.record("Expected resetAllData to throw when cleanupPersistentArtifacts fails")
        } catch is CleanupFailure {
            // expected
        }

        #expect(appState.selectedTab == .library)
        #expect(try await database.getSetting(key: "sample-setting") == "keep-me")
        #expect(try await database.fetchWatchHistory(mediaId: "tt7654321", episodeId: nil)?.id == existingHistory.id)
        #expect(flag.didPost() == false)
    }

    @Test
    @MainActor
    func resetAllDataRollsBackSecretNamespaceWhenDatabaseResetFails() async {
        let defaults = UserDefaults.standard
        let originalNamespace = AppState.currentSecretStoreNamespace(defaults: defaults)
        let sentinelNamespace = max(originalNamespace, 7)
        defaults.set(sentinelNamespace, forKey: "app.secret_store_namespace")
        defer { defaults.set(originalNamespace, forKey: "app.secret_store_namespace") }

        let appState = AppState(database: DatabaseManager.unavailable(message: "forced-reset-failure"))
        appState.selectedTab = .library

        let flag = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .appDidResetAllData,
            object: nil,
            queue: nil
        ) { _ in
            flag.markPosted()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        do {
            try await appState.resetAllData()
            Issue.record("Expected resetAllData to throw when database reset fails")
        } catch {
            #expect(AppState.currentSecretStoreNamespace(defaults: defaults) == sentinelNamespace)
            #expect(appState.selectedTab == .library)
            #expect(flag.didPost() == false)
        }
    }

    @Test
    @MainActor
    func resetAllDataRollsBackSecretNamespaceWhenArtifactCleanupFails() async throws {
        enum CleanupFailure: Error {
            case diskFailure
        }

        let defaults = UserDefaults.standard
        let originalNamespace = AppState.currentSecretStoreNamespace(defaults: defaults)
        let sentinelNamespace = max(originalNamespace + 1, 2_000_000)
        defaults.set(sentinelNamespace, forKey: "app.secret_store_namespace")
        defer { defaults.set(originalNamespace, forKey: "app.secret_store_namespace") }

        let (database, tempDir) = try await makeTemporaryDatabase(named: "appstate-reset-namespace-cleanup-failure.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appState = AppState(
            database: database,
            testHooks: .init(
                cleanupPersistentArtifacts: { _ in
                    throw CleanupFailure.diskFailure
                }
            )
        )

        do {
            try await appState.resetAllData()
            Issue.record("Expected resetAllData to throw when cleanupPersistentArtifacts fails")
        } catch is CleanupFailure {
            #expect(AppState.currentSecretStoreNamespace(defaults: defaults) == sentinelNamespace)
        }
    }

    @Test
    @MainActor
    func resetAllDataPreservesRotatedSecretNamespaceAfterDefaultsWipe() async throws {
        let defaults = UserDefaults.standard
        let originalNamespace = AppState.currentSecretStoreNamespace(defaults: defaults)
        let sentinelNamespace = max(originalNamespace + 1, 1_000_000)
        defaults.set(sentinelNamespace, forKey: "app.secret_store_namespace")
        defer { defaults.set(originalNamespace, forKey: "app.secret_store_namespace") }

        let (database, tempDir) = try await makeTemporaryDatabase(named: "appstate-reset-secret-namespace.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appState = AppState(
            database: database,
            testHooks: .init(
                cleanupPersistentArtifacts: { _ in }
            )
        )

        try await appState.resetAllData()

        #expect(AppState.currentSecretStoreNamespace(defaults: defaults) == sentinelNamespace + 1)
    }

    @Test
    @MainActor
    func migratePersistedSecretsIfNeededMovesLegacyDebridAndIndexerSecretsIntoSecretStore() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "appstate-secret-migration.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let debridID = "legacy-debrid"
        let indexerID = "legacy-indexer"

        try await database.saveDebridConfig(
            DebridConfig(
                id: debridID,
                serviceType: .realDebrid,
                apiTokenRef: "  plaintext-token  ",
                isActive: true,
                priority: 0
            )
        )
        try await database.saveIndexerConfig(
            IndexerConfig(
                id: indexerID,
                name: "Legacy",
                indexerType: .torznab,
                baseURL: "https://legacy.example",
                apiKey: "  plaintext-api-key  ",
                isActive: true,
                priority: 0
            )
        )

        let appState = AppState(database: database, secretStore: secretStore)
        try await appState.migratePersistedSecretsIfNeeded()

        let debridConfig = try #require(try await database.fetchAllDebridConfigs().first(where: { $0.id == debridID }))
        let indexerConfig = try #require(try await database.fetchAllIndexerConfigs().first(where: { $0.id == indexerID }))

        let expectedDebridKey = SecretKey.debridToken(service: .realDebrid, configId: debridID)
        let expectedIndexerKey = IndexerConfig.secretKey(for: indexerID)

        #expect(debridConfig.apiTokenRef == SecretReference.encode(key: expectedDebridKey))
        #expect(indexerConfig.apiKey == SecretReference.encode(key: expectedIndexerKey))
        #expect(try await secretStore.getSecret(for: expectedDebridKey) == "plaintext-token")
        #expect(try await secretStore.getSecret(for: expectedIndexerKey) == "plaintext-api-key")
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<8), full: Array(0..<16)))
    @MainActor
    func traktSyncRefreshHelperTreatsRetentionSweepAsLibraryInvalidation(index: Int) async {
        let _ = index
        let appState = AppState(testHooks: .init())

        let libraryFlag = NotificationFlag()
        let tasteFlag = NotificationFlag()
        let libraryToken = NotificationCenter.default.addObserver(
            forName: .libraryDidChange,
            object: nil,
            queue: nil
        ) { _ in
            libraryFlag.markPosted()
        }
        let tasteToken = NotificationCenter.default.addObserver(
            forName: .tasteProfileDidChange,
            object: nil,
            queue: nil
        ) { _ in
            tasteFlag.markPosted()
        }
        defer {
            NotificationCenter.default.removeObserver(libraryToken)
            NotificationCenter.default.removeObserver(tasteToken)
        }

        appState.applyTraktSyncLocalRefresh(
            for: .init(),
            removedHistoryEntryCount: 1
        )

        #expect(libraryFlag.didPost())
        #expect(tasteFlag.didPost() == false)
    }

    @Test
    func traktSyncEntryPointsShareTheSameRefreshHelper() throws {
        let appStateSource = try Self.contents(of: "VPStudio/App/AppState.swift")
        let settingsSource = try Self.contents(of: "VPStudio/Views/Windows/Settings/Destinations/TraktSettingsView.swift")

        #expect(appStateSource.contains("_ = await self.performTraktSyncAndRefreshLocalState(expectedGeneration: generation)"))
        #expect(settingsSource.contains("await appState.performTraktSyncAndRefreshLocalState()"))
    }
}
