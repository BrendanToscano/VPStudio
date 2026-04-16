import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct LocalDownloadServiceTests {
    private final class ControlledSnapshotDownloader: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [String: CheckedContinuation<URL, Error>] = [:]
        private var startedRepos: [String] = []

        func downloader(
            repo: String,
            progressHandler: @escaping @Sendable (Progress) -> Void
        ) async throws -> URL {
            _ = progressHandler
            lock.lock()
            startedRepos.append(repo)
            lock.unlock()

            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                continuations[repo] = continuation
                lock.unlock()
            }
        }

        func waitUntilStarted(repo: String) async {
            while true {
                lock.lock()
                let started = startedRepos.contains(repo)
                lock.unlock()
                if started { return }
                await Task.yield()
            }
        }

        func started(repo: String) -> Bool {
            lock.lock()
            let didStart = startedRepos.contains(repo)
            lock.unlock()
            return didStart
        }

        func fail(repo: String, error: some Error) {
            lock.lock()
            let continuation = continuations.removeValue(forKey: repo)
            lock.unlock()
            continuation?.resume(throwing: error)
        }
    }

    private func makeTemporaryDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, tempDir)
    }

    private func makeLocalModel(
        id: String,
        displayName: String
    ) -> LocalModelDescriptor {
        let now = Date()
        return LocalModelDescriptor(
            id: id,
            displayName: displayName,
            huggingFaceRepo: id,
            revision: "main",
            parameterCount: "360M",
            quantization: "float16",
            diskSizeMB: 700,
            minMemoryMB: 800,
            expectedFileCount: 5,
            maxContextTokens: 2_048,
            effectivePromptCap: 2_048,
            effectiveOutputCap: 1_024,
            status: .available,
            downloadProgress: 0,
            downloadedBytes: 0,
            totalBytes: 0,
            lastProgressAt: nil,
            checksumSHA256: nil,
            validationState: .pending,
            localPath: nil,
            partialDownloadPath: nil,
            isDefault: false,
            createdAt: now,
            updatedAt: now
        )
    }

    @Test
    func staleCleanupTokenDoesNotClearNewerActiveDownload() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "local-download-race.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let first = makeLocalModel(id: "apple/first-model", displayName: "First")
        let second = makeLocalModel(id: "apple/second-model", displayName: "Second")
        let third = makeLocalModel(id: "apple/third-model", displayName: "Third")
        try await database.saveLocalModel(first)
        try await database.saveLocalModel(second)
        try await database.saveLocalModel(third)

        let store = LocalModelCatalogStore(database: database)
        let downloader = ControlledSnapshotDownloader()
        let service = LocalDownloadService(catalogStore: store, snapshotDownloader: downloader.downloader)

        await service.downloadModel(id: first.id)
        await downloader.waitUntilStarted(repo: first.huggingFaceRepo)
        let firstState = await service.activeDownloadStateForTesting()
        #expect(firstState.modelID == first.id)
        #expect(firstState.token != nil)

        await service.cancelDownload(id: first.id)
        await service.downloadModel(id: second.id)
        await downloader.waitUntilStarted(repo: second.huggingFaceRepo)
        let secondState = await service.activeDownloadStateForTesting()
        #expect(secondState.modelID == second.id)
        #expect(secondState.token != nil)

        await service.clearActiveTaskIfCurrentForTesting(
            token: try #require(firstState.token),
            modelID: first.id
        )

        await service.downloadModel(id: third.id)
        #expect(!downloader.started(repo: third.huggingFaceRepo))

        let currentState = await service.activeDownloadStateForTesting()
        #expect(currentState.modelID == second.id)
        #expect(currentState.token == secondState.token)

        downloader.fail(repo: first.huggingFaceRepo, error: CancellationError())
        downloader.fail(repo: second.huggingFaceRepo, error: CancellationError())
    }

    @Test
    func matchingCleanupTokenClearsActiveDownloadState() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "local-download-token-clear.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeLocalModel(id: "apple/test-model", displayName: "Test")
        try await database.saveLocalModel(model)

        let store = LocalModelCatalogStore(database: database)
        let downloader = ControlledSnapshotDownloader()
        let service = LocalDownloadService(catalogStore: store, snapshotDownloader: downloader.downloader)

        await service.downloadModel(id: model.id)
        await downloader.waitUntilStarted(repo: model.huggingFaceRepo)
        let state = await service.activeDownloadStateForTesting()
        #expect(state.modelID == model.id)

        await service.clearActiveTaskIfCurrentForTesting(
            token: try #require(state.token),
            modelID: model.id
        )

        let clearedState = await service.activeDownloadStateForTesting()
        #expect(clearedState.modelID == nil)
        #expect(clearedState.token == nil)

        downloader.fail(repo: model.huggingFaceRepo, error: CancellationError())
    }
}
