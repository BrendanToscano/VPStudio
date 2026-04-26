import AVFoundation
import Foundation
import Observation
import os

@Observable
@MainActor
final class AppState {
    nonisolated private static let logger = Logger(subsystem: "com.vpstudio", category: "app-state")
    nonisolated private static let secretStoreNamespaceKey = "app.secret_store_namespace"
    nonisolated private static let secretStoreBaseServiceName = "com.vpstudio.credentials"
    private enum ResetAllDataError: LocalizedError {
        case fileCleanupFailed([String])

        var errorDescription: String? {
            switch self {
            case .fileCleanupFailed(let failures):
                let details = failures.joined(separator: " | ")
                return "Reset completed the database wipe, but disk cleanup failed: \(details)"
            }
        }
    }

    struct TestHooks: Sendable {
        var databaseFactory: (@Sendable () throws -> DatabaseManager)?
        var migrate: (@Sendable () async throws -> Void)?
        var initializeDebrid: (@Sendable () async throws -> Void)?
        var bootstrapEnvironments: (@Sendable () async throws -> Void)?
        var cleanupPersistentArtifacts: (@Sendable ([LocalModelDescriptor]) throws -> Void)?
        var fetchActiveEnvironment: (@Sendable () async throws -> EnvironmentAsset?)?
        var fetchDebridConfigs: (@Sendable () async throws -> [DebridConfig])?
        var availableDebridServices: (@Sendable () async -> [DebridServiceType])?
        var fetchTMDBApiKey: (@Sendable () async throws -> String?)?
        var initializeIndexers: (@Sendable () async throws -> Void)?

        nonisolated init(
            databaseFactory: (@Sendable () throws -> DatabaseManager)? = nil,
            migrate: (@Sendable () async throws -> Void)? = nil,
            initializeDebrid: (@Sendable () async throws -> Void)? = nil,
            bootstrapEnvironments: (@Sendable () async throws -> Void)? = nil,
            cleanupPersistentArtifacts: (@Sendable ([LocalModelDescriptor]) throws -> Void)? = nil,
            fetchActiveEnvironment: (@Sendable () async throws -> EnvironmentAsset?)? = nil,
            fetchDebridConfigs: (@Sendable () async throws -> [DebridConfig])? = nil,
            availableDebridServices: (@Sendable () async -> [DebridServiceType])? = nil,
            fetchTMDBApiKey: (@Sendable () async throws -> String?)? = nil,
            initializeIndexers: (@Sendable () async throws -> Void)? = nil
        ) {
            self.databaseFactory = databaseFactory
            self.migrate = migrate
            self.initializeDebrid = initializeDebrid
            self.bootstrapEnvironments = bootstrapEnvironments
            self.cleanupPersistentArtifacts = cleanupPersistentArtifacts
            self.fetchActiveEnvironment = fetchActiveEnvironment
            self.fetchDebridConfigs = fetchDebridConfigs
            self.availableDebridServices = availableDebridServices
            self.fetchTMDBApiKey = fetchTMDBApiKey
            self.initializeIndexers = initializeIndexers
        }
    }

    private struct QATraktRefreshFixture: Decodable {
        struct Media: Decodable {
            var id: String
            var type: MediaType
            var title: String
            var year: Int?
            var posterPath: String?
            var backdropPath: String?
            var overview: String?
            var genres: [String]?
            var imdbRating: Double?
            var runtime: Int?
            var status: String?
            var tmdbId: Int?
        }

        struct History: Decodable {
            var id: String
            var mediaId: String?
            var episodeId: String?
            var title: String
            var progress: Double
            var duration: Double
            var quality: String?
            var debridService: String?
            var streamURL: String?
            var watchedAt: Date
            var isCompleted: Bool
        }

        var media: Media
        var history: History
    }

    struct LocalAIProviderConfiguration: Equatable, Sendable {
        var isEnabled: Bool
        var selectedModelID: String?
        var resolvedModelID: String?

        var isUsable: Bool {
            isEnabled && resolvedModelID != nil
        }
    }

    // MARK: - Navigation
    var selectedTab: SidebarTab = .discover
    var navigationLayout: NavigationLayout = .bottomTabBar
    var isShowingSetup: Bool = false
    var setupRecommendationNeeded: Bool = false
    var navigationResetID: UUID = UUID()
    var isBootstrapping: Bool = true
    var runtimeDiagnosticsEnabled: Bool = false

    // MARK: - Warnings
    var environmentBootstrapWarning: String?
    var indexerReloadWarning: String?

    // MARK: - Immersive State
    var activeEnvironment: EnvironmentType?
    var isImmersiveSpaceOpen: Bool = false
    var selectedEnvironmentAsset: EnvironmentAsset?
    var isImmersiveTransitionInFlight: Bool = false
    var shouldRestoreImmersiveAfterSuspension: Bool = false
    private var pendingImmersiveDismissReason: ImmersiveDismissReason = .userInitiated

    // MARK: - Player Session
    var activePlayerSession: PlayerSessionRequest?
    var fullscreenBySessionID: [UUID: Bool] = [:]
    var isMainWindowSuppressedForPlayer = false

    // Cross-scene bridge: PlayerView sets these; immersive space reads them.
    // Weak because PlayerView owns the strong references via @State.
    weak var activeAVPlayer: AVPlayer?
    weak var activeVideoRenderer: AVSampleBufferVideoRenderer?

    let spatialAudioManager = SpatialAudioManager()

    // MARK: - Services (lazy-initialized)
    private var _database: DatabaseManager?
    private var _secretStore: (any SecretStore)?
    private var _settingsManager: SettingsManager?
    private var _debridManager: DebridManager?
    private var _indexerManager: IndexerManager?
    private var _downloadManager: DownloadManager?
    private var _environmentCatalogManager: EnvironmentCatalogManager?
    private var _scrobbleCoordinator: ScrobbleCoordinator?
    private var _traktSyncOrchestrator: TraktSyncOrchestrator?
    private var _aiAssistantManager: AIAssistantManager?
    private var _localCatalogStore: LocalModelCatalogStore?
    private var _localDownloadService: LocalDownloadService?
    private var _localInferenceEngine: LocalInferenceEngine?
    private var _libraryCSVImportService: LibraryCSVImportService?
    private var _networkMonitor: NetworkMonitor?
    private var backgroundTraktSyncTask: Task<Void, Never>?
    private var activeTraktSyncTask: Task<TraktSyncOrchestrator.SyncResult?, Never>?
    private var stateGeneration: UInt64 = 0
    private var traktSyncGeneration: UInt64 = 0
    private let injectedSecretStore: (any SecretStore)?
    private let testHooks: TestHooks

    init(
        database: DatabaseManager? = nil,
        secretStore: (any SecretStore)? = nil,
        settingsManager: SettingsManager? = nil,
        debridManager: DebridManager? = nil,
        indexerManager: IndexerManager? = nil,
        downloadManager: DownloadManager? = nil,
        environmentCatalogManager: EnvironmentCatalogManager? = nil,
        libraryCSVImportService: LibraryCSVImportService? = nil,
        testHooks: TestHooks = .init()
    ) {
        _database = database
        _secretStore = secretStore
        injectedSecretStore = secretStore
        _settingsManager = settingsManager
        _debridManager = debridManager
        _indexerManager = indexerManager
        _downloadManager = downloadManager
        _environmentCatalogManager = environmentCatalogManager
        _libraryCSVImportService = libraryCSVImportService
        self.testHooks = testHooks
    }

    var database: DatabaseManager {
        if let database = _database {
            return database
        }

        if let factory = testHooks.databaseFactory {
            do {
                let database = try factory()
                _database = database
                return database
            } catch {
                Self.logger.error("Injected database factory failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let database = Self.makeFallbackDatabase()
        _database = database
        return database
    }

    private static func makeFallbackDatabase() -> DatabaseManager {
        var failureMessages: [String] = []

        do {
            return try DatabaseManager(path: nil)
        } catch {
            let message = "Primary database initialization failed: \(error.localizedDescription)"
            failureMessages.append(message)
            Self.logger.fault("\(message, privacy: .public). Refusing to silently downgrade persistence to temporary or in-memory storage.")
        }

        let failureSummary = failureMessages.joined(separator: " | ")
        Self.logger.fault("All database initialization fallbacks failed. Database operations will remain unavailable. \(failureSummary, privacy: .public)")
        return DatabaseManager.unavailable(message: "Unable to initialize any database storage. \(failureSummary)")
    }

    nonisolated static func cleanupPersistentArtifacts(
        using fileManager: FileManager = .default,
        localModels: [LocalModelDescriptor] = [],
        appSupportDirectory: URL? = nil,
        cachesDirectory: URL? = nil
    ) throws {
        let resolvedAppSupport = appSupportDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let resolvedCaches = cachesDirectory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first

        var targets: [(URL, String)] = []
        if let resolvedAppSupport {
            let vpStudioDir = resolvedAppSupport.appendingPathComponent("VPStudio", isDirectory: true)
            targets.append((vpStudioDir.appendingPathComponent("Downloads", isDirectory: true), "Downloads"))
            targets.append((vpStudioDir.appendingPathComponent("Environments", isDirectory: true), "Environments"))
            targets.append((LocalDownloadService.modelsDirectoryURL(appSupportDirectory: resolvedAppSupport), "Models"))
        }

        let modelsDirectory = resolvedAppSupport.map {
            LocalDownloadService.modelsDirectoryURL(appSupportDirectory: $0).standardizedFileURL
        }
        let hubCacheRoot = LocalDownloadService.hubCacheRootDirectoryURL(cachesDirectory: resolvedCaches)?.standardizedFileURL
        var seenPaths = Set(targets.map { $0.0.standardizedFileURL.path })

        for model in localModels {
            if let repoCache = LocalDownloadService.hubCacheDirectoryURL(
                for: model.huggingFaceRepo,
                cachesDirectory: resolvedCaches
            ) {
                let standardizedPath = repoCache.standardizedFileURL.path
                if seenPaths.insert(standardizedPath).inserted {
                    targets.append((repoCache, "Model cache (\(model.displayName))"))
                }
            }

            for path in [model.localPath, model.partialDownloadPath].compactMap({ $0 }) {
                let artifactURL = URL(fileURLWithPath: path).standardizedFileURL
                let isAppOwnedModelPath = modelsDirectory.map { isDescendant(artifactURL, of: $0) } ?? false
                let isHubCachePath = hubCacheRoot.map { isDescendant(artifactURL, of: $0) } ?? false
                guard isAppOwnedModelPath || isHubCachePath else { continue }

                let standardizedPath = artifactURL.path
                if seenPaths.insert(standardizedPath).inserted {
                    targets.append((artifactURL, "Local model artifact (\(model.displayName))"))
                }
            }
        }

        var failures: [String] = []
        for (url, label) in targets where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                failures.append("\(label): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            throw ResetAllDataError.fileCleanupFailed(failures)
        }
    }

    nonisolated private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
    }

    nonisolated static func currentSecretStoreNamespace(defaults: UserDefaults = .standard) -> Int {
        max(defaults.integer(forKey: secretStoreNamespaceKey), 0)
    }

    nonisolated static func secretStoreServiceName(namespace: Int) -> String {
        guard namespace > 0 else { return secretStoreBaseServiceName }
        return "\(secretStoreBaseServiceName).v\(namespace)"
    }

    nonisolated static func currentSecretStoreServiceName(defaults: UserDefaults = .standard) -> String {
        secretStoreServiceName(namespace: currentSecretStoreNamespace(defaults: defaults))
    }

    @discardableResult
    nonisolated static func advanceSecretStoreNamespace(defaults: UserDefaults = .standard) -> Int {
        let nextNamespace = currentSecretStoreNamespace(defaults: defaults) + 1
        defaults.set(nextNamespace, forKey: secretStoreNamespaceKey)
        return nextNamespace
    }

    var secretStore: any SecretStore {
        if _secretStore == nil {
            if let injectedSecretStore {
                _secretStore = injectedSecretStore
            } else {
                _secretStore = KeychainSecretStore(serviceName: Self.currentSecretStoreServiceName())
            }
        }
        return _secretStore!
    }

    var settingsManager: SettingsManager {
        if _settingsManager == nil {
            _settingsManager = SettingsManager(database: database, secretStore: secretStore)
        }
        return _settingsManager!
    }

    var debridManager: DebridManager {
        if _debridManager == nil {
            _debridManager = DebridManager(database: database, secretStore: secretStore)
        }
        return _debridManager!
    }

    var indexerManager: IndexerManager {
        if _indexerManager == nil {
            _indexerManager = IndexerManager(database: database, secretStore: secretStore)
        }
        return _indexerManager!
    }

    var downloadManager: DownloadManager {
        if _downloadManager == nil {
            let debrid = debridManager
            _downloadManager = DownloadManager(
                database: database,
                linkRefresher: { context in
                    let stream = try await debrid.resolveStream(from: context)
                    return stream.streamURL
                },
                remoteTransferCleaner: { context in
                    await debrid.cleanupRemoteTransfer(from: context)
                }
            )
        }
        return _downloadManager!
    }

    var environmentCatalogManager: EnvironmentCatalogManager {
        if _environmentCatalogManager == nil {
            _environmentCatalogManager = EnvironmentCatalogManager(database: database)
        }
        return _environmentCatalogManager!
    }

    var scrobbleCoordinator: ScrobbleCoordinator {
        if _scrobbleCoordinator == nil {
            _scrobbleCoordinator = ScrobbleCoordinator(settingsManager: settingsManager, secretStore: secretStore)
        }
        return _scrobbleCoordinator!
    }

    /// Creates a configured `TraktSyncOrchestrator` by reading Trakt credentials
    /// from settings. Returns `nil` if credentials are missing.
    func makeTraktSyncOrchestrator() async -> TraktSyncOrchestrator? {
        let generation = stateGeneration
        let credentialGeneration = traktSyncGeneration
        let settingsManager = self.settingsManager
        let userClientId = try? await settingsManager.getString(key: SettingsKeys.traktClientId)
        let userClientSecret = try? await settingsManager.getString(key: SettingsKeys.traktClientSecret)
        guard let creds = TraktDefaults.resolvedCredentials(
            userClientId: userClientId,
            userClientSecret: userClientSecret
        ) else { return nil }
        let clientId = creds.clientId
        let clientSecret = creds.clientSecret

        let service = TraktSyncService(
            clientId: clientId,
            clientSecret: clientSecret,
            onTokensRefreshed: { [settingsManager] access, refresh in
                let shouldPersistTokens = await MainActor.run { [weak self] in
                    guard let self else { return false }
                    return self.stateGeneration == generation
                        && self.traktSyncGeneration == credentialGeneration
                }
                guard shouldPersistTokens else { return }
                do {
                    try await settingsManager.setString(key: SettingsKeys.traktAccessToken, value: access)
                    if let refresh {
                        try await settingsManager.setString(key: SettingsKeys.traktRefreshToken, value: refresh)
                    }
                } catch {
                    Self.logger.error("Failed to persist refreshed Trakt tokens: \(error.localizedDescription, privacy: .public)")
                }
            }
        )

        guard generation == stateGeneration, credentialGeneration == traktSyncGeneration else { return nil }

        if let accessToken = try? await settingsManager.getString(key: SettingsKeys.traktAccessToken),
           !accessToken.isEmpty {
            let refreshToken = try? await settingsManager.getString(key: SettingsKeys.traktRefreshToken)
            await service.setTokens(access: accessToken, refresh: refreshToken)
        }

        return TraktSyncOrchestrator(
            traktService: service,
            database: database,
            settingsManager: settingsManager
        )
    }

    var libraryCSVImportService: LibraryCSVImportService {
        if _libraryCSVImportService == nil {
            _libraryCSVImportService = LibraryCSVImportService(database: database)
        }
        return _libraryCSVImportService!
    }

    var networkMonitor: NetworkMonitor {
        if _networkMonitor == nil {
            _networkMonitor = NetworkMonitor()
        }
        return _networkMonitor!
    }

    var aiAssistantManager: AIAssistantManager {
        if _aiAssistantManager == nil {
            _aiAssistantManager = AIAssistantManager(database: database)
        }
        return _aiAssistantManager!
    }

    var localCatalogStore: LocalModelCatalogStore {
        if _localCatalogStore == nil {
            _localCatalogStore = LocalModelCatalogStore(database: database)
        }
        return _localCatalogStore!
    }

    var localDownloadService: LocalDownloadService {
        if _localDownloadService == nil {
            _localDownloadService = LocalDownloadService(catalogStore: localCatalogStore)
        }
        return _localDownloadService!
    }

    var localInferenceEngine: LocalInferenceEngine {
        if _localInferenceEngine == nil {
            _localInferenceEngine = LocalInferenceEngine(catalogStore: localCatalogStore)
        }
        return _localInferenceEngine!
    }

    func createMetadataService(apiKey: String) -> TMDBService {
        TMDBService(apiKey: apiKey)
    }

    // MARK: - Initialization

    func bootstrap() async {
        do {
            // Initialize the database eagerly so any filesystem errors surface here
            // rather than crashing later from an unexpected code path.
            if _database == nil {
                _ = database
            }

            if let migrate = testHooks.migrate {
                try await migrate()
            } else {
                try await database.migrate()
                _ = try await database.runRetentionSweepIfNeeded()
            }

            try await migratePersistedSecretsIfNeeded()

            if let initializeDebrid = testHooks.initializeDebrid {
                try await initializeDebrid()
            } else {
                try await debridManager.initialize()
            }

            // Start download-manager resume work early so persisted jobs can
            // rehydrate even if the user never opens the Downloads screen.
            _ = downloadManager

            // Environment bootstrap is non-fatal — the app works without environments
            do {
                if let bootstrapEnvironments = testHooks.bootstrapEnvironments {
                    try await bootstrapEnvironments()
                } else {
                    try await environmentCatalogManager.bootstrapCuratedAssets()
                }

                if let fetchActiveEnvironment = testHooks.fetchActiveEnvironment {
                    selectedEnvironmentAsset = try await fetchActiveEnvironment()
                } else {
                    selectedEnvironmentAsset = try await environmentCatalogManager.activeAsset()
                }
            } catch {
                environmentBootstrapWarning = error.localizedDescription
            }

            let hasDebridConfig: Bool
            if let fetchDebridConfigs = testHooks.fetchDebridConfigs {
                hasDebridConfig = try await !fetchDebridConfigs().isEmpty
            } else {
                hasDebridConfig = try await !database.fetchDebridConfigs().isEmpty
            }

            let hasReadyDebridService: Bool
            if let availableDebridServices = testHooks.availableDebridServices {
                hasReadyDebridService = await !availableDebridServices().isEmpty
            } else {
                hasReadyDebridService = await !debridManager.availableServices().isEmpty
            }

            let hasTMDBApiKey: Bool
            if let fetchTMDBApiKey = testHooks.fetchTMDBApiKey {
                let tmdbApiKey = try await fetchTMDBApiKey() ?? ""
                hasTMDBApiKey = !tmdbApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } else {
                let tmdbApiKey = (try? await settingsManager.getString(key: SettingsKeys.tmdbApiKey)) ?? ""
                hasTMDBApiKey = !tmdbApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            setupRecommendationNeeded = !hasDebridConfig || !hasReadyDebridService || !hasTMDBApiKey

            await localCatalogStore.seedCatalog()
            await localInferenceEngine.startMonitoring()
            await configureAIProviders()

            runtimeDiagnosticsEnabled = (try? await settingsManager.getBool(
                key: SettingsKeys.runtimeDiagnosticsEnabled,
                default: false
            )) ?? false

            // Auto-sync with Trakt on launch if credentials are available
            let generation = stateGeneration
            cancelTraktSyncWork(invalidateGeneration: false)
            backgroundTraktSyncTask = Task { [weak self] in
                guard let self else { return }
                _ = await self.performTraktSyncAndRefreshLocalState(expectedGeneration: generation)
            }
        } catch {
            Self.logger.error("Bootstrap error: \(error.localizedDescription, privacy: .public)")
            isShowingSetup = true
        }

        isBootstrapping = false
    }

    @discardableResult
    func performTraktSyncAndRefreshLocalState(expectedGeneration: UInt64? = nil) async -> TraktSyncOrchestrator.SyncResult? {
        if let activeTraktSyncTask {
            return await activeTraktSyncTask.value
        }

        let generation = expectedGeneration ?? stateGeneration
        let credentialGeneration = traktSyncGeneration
        guard generation == stateGeneration, credentialGeneration == traktSyncGeneration else { return nil }

        let task = Task { [weak self] in
            await self?.runTraktSyncAndRefreshLocalState(
                expectedGeneration: generation,
                expectedCredentialGeneration: credentialGeneration
            )
        }
        activeTraktSyncTask = task
        let result = await task.value
        activeTraktSyncTask = nil
        return result
    }

    private func runTraktSyncAndRefreshLocalState(
        expectedGeneration: UInt64,
        expectedCredentialGeneration: UInt64
    ) async -> TraktSyncOrchestrator.SyncResult? {
        guard expectedGeneration == stateGeneration,
              expectedCredentialGeneration == traktSyncGeneration else {
            return nil
        }
        guard let orchestrator = await makeTraktSyncOrchestrator() else { return nil }

        let result = await orchestrator.sync()
        guard !Task.isCancelled else { return nil }
        guard expectedGeneration == stateGeneration,
              expectedCredentialGeneration == traktSyncGeneration else {
            return nil
        }

        let removedHistoryEntryCount = (try? await database.runRetentionSweepIfNeeded()) ?? 0
        guard !Task.isCancelled else { return nil }
        guard expectedGeneration == stateGeneration,
              expectedCredentialGeneration == traktSyncGeneration else {
            return nil
        }

        applyTraktSyncLocalRefresh(for: result, removedHistoryEntryCount: removedHistoryEntryCount)
        return result
    }

    private func cancelTraktSyncWork(invalidateGeneration: Bool) {
        if invalidateGeneration {
            traktSyncGeneration &+= 1
        }
        backgroundTraktSyncTask?.cancel()
        backgroundTraktSyncTask = nil
        activeTraktSyncTask?.cancel()
        activeTraktSyncTask = nil
    }

    func disconnectTrakt() async throws {
        cancelTraktSyncWork(invalidateGeneration: true)
        let previousAccessToken = try await settingsManager.getString(key: SettingsKeys.traktAccessToken)
        let previousRefreshToken = try await settingsManager.getString(key: SettingsKeys.traktRefreshToken)

        do {
            try await settingsManager.setString(key: SettingsKeys.traktAccessToken, value: nil)
            try await settingsManager.setString(key: SettingsKeys.traktRefreshToken, value: nil)
        } catch {
            try? await settingsManager.setString(key: SettingsKeys.traktAccessToken, value: previousAccessToken)
            try? await settingsManager.setString(key: SettingsKeys.traktRefreshToken, value: previousRefreshToken)
            throw error
        }

        await scrobbleCoordinator.invalidateTraktSession()
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    func migratePersistedSecretsIfNeeded() async throws {
        let debridConfigs = try await database.fetchAllDebridConfigs()
        for config in debridConfigs {
            let persisted = try await config.persistedCopy(using: secretStore)
            if persisted.changed {
                try await database.saveDebridConfig(persisted.config)
            }
        }

        let indexerConfigs = try await database.fetchAllIndexerConfigs()
        for config in indexerConfigs {
            let persisted = try await config.persistedCopy(using: secretStore)
            if persisted.changed {
                try await database.saveIndexerConfig(persisted.config)
            }
        }
    }

    func runQATraktRefreshIfRequested() async {
        guard let fixturePath = QARuntimeOptions.traktRefreshFixturePath else { return }

        if let delaySeconds = QARuntimeOptions.traktRefreshDelaySeconds, delaySeconds > 0 {
            do {
                try await Task.sleep(nanoseconds: QARuntimeOptions.sleepNanoseconds(for: delaySeconds))
            } catch {
                return
            }
        }

        do {
            let fileURL = URL(fileURLWithPath: fixturePath)
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let fixture = try decoder.decode(QATraktRefreshFixture.self, from: data)

            let mediaItem = MediaItem(
                id: fixture.media.id,
                type: fixture.media.type,
                title: fixture.media.title,
                year: fixture.media.year,
                posterPath: fixture.media.posterPath,
                backdropPath: fixture.media.backdropPath,
                overview: fixture.media.overview,
                genres: fixture.media.genres ?? [],
                imdbRating: fixture.media.imdbRating,
                runtime: fixture.media.runtime,
                status: fixture.media.status,
                tmdbId: fixture.media.tmdbId,
                lastFetched: Date()
            )
            try await database.saveMediaItem(mediaItem)

            let history = WatchHistory(
                id: fixture.history.id,
                mediaId: fixture.history.mediaId ?? fixture.media.id,
                episodeId: fixture.history.episodeId,
                title: fixture.history.title,
                progress: fixture.history.progress,
                duration: fixture.history.duration,
                quality: fixture.history.quality,
                debridService: fixture.history.debridService,
                streamURL: fixture.history.streamURL,
                watchedAt: fixture.history.watchedAt,
                isCompleted: fixture.history.isCompleted
            )
            try await database.saveWatchHistory(history)

            applyTraktSyncLocalRefresh(for: .init(localRefreshTargets: [.library]))
            Self.logger.notice("Applied QA Trakt refresh fixture from \(fixturePath, privacy: .public)")
        } catch {
            Self.logger.error("Failed to apply QA Trakt refresh fixture \(fixturePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func applyTraktSyncLocalRefresh(
        for result: TraktSyncOrchestrator.SyncResult,
        removedHistoryEntryCount: Int = 0
    ) {
        // `libraryDidChange` is the existing invalidation bridge for local library,
        // watchlist, folder, and history-backed library surfaces.
        if result.localRefreshTargets.contains(.library) || removedHistoryEntryCount > 0 {
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }

        if result.localRefreshTargets.contains(.tasteProfile) {
            NotificationCenter.default.post(name: .tasteProfileDidChange, object: nil)
        }
    }

    nonisolated static func resolvedLocalModelID(
        preferredModelID: String?,
        downloadedModels: [LocalModelDescriptor]
    ) -> String? {
        guard !downloadedModels.isEmpty else { return nil }

        let normalizedPreferredModelID = preferredModelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let catalogDefaultModelID = AIModelCatalog.defaultModel(for: .local)?.id
        let bundledDefaultModelID = downloadedModels.first(where: \.isDefault)?.id
        let fallbackDownloadedModelID = downloadedModels.first?.id

        let candidateModelIDs = [
            normalizedPreferredModelID,
            catalogDefaultModelID,
            bundledDefaultModelID,
            fallbackDownloadedModelID,
        ]

        for candidateModelID in candidateModelIDs {
            guard let candidateModelID, !candidateModelID.isEmpty else { continue }
            if downloadedModels.contains(where: { $0.id == candidateModelID }) {
                return candidateModelID
            }
        }

        return nil
    }

    func localAIProviderConfiguration() async -> LocalAIProviderConfiguration {
        let isEnabled = (try? await settingsManager.getBool(key: SettingsKeys.localModelEnabled)) ?? false
        let selectedModelID = try? await settingsManager.getString(key: SettingsKeys.localModelPreset)
        let downloadedModels = (try? await localCatalogStore.downloadedModels()) ?? []
        let resolvedModelID = Self.resolvedLocalModelID(
            preferredModelID: selectedModelID,
            downloadedModels: downloadedModels
        )

        return LocalAIProviderConfiguration(
            isEnabled: isEnabled,
            selectedModelID: selectedModelID,
            resolvedModelID: resolvedModelID
        )
    }

    /// Loads saved API keys from settings and registers them with the AI assistant manager.
    /// Clears all providers first so stale registrations (e.g. Ollama) don't linger.
    func configureAIProviders() async {
        let anthropicKey = (try? await settingsManager.getString(key: SettingsKeys.anthropicApiKey)) ?? ""
        let openAIKey = (try? await settingsManager.getString(key: SettingsKeys.openAIApiKey)) ?? ""
        let geminiKey = (try? await settingsManager.getString(key: SettingsKeys.geminiApiKey)) ?? ""
        let openRouterKey = (try? await settingsManager.getString(key: SettingsKeys.openRouterApiKey)) ?? ""
        let ollamaURL = (try? await settingsManager.getString(key: SettingsKeys.ollamaEndpoint)) ?? "http://localhost:11434"
        let anthropicModel = try? await settingsManager.getString(key: SettingsKeys.anthropicModelPreset)
        let openAIModel = try? await settingsManager.getString(key: SettingsKeys.openAIModelPreset)
        let geminiModel = try? await settingsManager.getString(key: SettingsKeys.geminiModelPreset)
        let openRouterModel = try? await settingsManager.getString(key: SettingsKeys.openRouterModelPreset)
        let ollamaModel = try? await settingsManager.getString(key: SettingsKeys.ollamaModelPreset)

        let manager = aiAssistantManager
        await manager.clearProviders()

        if !anthropicKey.isEmpty {
            await manager.configure(provider: .anthropic, apiKey: anthropicKey, model: anthropicModel)
        }
        if !openAIKey.isEmpty {
            await manager.configure(provider: .openAI, apiKey: openAIKey, model: openAIModel)
        }
        if !geminiKey.isEmpty {
            await manager.configure(provider: .gemini, apiKey: geminiKey, model: geminiModel)
        }
        if !openRouterKey.isEmpty {
            await manager.configure(provider: .openRouter, apiKey: openRouterKey, model: openRouterModel)
        }
        let hasOllamaModel = ollamaModel != nil && !(ollamaModel?.isEmpty ?? true)
        let shouldRegisterOllama = !ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasOllamaModel
        if shouldRegisterOllama {
            await manager.configure(provider: .ollama, apiKey: "", baseURL: ollamaURL, model: ollamaModel)
        }

        // Register local on-device provider if enabled and a model is downloaded
        let localConfiguration = await localAIProviderConfiguration()
        if localConfiguration.isUsable, let localModelID = localConfiguration.resolvedModelID {
            let provider = LocalMLXProvider(
                inferenceEngine: localInferenceEngine,
                modelID: localModelID
            )
            await manager.registerProvider(kind: .local, provider: provider)
        }
    }

    func activateEnvironmentAsset(_ asset: EnvironmentAsset) async {
        selectedEnvironmentAsset = asset
        try? await environmentCatalogManager.activateAsset(id: asset.id)
    }

    func beginImmersiveTransition() -> Bool {
        guard !isImmersiveTransitionInFlight else { return false }
        isImmersiveTransitionInFlight = true
        return true
    }

    func cancelImmersiveTransition() {
        isImmersiveTransitionInFlight = false
    }

    func stageImmersiveDismiss(reason: ImmersiveDismissReason) {
        pendingImmersiveDismissReason = reason
        if reason == .suspension {
            shouldRestoreImmersiveAfterSuspension = isImmersiveSpaceOpen || isImmersiveTransitionInFlight
        } else {
            shouldRestoreImmersiveAfterSuspension = false
        }
    }

    func immersiveSpaceDidAppear(_ environment: EnvironmentType) {
        isImmersiveSpaceOpen = true
        activeEnvironment = environment
        isImmersiveTransitionInFlight = false
        pendingImmersiveDismissReason = .userInitiated
        shouldRestoreImmersiveAfterSuspension = false
    }

    func immersiveSpaceDidDisappear() {
        isImmersiveSpaceOpen = false
        activeEnvironment = nil
        isImmersiveTransitionInFlight = false
        if pendingImmersiveDismissReason != .suspension {
            shouldRestoreImmersiveAfterSuspension = false
        }
    }

    func completeImmersiveDismissIfStillPending() {
        guard isImmersiveSpaceOpen || isImmersiveTransitionInFlight else { return }
        immersiveSpaceDidDisappear()
    }

    func consumeSuspendedImmersiveRestoreRequest() -> Bool {
        guard shouldRestoreImmersiveAfterSuspension else { return false }
        shouldRestoreImmersiveAfterSuspension = false
        return true
    }

    func resetAllData() async throws {
        stateGeneration &+= 1
        cancelTraktSyncWork(invalidateGeneration: true)
        if let localInferenceEngine = _localInferenceEngine {
            await localInferenceEngine.stopMonitoring()
        }
        let persistedLocalModels = (try? await database.fetchLocalModels()) ?? []

        let defaults = UserDefaults.standard
        let namespaceRotation = injectedSecretStore == nil
            ? {
                let previousNamespace = Self.currentSecretStoreNamespace(defaults: defaults)
                return (previous: previousNamespace, next: previousNamespace + 1)
            }()
            : nil
        let activeSecretStore: any SecretStore = injectedSecretStore ?? secretStore
        let rotatesSecretNamespace = namespaceRotation != nil

        do {
            // Clean up downloaded and environment files left on disk
            // Actual storage paths are under Application Support/VPStudio/
            if let cleanupPersistentArtifacts = testHooks.cleanupPersistentArtifacts {
                try cleanupPersistentArtifacts(persistedLocalModels)
            } else {
                try Self.cleanupPersistentArtifacts(localModels: persistedLocalModels)
            }

            if let namespaceRotation {
                defaults.set(namespaceRotation.next, forKey: Self.secretStoreNamespaceKey)
                _secretStore = nil
            }

            if !rotatesSecretNamespace {
                try await activeSecretStore.deleteAllSecrets()
            }

            // Reset the database only after filesystem cleanup succeeds so
            // a cleanup failure cannot leave the app in a partially wiped state.
            try await database.resetAllData()

            // Clear persisted UI state so reset behaves like a true fresh install.
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                defaults.removePersistentDomain(forName: bundleIdentifier)
            }
            if let namespaceRotation {
                defaults.set(namespaceRotation.next, forKey: Self.secretStoreNamespaceKey)
            }
            defaults.set(false, forKey: "onboarding.soft_setup_dismissed")
            defaults.set("", forKey: "settings.last_destination")
            defaults.set("", forKey: "settings.search_query")

            // Clear in-memory state
            selectedTab = .discover
            navigationLayout = .bottomTabBar
            isShowingSetup = false
            setupRecommendationNeeded = true
            navigationResetID = UUID()
            runtimeDiagnosticsEnabled = false
            activePlayerSession = nil
            activeAVPlayer = nil
            activeVideoRenderer = nil
            fullscreenBySessionID.removeAll()
            selectedEnvironmentAsset = nil
            activeEnvironment = nil
            isImmersiveSpaceOpen = false
            isImmersiveTransitionInFlight = false
            shouldRestoreImmersiveAfterSuspension = false
            environmentBootstrapWarning = nil
            indexerReloadWarning = nil

            // Drop cached service actors that can hold stale configuration/state after reset.
            _settingsManager = nil
            _debridManager = nil
            _indexerManager = nil
            _downloadManager = nil
            _environmentCatalogManager = nil
            _scrobbleCoordinator = nil
            _traktSyncOrchestrator = nil
            _aiAssistantManager = nil
            _localCatalogStore = nil
            _localDownloadService = nil
            _localInferenceEngine = nil
            _libraryCSVImportService = nil
            _networkMonitor = nil
            _secretStore = nil

            if rotatesSecretNamespace {
                do {
                    try await activeSecretStore.deleteAllSecrets()
                } catch {
                    Self.logger.error("Secret cleanup after namespace rotation failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
            NotificationCenter.default.post(name: .appDidResetAllData, object: nil)
        } catch {
            if let namespaceRotation {
                defaults.set(namespaceRotation.previous, forKey: Self.secretStoreNamespaceKey)
                _secretStore = nil
            }
            throw error
        }
    }

    func reloadIndexers() async {
        do {
            if let initializeIndexers = testHooks.initializeIndexers {
                try await initializeIndexers()
            } else {
                try await indexerManager.initialize()
            }
            indexerReloadWarning = nil
            NotificationCenter.default.post(name: .indexersDidChange, object: nil)
        } catch {
            let message = error.localizedDescription
            indexerReloadWarning = message
            Self.logger.error("Indexer reload error: \(message, privacy: .public)")
        }
    }

    // MARK: - Player Lifecycle

    func terminateActivePlayerSession() {
        releasePlayerResources(clearSession: true)
    }

    func releasePlayerResources(clearSession: Bool = true, sessionID: UUID? = nil) {
        activeAVPlayer = nil
        activeVideoRenderer = nil

        guard clearSession else { return }

        if let targetSessionID = sessionID ?? activePlayerSession?.id {
            fullscreenBySessionID.removeValue(forKey: targetSessionID)
        }
        activePlayerSession = nil
    }
}

// MARK: - Navigation

enum SidebarTab: String, CaseIterable, Identifiable {
    case discover = "Discover"
    case search = "Explore"
    case library = "Library"
    case downloads = "Downloads"
    case environments = "Environments"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .discover: return "safari"
        case .search: return "sparkle.magnifyingglass"
        case .library: return "books.vertical"
        case .downloads: return "arrow.down.circle"
        case .environments: return "mountain.2"
        case .settings: return "gearshape"
        }
    }

    /// Tabs shown in the main section of the sidebar (excludes settings which is pinned to bottom).
    static var mainTabs: [SidebarTab] {
        [.discover, .search, .library, .downloads, .environments]
    }
}

// MARK: - Environment Types

enum EnvironmentType: String, CaseIterable, Identifiable {
    case hdriSkybox = "HDRI Skybox"
    case customEnvironment = "Custom Environment"
    case cinemaEnvironment = "Cinema Environment"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hdriSkybox: return "pano"
        case .customEnvironment: return "cube.transparent"
        case .cinemaEnvironment: return "theatermasks"
        }
    }

    var immersiveSpaceId: String {
        switch self {
        case .hdriSkybox: return "hdriSkybox"
        case .customEnvironment: return "customEnvironment"
        case .cinemaEnvironment: return "cinemaEnvironment"
        }
    }

    var description: String {
        switch self {
        case .hdriSkybox: return "360-degree HDRI panoramic skybox"
        case .customEnvironment: return "User-imported 3D environment model"
        case .cinemaEnvironment: return "Configurable cinema screen with persistent seating and lighting controls"
        }
    }
}

enum NavigationLayout: String, CaseIterable, Sendable {
    case bottomTabBar = "bottom"
    case leftSidebar = "sidebar"

    var displayName: String {
        switch self {
        case .bottomTabBar: return "Bottom Tab Bar"
        case .leftSidebar: return "Left Sidebar"
        }
    }
}

enum ImmersiveDismissReason: Sendable, Equatable {
    case userInitiated
    case switchingEnvironment
    case suspension
    case memoryPressure
    case playerClosed
}
