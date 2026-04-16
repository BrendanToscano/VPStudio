import Foundation
import CoreGraphics
import Testing
@testable import VPStudio

// MARK: - VPPlayerEngine Update Batching Tests

@Suite("VPPlayerEngine - Update Batching")
struct VPPlayerEngineUpdateBatchingTests {

    @Test @MainActor func errorDefaultsToNil() {
        let engine = VPPlayerEngine()
        #expect(engine.error == nil, "Engine error should start nil")
    }

    @Test @MainActor func redundantCurrentTimeSetDoesNotTriggerSubtitleUpdate() throws {
        let engine = VPPlayerEngine()
        engine.currentTime = 42.0

        // Load a real subtitle track with a cue at a different time (100-110s).
        // This ensures that if updateSubtitleText(at: 42.0) were called,
        // it would find no active cue and set currentSubtitleText to nil.
        let tmpDir = FileManager.default.temporaryDirectory
        let srtURL = tmpDir.appendingPathComponent("perf-test-\(UUID().uuidString).srt")
        let srtContent = "1\n00:01:40,000 --> 00:01:50,000\nDistant cue\n"
        try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: srtURL) }

        let subtitle = Subtitle(
            id: "perf-test",
            language: "en",
            fileName: srtURL.lastPathComponent,
            url: srtURL.absoluteString,
            format: .srt
        )
        engine.loadExternalSubtitles([subtitle])
        // Track 0 is auto-selected; updateSubtitleText(at: 42.0) finds no cue → text = nil
        #expect(engine.selectedSubtitleTrack == 0)

        // Manually set subtitle text to a sentinel value
        engine.currentSubtitleText = "Frozen subtitle"

        // Redundant set: currentTime is already 42.0
        engine.currentTime = 42.0
        #expect(engine.currentSubtitleText == "Frozen subtitle",
                "Subtitle text should not be disturbed when currentTime is set to same value")
    }

    @Test @MainActor func defaultEngineStateIsClean() {
        let engine = VPPlayerEngine()
        #expect(engine.isPlaying == false)
        #expect(engine.isBuffering == true)
        #expect(engine.currentTime == 0)
        #expect(engine.duration == 0)
        #expect(engine.videoSize == .zero)
        #expect(engine.playbackRate == 1.0)
    }

    @Test @MainActor func settingDifferentValuesUpdatesProperties() {
        let engine = VPPlayerEngine()

        engine.currentTime = 10.0
        #expect(engine.currentTime == 10.0)

        engine.duration = 100.0
        #expect(engine.duration == 100.0)

        engine.isBuffering = false
        #expect(engine.isBuffering == false)

        engine.videoSize = CGSize(width: 1920, height: 1080)
        #expect(engine.videoSize == CGSize(width: 1920, height: 1080))
    }
}

// MARK: - Environment Preset Curation Tests

@Suite("Environment Presets - Curation")
struct EnvironmentPresetCurationTests {

    @Test func onlinePresetsCountIsTwo() {
        let presets = EnvironmentCatalogManager.onlinePresets
        #expect(presets.count == 2, "Only cinema-themed presets should remain")
    }

    @Test func onlinePresetsContainPretvilleCinema() {
        let presets = EnvironmentCatalogManager.onlinePresets
        let pretville = presets.first(where: { $0.id == "polyhaven-pretville-cinema" })
        #expect(pretville != nil, "Pretville Cinema should be available")
        #expect(pretville?.name == "Pretville Cinema")
        #expect(pretville?.provider == .polyHaven)
        #expect(pretville?.licenseName == "CC0 1.0 Universal")
    }

    @Test func onlinePresetsContainCinemaHall() {
        let presets = EnvironmentCatalogManager.onlinePresets
        let cinemaHall = presets.first(where: { $0.id == "polyhaven-cinema-hall" })
        #expect(cinemaHall != nil, "Cinema Hall should be available")
        #expect(cinemaHall?.name == "Cinema Hall")
        #expect(cinemaHall?.provider == .polyHaven)
    }

    @Test func onlinePresetsDoNotContainTheaterStage() {
        let presets = EnvironmentCatalogManager.onlinePresets
        let theater = presets.first(where: { $0.id == "polyhaven-theater-01" })
        #expect(theater == nil, "Theater Stage should have been removed")
    }

    @Test func onlinePresetsDoNotContainTheaterBalcony() {
        let presets = EnvironmentCatalogManager.onlinePresets
        let theater = presets.first(where: { $0.id == "polyhaven-theater-02" })
        #expect(theater == nil, "Theater Balcony should have been removed")
    }

    @Test func allPresetsAreCinemaThemed() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            let nameLC = preset.name.lowercased()
            #expect(nameLC.contains("cinema"), "Preset '\(preset.name)' should be cinema-themed")
        }
    }

    @Test func allPresetsHaveValidDownloadURLs() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            #expect(preset.downloadURL.scheme == "https", "Preset \(preset.name) should use HTTPS")
            #expect(preset.downloadURL.pathExtension == "hdr", "Preset \(preset.name) should be .hdr format")
        }
    }

    @Test func allPresetsHaveAttributionURLs() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            #expect(!preset.sourceAttributionURL.isEmpty, "Preset \(preset.name) should have attribution URL")
            #expect(URL(string: preset.sourceAttributionURL) != nil, "Attribution URL should be valid")
        }
    }

    @Test func presetIDsAreUnique() {
        let presets = EnvironmentCatalogManager.onlinePresets
        let ids = Set(presets.map(\.id))
        #expect(ids.count == presets.count, "All preset IDs should be unique")
    }
}

// MARK: - Curated Defaults Tests

@Suite("Environment Catalog - Curated Defaults")
struct EnvironmentCatalogCuratedDefaultsTests {

    @Test func curatedDefaultsIsEmpty() async throws {
        // No bundled defaults — all environments are imported or downloaded
        let (database, rootDir) = try await makeDatabase(named: "curated-defaults-empty.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true)
        )
        try await manager.bootstrapCuratedAssets()

        let assets = try await manager.fetchAssets()
        let bundled = assets.filter { $0.sourceType == .bundled }
        #expect(bundled.isEmpty, "No bundled defaults should exist")
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

// MARK: - Immersive Space Routing Tests (regression)

@Suite("Environment - Immersive Space Routing")
struct EnvironmentImmersiveSpaceRoutingTests {

    @Test func hdriAssetRoutesToHdriSkybox() async throws {
        let (database, rootDir) = try await makeDatabase(named: "routing-hdri.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )

        let source = rootDir.appendingPathComponent("test.hdr")
        try Data("fake-hdr".utf8).write(to: source)
        let asset = try await manager.importEnvironment(from: source)

        let spaceID = await manager.immersiveSpaceID(for: asset)
        #expect(spaceID == "hdriSkybox")
    }

    @Test func exrAssetRoutesToHdriSkybox() async throws {
        let (database, rootDir) = try await makeDatabase(named: "routing-exr.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )

        let source = rootDir.appendingPathComponent("test.exr")
        try Data("fake-exr".utf8).write(to: source)
        let asset = try await manager.importEnvironment(from: source)

        let spaceID = await manager.immersiveSpaceID(for: asset)
        #expect(spaceID == "hdriSkybox")
    }

    @Test func usdzAssetRoutesToCustomEnvironment() async throws {
        let (database, rootDir) = try await makeDatabase(named: "routing-usdz.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )

        let source = rootDir.appendingPathComponent("test.usdz")
        try Data("fake-usdz".utf8).write(to: source)
        let asset = try await manager.importEnvironment(from: source)

        let spaceID = await manager.immersiveSpaceID(for: asset)
        #expect(spaceID == "customEnvironment")
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
