import Foundation
import Testing
@testable import VPStudio

@Suite("LocalModelCatalogStore", .serialized)
struct LocalModelCatalogStoreTests {
    @Test
    func seedCatalogIsIdempotentAndMarksDefaultModel() async throws {
        let (database, store, rootDir) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        await store.seedCatalog()
        await store.seedCatalog()

        let models = try await store.availableModels()
        #expect(models.count == 3)
        #expect(models.filter(\.isDefault).count == 1)
        #expect(models.allSatisfy { $0.status == .available })

        let databaseModels = try await database.fetchLocalModels()
        #expect(databaseModels.map(\.id).sorted() == models.map(\.id).sorted())
    }

    @Test
    func downloadedModelsOnlyReturnsDownloadedEntries() async throws {
        let (database, store, rootDir) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        try await database.saveLocalModel(makeModel(id: "available", status: .available))
        try await database.saveLocalModel(
            makeModel(id: "downloaded", status: .downloaded, localPath: rootDir.appendingPathComponent("model").path)
        )

        let downloaded = try await store.downloadedModels()

        #expect(downloaded.map(\.id) == ["downloaded"])
    }

    @Test
    func updateStatusHonorsStateMachineAndMissingModelsAreNoOp() async throws {
        let (database, store, rootDir) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        try await database.saveLocalModel(makeModel(id: "model", status: .available))

        try await store.updateStatus(id: "model", to: .downloaded, localPath: "/should-not-store")
        #expect(try await store.model(id: "model")?.status == .available)
        #expect(try await store.model(id: "model")?.localPath == nil)

        try await store.updateStatus(id: "model", to: .downloading)
        #expect(try await store.model(id: "model")?.status == .downloading)

        try await store.updateStatus(id: "missing", to: .downloading)
        #expect(try await store.model(id: "missing") == nil)
    }

    @Test
    func updateProgressAndResetToAvailablePersistNormalizedState() async throws {
        let (database, store, rootDir) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        try await database.saveLocalModel(makeModel(id: "model", status: .downloading))

        try await store.updateProgress(
            id: "model",
            progress: 0.55,
            downloadedBytes: 55,
            totalBytes: 100
        )
        var model = try #require(try await store.model(id: "model"))
        #expect(model.downloadProgress == 0.55)
        #expect(model.downloadedBytes == 55)
        #expect(model.totalBytes == 100)

        try await store.resetToAvailable(id: "model")
        model = try #require(try await store.model(id: "model"))
        #expect(model.status == .available)
        #expect(model.downloadProgress == 0)
        #expect(model.downloadedBytes == 0)
        #expect(model.localPath == nil)
        #expect(model.partialDownloadPath == nil)

        try await store.resetToAvailable(id: "missing")
        #expect(try await store.model(id: "missing") == nil)
    }

    private func makeStore() async throws -> (DatabaseManager, LocalModelCatalogStore, URL) {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let database = try DatabaseManager(path: rootDir.appendingPathComponent("local-models.sqlite").path)
        try await database.migrate()
        let store = LocalModelCatalogStore(database: database)
        return (database, store, rootDir)
    }

    private func makeModel(
        id: String,
        status: LocalModelStatus,
        localPath: String? = nil
    ) -> LocalModelDescriptor {
        LocalModelDescriptor(
            id: id,
            displayName: id,
            huggingFaceRepo: id,
            revision: "main",
            parameterCount: "1B",
            quantization: "float16",
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
            partialDownloadPath: status == .downloading ? "/tmp/partial" : nil,
            isDefault: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
