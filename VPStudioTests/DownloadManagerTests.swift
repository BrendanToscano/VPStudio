import Foundation
import Testing
@testable import VPStudio

private enum DownloadManagerTestError: Error {
    case timeout
}

private func waitForFile(at url: URL, timeoutSeconds: TimeInterval = 5) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)

    while Date() < deadline {
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        try await Task.sleep(for: .milliseconds(25))
    }

    throw DownloadManagerTestError.timeout
}

private actor AttemptCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

private actor BlockingDownloadGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@Suite(.serialized)
struct DownloadManagerTests {
    @Test func queuedDownloadCompletesAndPersists() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-complete.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeSuccessfulPerformer(bytes: 2048)
        )

        let task = try await manager.enqueueDownload(stream: makeStream(name: "movie.mkv"), mediaId: "tt100", episodeId: nil)

        let completed = try await waitForStatus(database: database, id: task.id, expected: .completed)
        #expect(completed.progress == 1.0)
        #expect(completed.destinationURL != nil)
        #expect(completed.totalBytes == 2048)
        #expect(FileManager.default.fileExists(atPath: completed.destinationURL!.path))

        let listed = try await manager.listDownloads()
        #expect(listed.contains(where: { $0.id == task.id && $0.status == .completed }))
    }

    @Test func cancelMarksTaskCancelled() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-cancel.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeDelayedPerformer()
        )

        let task = try await manager.enqueueDownload(stream: makeStream(name: "cancel.mkv"), mediaId: "tt101", episodeId: nil)
        _ = try await waitForStatus(database: database, id: task.id, expected: .downloading, timeoutSeconds: 10)

        await manager.cancelDownload(id: task.id)

        let cancelled = try await waitForStatus(database: database, id: task.id, expected: .cancelled)
        #expect(cancelled.status == .cancelled)
    }

    @Test func retryAfterFailureTransitionsToCompleted() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-retry.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let attemptCounter = AttemptCounter()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)

        let performer: DownloadManager.DownloadPerformer = { _, _ in
            let attempt = await attemptCounter.next()
            if attempt == 1 {
                throw URLError(.timedOut)
            }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let bytes = Data(repeating: 0x2A, count: 1024)
            try bytes.write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/retry.mkv")!,
                mimeType: "video/x-matroska",
                expectedContentLength: 1024,
                textEncodingName: nil
            )
            return (tempURL, response)
        }

        let manager = DownloadManager(database: database, downloadsDirectory: downloadsDir, performer: performer)
        let task = try await manager.enqueueDownload(stream: makeStream(name: "retry.mkv"), mediaId: "tt102", episodeId: nil)

        _ = try await waitForStatus(database: database, id: task.id, expected: .failed)

        try await manager.retryDownload(id: task.id)
        let completed = try await waitForStatus(database: database, id: task.id, expected: .completed)
        #expect(completed.errorMessage == nil)
        #expect(completed.destinationURL != nil)
    }

    @Test func duplicateFileNamesUseCollisionSafeSuffixes() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-duplicate.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let expectedFirstName = "same-name.mkv"
        let expectedSecondName = "same-name (1).mkv"
        let expectedSecondURL = downloadsDir.appendingPathComponent(expectedSecondName)
        let attemptCounter = AttemptCounter()

        let performer: DownloadManager.DownloadPerformer = { _, _ in
            let attempt = await attemptCounter.next()
            if attempt == 1 {
                // Force completion inversion: the first download can't finish
                // until the second destination file exists on disk.
                try await waitForFile(at: expectedSecondURL, timeoutSeconds: 10)
            }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x01, count: 512)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/video.mkv")!,
                mimeType: "video/x-matroska",
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            return (tempURL, response)
        }

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: performer
        )

        let first = try await manager.enqueueDownload(stream: makeStream(name: "same-name.mkv"), mediaId: "tt103", episodeId: nil)
        let second = try await manager.enqueueDownload(stream: makeStream(name: "same-name.mkv"), mediaId: "tt104", episodeId: nil)

        let secondCompleted = try await waitForStatus(database: database, id: second.id, expected: .completed)
        let firstCompleted = try await waitForStatus(database: database, id: first.id, expected: .completed)

        let firstPath = try #require(firstCompleted.destinationPath)
        let secondPath = try #require(secondCompleted.destinationPath)
        let firstName = URL(fileURLWithPath: firstPath).lastPathComponent
        let secondName = URL(fileURLWithPath: secondPath).lastPathComponent

        #expect(firstPath != secondPath)
        #expect(firstName == expectedFirstName)
        #expect(secondName == expectedSecondName)
        #expect(secondCompleted.updatedAt <= firstCompleted.updatedAt)
        #expect(FileManager.default.fileExists(atPath: firstPath))
        #expect(FileManager.default.fileExists(atPath: secondPath))
    }

    @Test func completedDownloadsAreVisibleAfterManagerRecreate() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-reload.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)

        let managerA = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeSuccessfulPerformer(bytes: 1024)
        )

        let task = try await managerA.enqueueDownload(stream: makeStream(name: "persist.mkv"), mediaId: "tt105", episodeId: nil)
        _ = try await waitForStatus(database: database, id: task.id, expected: .completed)

        let managerB = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeSuccessfulPerformer(bytes: 256)
        )
        let listed = try await managerB.listDownloads()

        #expect(listed.contains(where: { $0.id == task.id && $0.status == .completed }))
    }

    @Test func cancellationStopsProgressSimulationUpdates() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-cancel-progress.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let gate = BlockingDownloadGate()
        defer {
            Task { await gate.resume() }
        }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let performer: DownloadManager.DownloadPerformer = { _, progressHandler in
            // Report partial progress before blocking so the test can observe it
            progressHandler(512, 512, 10_000)
            await gate.wait()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data([0x7A]).write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/blocking.mkv")!,
                mimeType: "video/x-matroska",
                expectedContentLength: 1,
                textEncodingName: nil
            )
            return (tempURL, response)
        }

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: performer,
            sleep: { _ in
                try await Task.sleep(for: .milliseconds(20))
            }
        )

        let task = try await manager.enqueueDownload(stream: makeStream(name: "blocked.mkv"), mediaId: "tt106", episodeId: nil)
        _ = try await waitForStatus(database: database, id: task.id, expected: .downloading, timeoutSeconds: 10)
        _ = try await waitForProgress(database: database, id: task.id, minimum: 0.05, timeoutSeconds: 10)

        await manager.cancelDownload(id: task.id)
        _ = try await waitForStatus(database: database, id: task.id, expected: .cancelled, timeoutSeconds: 10)

        try await Task.sleep(for: .milliseconds(100))
        let baselineTask = try #require(try await database.fetchDownloadTask(id: task.id))
        let baselineProgress = baselineTask.progress

        try await Task.sleep(for: .milliseconds(300))
        let laterTask = try #require(try await database.fetchDownloadTask(id: task.id))
        let laterProgress = laterTask.progress

        #expect(abs(laterProgress - baselineProgress) < 0.0001)
    }

    private func makeDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, rootDir)
    }

    private func waitForStatus(
        database: DatabaseManager,
        id: String,
        expected: DownloadStatus,
        timeoutSeconds: TimeInterval = 5
    ) async throws -> DownloadTask {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            if let task = try await database.fetchDownloadTask(id: id), task.status == expected {
                return task
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw DownloadManagerTestError.timeout
    }

    private func waitForProgress(
        database: DatabaseManager,
        id: String,
        minimum: Double,
        timeoutSeconds: TimeInterval = 5
    ) async throws -> DownloadTask {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            if let task = try await database.fetchDownloadTask(id: id), task.progress >= minimum {
                return task
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw DownloadManagerTestError.timeout
    }

    private func makeSuccessfulPerformer(bytes: Int) -> DownloadManager.DownloadPerformer {
        { _, _ in
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x01, count: bytes)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/video.mkv")!,
                mimeType: "video/x-matroska",
                expectedContentLength: bytes,
                textEncodingName: nil
            )
            return (tempURL, response)
        }
    }

    private func makeDelayedPerformer() -> DownloadManager.DownloadPerformer {
        { _, _ in
            try await Task.sleep(for: .seconds(5))
            try Task.checkCancellation()

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data([0]).write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/delayed.mkv")!,
                mimeType: "video/x-matroska",
                expectedContentLength: 1,
                textEncodingName: nil
            )
            return (tempURL, response)
        }
    }

    private func makeStream(name: String) -> StreamInfo {
        StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/\(UUID().uuidString).mkv")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: name,
            sizeBytes: 100,
            debridService: DebridServiceType.realDebrid.rawValue
        )
    }
}
