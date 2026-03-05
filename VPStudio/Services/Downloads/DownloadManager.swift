import Foundation

actor DownloadManager {
    typealias DownloadPerformer = @Sendable (URL, @escaping @Sendable (Int64, Int64, Int64) -> Void) async throws -> (URL, URLResponse)
    typealias SleepClosure = @Sendable (Duration) async throws -> Void

    private let database: DatabaseManager
    private let fileManager: FileManager
    private let downloadsDirectory: URL
    private let performer: DownloadPerformer
    private let sleep: SleepClosure

    private var jobs: [String: Task<Void, Never>] = [:]
    private var reservedDestinationByTaskID: [String: URL] = [:]
    private var reservedDestinationPaths: Set<String> = []

    init(
        database: DatabaseManager,
        fileManager: FileManager = .default,
        downloadsDirectory: URL? = nil,
        performer: DownloadPerformer? = nil,
        sleep: @escaping SleepClosure = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.database = database
        self.fileManager = fileManager
        self.sleep = sleep

        if let downloadsDirectory {
            self.downloadsDirectory = downloadsDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.downloadsDirectory = appSupport
                .appendingPathComponent("VPStudio", isDirectory: true)
                .appendingPathComponent("Downloads", isDirectory: true)
        }

        self.performer = performer ?? Self.makeDefaultPerformer()
    }

    func enqueueDownload(stream: StreamInfo, mediaId: String, episodeId: String?, mediaTitle: String = "", mediaType: String = "movie", posterPath: String? = nil, seasonNumber: Int? = nil, episodeNumber: Int? = nil, episodeTitle: String? = nil) async throws -> DownloadTask {
        let task = DownloadTask(
            mediaId: mediaId,
            episodeId: episodeId,
            streamURL: stream.streamURL.absoluteString,
            fileName: sanitizedFileName(stream.fileName),
            mediaTitle: mediaTitle,
            mediaType: mediaType,
            posterPath: posterPath,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle
        )

        try await database.saveDownloadTask(task)
        reserveDestinationIfNeeded(for: task.id, fileName: task.fileName)
        notifyDownloadsChanged()
        startJob(for: task.id)
        return task
    }

    func listDownloads() async throws -> [DownloadTask] {
        try await database.fetchDownloadTasks()
    }

    func cancelDownload(id: String) async {
        jobs[id]?.cancel()
        jobs[id] = nil
        try? await database.updateDownloadTaskStatus(id: id, status: .cancelled, errorMessage: nil)
        notifyDownloadsChanged()
    }

    func retryDownload(id: String) async throws {
        guard let existing = try await database.fetchDownloadTask(id: id) else { return }

        let resetTask = DownloadTask(
            id: existing.id,
            mediaId: existing.mediaId,
            episodeId: existing.episodeId,
            streamURL: existing.streamURL,
            fileName: existing.fileName,
            status: .queued,
            progress: 0,
            bytesWritten: 0,
            totalBytes: nil,
            destinationPath: nil,
            errorMessage: nil,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )

        try await database.saveDownloadTask(resetTask)
        reserveDestinationIfNeeded(for: id, fileName: resetTask.fileName)
        notifyDownloadsChanged()
        startJob(for: id)
    }

    func removeDownload(id: String) async throws {
        jobs[id]?.cancel()
        jobs[id] = nil

        if let existing = try await database.fetchDownloadTask(id: id),
           let destination = existing.destinationURL,
           fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        try await database.deleteDownloadTask(id: id)
        notifyDownloadsChanged()
    }

    func removeDownloads(mediaId: String) async throws {
        let tasks = try await database.fetchDownloadTasks()
        let matching = tasks.filter { $0.mediaId == mediaId }
        for task in matching {
            try await removeDownload(id: task.id)
        }
    }

    private func startJob(for id: String) {
        guard jobs[id] == nil else { return }

        jobs[id] = Task { [weak self] in
            await self?.processDownload(id: id)
        }
    }

    private func processDownload(id: String) async {
        defer {
            jobs[id] = nil
            releaseReservedDestination(for: id)
        }

        guard let task = try? await database.fetchDownloadTask(id: id),
              let streamURL = URL(string: task.streamURL) else {
            try? await database.updateDownloadTaskStatus(
                id: id,
                status: .failed,
                errorMessage: "Invalid stream URL"
            )
            notifyDownloadsChanged()
            return
        }

        reserveDestinationIfNeeded(for: id, fileName: task.fileName)
        try? await database.updateDownloadTaskStatus(id: id, status: .downloading, errorMessage: nil)
        notifyDownloadsChanged()

        // Throttle DB writes to at most once per second
        let lastUpdateTime = ManagedAtomic<UInt64>(0)

        do {
            let (tempURL, _) = try await withTaskCancellationHandler(
                operation: {
                    try await performer(streamURL) { bytesWritten, totalBytesWritten, totalBytesExpected in
                        let now = DispatchTime.now().uptimeNanoseconds
                        let last = lastUpdateTime.load()
                        let elapsed = now - last
                        // Update at most once per second (1_000_000_000 ns)
                        guard elapsed > 1_000_000_000 || totalBytesWritten == totalBytesExpected else { return }
                        lastUpdateTime.store(now)

                        let progress = totalBytesExpected > 0
                            ? Double(totalBytesWritten) / Double(totalBytesExpected)
                            : 0.0
                        let db = self.database
                        try? await db.updateDownloadTaskProgress(
                            id: id,
                            progress: min(progress, 0.99),
                            bytesWritten: totalBytesWritten,
                            totalBytes: totalBytesExpected > 0 ? totalBytesExpected : nil,
                            destinationPath: nil
                        )
                        self.notifyDownloadsChanged()
                    }
                },
                onCancel: {}
            )

            try Task.checkCancellation()
            try ensureDownloadsDirectory()

            let destination = reservedDestinationURL(for: id, fileName: task.fileName)
            try fileManager.moveItem(at: tempURL, to: destination)

            let finalBytes = (try? fileSize(at: destination)) ?? 0

            try await database.updateDownloadTaskProgress(
                id: id,
                progress: 1.0,
                bytesWritten: finalBytes,
                totalBytes: finalBytes > 0 ? finalBytes : nil,
                destinationPath: destination.path
            )
            try await database.updateDownloadTaskStatus(id: id, status: .completed, errorMessage: nil)
            notifyDownloadsChanged()
        } catch is CancellationError {
            try? await database.updateDownloadTaskStatus(id: id, status: .cancelled, errorMessage: nil)
            notifyDownloadsChanged()
        } catch {
            try? await database.updateDownloadTaskStatus(
                id: id,
                status: .failed,
                errorMessage: error.localizedDescription
            )
            notifyDownloadsChanged()
        }
    }

    // MARK: - Default Performer (delegate-based URLSession)

    private static func makeDefaultPerformer() -> DownloadPerformer {
        { url, progressHandler in
            let delegate = DownloadProgressDelegate(onProgress: progressHandler)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }

            return try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: url)
                delegate.continuation = continuation
                task.resume()
            }
        }
    }

    // MARK: - Directory Helpers

    private func ensureDownloadsDirectory() throws {
        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
    }

    private func reserveDestinationIfNeeded(for id: String, fileName: String) {
        guard reservedDestinationByTaskID[id] == nil else { return }

        let destination = uniqueDestinationURL(for: fileName)
        reservedDestinationByTaskID[id] = destination
        reservedDestinationPaths.insert(destination.path)
    }

    private func reservedDestinationURL(for id: String, fileName: String) -> URL {
        if let destination = reservedDestinationByTaskID[id] {
            return destination
        }

        let destination = uniqueDestinationURL(for: fileName)
        reservedDestinationByTaskID[id] = destination
        reservedDestinationPaths.insert(destination.path)
        return destination
    }

    private func releaseReservedDestination(for id: String) {
        guard let destination = reservedDestinationByTaskID.removeValue(forKey: id) else { return }
        reservedDestinationPaths.remove(destination.path)
    }

    private func isDestinationAvailable(_ candidate: URL) -> Bool {
        !reservedDestinationPaths.contains(candidate.path) && !fileManager.fileExists(atPath: candidate.path)
    }

    private func uniqueDestinationURL(for fileName: String) -> URL {
        let candidate = downloadsDirectory.appendingPathComponent(fileName)
        if isDestinationAvailable(candidate) {
            return candidate
        }

        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let suffix = " (\(index))"
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            let next = downloadsDirectory.appendingPathComponent(name)
            if isDestinationAvailable(next) {
                return next
            }
            index += 1
        }
    }

    private func sanitizedFileName(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(
            of: "[^a-zA-Z0-9._ -]",
            with: "_",
            options: .regularExpression
        )
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "download-\(UUID().uuidString).mp4"
        }
        return trimmed
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    nonisolated private func notifyDownloadsChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
        }
    }
}

// MARK: - Download Progress Delegate

/// Bridges `URLSessionDownloadDelegate` callbacks into the async performer closure.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let onProgress: @Sendable (Int64, Int64, Int64) -> Void
    // Continuation is set once by the performer before task.resume().
    nonisolated(unsafe) var continuation: CheckedContinuation<(URL, URLResponse), any Error>?

    init(onProgress: @escaping @Sendable (Int64, Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Move the file to a temp location that persists beyond this callback
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + location.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            continuation?.resume(returning: (tmp, downloadTask.response ?? URLResponse()))
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

// MARK: - Atomic helper (lock-free UInt64 for throttling)

private final class ManagedAtomic<Value: FixedWidthInteger>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        _value = value
    }

    func load(ordering: Void = ()) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func store(_ value: Value, ordering: Void = ()) {
        lock.lock()
        defer { lock.unlock() }
        _value = value
    }
}
