import Foundation
import Testing
@testable import VPStudio

private enum DownloadManagerTestError: Error {
    case timeout
}

private func waitForFile(at url: URL, timeoutSeconds: TimeInterval = 10) async throws {
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

    func snapshot() -> Int {
        count
    }
}

private actor RetryCancellationRecorder {
    private var firstAttemptCancelledAt: Date?
    private var secondAttemptStartedAt: Date?

    func markFirstAttemptCancelled() {
        firstAttemptCancelledAt = Date()
    }

    func markSecondAttemptStarted() {
        secondAttemptStartedAt = Date()
    }

    func snapshot() -> (Date?, Date?) {
        (firstAttemptCancelledAt, secondAttemptStartedAt)
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

private actor MultiDownloadGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeOne() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private actor ResumeDataRecorder {
    private var sawResumeData = false

    func record(_ resumeData: Data?) {
        if resumeData != nil {
            sawResumeData = true
        }
    }

    func snapshot() -> Bool {
        sawResumeData
    }
}

private actor TransferRequestRecorder {
    struct Snapshot: Equatable {
        let usedResumeData: Bool
        let url: String?
    }

    private var snapshots: [Snapshot] = []

    func record(request: DownloadManager.TransferRequest) {
        snapshots.append(
            Snapshot(
                usedResumeData: request.resumeData != nil,
                url: request.url?.absoluteString
            )
        )
    }

    func snapshot() -> [Snapshot] {
        snapshots
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

    @Test func httpErrorResponsesDoNotCompleteDownload() async throws {
        try await assertHTTPErrorResponseDoesNotComplete(statusCode: 403, fileName: "forbidden.mkv", databaseName: "download-manager-http-403.sqlite")
        try await assertHTTPErrorResponseDoesNotComplete(statusCode: 410, fileName: "gone.mkv", databaseName: "download-manager-http-410.sqlite")
    }

    @Test func serverErrorResponsesDoNotCompleteDownload() async throws {
        try await assertHTTPErrorResponseDoesNotComplete(statusCode: 500, fileName: "server-error.mkv", databaseName: "download-manager-http-500.sqlite")
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

    @Test func cancellingRecoveryBackedTaskClearsPersistedReplayableTransportState() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-cancel-redacts-recovery.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let recoveryContext = try #require(
            StreamRecoveryContext(
                infoHash: "deadc0dedeadc0dedeadc0dedeadc0dedeadc0de",
                preferredService: .realDebrid,
                seasonNumber: 2,
                episodeNumber: 5
            )
        )
        let persisted = DownloadTask(
            id: "cancel-recovery-backed",
            mediaId: "tt-cancel-recovery",
            streamURL: "https://cdn.example.com/stale.mkv?token=secret",
            fileName: "cancel-recovery.mkv",
            status: .failed,
            progress: 0.33,
            bytesWritten: 333,
            totalBytes: 1_000,
            mediaTitle: "Cancel Recovery",
            recoveryContextJSON: try recoveryContext.jsonString(),
            expectedBytes: 1_000,
            resumeDataBase64: Data("legacy-resume".utf8).base64EncodedString()
        )
        try await database.saveDownloadTask(persisted)

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeSuccessfulPerformer(bytes: 1),
            linkRefresher: { _ in
                URL(string: "https://cdn.example.com/fresh.mkv")!
            }
        )

        await manager.cancelDownload(id: persisted.id)

        let cancelled = try await waitForStatus(database: database, id: persisted.id, expected: .cancelled)
        #expect(cancelled.persistedStreamURL == nil)
        #expect(cancelled.resumeData == nil)
    }

    @Test func diskSpacePreflightRejectsOversizedDownloadBeforeQueueing() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-disk-space.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeSuccessfulPerformer(bytes: 1_024),
            minimumFreeSpaceBufferBytes: 128,
            availableDiskSpace: { _ in 1_024 }
        )

        var didThrow = false
        do {
            _ = try await manager.enqueueDownload(
                stream: makeStream(name: "too-large.mkv", sizeBytes: 2_048),
                mediaId: "tt-disk-space",
                episodeId: nil
            )
        } catch let error as DownloadTransferError {
            didThrow = true
            if case .insufficientDiskSpace = error {
                #expect(true)
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        #expect(didThrow)
        let stored = try await manager.listDownloads()
        #expect(stored.isEmpty)
    }

    @Test func retryAfterFailureTransitionsToCompleted() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-retry.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let attemptCounter = AttemptCounter()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let recoveryContext = StreamRecoveryContext(
            infoHash: "0123456789abcdef0123456789abcdef01234567",
            preferredService: .realDebrid,
            seasonNumber: 1,
            episodeNumber: 2
        )!

        let performer: DownloadManager.DownloadPerformer = { _, _, _ in
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
        let task = try await manager.enqueueDownload(
            stream: makeStream(name: "retry.mkv", recoveryContext: recoveryContext),
            mediaId: "tt102",
            episodeId: nil
        )

        _ = try await waitForStatus(database: database, id: task.id, expected: .failed)

        try await manager.retryDownload(id: task.id)
        let completed = try await waitForStatus(database: database, id: task.id, expected: .completed)
        #expect(completed.errorMessage == nil)
        #expect(completed.destinationURL != nil)
        #expect(completed.recoveryContext?.infoHash == recoveryContext.infoHash)
        #expect(completed.recoveryContext?.preferredService == recoveryContext.preferredService)
        #expect(completed.recoveryContext?.seasonNumber == recoveryContext.seasonNumber)
        #expect(completed.recoveryContext?.episodeNumber == recoveryContext.episodeNumber)
        #expect(completed.recoveryContextJSON != nil)
    }

    @Test func retryWaitsForCancelledTransferTeardownBeforeRestarting() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-retry-cancel.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let attemptCounter = AttemptCounter()
        let recorder = RetryCancellationRecorder()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)

        let performer: DownloadManager.DownloadPerformer = { _, _, cancellationController in
            let attempt = await attemptCounter.next()
            if attempt == 1 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    cancellationController.register {
                        Task { await recorder.markFirstAttemptCancelled() }
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }

            await recorder.markSecondAttemptStarted()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x3C, count: 256)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/restart.mkv")!,
                mimeType: "video/x-matroska",
                expectedContentLength: 256,
                textEncodingName: nil
            )
            return (tempURL, response)
        }

        let manager = DownloadManager(database: database, downloadsDirectory: downloadsDir, performer: performer)
        let task = try await manager.enqueueDownload(stream: makeStream(name: "restart.mkv"), mediaId: "tt107", episodeId: nil)
        _ = try await waitForStatus(database: database, id: task.id, expected: .downloading)

        try await manager.retryDownload(id: task.id)

        let completed = try await waitForStatus(database: database, id: task.id, expected: .completed)
        let (cancelledAt, secondStartedAt) = await recorder.snapshot()
        #expect(completed.status == .completed)
        #expect(cancelledAt != nil)
        #expect(secondStartedAt != nil)
        if let cancelledAt, let secondStartedAt {
            #expect(secondStartedAt >= cancelledAt)
        }
    }

    @Test func retryPreservesProgressWhenResumeDataIsProduced() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-retry-resume-data.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let secondAttemptGate = BlockingDownloadGate()
        let resumeRecorder = ResumeDataRecorder()
        let producedResumeData = Data("resume-point".utf8)
        let performer: DownloadManager.DownloadPerformer = { request, progressHandler, cancellationController in
            await resumeRecorder.record(request.resumeData)
            if request.resumeData == nil {
                progressHandler(200, 200, 1_000)
                return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
                    cancellationController.register {
                        continuation.resume(throwing: DownloadTransferError.resumeDataProduced(producedResumeData))
                    }
                }
            }

            await secondAttemptGate.wait()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x7C, count: 800)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/resume-produced.mkv")!,
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

        let task = try await manager.enqueueDownload(
            stream: makeStream(name: "resume-produced.mkv", sizeBytes: 1_000),
            mediaId: "tt108",
            episodeId: nil
        )
        _ = try await waitForStatus(database: database, id: task.id, expected: .downloading)
        _ = try await waitForProgress(database: database, id: task.id, minimum: 0.2)

        try await manager.retryDownload(id: task.id)

        let resumed = try await waitForStatus(database: database, id: task.id, expected: .downloading)
        #expect(abs(resumed.progress - 0.2) < 0.001)
        #expect(resumed.bytesWritten == 200)
        #expect(resumed.resumeData != nil)
        #expect(await resumeRecorder.snapshot())

        await secondAttemptGate.resume()
        let completed = try await waitForStatus(database: database, id: task.id, expected: .completed)
        #expect(completed.resumeData == nil)
    }

    @Test func retryWithoutResumeDataResetsObservedProgress() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-retry-partial-no-resume.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let blocker = BlockingDownloadGate()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)

        let performer: DownloadManager.DownloadPerformer = { _, _, _ in
            await blocker.wait()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x3A, count: 1_024)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/no-resume-retry.mkv")!,
                mimeType: "video/x-matroska",
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            return (tempURL, response)
        }

        try await database.saveDownloadTask(
            DownloadTask(
                id: "partial-no-resume",
                mediaId: "tt-no-resume",
                streamURL: "https://cdn.example.com/no-resume-retry.mkv",
                fileName: "no-resume-retry.mkv",
                status: .failed,
                progress: 0.42,
                bytesWritten: 420,
                totalBytes: 1_024,
                mediaTitle: "No Resume Retry",
                mediaType: "movie"
            )
        )

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: performer
        )

        try await manager.retryDownload(id: "partial-no-resume")

        let restarting = try await waitForStatus(database: database, id: "partial-no-resume", expected: .downloading)
        #expect(restarting.progress == 0)
        #expect(restarting.bytesWritten == 0)

        await blocker.resume()

        let completed = try await waitForStatus(database: database, id: "partial-no-resume", expected: .completed)
        #expect(completed.bytesWritten == 1_024)
    }

    @Test func retryWithResumeDataUsesRemainingDiskAllowance() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-retry-remaining-bytes.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let blocker = BlockingDownloadGate()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)

        let performer: DownloadManager.DownloadPerformer = { _, _, _ in
            await blocker.wait()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x3A, count: 1_000)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/remaining-allowance.mkv")!,
                mimeType: "video/x-matroska",
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            return (tempURL, response)
        }

        let resumedTask = DownloadTask(
            id: "partial-resume",
            mediaId: "tt-resume-allowance",
            streamURL: "https://cdn.example.com/remaining-allowance.mkv",
            fileName: "remaining-allowance.mkv",
            status: .failed,
            progress: 0.42,
            bytesWritten: 800,
            mediaTitle: "Allowance Test",
            expectedBytes: 1_000,
            resumeDataBase64: Data("resume-point".utf8).base64EncodedString()
        )
        try await database.saveDownloadTask(resumedTask)

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: performer,
            minimumFreeSpaceBufferBytes: 0,
            availableDiskSpace: { _ in 250 }
        )

        try await manager.retryDownload(id: resumedTask.id)

        let restarting = try await waitForStatus(database: database, id: resumedTask.id, expected: .downloading)
        #expect(restarting.status == DownloadStatus.downloading)

        await blocker.resume()
        _ = try await waitForStatus(database: database, id: resumedTask.id, expected: .completed)
    }

    @Test func recoveryBackedDownloadsRedactReplayableURLButKeepEnrichedContext() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-recovery-context.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let gate = BlockingDownloadGate()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let replayableURL = URL(string: "https://cdn.example.com/replayable.mkv?token=abc123")!
        let recoveryContext = StreamRecoveryContext(
            infoHash: "fedcba9876543210fedcba9876543210fedcba98",
            preferredService: .realDebrid,
            seasonNumber: 1,
            episodeNumber: 4
        )!

        let performer: DownloadManager.DownloadPerformer = { _, _, _ in
            await gate.wait()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x2B, count: 128)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: replayableURL,
                mimeType: "video/x-matroska",
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            return (tempURL, response)
        }

        defer {
            Task { await gate.resume() }
        }

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: performer,
            linkRefresher: { _ in
                URL(string: "https://cdn.example.com/refreshed.mkv")!
            }
        )

        let task = try await manager.enqueueDownload(
            stream: StreamInfo(
                streamURL: replayableURL,
                quality: .hd1080p,
                codec: .h264,
                audio: .aac,
                source: .webDL,
                hdr: .sdr,
                fileName: "Replayable.S01E04.mkv",
                sizeBytes: 4_096,
                debridService: DebridServiceType.realDebrid.rawValue,
                recoveryContext: recoveryContext
            ),
            mediaId: "tt-replayable",
            episodeId: "ep-4"
        )

        let stored = try #require(try await database.fetchDownloadTask(id: task.id))
        let storedContext = try #require(stored.recoveryContext)
        #expect(stored.persistedStreamURL == nil)
        #expect(storedContext.infoHash == recoveryContext.infoHash)
        #expect(storedContext.preferredService == recoveryContext.preferredService)
        #expect(storedContext.seasonNumber == recoveryContext.seasonNumber)
        #expect(storedContext.episodeNumber == recoveryContext.episodeNumber)
        #expect(storedContext.resolvedDebridService == DebridServiceType.realDebrid.rawValue)
        #expect(storedContext.resolvedFileName == "Replayable.S01E04.mkv")
        #expect(storedContext.resolvedFileSizeBytes == 4_096)
    }

    @Test func recoveryBackedDownloadsRetryInSameSessionWithoutPersistingReplayableTransportState() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-recovery-runtime-retry.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let recorder = TransferRequestRecorder()
        let attempts = AttemptCounter()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let replayableURL = URL(string: "https://cdn.example.com/runtime-retry.mkv?token=abc123")!
        let recoveryContext = try #require(
            StreamRecoveryContext(
                infoHash: "abababababababababababababababababababab",
                preferredService: .realDebrid,
                seasonNumber: 1,
                episodeNumber: 6
            )
        )

        let performer: DownloadManager.DownloadPerformer = { request, _, _ in
            await recorder.record(request: request)
            let attempt = await attempts.next()
            if attempt == 1 {
                throw DownloadManagerTestError.timeout
            }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x44, count: 512)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: replayableURL,
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

        let task = try await manager.enqueueDownload(
            stream: StreamInfo(
                streamURL: replayableURL,
                quality: .hd1080p,
                codec: .h264,
                audio: .aac,
                source: .webDL,
                hdr: .sdr,
                fileName: "RuntimeRetry.S01E06.mkv",
                sizeBytes: 512,
                debridService: DebridServiceType.realDebrid.rawValue,
                recoveryContext: recoveryContext
            ),
            mediaId: "tt-runtime-retry",
            episodeId: "ep-6"
        )

        let failed = try await waitForStatus(database: database, id: task.id, expected: .failed)
        #expect(failed.persistedStreamURL == nil)
        #expect(failed.resumeData == nil)

        try await manager.retryDownload(id: task.id)

        let completed = try await waitForStatus(database: database, id: task.id, expected: .completed)
        #expect(completed.persistedStreamURL == nil)
        #expect(completed.resumeData == nil)

        let requests = await recorder.snapshot()
        #expect(requests == [
            .init(usedResumeData: false, url: replayableURL.absoluteString),
            .init(usedResumeData: false, url: replayableURL.absoluteString),
        ])
    }

    @Test func duplicateFileNamesUseCollisionSafeSuffixes() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-duplicate.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let expectedFirstName = "same-name.mkv"
        let expectedSecondName = "same-name (1).mkv"
        let expectedSecondURL = downloadsDir.appendingPathComponent(expectedSecondName)
        let attemptCounter = AttemptCounter()

        let performer: DownloadManager.DownloadPerformer = { _, _, _ in
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

    @Test func schedulerCapsConcurrentDownloadsAndStartsQueuedWorkWhenSlotFrees() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-concurrency.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let gate = MultiDownloadGate()
        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: { _, _, _ in
                await gate.wait()
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let data = Data(repeating: 0x21, count: 256)
                try data.write(to: tempURL)
                let response = URLResponse(
                    url: URL(string: "https://cdn.example.com/queued.mkv")!,
                    mimeType: "video/x-matroska",
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                return (tempURL, response)
            },
            maxConcurrentTransfers: 2
        )

        let first = try await manager.enqueueDownload(stream: makeStream(name: "first.mkv"), mediaId: "tt201", episodeId: nil)
        let second = try await manager.enqueueDownload(stream: makeStream(name: "second.mkv"), mediaId: "tt202", episodeId: nil)
        let third = try await manager.enqueueDownload(stream: makeStream(name: "third.mkv"), mediaId: "tt203", episodeId: nil)

        _ = try await waitForStatus(database: database, id: first.id, expected: .downloading)
        _ = try await waitForStatus(database: database, id: second.id, expected: .downloading)
        try await Task.sleep(for: .milliseconds(150))
        let queued = try #require(try await database.fetchDownloadTask(id: third.id))
        #expect(queued.status == .queued)

        await gate.resumeOne()
        _ = try await waitForStatus(database: database, id: third.id, expected: .downloading)

        await gate.resumeAll()
        _ = try await waitForStatus(database: database, id: first.id, expected: .completed)
        _ = try await waitForStatus(database: database, id: second.id, expected: .completed)
        _ = try await waitForStatus(database: database, id: third.id, expected: .completed)
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

    @Test func inFlightDownloadWithCompletedDestinationRepairsOnStartup() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-startup-repair.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let destinationURL = downloadsDir.appendingPathComponent("startup-repair.mkv")
        let bytes = Data(repeating: 0x2D, count: 512)
        try bytes.write(to: destinationURL)

        let attemptCounter = AttemptCounter()
        let task = DownloadTask(
            id: "startup-repair",
            mediaId: "tt-repair",
            streamURL: "https://cdn.example.com/startup-repair.mkv",
            fileName: "startup-repair.mkv",
            status: .downloading,
            progress: 0.99,
            bytesWritten: 512,
            totalBytes: 512,
            destinationPath: destinationURL.path,
            mediaTitle: "Startup Repair",
            mediaType: "movie"
        )
        try await database.saveDownloadTask(task)

        _ = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: { _, _, _ in
                _ = await attemptCounter.next()
                throw DownloadManagerTestError.timeout
            }
        )

        let repaired = try await waitForStatus(database: database, id: task.id, expected: .completed)
        let attempts = await attemptCounter.snapshot()
        #expect(attempts == 0)
        #expect(repaired.progress == 1.0)
        #expect(repaired.destinationURL?.path == destinationURL.path)
        #expect(repaired.resumeData == nil)
    }

    @Test func persistedInFlightDownloadResumesAfterManagerRecreate() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-resume.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let recoveryContext = StreamRecoveryContext(
            infoHash: "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
            preferredService: .realDebrid,
            seasonNumber: 3,
            episodeNumber: 7
        )!
        let persisted = DownloadTask(
            mediaId: "tt150",
            episodeId: "tmdb-123-s3e7",
            streamURL: "https://cdn.example.com/resume.mkv",
            fileName: "resume.mkv",
            status: .downloading,
            progress: 0.42,
            bytesWritten: 420,
            totalBytes: 1_000,
            destinationPath: nil,
            errorMessage: "stale",
            mediaTitle: "Resume Test",
            mediaType: "series",
            seasonNumber: 3,
            episodeNumber: 7,
            episodeTitle: "Resume",
            recoveryContextJSON: try recoveryContext.jsonString()
        )
        try await database.saveDownloadTask(persisted)

        _ = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeSuccessfulPerformer(bytes: 1_024)
        )

        let completed = try await waitForStatus(database: database, id: persisted.id, expected: .completed)
        #expect(completed.status == .completed)
        #expect(completed.progress == 1.0)
        #expect(completed.errorMessage == nil)
        #expect(completed.recoveryContext?.infoHash == recoveryContext.infoHash)
        #expect(completed.recoveryContext?.preferredService == recoveryContext.preferredService)
        #expect(completed.recoveryContext?.seasonNumber == recoveryContext.seasonNumber)
        #expect(completed.recoveryContext?.episodeNumber == recoveryContext.episodeNumber)
    }

    @Test func expiredLinkRecoveryClearsStaleResumeDataAndReusesFreshURL() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-expired-link-retry.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let recorder = TransferRequestRecorder()
        let attemptCounter = AttemptCounter()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let staleURL = "https://cdn.example.com/stale-link.mkv?token=expired"
        let freshURL = URL(string: "https://cdn.example.com/fresh-link.mkv?token=fresh")!
        let recoveryContext = StreamRecoveryContext(
            infoHash: "00112233445566778899aabbccddeeff00112233",
            preferredService: .realDebrid
        )!

        let persisted = DownloadTask(
            id: "expired-link-retry",
            mediaId: "tt-expired-link",
            streamURL: staleURL,
            fileName: "expired-link.mkv",
            status: .failed,
            progress: 0.4,
            bytesWritten: 400,
            totalBytes: 1_000,
            mediaTitle: "Expired Link",
            recoveryContextJSON: try recoveryContext.jsonString(),
            expectedBytes: 1_000,
            resumeDataBase64: Data("stale-resume-data".utf8).base64EncodedString()
        )
        try await database.saveDownloadTask(persisted)

        let performer: DownloadManager.DownloadPerformer = { request, _, _ in
            await recorder.record(request: request)
            let attempt = await attemptCounter.next()
            switch attempt {
            case 1:
                throw DownloadTransferError.badHTTPStatus(403)
            case 2:
                throw DownloadManagerTestError.timeout
            default:
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let data = Data(repeating: 0x4F, count: 1_000)
                try data.write(to: tempURL)
                let response = URLResponse(
                    url: freshURL,
                    mimeType: "video/x-matroska",
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                return (tempURL, response)
            }
        }

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: performer,
            linkRefresher: { _ in freshURL }
        )

        try await manager.retryDownload(id: persisted.id)

        let failed = try await waitForStatus(database: database, id: persisted.id, expected: .failed)
        #expect(failed.resumeData == nil)
        #expect(failed.persistedStreamURL == nil)

        try await manager.retryDownload(id: persisted.id)
        let completed = try await waitForStatus(database: database, id: persisted.id, expected: .completed)
        #expect(completed.resumeData == nil)

        let requests = await recorder.snapshot()
        #expect(requests.count == 3)
        #expect(requests[0] == .init(usedResumeData: false, url: freshURL.absoluteString))
        #expect(requests[1] == .init(usedResumeData: false, url: freshURL.absoluteString))
        #expect(requests[2] == .init(usedResumeData: false, url: freshURL.absoluteString))
    }

    @Test func cancellingRefreshedRecoveryDownloadDoesNotRestoreLegacyResumeData() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-refresh-cancel-redaction.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let recorder = TransferRequestRecorder()
        let attemptCounter = AttemptCounter()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let freshURL = URL(string: "https://cdn.example.com/fresh-after-expiry.mkv?token=fresh")!
        let recoveryContext = StreamRecoveryContext(
            infoHash: "9988776655443322110099887766554433221100",
            preferredService: .realDebrid
        )!

        let persisted = DownloadTask(
            id: "refresh-cancel-redaction",
            mediaId: "tt-refresh-cancel",
            streamURL: "https://cdn.example.com/stale-before-refresh.mkv?token=stale",
            fileName: "refresh-cancel.mkv",
            status: .failed,
            progress: 0.4,
            bytesWritten: 400,
            totalBytes: 1_000,
            mediaTitle: "Refresh Cancel",
            recoveryContextJSON: try recoveryContext.jsonString(),
            expectedBytes: 1_000,
            resumeDataBase64: Data("legacy-resume-data".utf8).base64EncodedString()
        )
        try await database.saveDownloadTask(persisted)

        let performer: DownloadManager.DownloadPerformer = { request, _, cancellationController in
            await recorder.record(request: request)
            let attempt = await attemptCounter.next()
            if attempt == 1 {
                throw DownloadTransferError.badHTTPStatus(403)
            }

            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
                cancellationController.register {
                    continuation.resume(throwing: CancellationError())
                }
            }
        }

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: performer,
            linkRefresher: { _ in freshURL }
        )

        try await manager.retryDownload(id: persisted.id)
        _ = try await waitForStatus(database: database, id: persisted.id, expected: .downloading)

        await manager.cancelDownload(id: persisted.id)

        let cancelled = try await waitForStatus(database: database, id: persisted.id, expected: .cancelled)
        #expect(cancelled.persistedStreamURL == nil)
        #expect(cancelled.resumeData == nil)

        let requests = await recorder.snapshot()
        #expect(requests == [
            .init(usedResumeData: false, url: freshURL.absoluteString),
            .init(usedResumeData: false, url: freshURL.absoluteString),
        ])
    }

    @Test func recoveryBackedPersistedDownloadsIgnoreLegacyResumeDataOnStartup() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-legacy-recovery-redaction.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let recorder = TransferRequestRecorder()
        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let freshURL = URL(string: "https://cdn.example.com/recovered.mkv?token=fresh")!
        let recoveryContext = StreamRecoveryContext(
            infoHash: "1111222233334444555566667777888899990000",
            preferredService: .realDebrid
        )!

        let persisted = DownloadTask(
            id: "legacy-recovery-download",
            mediaId: "tt-legacy",
            streamURL: "https://cdn.example.com/stale.mkv?token=stale",
            fileName: "legacy-recovery.mkv",
            status: .downloading,
            progress: 0.2,
            bytesWritten: 200,
            totalBytes: 1_000,
            mediaTitle: "Legacy Recovery",
            recoveryContextJSON: try recoveryContext.jsonString(),
            expectedBytes: 1_000,
            resumeDataBase64: Data("legacy-resume".utf8).base64EncodedString()
        )
        try await database.saveDownloadTask(persisted)

        let performer: DownloadManager.DownloadPerformer = { request, _, _ in
            await recorder.record(request: request)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let data = Data(repeating: 0x6B, count: 1_000)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: freshURL,
                mimeType: "video/x-matroska",
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            return (tempURL, response)
        }

        _ = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: performer,
            linkRefresher: { _ in freshURL }
        )

        let completed = try await waitForStatus(database: database, id: persisted.id, expected: .completed)
        #expect(completed.persistedStreamURL == nil)
        #expect(completed.resumeData == nil)

        let requests = await recorder.snapshot()
        #expect(requests == [.init(usedResumeData: false, url: freshURL.absoluteString)])
    }

    @Test func completedDownloadClearsPersistedStreamURL() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-redacts-completed-url.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeSuccessfulPerformer(bytes: 512)
        )

        let task = try await manager.enqueueDownload(stream: makeStream(name: "redact-on-complete.mkv"), mediaId: "tt151", episodeId: nil)
        let completed = try await waitForStatus(database: database, id: task.id, expected: .completed)

        #expect(completed.streamURL.isEmpty)
        #expect(completed.persistedStreamURL == nil)
    }

    @Test func removeDownloadKeepsRowWhenFileDeletionFails() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-remove-fails.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let fileURL = downloadsDir.appendingPathComponent("locked-file.mkv")
        try Data(repeating: 0x5A, count: 64).write(to: fileURL)
        let task = DownloadTask(
            mediaId: "tt151",
            streamURL: "https://cdn.example.com/locked-file.mkv",
            fileName: "locked-file.mkv",
            status: .completed,
            progress: 1.0,
            bytesWritten: 64,
            totalBytes: 64,
            destinationPath: fileURL.path,
            mediaTitle: "Locked",
            mediaType: "movie"
        )
        try await database.saveDownloadTask(task)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: downloadsDir.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: downloadsDir.path)

        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeSuccessfulPerformer(bytes: 1)
        )

        var didThrow = false
        do {
            try await manager.removeDownload(id: task.id)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        let stored = try #require(try await database.fetchDownloadTask(id: task.id))
        #expect(stored.id == task.id)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func cancellationStopsProgressSimulationUpdates() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-cancel-progress.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let gate = BlockingDownloadGate()
        defer {
            Task { await gate.resume() }
        }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let performer: DownloadManager.DownloadPerformer = { _, progressHandler, _ in
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

    @Test func moveFailureCleansTemporaryFile() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-manager-move-failure.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let gate = BlockingDownloadGate()
        let tempURL = rootDir.appendingPathComponent("move-failure-temp.bin")
        let fileName = "move-failure.mkv"
        let destinationPath = downloadsDir.appendingPathComponent(fileName)

        let performer: DownloadManager.DownloadPerformer = { _, _, _ in
            await gate.wait()
            let data = Data(repeating: 0x33, count: 256)
            try data.write(to: tempURL)
            let response = URLResponse(
                url: URL(string: "https://cdn.example.com/move-failure.mkv")!,
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

        let task = try await manager.enqueueDownload(stream: makeStream(name: fileName), mediaId: "tt152", episodeId: nil)
        _ = try await waitForStatus(database: database, id: task.id, expected: .downloading)

        try FileManager.default.createDirectory(at: destinationPath, withIntermediateDirectories: true)
        Task { await gate.resume() }

        let failed = try await waitForStatus(database: database, id: task.id, expected: .failed)
        #expect(failed.status == .failed)
        #expect(!FileManager.default.fileExists(atPath: tempURL.path))
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
        timeoutSeconds: TimeInterval = 10
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
        timeoutSeconds: TimeInterval = 10
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
        { _, _, _ in
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

    private func makeHTTPErrorPerformer(statusCode: Int, tempURL: URL, bytes: Int = 512) -> DownloadManager.DownloadPerformer {
        { _, _, _ in
            let data = Data(repeating: 0x45, count: bytes)
            try data.write(to: tempURL)
            let response = HTTPURLResponse(
                url: URL(string: "https://cdn.example.com/error-page.mkv")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/html; charset=utf-8",
                ]
            ) ?? URLResponse(
                url: URL(string: "https://cdn.example.com/error-page.mkv")!,
                mimeType: "text/html",
                expectedContentLength: bytes,
                textEncodingName: "utf-8"
            )
            return (tempURL, response)
        }
    }

    private func assertHTTPErrorResponseDoesNotComplete(
        statusCode: Int,
        fileName: String,
        databaseName: String
    ) async throws {
        let (database, rootDir) = try await makeDatabase(named: databaseName)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let downloadsDir = rootDir.appendingPathComponent("downloads", isDirectory: true)
        let tempURL = rootDir.appendingPathComponent("error-source-\(statusCode).bin")
        let manager = DownloadManager(
            database: database,
            downloadsDirectory: downloadsDir,
            performer: makeHTTPErrorPerformer(statusCode: statusCode, tempURL: tempURL)
        )

        let task = try await manager.enqueueDownload(
            stream: makeStream(name: fileName),
            mediaId: "tt-http-\(statusCode)",
            episodeId: nil
        )

        let finished = try await waitForStatus(database: database, id: task.id, expected: .failed)
        #expect(finished.status == .failed)
        #expect(finished.destinationURL == nil)
        #expect(finished.errorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: tempURL.path))
    }

    private func makeDelayedPerformer() -> DownloadManager.DownloadPerformer {
        { _, _, _ in
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

    private func makeStream(name: String, sizeBytes: Int64 = 100, recoveryContext: StreamRecoveryContext? = nil) -> StreamInfo {
        StreamInfo(
            streamURL: URL(string: "https://cdn.example.com/\(UUID().uuidString).mkv")!,
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: name,
            sizeBytes: sizeBytes,
            debridService: DebridServiceType.realDebrid.rawValue,
            recoveryContext: recoveryContext
        )
    }
}

extension StreamRecoveryContext {
    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}


extension DownloadTask {
    static func == (lhs: DownloadTask, rhs: DownloadTask) -> Bool {
        lhs.id == rhs.id &&
        lhs.mediaId == rhs.mediaId &&
        lhs.episodeId == rhs.episodeId &&
        lhs.streamURL == rhs.streamURL &&
        lhs.fileName == rhs.fileName &&
        lhs.status == rhs.status &&
        lhs.progress == rhs.progress &&
        lhs.bytesWritten == rhs.bytesWritten &&
        lhs.totalBytes == rhs.totalBytes &&
        lhs.destinationPath == rhs.destinationPath &&
        lhs.errorMessage == rhs.errorMessage &&
        lhs.mediaTitle == rhs.mediaTitle &&
        lhs.mediaType == rhs.mediaType &&
        lhs.posterPath == rhs.posterPath &&
        lhs.seasonNumber == rhs.seasonNumber &&
        lhs.episodeNumber == rhs.episodeNumber &&
        lhs.episodeTitle == rhs.episodeTitle &&
        lhs.expectedBytes == rhs.expectedBytes &&
        lhs.resumeDataBase64 == rhs.resumeDataBase64
        // Intentionally ignore createdAt/updatedAt which can vary across persistence round-trips.
    }
}
