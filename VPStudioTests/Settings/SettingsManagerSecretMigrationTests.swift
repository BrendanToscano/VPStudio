import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SettingsManagerSecretMigrationTests {
    struct CaseData: Sendable {
        let key: String
        let value: String
        let shouldStoreAsSecret: Bool
    }

    private static let knownSecretKeys: [String] = [
        SettingsKeys.tmdbApiKey,
        SettingsKeys.openSubtitlesApiKey,
        SettingsKeys.openAIApiKey,
        SettingsKeys.anthropicApiKey,
        SettingsKeys.traktClientId,
        SettingsKeys.traktClientSecret,
        SettingsKeys.traktAccessToken,
        SettingsKeys.traktRefreshToken,
        SettingsKeys.simklAccessToken,
    ]

    private static let nonSecretKeys: [String] = [
        SettingsKeys.preferredQuality,
        SettingsKeys.subtitleLanguage,
        SettingsKeys.subtitleFontSize,
        SettingsKeys.subtitleAutoSearch,
        SettingsKeys.autoPlayNext,
        SettingsKeys.hardwareDecoding,
        SettingsKeys.playerEngineStrategy,
        SettingsKeys.externalPlayerApp,
        SettingsKeys.externalPlayerURLTemplate,
        SettingsKeys.preferCachedStreams,
        SettingsKeys.preferAtmosAudio,
        SettingsKeys.preferredHDRFormat,
        SettingsKeys.defaultDebridService,
        SettingsKeys.defaultAIProvider,
        SettingsKeys.aiCompareMode,
        SettingsKeys.ollamaEndpoint,
        SettingsKeys.ollamaModelPreset,
        SettingsKeys.personalizationEnabled,
        SettingsKeys.preferredEnvironment,
        SettingsKeys.feedbackScaleMode,
        SettingsKeys.runtimeDiagnosticsEnabled,
        SettingsKeys.traktAutoScrobble,
        SettingsKeys.traktSyncWatchlist,
        SettingsKeys.traktSyncHistory,
    ]

    private static let migrationCases: [CaseData] = {
        let secretCases = knownSecretKeys.prefix(32).enumerated().map { idx, key in
            CaseData(key: key, value: "legacy-secret-\(idx)", shouldStoreAsSecret: true)
        }
        let nonSecretCases = nonSecretKeys.prefix(32).enumerated().map { idx, key in
            CaseData(key: key, value: "plain-\(idx)", shouldStoreAsSecret: false)
        }
        return Array(secretCases + nonSecretCases)
    }()

    struct BoolCase: Sendable {
        let storedValue: String?
        let defaultValue: Bool
        let expected: Bool
    }

    private static let boolCases: [BoolCase] = [
        BoolCase(storedValue: nil, defaultValue: true, expected: true),
        BoolCase(storedValue: nil, defaultValue: false, expected: false),
        BoolCase(storedValue: "1", defaultValue: false, expected: true),
        BoolCase(storedValue: "0", defaultValue: true, expected: false),
        BoolCase(storedValue: "true", defaultValue: false, expected: true),
        BoolCase(storedValue: "TRUE", defaultValue: false, expected: true),
        BoolCase(storedValue: "false", defaultValue: true, expected: false),
        BoolCase(storedValue: "FaLsE", defaultValue: true, expected: false),
        BoolCase(storedValue: "yes", defaultValue: true, expected: false),
        BoolCase(storedValue: "no", defaultValue: true, expected: false),
        BoolCase(storedValue: " 1 ", defaultValue: false, expected: false),
        BoolCase(storedValue: "", defaultValue: true, expected: false),
        BoolCase(storedValue: "random", defaultValue: true, expected: false),
        BoolCase(storedValue: "TRUE ", defaultValue: false, expected: false),
        BoolCase(storedValue: " false", defaultValue: true, expected: false),
        BoolCase(storedValue: "tRuE", defaultValue: false, expected: true),
        BoolCase(storedValue: "2", defaultValue: false, expected: false),
        BoolCase(storedValue: "-1", defaultValue: true, expected: false),
        BoolCase(storedValue: "on", defaultValue: false, expected: false),
        BoolCase(storedValue: "off", defaultValue: true, expected: false),
    ]

    @Test(arguments: ExhaustiveMode.choose(fast: Array(migrationCases.prefix(20)), full: migrationCases))
    func secretMigrationAndRetrieval(data: CaseData) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("settings.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()

        let secretStore = TestSecretStore()
        let manager = SettingsManager(database: database, secretStore: secretStore)

        // Write directly to DB to simulate legacy plaintext records.
        try await database.setSetting(key: data.key, value: data.value)

        let fetched = try await manager.getString(key: data.key)
        #expect(fetched == data.value)

        let stored = try await database.getSetting(key: data.key)
        if data.shouldStoreAsSecret {
            #expect(stored?.hasPrefix(SecretReference.keychainPrefix) == true)
            let secret = try await secretStore.getSecret(for: SecretKey.setting(data.key))
            #expect(secret == data.value)
        } else {
            #expect(stored == data.value)
        }
    }

    @Test(arguments: boolCases)
    func boolParsingBoundaries(data: BoolCase) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("settings-bool.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()
        let manager = SettingsManager(database: database, secretStore: TestSecretStore())

        try await database.setSetting(key: SettingsKeys.personalizationEnabled, value: data.storedValue)
        let parsed = try await manager.getBool(key: SettingsKeys.personalizationEnabled, default: data.defaultValue)

        #expect(parsed == data.expected)
    }

    @Test
    func settingSecretTrimsWhitespaceBeforePersisting() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("settings-trim.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()
        let secretStore = TestSecretStore()
        let manager = SettingsManager(database: database, secretStore: secretStore)

        try await manager.setString(key: SettingsKeys.tmdbApiKey, value: "  token-value  ")

        let persisted = try await manager.getString(key: SettingsKeys.tmdbApiKey)
        let storedSecret = try await secretStore.getSecret(for: SecretKey.setting(SettingsKeys.tmdbApiKey))
        #expect(persisted == "token-value")
        #expect(storedSecret == "token-value")
    }

    @Test
    func settingSecretWhitespaceOnlyClearsStoredSecret() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("settings-trim-clear.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()
        let secretStore = TestSecretStore()
        let manager = SettingsManager(database: database, secretStore: secretStore)

        try await manager.setString(key: SettingsKeys.tmdbApiKey, value: "token")
        try await manager.setString(key: SettingsKeys.tmdbApiKey, value: "   ")

        let persisted = try await manager.getString(key: SettingsKeys.tmdbApiKey)
        let raw = try await database.getSetting(key: SettingsKeys.tmdbApiKey)
        let storedSecret = try await secretStore.getSecret(for: SecretKey.setting(SettingsKeys.tmdbApiKey))

        #expect(persisted == nil)
        #expect(raw == nil)
        #expect(storedSecret == nil)
    }
}
