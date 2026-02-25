import Foundation
#if os(macOS)
import AppKit
#endif
import Observation

protocol DownloadManaging: Sendable {
    func listDownloads() async throws -> [DownloadTask]
    func cancelDownload(id: String) async
    func retryDownload(id: String) async throws
    func removeDownload(id: String) async throws
    func removeDownloads(mediaId: String) async throws
}

extension DownloadManager: DownloadManaging {}

struct DownloadMediaGroup: Identifiable {
    var id: String { mediaId }
    let mediaId: String
    let mediaTitle: String
    let mediaType: String
    let posterPath: String?
    var tasks: [DownloadTask]

    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }

    var completedCount: Int {
        tasks.filter { $0.status == .completed }.count
    }

    var totalCount: Int { tasks.count }

    var overallProgress: Double {
        guard !tasks.isEmpty else { return 0 }
        return tasks.reduce(0.0) { $0 + $1.progress } / Double(tasks.count)
    }

    var hasActiveDownloads: Bool {
        tasks.contains { !$0.status.isTerminal }
    }
}

@Observable
@MainActor
final class DownloadsViewModel {
    var groups: [DownloadMediaGroup] = []
    var tasks: [DownloadTask] = []
    var isLoading = false
    var errorMessage: String?

    private let appState: AppState
    private let downloadManager: any DownloadManaging

    init(appState: AppState, downloadManager: (any DownloadManaging)? = nil) {
        self.appState = appState
        self.downloadManager = downloadManager ?? appState.downloadManager
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let latestTasks = try await downloadManager.listDownloads()
            guard !Task.isCancelled else { return }
            tasks = latestTasks
            groups = buildGroups(from: latestTasks)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func cancel(_ task: DownloadTask) async {
        await downloadManager.cancelDownload(id: task.id)
        await load()
    }

    func retry(_ task: DownloadTask) async {
        do {
            try await downloadManager.retryDownload(id: task.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ task: DownloadTask) async {
        do {
            try await downloadManager.removeDownload(id: task.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAll(mediaId: String) async {
        do {
            try await downloadManager.removeDownloads(mediaId: mediaId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playFile(_ task: DownloadTask) {
        guard task.status == .completed, let fileURL = task.destinationURL else { return }
        #if os(macOS)
        NSWorkspace.shared.open(fileURL)
        #else
        // On visionOS, create a player session from the local file
        let stream = StreamInfo(
            streamURL: fileURL,
            quality: .unknown,
            codec: .unknown,
            audio: .unknown,
            source: .unknown,
            hdr: .sdr,
            fileName: task.fileName,
            sizeBytes: task.totalBytes,
            debridService: "local"
        )
        let request = PlayerSessionRequest(
            stream: stream,
            mediaTitle: task.displayTitle,
            mediaId: task.mediaId,
            episodeId: task.episodeId
        )
        appState.activePlayerSession = request
        #endif
    }

    private func buildGroups(from tasks: [DownloadTask]) -> [DownloadMediaGroup] {
        var groupDict: [String: DownloadMediaGroup] = [:]

        for task in tasks {
            if var existing = groupDict[task.mediaId] {
                existing.tasks.append(task)
                groupDict[task.mediaId] = existing
            } else {
                groupDict[task.mediaId] = DownloadMediaGroup(
                    mediaId: task.mediaId,
                    mediaTitle: task.mediaTitle,
                    mediaType: task.mediaType,
                    posterPath: task.posterPath,
                    tasks: [task]
                )
            }
        }

        return groupDict.values
            .map { group in
                var sorted = group
                sorted.tasks.sort { lhs, rhs in
                    if lhs.episodeSortKey != rhs.episodeSortKey {
                        return lhs.episodeSortKey < rhs.episodeSortKey
                    }
                    return lhs.createdAt < rhs.createdAt
                }
                return sorted
            }
            .sorted { $0.tasks.first?.updatedAt ?? .distantPast > $1.tasks.first?.updatedAt ?? .distantPast }
    }
}
