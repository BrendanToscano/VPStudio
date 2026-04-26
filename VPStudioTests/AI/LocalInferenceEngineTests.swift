import Foundation
import Testing
@testable import VPStudio

@Suite("Local Inference Engine")
struct LocalInferenceEngineTests {
    private struct ThrowingAdapter: LocalInferenceAdapting {
        var errorMessage: String

        func loadModel(from directory: URL) async throws -> LoadedLocalModel {
            throw LocalInferenceError.inferenceError("\(errorMessage): \(directory.lastPathComponent)")
        }

        func generate(
            model: LoadedLocalModel,
            system: String,
            userMessage: String,
            maxTokens: Int
        ) async throws -> LocalGenerationResult {
            throw LocalInferenceError.inferenceError("generation should not run")
        }
    }

    @Test
    func checkMemoryForUnknownModelReturnsInsufficientSentinel() async throws {
        let (engine, _, _, tempDir) = try await makeEngine()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let availability = await engine.checkMemory(for: "missing-model")

        if case .insufficient(let availableMB, let requiredMB) = availability {
            #expect(availableMB == 0)
            #expect(requiredMB == 0)
        } else {
            Issue.record("Expected missing models to report insufficient memory sentinel")
        }
    }

    @Test
    func checkMemoryClassifiesOkTightAndInsufficientThresholds() async throws {
        let (database, store, tempDir) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeModel(id: "local/memory-threshold", status: .downloaded, localPath: tempDir.path)
        try await database.saveLocalModel(model)

        let okEngine = LocalInferenceEngine(
            catalogStore: store,
            availableMemoryProvider: { UInt64(model.minMemoryMB * 2) * 1_048_576 }
        )
        let tightEngine = LocalInferenceEngine(
            catalogStore: store,
            availableMemoryProvider: { UInt64(model.minMemoryMB) * 1_048_576 }
        )
        let insufficientEngine = LocalInferenceEngine(
            catalogStore: store,
            availableMemoryProvider: { UInt64(model.minMemoryMB - 1) * 1_048_576 }
        )

        if case .ok = await okEngine.checkMemory(for: model.id) {
            #expect(Bool(true))
        } else {
            Issue.record("Expected enough memory to be classified as ok")
        }

        if case .tight(let availableMB, let requiredMB) = await tightEngine.checkMemory(for: model.id) {
            #expect(availableMB == model.minMemoryMB)
            #expect(requiredMB == model.minMemoryMB)
        } else {
            Issue.record("Expected single-threshold memory to be classified as tight")
        }

        if case .insufficient(let availableMB, let requiredMB) = await insufficientEngine.checkMemory(for: model.id) {
            #expect(availableMB == model.minMemoryMB - 1)
            #expect(requiredMB == model.minMemoryMB)
        } else {
            Issue.record("Expected below-threshold memory to be classified as insufficient")
        }
    }

    @Test
    func loadModelThrowsWhenDescriptorIsNotDownloaded() async throws {
        let (engine, _, database, tempDir) = try await makeEngine()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeModel(id: "local/not-downloaded", status: .available, localPath: nil)
        try await database.saveLocalModel(model)

        do {
            try await engine.loadModel(id: model.id)
            Issue.record("Expected loadModel to reject unavailable local models")
        } catch LocalInferenceError.modelNotDownloaded {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func loadModelThrowsWhenDownloadedDescriptorHasNoLocalPath() async throws {
        let (engine, _, database, tempDir) = try await makeEngine()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeModel(id: "local/downloaded-missing-path", status: .downloaded, localPath: nil)
        try await database.saveLocalModel(model)

        do {
            try await engine.loadModel(id: model.id)
            Issue.record("Expected loadModel to reject downloaded descriptors without local paths")
        } catch LocalInferenceError.modelNotDownloaded {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func loadModelPropagatesAdapterLoadFailureForDownloadedDescriptor() async throws {
        let (database, store, tempDir) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelDir = tempDir.appendingPathComponent("AdapterModel", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let model = makeModel(id: "local/adapter-failure", status: .downloaded, localPath: modelDir.path)
        try await database.saveLocalModel(model)
        let engine = LocalInferenceEngine(
            catalogStore: store,
            adapter: ThrowingAdapter(errorMessage: "adapter failed")
        )

        do {
            try await engine.loadModel(id: model.id)
            Issue.record("Expected adapter failure to propagate")
        } catch LocalInferenceError.inferenceError(let message) {
            #expect(message.contains("adapter failed"))
            #expect(message.contains(modelDir.lastPathComponent))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: [1, 255])
    func loadModelContinuesThroughMemoryPreflightWarnings(availableMemoryMB: Int) async throws {
        let (database, store, tempDir) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelDir = tempDir.appendingPathComponent("MemoryWarningModel", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let model = makeModel(id: "local/memory-warning-\(availableMemoryMB)", status: .downloaded, localPath: modelDir.path)
        try await database.saveLocalModel(model)
        let engine = LocalInferenceEngine(
            catalogStore: store,
            adapter: ThrowingAdapter(errorMessage: "load attempted"),
            availableMemoryProvider: { UInt64(availableMemoryMB) * 1_048_576 }
        )

        do {
            try await engine.loadModel(id: model.id)
            Issue.record("Expected adapter failure after memory preflight")
        } catch LocalInferenceError.inferenceError(let message) {
            #expect(message.contains("load attempted"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func generateThrowsWhenModelIsNotDownloaded() async throws {
        let (engine, _, database, tempDir) = try await makeEngine()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeModel(id: "local/generate-missing", status: .available, localPath: nil)
        try await database.saveLocalModel(model)

        do {
            _ = try await engine.generate(modelID: model.id, system: "system", userMessage: "hello")
            Issue.record("Expected generate to reject unavailable local models")
        } catch LocalInferenceError.modelNotDownloaded {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func localProviderSurfacesMissingModelError() async throws {
        let (engine, _, database, tempDir) = try await makeEngine()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeModel(id: "local/provider-missing", status: .available, localPath: nil)
        try await database.saveLocalModel(model)
        let provider = LocalMLXProvider(inferenceEngine: engine, modelID: model.id)

        do {
            _ = try await provider.complete(system: "system", userMessage: "hello")
            Issue.record("Expected local provider to surface missing-model failures")
        } catch LocalInferenceError.modelNotDownloaded {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func unloadAndForceUnloadAreIdempotentWhenNothingIsLoaded() async throws {
        let (engine, _, _, tempDir) = try await makeEngine()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await engine.unloadModel()
        await engine.forceUnload()
    }

    @Test
    func monitoringCanStartStopAndRestart() async throws {
        let (engine, _, _, tempDir) = try await makeEngine()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await engine.startMonitoring()
        await engine.stopMonitoring()
        await engine.startMonitoring()
        await engine.stopMonitoring()
    }

    @Test(arguments: [
        (LocalInferenceError.modelNotDownloaded, "Model not downloaded."),
        (LocalInferenceError.insufficientMemory(availableMB: 512, requiredMB: 2_048), "512MB available, 2048MB required."),
        (LocalInferenceError.generationTimeout, "Generation timed out"),
        (LocalInferenceError.inferenceError("tokenizer missing"), "tokenizer missing"),
    ])
    func localInferenceErrorsDescribeRecoveryContext(error: LocalInferenceError, expectedFragment: String) {
        #expect(error.errorDescription?.contains(expectedFragment) == true)
    }

    private func makeEngine() async throws -> (LocalInferenceEngine, LocalModelCatalogStore, DatabaseManager, URL) {
        let (database, store, tempDir) = try await makeStore()
        return (LocalInferenceEngine(catalogStore: store), store, database, tempDir)
    }

    private func makeStore() async throws -> (DatabaseManager, LocalModelCatalogStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let database = try DatabaseManager(path: tempDir.appendingPathComponent("local-inference.sqlite").path)
        try await database.migrate()
        let store = LocalModelCatalogStore(database: database)
        return (database, store, tempDir)
    }

    private func makeModel(id: String, status: LocalModelStatus, localPath: String?) -> LocalModelDescriptor {
        LocalModelDescriptor(
            id: id,
            displayName: "Test Model",
            huggingFaceRepo: id,
            revision: "main",
            parameterCount: "1B",
            quantization: "4bit",
            diskSizeMB: 100,
            minMemoryMB: 256,
            expectedFileCount: 1,
            maxContextTokens: 2_048,
            effectivePromptCap: 1_024,
            effectiveOutputCap: 512,
            status: status,
            downloadProgress: status == .downloaded ? 1 : 0,
            downloadedBytes: 0,
            totalBytes: 0,
            lastProgressAt: nil,
            checksumSHA256: nil,
            validationState: .pending,
            localPath: localPath,
            partialDownloadPath: nil,
            isDefault: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
