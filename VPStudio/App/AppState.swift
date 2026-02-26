import AVFoundation
import Foundation
import Observation
import os

@Observable
@MainActor
final class AppState {
    private static let logger = Logger(subsystem: "com.vpstudio", category: "app-state")
    struct TestHooks: Sendable {
        var migrate: (@Sendable () async throws -> Void)?
        var initializeDebrid: (@Sendable () async throws -> Void)?
        var bootstrapEnvironments: (@Sendable () async throws -> Void)?
        var fetchActiveEnvironment: (@Sendable () async throws -> EnvironmentAsset?)?
        var fetchDebridConfigs: (@Sendable () async throws -> [DebridConfig])?
        var availableDebridServices: (@Sendable () async -> [DebridServiceType])?
        var initializeIndexers: (@Sendable () async throws -> Void)?

        nonisolated init(
            migrate: (@Sendable () async throws -> Void)? = nil,
            initializeDebrid: (@Sendable () async throws -> Void)? = nil,
            bootstrapEnvironments: (@Sendable () async throws -> Void)? = nil,
            fetchActiveEnvironment: (@Sendable () async throws -> EnvironmentAsset?)? = nil,
            fetchDebridConfigs: (@Sendable () async throws -> [DebridConfig])? = nil,
            availableDebridServices: (@Sendable () async -> [DebridServiceType])? = nil,
            initializeIndexers: (@Sendable () async throws -> Void)? = nil
        ) {
            self.migrate = migrate
            self.initializeDebrid = initializeDebrid
            self.bootstrapEnvironments = bootstrapEnvironments
            self.fetchActiveEnvironment = fetchActiveEnvironment
            self.fetchDebridConfigs = fetchDebridConfigs
            self.availableDebridServices = availableDebridServices
            self.initializeIndexers = initializeIndexers
        }
    }

    // MARK: - Navigation
    var selectedTab: SidebarTab = .discover
    var navigationLayout: NavigationLayout = .leftSidebar
    var isShowingSetup: Bool = false
    var setupRecommendationNeeded: Bool = false
    var navigationResetID: UUID = UUID()
    var isBootstrapping: Bool = true
    var runtimeDiagnosticsEnabled: Bool = false

    // MARK: - Warnings
    var environmentBootstrapWarning: String?

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
    private var _libraryCSVImportService: LibraryCSVImportService?
    private var _networkMonitor: NetworkMonitor?
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
        _settingsManager = settingsManager
        _debridManager = debridManager
        _indexerManager = indexerManager
        _downloadManager = downloadManager
        _environmentCatalogManager = environmentCatalogManager
        _libraryCSVImportService = libraryCSVImportService
        self.testHooks = testHooks
    }

    var database: DatabaseManager {
        if _database == nil {
            do {
                _database = try DatabaseManager()
            } catch {
                Self.logger.error("Database initialization failed: \(error.localizedDescription, privacy: .public). Falling back to temporary directory.")
                let fallbackDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("VPStudio", isDirectory: true)
                try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
                let fallbackPath = fallbackDir.appendingPathComponent("vpstudio-fallback.sqlite").path
                do {
                    _database = try DatabaseManager(path: fallbackPath)
                } catch {
                    // Second fallback: unique temp file — WAL mode requires a real file path.
                    Self.logger.error("Fallback DB also failed: \(error.localizedDescription, privacy: .public). Using temporary database.")
                    let tempPath = FileManager.default.temporaryDirectory
                        .appendingPathComponent("vpstudio-emergency.sqlite").path
                    _database = try? DatabaseManager(path: tempPath)
                }
            }
        }
        guard let db = _database else {
            fatalError("AppState.database accessed but no DatabaseManager could be created. Check file system permissions and disk space.")
        }
        return db
    }

    var secretStore: any SecretStore {
        if _secretStore == nil {
            _secretStore = KeychainSecretStore(serviceName: "com.vpstudio.credentials")
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
            _indexerManager = IndexerManager(database: database)
        }
        return _indexerManager!
    }

    var downloadManager: DownloadManager {
        if _downloadManager == nil {
            _downloadManager = DownloadManager(database: database)
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
                try? await settingsManager.setString(key: SettingsKeys.traktAccessToken, value: access)
                if let refresh {
                    try? await settingsManager.setString(key: SettingsKeys.traktRefreshToken, value: refresh)
                }
            }
        )

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

    func createMetadataService(apiKey: String) -> TMDBService {
        TMDBService(apiKey: apiKey)
    }

    // MARK: - Initialization

    func bootstrap() async {
        do {
            // Initialize the database eagerly so any filesystem errors surface here
            // rather than crashing later from an unexpected code path.
            if _database == nil {
                _database = try DatabaseManager()
            }

            if let migrate = testHooks.migrate {
                try await migrate()
            } else {
                try await database.migrate()
            }

            if let initializeDebrid = testHooks.initializeDebrid {
                try await initializeDebrid()
            } else {
                try await debridManager.initialize()
            }

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

            setupRecommendationNeeded = !hasDebridConfig || !hasReadyDebridService

            await configureAIProviders()

            runtimeDiagnosticsEnabled = (try? await settingsManager.getBool(
                key: SettingsKeys.runtimeDiagnosticsEnabled,
                default: false
            )) ?? false
        } catch {
            Self.logger.error("Bootstrap error: \(error.localizedDescription, privacy: .public)")
            isShowingSetup = true
        }
        // Auto-sync with Trakt on launch if credentials are available
        Task.detached { [weak self] in
            guard let self else { return }
            // Capture needed data from @MainActor context before entering detached task
            let traktClientId = try? await self.settingsManager.getString(key: SettingsKeys.traktClientId)
            let traktClientSecret = try? await self.settingsManager.getString(key: SettingsKeys.traktSecret)
            let database = self.database
            let settingsManager = self.settingsManager

            // Now create orchestrator off main actor using captured data
            guard let creds = TraktDefaults.resolvedCredentials(
                userClientId: traktClientId,
                userClientSecret: traktClientSecret
            ) else { return }

            let service = TraktSyncService(
                clientId: creds.clientId,
                clientSecret: creds.clientSecret,
                onTokensRefreshed: { [settingsManager] access, refresh in
                    try? await settingsManager.setString(key: SettingsKeys.traktAccessToken, value: access)
                    if let refresh {
                        try? await settingsManager.setString(key: SettingsKeys.traktRefreshToken, value: refresh)
                    }
                }
            )

            if let accessToken = try? await settingsManager.getString(key: SettingsKeys.traktAccessToken),
               !accessToken.isEmpty {
                let refreshToken = try? await settingsManager.getString(key: SettingsKeys.traktRefreshToken)
                await service.setTokens(access: accessToken, refresh: refreshToken)
            }

            let orchestrator = TraktSyncOrchestrator(
                traktService: service,
                database: database,
                settingsManager: settingsManager
            )

            let result = await orchestrator.sync()
            if result.totalPulled + result.totalPushed > 0 {
                await MainActor.run {
                    NotificationCenter.default.post(name: .tasteProfileDidChange, object: nil)
                }
            }
        }

        isBootstrapping = false
    }

    /// Loads saved API keys from settings and registers them with the AI assistant manager.
    /// Clears all providers first so stale registrations (e.g. Ollama) don't linger.
    func configureAIProviders() async {
        let anthropicKey = (try? await settingsManager.getString(key: SettingsKeys.anthropicApiKey)) ?? ""
        let openAIKey = (try? await settingsManager.getString(key: SettingsKeys.openAIApiKey)) ?? ""
        let geminiKey = (try? await settingsManager.getString(key: SettingsKeys.geminiApiKey)) ?? ""
        let ollamaURL = (try? await settingsManager.getString(key: SettingsKeys.ollamaEndpoint)) ?? "http://localhost:11434"
        let anthropicModel = try? await settingsManager.getString(key: SettingsKeys.anthropicModelPreset)
        let openAIModel = try? await settingsManager.getString(key: SettingsKeys.openAIModelPreset)
        let geminiModel = try? await settingsManager.getString(key: SettingsKeys.geminiModelPreset)
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
        // Only register Ollama if no cloud provider is available,
        // to avoid connection-refused errors to localhost when Ollama isn't running.
        let hasCloudProvider = !anthropicKey.isEmpty || !openAIKey.isEmpty || !geminiKey.isEmpty
        if !hasCloudProvider {
            await manager.configure(provider: .ollama, apiKey: "", baseURL: ollamaURL, model: ollamaModel)
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

    func consumeSuspendedImmersiveRestoreRequest() -> Bool {
        guard shouldRestoreImmersiveAfterSuspension else { return false }
        shouldRestoreImmersiveAfterSuspension = false
        return true
    }

    func resetAllData() async throws {
        // Delete all secrets from keychain
        try await secretStore.deleteAllSecrets()

        // Reset the database by running a destructive wipe
        try await database.resetAllData()

        // Clear in-memory state
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
    }

    func reloadIndexers() async {
        do {
            if let initializeIndexers = testHooks.initializeIndexers {
                try await initializeIndexers()
            } else {
                try await indexerManager.initialize()
            }
            NotificationCenter.default.post(name: .indexersDidChange, object: nil)
        } catch {
            Self.logger.warning("Indexer reload error: \(error.localizedDescription, privacy: .public)")
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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hdriSkybox: return "pano"
        case .customEnvironment: return "cube.transparent"
        }
    }

    var immersiveSpaceId: String {
        switch self {
        case .hdriSkybox: return "hdriSkybox"
        case .customEnvironment: return "customEnvironment"
        }
    }

    var description: String {
        switch self {
        case .hdriSkybox: return "360-degree HDRI panoramic skybox"
        case .customEnvironment: return "User-imported 3D environment model"
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
