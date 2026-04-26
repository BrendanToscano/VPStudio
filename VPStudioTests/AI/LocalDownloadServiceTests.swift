import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct LocalDownloadServiceTests {
    private final class ControlledSnapshotDownloader: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [String: CheckedContinuation<URL, Error>] = [:]
        private var startedRepos: [String] = []
        private var progressHandlers: [String: @Sendable (Progress) -> Void] = [:]

        func downloader(
            repo: String,
            progressHandler: @escaping @Sendable (Progress) -> Void
        ) async throws -> URL {
            recordStarted(repo: repo)
            storeProgressHandler(progressHandler, for: repo)

            return try await withCheckedThrowingContinuation { continuation in
                storeContinuation(continuation, for: repo)
            }
        }

        func waitUntilStarted(repo: String) async {
            while true {
                if readyToResume(repo: repo) { return }
                await Task.yield()
            }
        }

        func started(repo: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let didStart = startedRepos.contains(repo)
            return didStart
        }

        func startCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return startedRepos.count
        }

        func readyToResume(repo: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return startedRepos.contains(repo) && continuations[repo] != nil
        }

        func reportProgress(repo: String, completed: Int64, total: Int64) {
            let handler: (@Sendable (Progress) -> Void)? = {
                lock.lock()
                defer { lock.unlock() }
                return progressHandlers[repo]
            }()
            let progress = Progress(totalUnitCount: total)
            progress.completedUnitCount = completed
            handler?(progress)
        }

        func complete(repo: String, url: URL) {
            let continuation = takeContinuation(for: repo)
            continuation?.resume(returning: url)
        }

        func fail(repo: String, error: some Error) {
            let continuation = takeContinuation(for: repo)
            continuation?.resume(throwing: error)
        }

        private func recordStarted(repo: String) {
            lock.lock()
            defer { lock.unlock() }
            startedRepos.append(repo)
        }

        private func storeContinuation(_ continuation: CheckedContinuation<URL, Error>, for repo: String) {
            lock.lock()
            defer { lock.unlock() }
            continuations[repo] = continuation
        }

        private func storeProgressHandler(_ progressHandler: @escaping @Sendable (Progress) -> Void, for repo: String) {
            lock.lock()
            defer { lock.unlock() }
            progressHandlers[repo] = progressHandler
        }

        private func takeContinuation(for repo: String) -> CheckedContinuation<URL, Error>? {
            lock.lock()
            defer { lock.unlock() }
            return continuations.removeValue(forKey: repo)
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

    private func waitForStatus(
        store: LocalModelCatalogStore,
        id: String,
        status expected: LocalModelStatus
    ) async throws -> LocalModelDescriptor {
        for _ in 0..<200 {
            if let model = try await store.model(id: id), model.status == expected {
                return model
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let model = try #require(try await store.model(id: id))
        Issue.record("Timed out waiting for \(id) to reach \(expected.rawValue); current status is \(model.status.rawValue)")
        return model
    }

    private func waitForProgress(
        store: LocalModelCatalogStore,
        id: String,
        minimumProgress: Double
    ) async throws -> LocalModelDescriptor {
        for _ in 0..<200 {
            if let model = try await store.model(id: id), model.downloadProgress >= minimumProgress {
                return model
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let model = try #require(try await store.model(id: id))
        Issue.record("Timed out waiting for \(id) progress >= \(minimumProgress); current progress is \(model.downloadProgress)")
        return model
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

    @Test
    func successfulDownloadUpdatesProgressStatusAndLocalPath() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "local-download-success.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeLocalModel(id: "apple/success-model", displayName: "Success")
        try await database.saveLocalModel(model)

        let store = LocalModelCatalogStore(database: database)
        let downloader = ControlledSnapshotDownloader()
        let service = LocalDownloadService(catalogStore: store, snapshotDownloader: downloader.downloader)
        let downloadURL = tempDir.appendingPathComponent("downloaded-model", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadURL, withIntermediateDirectories: true)

        await service.downloadModel(id: model.id)
        await downloader.waitUntilStarted(repo: model.huggingFaceRepo)
        downloader.reportProgress(repo: model.huggingFaceRepo, completed: 64, total: 128)
        let progressed = try await waitForProgress(store: store, id: model.id, minimumProgress: 0.5)
        #expect(progressed.downloadedBytes == 64)
        #expect(progressed.totalBytes == 128)

        downloader.complete(repo: model.huggingFaceRepo, url: downloadURL)

        let downloaded = try await waitForStatus(store: store, id: model.id, status: .downloaded)
        #expect(downloaded.localPath == downloadURL.path)

        for _ in 0..<100 {
            let state = await service.activeDownloadStateForTesting()
            if state.modelID == nil {
                #expect(state.token == nil)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Successful download did not clear active state")
    }

    @Test
    func failedDownloadMarksModelFailedAndClearsActiveState() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "local-download-failure.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeLocalModel(id: "apple/failure-model", displayName: "Failure")
        try await database.saveLocalModel(model)

        let store = LocalModelCatalogStore(database: database)
        let downloader = ControlledSnapshotDownloader()
        let service = LocalDownloadService(catalogStore: store, snapshotDownloader: downloader.downloader)

        await service.downloadModel(id: model.id)
        await downloader.waitUntilStarted(repo: model.huggingFaceRepo)
        downloader.fail(repo: model.huggingFaceRepo, error: URLError(.badServerResponse))

        _ = try await waitForStatus(store: store, id: model.id, status: .failed)

        for _ in 0..<100 {
            let state = await service.activeDownloadStateForTesting()
            if state.modelID == nil {
                #expect(state.token == nil)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Failed download did not clear active state")
    }

    @Test
    func unknownModelDoesNotStartDownloader() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "local-download-missing.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = LocalModelCatalogStore(database: database)
        let downloader = ControlledSnapshotDownloader()
        let service = LocalDownloadService(catalogStore: store, snapshotDownloader: downloader.downloader)

        await service.downloadModel(id: "missing/model")

        #expect(downloader.startCount() == 0)
        let state = await service.activeDownloadStateForTesting()
        #expect(state.modelID == nil)
        #expect(state.token == nil)
    }

    @Test
    func cancelNonActiveDownloadIsNoOp() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "local-download-cancel-noop.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = LocalModelCatalogStore(database: database)
        let downloader = ControlledSnapshotDownloader()
        let service = LocalDownloadService(catalogStore: store, snapshotDownloader: downloader.downloader)

        await service.cancelDownload(id: "missing/model")

        #expect(downloader.startCount() == 0)
        let state = await service.activeDownloadStateForTesting()
        #expect(state.modelID == nil)
        #expect(state.token == nil)
    }

    @Test
    func deleteModelResetsCatalogStateAndClearsActiveDownload() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "local-download-delete.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = makeLocalModel(
            id: "local-delete-\(UUID().uuidString)/model",
            displayName: "Delete"
        )
        try await database.saveLocalModel(model)

        let store = LocalModelCatalogStore(database: database)
        let downloader = ControlledSnapshotDownloader()
        let service = LocalDownloadService(catalogStore: store, snapshotDownloader: downloader.downloader)

        await service.downloadModel(id: model.id)
        await downloader.waitUntilStarted(repo: model.huggingFaceRepo)
        #expect((await service.activeDownloadStateForTesting()).modelID == model.id)

        await service.deleteModel(id: model.id)

        let reset = try #require(try await store.model(id: model.id))
        #expect(reset.status == .available)
        #expect(reset.downloadProgress == 0)
        #expect(reset.localPath == nil)
        #expect(reset.partialDownloadPath == nil)
        #expect((await service.activeDownloadStateForTesting()).modelID == nil)

        downloader.fail(repo: model.huggingFaceRepo, error: CancellationError())
    }

    @Test
    func directoryHelpersBuildStableAppAndHubPaths() throws {
        let appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let caches = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let models = LocalDownloadService.modelsDirectoryURL(appSupportDirectory: appSupport)
        let hubRoot = try #require(LocalDownloadService.hubCacheRootDirectoryURL(cachesDirectory: caches))
        let repoCache = try #require(LocalDownloadService.hubCacheDirectoryURL(for: "apple/Test-Model", cachesDirectory: caches))

        #expect(models == appSupport.appendingPathComponent("VPStudio/Models", isDirectory: true))
        #expect(hubRoot == caches.appendingPathComponent("huggingface/hub", isDirectory: true))
        #expect(repoCache.lastPathComponent == "models--apple--Test-Model")
        #expect(repoCache.deletingLastPathComponent() == hubRoot)
    }

    @Test
    func progressNotifyThrottleAllowsFirstAndThrottlesImmediateRepeat() async {
        let throttle = ProgressNotifyThrottle()

        #expect(await throttle.shouldNotify(interval: 60))
        #expect(await throttle.shouldNotify(interval: 60) == false)
        #expect(await throttle.shouldNotify(interval: 0))
    }
}
