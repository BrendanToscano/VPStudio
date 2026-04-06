import Foundation

final class DownloadCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelledFlag = false
    private var callbacks: [@Sendable () -> Void] = []

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelledFlag
    }

    func register(_ callback: @escaping @Sendable () -> Void) {
        let shouldInvokeImmediately: Bool
        lock.lock()
        if isCancelledFlag {
            shouldInvokeImmediately = true
        } else {
            callbacks.append(callback)
            shouldInvokeImmediately = false
        }
        lock.unlock()

        if shouldInvokeImmediately {
            callback()
        }
    }

    func cancel() {
        let pendingCallbacks: [@Sendable () -> Void]
        lock.lock()
        guard !isCancelledFlag else {
            lock.unlock()
            return
        }
        isCancelledFlag = true
        pendingCallbacks = callbacks
        callbacks.removeAll()
        lock.unlock()

        for callback in pendingCallbacks {
            callback()
        }
    }
}

actor DownloadManager {
    typealias DownloadPerformer = @Sendable (URL, @escaping @Sendable (Int64, Int64, Int64) -> Void, DownloadCancellationController) async throws -> (URL, URLResponse)
    typealias LinkRefresher = @Sendable (StreamRecoveryContext) async throws -> URL
    typealias SleepClosure = @Sendable (Duration) async throws -> Void

    private let database: DatabaseManager
    private let fileManager: FileManager
    private let downloadsDirectory: URL
    private let performer: DownloadPerformer
    private let linkRefresher: LinkRefresher?
    private let sleep: SleepClosure

    private struct DownloadJob {
        let task: Task<Void, Never>
        let cancellationController: DownloadCancellationController
    }

    private var jobs: [String: DownloadJob] = [:]
    private var reservedDestinationByTaskID: [String: URL] = [:]
    private var reservedDestinationPaths: Set<String> = []

    init(
        database: DatabaseManager,
        fileManager: FileManager = .default,
        downloadsDirectory: URL? = nil,
        performer: DownloadPerformer? = nil,
        linkRefresher: LinkRefresher? = nil,
        sleep: @escaping SleepClosure = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.database = database
        self.fileManager = fileManager
        self.linkRefresher = linkRefresher
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
        var recoveryJSON: String?
        if let ctx = stream.recoveryContext,
           let data = try? JSONEncoder().encode(ctx) {
            recoveryJSON = String(data: data, encoding: .utf8)
        }

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
            episodeTitle: episodeTitle,
            recoveryContextJSON: recoveryJSON
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
        if let job = jobs[id] {
            job.cancellationController.cancel()
            job.task.cancel()
        }
        try? await database.updateDownloadTaskStatus(id: id, status: .cancelled, errorMessage: nil)
        notifyDownloadsChanged()
    }

    func retryDownload(id: String) async throws {
        if let job = jobs[id] {
            job.cancellationController.cancel()
            job.task.cancel()
            await waitForJobTeardown(id: id)
        }

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
            mediaTitle: existing.mediaTitle,
            mediaType: existing.mediaType,
            posterPath: existing.posterPath,
            seasonNumber: existing.seasonNumber,
            episodeNumber: existing.episodeNumber,
            episodeTitle: existing.episodeTitle,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )

        try await database.saveDownloadTask(resetTask)
        reserveDestinationIfNeeded(for: id, fileName: resetTask.fileName)
        notifyDownloadsChanged()
        startJob(for: id)
    }

    func removeDownload(id: String) async throws {
        if let job = jobs[id] {
            job.cancellationController.cancel()
            job.task.cancel()
            await waitForJobTeardown(id: id)
        }

        if let existing = try await database.fetchDownloadTask(id: id),
           let destination = existing.destinationURL,
           fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        try await database.deleteDownloadTask(id: id)
        releaseReservedDestination(for: id)
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

        let cancellationController = DownloadCancellationController()
        let task = Task {
            await self.processDownload(id: id, cancellationController: cancellationController)
        }
        jobs[id] = DownloadJob(task: task, cancellationController: cancellationController)
    }

    private func waitForJobTeardown(id: String) async {
        while jobs[id] != nil {
            try? await sleep(.milliseconds(25))
        }
    }

    private func processDownload(id: String, cancellationController: DownloadCancellationController) async {
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

        var currentURL = streamURL
        var linkRefreshAttempted = false

        do {
            let tempURL = try await attemptDownload(url: currentURL, id: id, cancellationController: cancellationController)

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
            // Attempt link refresh on network/SSL errors if we have recovery context
            if !linkRefreshAttempted,
               Self.isLinkExpiredError(error),
               let refresher = linkRefresher,
               let context = task.recoveryContext {
                linkRefreshAttempted = true

                do {
                    try? await database.updateDownloadTaskStatus(id: id, status: .resolving, errorMessage: nil)
                    notifyDownloadsChanged()

                    let freshURL = try await refresher(context)
                    currentURL = freshURL

                    // Update the stored stream URL for future retries
                    try? await database.updateDownloadTaskStreamURL(id: id, streamURL: freshURL.absoluteString)

                    // Retry with fresh URL
                    try? await database.updateDownloadTaskStatus(id: id, status: .downloading, errorMessage: nil)
                    notifyDownloadsChanged()

                    let tempURL = try await attemptDownload(url: freshURL, id: id, cancellationController: cancellationController)

                    try Task.checkCancellation()
                    try ensureDownloadsDirectory()

                    let destination = reservedDestinationURL(for: id, fileName: task.fileName)
                    try fileManager.moveItem(at: tempURL, to: destination)

                    let finalBytes = (try? fileSize(at: destination)) ?? 0
                    try await database.updateDownloadTaskProgress(
                        id: id, progress: 1.0, bytesWritten: finalBytes,
                        totalBytes: finalBytes > 0 ? finalBytes : nil,
                        destinationPath: destination.path
                    )
                    try await database.updateDownloadTaskStatus(id: id, status: .completed, errorMessage: nil)
                    notifyDownloadsChanged()
                    return
                } catch is CancellationError {
                    try? await database.updateDownloadTaskStatus(id: id, status: .cancelled, errorMessage: nil)
                    notifyDownloadsChanged()
                    return
                } catch {
                    // Link refresh also failed — fall through to failure
                }
            }

            try? await database.updateDownloadTaskStatus(
                id: id,
                status: .failed,
                errorMessage: error.localizedDescription
            )
            notifyDownloadsChanged()
        }
    }

    private func attemptDownload(url: URL, id: String, cancellationController: DownloadCancellationController) async throws -> URL {
        let lastUpdateTime = ManagedAtomic<UInt64>(0)
        let updateInFlight = ManagedAtomic<Bool>(false)

        let (tempURL, _) = try await withTaskCancellationHandler(
            operation: {
                try await performer(url, { bytesWritten, totalBytesWritten, totalBytesExpected in
                    guard !cancellationController.isCancelled else { return }

                    let now = DispatchTime.now().uptimeNanoseconds
                    let last = lastUpdateTime.load()
                    let elapsed = now - last
                    guard elapsed > 1_000_000_000 || totalBytesWritten == totalBytesExpected else { return }
                    lastUpdateTime.store(now)

                    let progress = totalBytesExpected > 0
                        ? Double(totalBytesWritten) / Double(totalBytesExpected)
                        : 0.0
                    guard !updateInFlight.load() else { return }
                    updateInFlight.store(true)
                    let db = self.database
                    Task {
                        defer { updateInFlight.store(false) }
                        guard !cancellationController.isCancelled else { return }
                        try? await db.updateDownloadTaskProgress(
                            id: id,
                            progress: min(progress, 0.99),
                            bytesWritten: totalBytesWritten,
                            totalBytes: totalBytesExpected > 0 ? totalBytesExpected : nil,
                            destinationPath: nil
                        )
                        self.notifyDownloadsChanged()
                    }
                }, cancellationController)
            },
            onCancel: {
                cancellationController.cancel()
            }
        )
        return tempURL
    }

    /// Detect network errors that indicate an expired or dead download link.
    /// Works for any debrid service — checks for SSL timeouts, connection refused, HTTP 403/410.
    private static func isLinkExpiredError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // SSL/TLS handshake timeout (the exact error from the logs: domain 4, code -2205)
        if nsError.domain == "kCFErrorDomainCFNetwork" || nsError.domain == NSURLErrorDomain {
            // CFNetwork code 303 = secure connection failed
            if nsError.code == 303 { return true }
            // NSURLError codes for connection issues
            switch nsError.code {
            case NSURLErrorSecureConnectionFailed,     // -1200
                 NSURLErrorTimedOut,                    // -1001
                 NSURLErrorCannotConnectToHost,         // -1004
                 NSURLErrorNetworkConnectionLost,       // -1005
                 NSURLErrorServerCertificateUntrusted,  // -1202
                 NSURLErrorCannotFindHost:              // -1003
                return true
            default:
                break
            }
        }

        // Check underlying SSL error (kCFStreamErrorDomainSSL = 4, errSSLNetworkTimeout = -2205)
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return Self.isLinkExpiredError(underlyingError)
        }

        // Check for HTTP 403 (forbidden — expired token) or 410 (gone — link removed)
        if let response = nsError.userInfo["NSErrorFailingURLKey"] as? HTTPURLResponse {
            return response.statusCode == 403 || response.statusCode == 410
        }

        return false
    }

    // MARK: - Default Performer (delegate-based URLSession)

    private static func makeDefaultPerformer() -> DownloadPerformer {
        { url, progressHandler, cancellationController in
            let delegate = DownloadProgressDelegate(onProgress: progressHandler)
            let config = URLSessionConfiguration.default
            config.urlCache = nil                       // downloads don't need URL caching
            config.httpMaximumConnectionsPerHost = 4    // limit per-host concurrency
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

            return try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: url)
                delegate.setContinuation(continuation)
                cancellationController.register {
                    task.cancel()
                    session.invalidateAndCancel()
                    delegate.resumeIfNeeded(throwing: CancellationError())
                }
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
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Int64, Int64, Int64) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<(URL, URLResponse), any Error>?

    init(onProgress: @escaping @Sendable (Int64, Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func setContinuation(_ continuation: CheckedContinuation<(URL, URLResponse), any Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resumeIfNeeded(returning value: (URL, URLResponse)) {
        let continuation = takeContinuation()
        continuation?.resume(returning: value)
    }

    func resumeIfNeeded(throwing error: any Error) {
        let continuation = takeContinuation()
        continuation?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<(URL, URLResponse), any Error>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = continuation
        self.continuation = nil
        return continuation
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
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + location.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            resumeIfNeeded(returning: (tmp, downloadTask.response ?? URLResponse()))
        } catch {
            resumeIfNeeded(throwing: error)
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            resumeIfNeeded(throwing: error)
        }
        session.finishTasksAndInvalidate()
    }
}

// MARK: - Atomic helper (lock-based access)

private final class ManagedAtomic<Value>: @unchecked Sendable {
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
