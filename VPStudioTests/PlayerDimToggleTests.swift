import Foundation
import Testing
@testable import VPStudio

@Suite("Player Dim Passthrough Toggle")
@MainActor
struct PlayerDimToggleTests {
    // MARK: - Helpers

    private func makeDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, rootDir)
    }

    // MARK: - VPPlayerEngine Default

    @Test("isDimEnabled defaults to true")
    func defaultDimEnabledIsTrue() {
        let engine = VPPlayerEngine()
        #expect(engine.isDimEnabled == true)
    }

    // MARK: - Toggle State

    @Test("toggling isDimEnabled flips value")
    func toggleDimEnabled() {
        let engine = VPPlayerEngine()
        #expect(engine.isDimEnabled == true)

        engine.isDimEnabled = false
        #expect(engine.isDimEnabled == false)

        engine.isDimEnabled = true
        #expect(engine.isDimEnabled == true)
    }

    @Test("isDimEnabled can be explicitly set to false")
    func setDimEnabledFalse() {
        let engine = VPPlayerEngine()
        engine.isDimEnabled = false
        #expect(engine.isDimEnabled == false)
    }

    // MARK: - SettingsKeys

    @Test("playerDimPassthrough key has expected value")
    func settingsKeyValue() {
        #expect(SettingsKeys.playerDimPassthrough == "player_dim_passthrough")
    }

    // MARK: - Settings Persistence

    @Test("dim preference persists true through SettingsManager")
    func persistDimTrue() async throws {
        let (db, rootDir) = try await makeDatabase(named: "dim-true.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let settings = SettingsManager(database: db, secretStore: TestSecretStore())

        try await settings.setBool(key: SettingsKeys.playerDimPassthrough, value: true)
        let loaded = try await settings.getBool(key: SettingsKeys.playerDimPassthrough, default: false)
        #expect(loaded == true)
    }

    @Test("dim preference persists false through SettingsManager")
    func persistDimFalse() async throws {
        let (db, rootDir) = try await makeDatabase(named: "dim-false.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let settings = SettingsManager(database: db, secretStore: TestSecretStore())

        try await settings.setBool(key: SettingsKeys.playerDimPassthrough, value: false)
        let loaded = try await settings.getBool(key: SettingsKeys.playerDimPassthrough, default: true)
        #expect(loaded == false)
    }

    @Test("dim preference defaults to true when not set")
    func defaultFromSettingsIsTrue() async throws {
        let (db, rootDir) = try await makeDatabase(named: "dim-default.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let settings = SettingsManager(database: db, secretStore: TestSecretStore())

        let loaded = try await settings.getBool(key: SettingsKeys.playerDimPassthrough, default: true)
        #expect(loaded == true)
    }

    @Test("dim preference round-trip: set true, read, set false, read")
    func roundTripPersistence() async throws {
        let (db, rootDir) = try await makeDatabase(named: "dim-roundtrip.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let settings = SettingsManager(database: db, secretStore: TestSecretStore())

        // Initially unset, default is true
        var loaded = try await settings.getBool(key: SettingsKeys.playerDimPassthrough, default: true)
        #expect(loaded == true)

        // Set to false
        try await settings.setBool(key: SettingsKeys.playerDimPassthrough, value: false)
        loaded = try await settings.getBool(key: SettingsKeys.playerDimPassthrough, default: true)
        #expect(loaded == false)

        // Set back to true
        try await settings.setBool(key: SettingsKeys.playerDimPassthrough, value: true)
        loaded = try await settings.getBool(key: SettingsKeys.playerDimPassthrough, default: true)
        #expect(loaded == true)
    }

    @Test("engine state matches loaded preference value")
    func engineStateMatchesPreference() async throws {
        let (db, rootDir) = try await makeDatabase(named: "dim-engine-match.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let settings = SettingsManager(database: db, secretStore: TestSecretStore())

        // Simulate saving "off"
        try await settings.setBool(key: SettingsKeys.playerDimPassthrough, value: false)
        let loaded = try await settings.getBool(key: SettingsKeys.playerDimPassthrough, default: true)

        // Simulate the load pattern used by PlayerView
        let engine = VPPlayerEngine()
        engine.isDimEnabled = loaded
        #expect(engine.isDimEnabled == false)
    }
}
