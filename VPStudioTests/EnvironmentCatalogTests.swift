import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct EnvironmentCatalogTests {
    @Test func importAndFetchEnvironmentAssetRoundTrip() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-import.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )
        try await manager.bootstrapCuratedAssets()

        let source = rootDir.appendingPathComponent("my-space.usdz")
        try Data("fake-usdz".utf8).write(to: source)

        let imported = try await manager.importEnvironment(from: source)
        let fetched = try await manager.fetchAssets()

        #expect(imported.sourceType == .imported)
        #expect(fetched.contains(where: { $0.id == imported.id }))
        #expect(FileManager.default.fileExists(atPath: imported.assetPath))
    }

    @Test func bootstrapHasNoBundledDefaults() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-bootstrap.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true)
        )
        try await manager.bootstrapCuratedAssets()

        let assets = try await manager.fetchAssets()
        let bundled = assets.filter { $0.sourceType == .bundled }
        #expect(bundled.isEmpty, "No bundled defaults — void was removed")
    }

    @Test func bootstrapRemovesStaleBundledAssetsButPreservesImported() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-stale.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let envDir = rootDir.appendingPathComponent("env", isDirectory: true)

        // Insert a fake old bundled asset that should be cleaned up
        let staleAsset = EnvironmentAsset(
            id: "builtin-theater",
            name: "Cinema Theater",
            sourceType: .bundled,
            assetPath: "theater",
            licenseName: "VPStudio Built-In",
            sourceAttributionURL: nil,
            previewImagePath: nil
        )
        try await database.saveEnvironmentAsset(staleAsset)

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: envDir,
            assetValidator: { _ in true }
        )

        // Import a real asset that should survive bootstrap
        let source = rootDir.appendingPathComponent("keeper.hdr")
        try Data("fake-hdr".utf8).write(to: source)
        let imported = try await manager.importEnvironment(from: source)

        try await manager.bootstrapCuratedAssets()

        let assets = try await manager.fetchAssets()
        #expect(!assets.contains(where: { $0.id == "builtin-theater" }), "Stale bundled theater should be removed")
        #expect(assets.contains(where: { $0.id == imported.id }), "Imported asset should survive bootstrap")
    }

    @Test func unsupportedFileTypeIsRejected() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-invalid-type.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true)
        )

        let source = rootDir.appendingPathComponent("bad.txt")
        try Data("invalid".utf8).write(to: source)

        do {
            _ = try await manager.importEnvironment(from: source)
            Issue.record("Expected EnvironmentCatalogError.unsupportedFileType")
        } catch let error as EnvironmentCatalogError {
            if case .unsupportedFileType = error {
                return
            }
            Issue.record("Unexpected EnvironmentCatalogError: \(error)")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func hdrFileTypeIsAccepted() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-hdr-type.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )

        let source = rootDir.appendingPathComponent("cinema.hdr")
        try Data("fake-hdr-data".utf8).write(to: source)

        let imported = try await manager.importEnvironment(from: source)
        #expect(imported.sourceType == .imported)
        #expect(imported.assetPath.hasSuffix(".hdr"))
    }

    @Test func exrFileTypeIsAccepted() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-exr-type.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )

        let source = rootDir.appendingPathComponent("skybox.exr")
        try Data("fake-exr-data".utf8).write(to: source)

        let imported = try await manager.importEnvironment(from: source)
        #expect(imported.sourceType == .imported)
        #expect(imported.assetPath.hasSuffix(".exr"))
    }

    @Test func invalidRealityAssetIsRejectedByValidator() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-invalid-validator.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in false }
        )

        let source = rootDir.appendingPathComponent("bad.usdz")
        try Data("not-loadable".utf8).write(to: source)

        do {
            _ = try await manager.importEnvironment(from: source)
            Issue.record("Expected EnvironmentCatalogError.invalidAsset")
        } catch let error as EnvironmentCatalogError {
            if case .invalidAsset = error {
                return
            }
            Issue.record("Unexpected EnvironmentCatalogError: \(error)")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func deletingActiveImportedEnvironmentFallsBackToRemainingAsset() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-fallback.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )

        // Import two assets so deleting one can fall back to the other
        let source1 = rootDir.appendingPathComponent("first.reality")
        try Data("fake-reality-1".utf8).write(to: source1)
        let source2 = rootDir.appendingPathComponent("second.reality")
        try Data("fake-reality-2".utf8).write(to: source2)

        let first = try await manager.importEnvironment(from: source1)
        let second = try await manager.importEnvironment(from: source2)
        try await manager.activateAsset(id: first.id)
        try await manager.deleteAsset(id: first.id)

        let active = try await manager.activeAsset()
        #expect(active != nil, "Should fall back to remaining asset after deleting active one")
        #expect(active?.id == second.id)
    }

    @Test func bundledAssetWithNoExtensionRoutesToCustomEnvironment() async throws {
        let (database, _) = try await makeDatabase(named: "environment-catalog-bundled-routing.sqlite")

        let bundled = EnvironmentAsset(
            id: "b1",
            name: "Some Bundled",
            sourceType: .bundled,
            assetPath: "some-asset",
            isActive: true
        )

        let manager = EnvironmentCatalogManager(database: database)
        let spaceID = await manager.immersiveSpaceID(for: bundled)
        #expect(spaceID == "customEnvironment")
    }

    @Test func importedHdrRoutesToHdriSkyboxImmersiveSpace() async throws {
        let (database, _) = try await makeDatabase(named: "environment-catalog-hdr-routing.sqlite")

        let imported = EnvironmentAsset(
            id: "i1",
            name: "Imported HDRI",
            sourceType: .imported,
            assetPath: "/tmp/cinema.hdr",
            isActive: false
        )

        let manager = EnvironmentCatalogManager(database: database)
        let spaceID = await manager.immersiveSpaceID(for: imported)
        #expect(spaceID == "hdriSkybox")
    }

    @Test func importedExrRoutesToHdriSkyboxImmersiveSpace() async throws {
        let (database, _) = try await makeDatabase(named: "environment-catalog-exr-routing.sqlite")

        let imported = EnvironmentAsset(
            id: "i2",
            name: "Imported EXR",
            sourceType: .imported,
            assetPath: "/tmp/skybox.exr",
            isActive: false
        )

        let manager = EnvironmentCatalogManager(database: database)
        let spaceID = await manager.immersiveSpaceID(for: imported)
        #expect(spaceID == "hdriSkybox")
    }

    @Test func importedUsdzRoutesToCustomEnvironmentImmersiveSpace() async throws {
        let (database, _) = try await makeDatabase(named: "environment-catalog-usdz-routing.sqlite")

        let imported = EnvironmentAsset(
            id: "i3",
            name: "Imported USDZ",
            sourceType: .imported,
            assetPath: "/tmp/model.usdz",
            isActive: false
        )

        let manager = EnvironmentCatalogManager(database: database)
        let spaceID = await manager.immersiveSpaceID(for: imported)
        #expect(spaceID == "customEnvironment")
    }

    @Test func importedRealityRoutesToCustomEnvironmentImmersiveSpace() async throws {
        let (database, _) = try await makeDatabase(named: "environment-catalog-reality-routing.sqlite")

        let imported = EnvironmentAsset(
            id: "i4",
            name: "Imported Reality",
            sourceType: .imported,
            assetPath: "/tmp/scene.reality",
            isActive: false
        )

        let manager = EnvironmentCatalogManager(database: database)
        let spaceID = await manager.immersiveSpaceID(for: imported)
        #expect(spaceID == "customEnvironment")
    }

    @Test func onlinePresetsContainPolyHavenHDRIs() {
        let presets = EnvironmentCatalogManager.onlinePresets
        #expect(!presets.isEmpty)
        #expect(presets.allSatisfy { $0.provider == .polyHaven })
        #expect(
            presets.allSatisfy {
                let ext = $0.downloadURL.pathExtension.lowercased()
                return ext == "hdr" || ext == "exr"
            }
        )
    }

    @Test func remoteImportRoundTripPersistsMetadata() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-remote-import.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("remote-hdr".utf8), response)
            }
        )

        let imported = try await manager.importEnvironment(
            fromRemote: URL(string: "https://dl.polyhaven.org/file/test.hdr")!,
            preferredName: "Remote HDRI",
            licenseName: "CC0 1.0 Universal",
            sourceAttributionURL: "https://polyhaven.com/a/test",
            previewImagePath: nil
        )
        let assets = try await manager.fetchAssets()
        let stored = assets.first(where: { $0.id == imported.id })

        #expect(stored != nil)
        #expect(stored?.name == "Remote HDRI")
        #expect(stored?.licenseName == "CC0 1.0 Universal")
        #expect(stored?.sourceAttributionURL == "https://polyhaven.com/a/test")
        #expect(FileManager.default.fileExists(atPath: imported.assetPath))
    }

    @Test func curatedPresetImportIsDeduplicatedByNameAndSource() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-curated-dedupe.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("remote-hdr-data".utf8), response)
            }
        )

        guard let preset = EnvironmentCatalogManager.onlinePresets.first else {
            Issue.record("Expected at least one online preset")
            return
        }

        let first = try await manager.importCuratedPreset(preset)
        let second = try await manager.importCuratedPreset(preset)
        let imported = try await manager.fetchAssets().filter {
            $0.sourceType == .imported
                && $0.name == preset.name
                && $0.sourceAttributionURL == preset.sourceAttributionURL
        }

        #expect(first.id == second.id)
        #expect(imported.count == 1)
    }

    @Test func remoteImportWithHTTPErrorThrowsDownloadFailed() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-http-error.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
        )

        do {
            _ = try await manager.importEnvironment(
                fromRemote: URL(string: "https://example.com/missing.hdr")!
            )
            Issue.record("Expected download failure")
        } catch let error as EnvironmentCatalogError {
            if case .downloadFailed = error {
                return
            }
            Issue.record("Expected downloadFailed, got \(error)")
        }
    }

    @Test func remoteImportWithEmptyDataThrowsDownloadFailed() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-empty-data.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
        )

        do {
            _ = try await manager.importEnvironment(
                fromRemote: URL(string: "https://example.com/empty.hdr")!
            )
            Issue.record("Expected download failure for empty data")
        } catch let error as EnvironmentCatalogError {
            if case .downloadFailed = error {
                return
            }
            Issue.record("Expected downloadFailed, got \(error)")
        }
    }

    @Test func missingLocalFileThrowsMissingFile() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-missing-file.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true)
        )

        let nonexistent = rootDir.appendingPathComponent("doesnt-exist.hdr")

        do {
            _ = try await manager.importEnvironment(from: nonexistent)
            Issue.record("Expected EnvironmentCatalogError.missingFile")
        } catch let error as EnvironmentCatalogError {
            if case .missingFile = error {
                return
            }
            Issue.record("Expected missingFile, got \(error)")
        }
    }

    @Test func importWithYawOffsetPersistsThroughRoundTrip() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-yaw-offset.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("fake-hdr".utf8), response)
            }
        )

        let imported = try await manager.importEnvironment(
            fromRemote: URL(string: "https://example.com/cinema.hdr")!,
            preferredName: "Cinema",
            licenseName: "CC0",
            sourceAttributionURL: "https://example.com",
            previewImagePath: nil,
            hdriYawOffset: 45.0
        )

        let assets = try await manager.fetchAssets()
        let stored = assets.first(where: { $0.id == imported.id })

        #expect(stored != nil)
        #expect(stored?.hdriYawOffset == 45.0)
    }

    @Test func importWithNilYawOffsetPersistsAsNil() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-yaw-nil.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("fake-hdr".utf8), response)
            }
        )

        let imported = try await manager.importEnvironment(
            fromRemote: URL(string: "https://example.com/sky.hdr")!,
            preferredName: "Sky"
        )

        let assets = try await manager.fetchAssets()
        let stored = assets.first(where: { $0.id == imported.id })

        #expect(stored != nil)
        #expect(stored?.hdriYawOffset == nil)
    }

    @Test func curatedPresetPassesYawOffsetThrough() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-curated-yaw.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("fake-hdr-preset".utf8), response)
            }
        )

        let preset = CuratedEnvironmentPreset(
            id: "yaw-test",
            name: "Yaw Test Cinema",
            description: "Test preset with yaw offset",
            provider: .polyHaven,
            downloadURL: URL(string: "https://dl.polyhaven.org/file/test_yaw.hdr")!,
            sourceAttributionURL: "https://polyhaven.com/a/test_yaw",
            licenseName: "CC0 1.0 Universal",
            defaultHdriYawOffset: -30.0
        )

        let imported = try await manager.importCuratedPreset(preset)
        let assets = try await manager.fetchAssets()
        let stored = assets.first(where: { $0.id == imported.id })

        #expect(stored != nil)
        #expect(stored?.hdriYawOffset == -30.0)
    }

    @Test func localImportDefaultsYawOffsetToNil() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-local-yaw.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )

        let source = rootDir.appendingPathComponent("local.hdr")
        try Data("fake-hdr".utf8).write(to: source)

        let imported = try await manager.importEnvironment(from: source)
        #expect(imported.hdriYawOffset == nil, "Local imports should default to nil yaw offset")
    }

    @Test func hdriYawOffsetDatabaseMigrationAddsColumn() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-migration-yaw.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        // Save an asset with yaw offset to confirm column exists after migration
        let asset = EnvironmentAsset(
            id: "migration-test",
            name: "Migration Test",
            sourceType: .imported,
            assetPath: "/tmp/test.hdr",
            hdriYawOffset: 180.0
        )
        try await database.saveEnvironmentAsset(asset)

        let fetched = try await database.fetchEnvironmentAssets()
        let stored = fetched.first(where: { $0.id == "migration-test" })
        #expect(stored?.hdriYawOffset == 180.0)
    }

    @Test func bootstrapPrunesImportedAssetsWhoseFilesAreMissing() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-prune-missing.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let envDir = rootDir.appendingPathComponent("env", isDirectory: true)
        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: envDir,
            assetValidator: { _ in true }
        )

        // Create a real file and import it.
        let source = rootDir.appendingPathComponent("temp.hdr")
        try Data("fake-hdr".utf8).write(to: source)
        let imported = try await manager.importEnvironment(from: source)

        // First bootstrap — asset still has its backing file.
        try await manager.bootstrapCuratedAssets()
        var assets = try await manager.fetchAssets()
        #expect(assets.contains(where: { $0.id == imported.id }), "Asset should survive bootstrap when file exists")

        // Delete the backing file, simulating app reinstall / manual deletion.
        try FileManager.default.removeItem(atPath: imported.assetPath)

        // Second bootstrap — should prune the orphan.
        try await manager.bootstrapCuratedAssets()
        assets = try await manager.fetchAssets()
        #expect(!assets.contains(where: { $0.id == imported.id }), "Orphaned imported asset should be pruned on second bootstrap")
    }

    @Test func bootstrapPrunesOnEveryCallNotJustFirstLaunch() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-prune-every-launch.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let envDir = rootDir.appendingPathComponent("env", isDirectory: true)
        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: envDir,
            assetValidator: { _ in true }
        )

        // Run bootstrap once (simulating first launch).
        try await manager.bootstrapCuratedAssets()

        // Import an asset after first bootstrap.
        let source = rootDir.appendingPathComponent("late.hdr")
        try Data("fake-hdr-late".utf8).write(to: source)
        let imported = try await manager.importEnvironment(from: source)

        // Delete the backing file.
        try FileManager.default.removeItem(atPath: imported.assetPath)

        // Run bootstrap again (simulating second launch).
        try await manager.bootstrapCuratedAssets()
        let assets = try await manager.fetchAssets()
        #expect(!assets.contains(where: { $0.id == imported.id }), "Asset imported after first bootstrap should still be pruned on subsequent bootstrap")
    }

    @Test func localImportFailsCleanlyIfSourceDisappearsDuringValidationRace() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-local-race.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let validationGate = ValidationGate()
        let envDir = rootDir.appendingPathComponent("env", isDirectory: true)
        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: envDir,
            assetValidator: { url in
                await validationGate.validate(url: url)
            }
        )

        let source = rootDir.appendingPathComponent("race.hdr")
        try Data("fake-hdr".utf8).write(to: source)

        let importTask = Task { try await manager.importEnvironment(from: source) }
        await validationGate.waitForValidationStart()

        try FileManager.default.removeItem(at: source)
        await validationGate.allowValidationToContinue()

        do {
            _ = try await importTask.value
            Issue.record("Expected import to fail after source file deletion")
        } catch {
            // Expected: copy from source should fail once file is removed.
        }

        let assets = try await manager.fetchAssets()
        #expect(assets.isEmpty)
    }

    @Test func cancelledRemoteImportDoesNotPersistAssetsOrTempFiles() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-remote-cancel.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let fetchGate = CancellableRemoteFetchGate()
        let envDir = rootDir.appendingPathComponent("env", isDirectory: true)
        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: envDir,
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                try await fetchGate.fetch(url: url)
            }
        )

        let importTask = Task {
            try await manager.importEnvironment(fromRemote: URL(string: "https://example.com/cancel.hdr")!)
        }

        await fetchGate.waitForFetchStart()
        importTask.cancel()

        do {
            _ = try await importTask.value
            Issue.record("Expected remote import cancellation to throw")
        } catch let error as EnvironmentCatalogError {
            if case .downloadFailed = error {
                // Expected because cancellation is wrapped as a download failure.
            } else {
                Issue.record("Expected downloadFailed error, got: \(error)")
            }
        } catch {
            Issue.record("Expected EnvironmentCatalogError, got: \(error)")
        }

        let assets = try await manager.fetchAssets()
        #expect(assets.isEmpty)

        if FileManager.default.fileExists(atPath: envDir.path) {
            let files = try FileManager.default.contentsOfDirectory(atPath: envDir.path)
            #expect(files.isEmpty)
        }
    }

    private func makeDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, rootDir)
    }

    @Test func environmentAssetCountReflectsImportedAssets() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-count.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true }
        )

        // Initially should be empty
        var assets = try await manager.fetchAssets()
        #expect(assets.count == 0)

        // Import one asset
        let source1 = rootDir.appendingPathComponent("cinema1.hdr")
        try Data("fake-hdr-1".utf8).write(to: source1)
        _ = try await manager.importEnvironment(from: source1)

        assets = try await manager.fetchAssets()
        #expect(assets.count == 1)

        // Import second asset
        let source2 = rootDir.appendingPathComponent("cinema2.hdr")
        try Data("fake-hdr-2".utf8).write(to: source2)
        _ = try await manager.importEnvironment(from: source2)

        assets = try await manager.fetchAssets()
        #expect(assets.count == 2)
    }

    @Test func importingCuratedPresetNotifiesEnvironmentsChanged() async throws {
        let (database, rootDir) = try await makeDatabase(named: "environment-catalog-notify.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .environmentsDidChange,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let manager = EnvironmentCatalogManager(
            database: database,
            environmentsDirectory: rootDir.appendingPathComponent("env", isDirectory: true),
            assetValidator: { _ in true },
            remoteDataFetcher: { url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data("fake-hdr".utf8), response)
            }
        )

        let preset = CuratedEnvironmentPreset(
            id: "test-preset",
            name: "Test Cinema",
            description: "Test preset",
            provider: .polyHaven,
            downloadURL: URL(string: "https://example.com/test.hdr")!,
            sourceAttributionURL: "https://example.com",
            licenseName: "CC0"
        )

        _ = try await manager.importCuratedPreset(preset)

        // Allow time for notification to propagate
        try await Task.sleep(for: .milliseconds(100))

        #expect(notificationReceived, "Notification should be sent after importing preset")
    }
}

private actor ValidationGate {
    private var validationStartedContinuation: CheckedContinuation<Void, Never>?
    private var validationContinuation: CheckedContinuation<Bool, Never>?

    func validate(url _: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            validationContinuation = continuation
            validationStartedContinuation?.resume()
            validationStartedContinuation = nil
        }
    }

    func waitForValidationStart() async {
        if validationContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            validationStartedContinuation = continuation
        }
    }

    func allowValidationToContinue(result: Bool = true) {
        validationContinuation?.resume(returning: result)
        validationContinuation = nil
    }
}

private actor CancellableRemoteFetchGate {
    private var fetchStartedContinuation: CheckedContinuation<Void, Never>?
    private var fetchContinuation: CheckedContinuation<(Data, URLResponse), Error>?

    func fetch(url: URL) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    fetchContinuation = continuation
                    fetchStartedContinuation?.resume()
                    fetchStartedContinuation = nil
                }
            },
            onCancel: {
                Task { await self.resumeFetchIfNeeded(throwing: CancellationError()) }
            }
        )
    }

    func waitForFetchStart() async {
        if fetchContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            fetchStartedContinuation = continuation
        }
    }

    private func resumeFetchIfNeeded(throwing error: Error) {
        fetchContinuation?.resume(throwing: error)
        fetchContinuation = nil
    }
}
