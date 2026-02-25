import Foundation
import Testing
@testable import VPStudio

// MARK: - DownloadMediaGroup Model Tests

@Suite
struct DownloadMediaGroupTests {
    @Test
    func posterURLBuildsFromPath() {
        let group = DownloadMediaGroup(
            mediaId: "tt100",
            mediaTitle: "Movie",
            mediaType: "movie",
            posterPath: "/abc123.jpg",
            tasks: []
        )
        #expect(group.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342/abc123.jpg")
    }

    @Test
    func posterURLIsNilWhenPathIsNil() {
        let group = DownloadMediaGroup(
            mediaId: "tt100",
            mediaTitle: "Movie",
            mediaType: "movie",
            posterPath: nil,
            tasks: []
        )
        #expect(group.posterURL == nil)
    }

    @Test
    func completedCountFiltersCorrectly() {
        let group = DownloadMediaGroup(
            mediaId: "tt100",
            mediaTitle: "Movie",
            mediaType: "movie",
            posterPath: nil,
            tasks: [
                makeTask(id: "1", status: .completed),
                makeTask(id: "2", status: .downloading),
                makeTask(id: "3", status: .completed),
                makeTask(id: "4", status: .failed),
            ]
        )
        #expect(group.completedCount == 2)
    }

    @Test
    func totalCountIsTaskCount() {
        let group = DownloadMediaGroup(
            mediaId: "tt100",
            mediaTitle: "Movie",
            mediaType: "movie",
            posterPath: nil,
            tasks: [
                makeTask(id: "1", status: .completed),
                makeTask(id: "2", status: .downloading),
            ]
        )
        #expect(group.totalCount == 2)
    }

    @Test
    func overallProgressAveragesTasks() {
        let group = DownloadMediaGroup(
            mediaId: "tt100",
            mediaTitle: "Movie",
            mediaType: "movie",
            posterPath: nil,
            tasks: [
                makeTask(id: "1", progress: 1.0),
                makeTask(id: "2", progress: 0.5),
            ]
        )
        #expect(abs(group.overallProgress - 0.75) < 0.001)
    }

    @Test
    func overallProgressZeroForEmptyTasks() {
        let group = DownloadMediaGroup(
            mediaId: "tt100",
            mediaTitle: "Movie",
            mediaType: "movie",
            posterPath: nil,
            tasks: []
        )
        #expect(group.overallProgress == 0)
    }

    @Test
    func hasActiveDownloadsDetectsNonTerminal() {
        let groupWithActive = DownloadMediaGroup(
            mediaId: "tt100",
            mediaTitle: "Movie",
            mediaType: "movie",
            posterPath: nil,
            tasks: [
                makeTask(id: "1", status: .completed),
                makeTask(id: "2", status: .downloading),
            ]
        )
        #expect(groupWithActive.hasActiveDownloads == true)

        let groupAllTerminal = DownloadMediaGroup(
            mediaId: "tt101",
            mediaTitle: "Movie 2",
            mediaType: "movie",
            posterPath: nil,
            tasks: [
                makeTask(id: "3", status: .completed),
                makeTask(id: "4", status: .failed),
            ]
        )
        #expect(groupAllTerminal.hasActiveDownloads == false)
    }

    @Test
    func identifiableUsesMediaId() {
        let group = DownloadMediaGroup(
            mediaId: "tt999",
            mediaTitle: "Title",
            mediaType: "movie",
            posterPath: nil,
            tasks: []
        )
        #expect(group.id == "tt999")
    }

    private func makeTask(
        id: String = UUID().uuidString,
        status: DownloadStatus = .queued,
        progress: Double = 0
    ) -> DownloadTask {
        DownloadTask(
            id: id,
            mediaId: "tt100",
            streamURL: "https://cdn.example.com/file.mkv",
            fileName: "file.mkv",
            status: status,
            progress: progress
        )
    }
}

// MARK: - DownloadsViewModel Tests

@Suite(.serialized)
struct DownloadsViewModelTests {
    // MARK: - Load & Grouping

    @Test
    @MainActor
    func loadPopulatesGroupsAndTasks() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task1 = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", mediaTitle: "Movie A", mediaType: "movie")
        let task2 = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/2.mkv", fileName: "2.mkv", mediaTitle: "Movie A", mediaType: "movie")
        let task3 = DownloadTask(mediaId: "tt200", streamURL: "https://cdn.example.com/3.mkv", fileName: "3.mkv", mediaTitle: "Movie B", mediaType: "movie")
        await stubManager.setDownloads([task1, task2, task3])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()

        #expect(vm.tasks.count == 3)
        #expect(vm.groups.count == 2)

        let groupA = vm.groups.first(where: { $0.mediaId == "tt100" })
        #expect(groupA?.tasks.count == 2)
        #expect(groupA?.mediaTitle == "Movie A")

        let groupB = vm.groups.first(where: { $0.mediaId == "tt200" })
        #expect(groupB?.tasks.count == 1)
    }

    @Test
    @MainActor
    func loadGroupsSeriesEpisodesBySortKey() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        // Episodes out of order: S02E01, S01E03, S01E01
        let ep1 = DownloadTask(mediaId: "tt300", streamURL: "https://cdn.example.com/s02e01.mkv", fileName: "s02e01.mkv", mediaTitle: "Show", mediaType: "series", seasonNumber: 2, episodeNumber: 1, episodeTitle: "Ep 1")
        let ep2 = DownloadTask(mediaId: "tt300", streamURL: "https://cdn.example.com/s01e03.mkv", fileName: "s01e03.mkv", mediaTitle: "Show", mediaType: "series", seasonNumber: 1, episodeNumber: 3, episodeTitle: "Ep 3")
        let ep3 = DownloadTask(mediaId: "tt300", streamURL: "https://cdn.example.com/s01e01.mkv", fileName: "s01e01.mkv", mediaTitle: "Show", mediaType: "series", seasonNumber: 1, episodeNumber: 1, episodeTitle: "Ep 1")
        await stubManager.setDownloads([ep1, ep2, ep3])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()

        #expect(vm.groups.count == 1)
        let group = vm.groups[0]
        #expect(group.mediaType == "series")

        // Should be sorted: S01E01, S01E03, S02E01
        let sortKeys = group.tasks.map(\.episodeSortKey)
        #expect(sortKeys == [10001, 10003, 20001])
    }

    @Test
    @MainActor
    func loadWithEmptyResultsSetsEmptyGroupsAndTasks() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        await stubManager.setDownloads([])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()

        #expect(vm.tasks.isEmpty)
        #expect(vm.groups.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test
    @MainActor
    func loadErrorSetsErrorMessage() async {
        let appState = AppState()
        let manager = FailingDownloadManager(error: NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "load-failed"]))

        let vm = DownloadsViewModel(appState: appState, downloadManager: manager)
        await vm.load()

        #expect(vm.errorMessage == "load-failed")
    }

    // MARK: - Cancel

    @Test
    @MainActor
    func cancelUpdatesTaskStatus() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", status: .downloading)
        await stubManager.setDownloads([task])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()
        await vm.cancel(task)

        #expect(vm.tasks.first?.status == .cancelled)
    }

    // MARK: - Retry

    @Test
    @MainActor
    func retryRequeuesTask() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", status: .failed)
        await stubManager.setDownloads([task])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()
        await vm.retry(task)

        #expect(vm.tasks.first?.status == .queued)
    }

    @Test
    @MainActor
    func retryErrorSurfacesMessage() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", status: .failed)
        await stubManager.setDownloads([task])
        await stubManager.setRetryError(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "retry-error"]))

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.retry(task)

        #expect(vm.errorMessage == "retry-error")
    }

    // MARK: - Remove Single

    @Test
    @MainActor
    func removeDeletesTask() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv")
        await stubManager.setDownloads([task])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()
        #expect(vm.tasks.count == 1)

        await vm.remove(task)
        #expect(vm.tasks.isEmpty)
        #expect(vm.groups.isEmpty)
    }

    @Test
    @MainActor
    func removeErrorSurfacesMessage() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv")
        await stubManager.setDownloads([task])
        await stubManager.setRemoveError(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "remove-error"]))

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.remove(task)

        #expect(vm.errorMessage == "remove-error")
    }

    // MARK: - Remove All (Group Delete)

    @Test
    @MainActor
    func removeAllDeletesEntireMediaGroup() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task1 = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", mediaTitle: "Movie A")
        let task2 = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/2.mkv", fileName: "2.mkv", mediaTitle: "Movie A")
        let task3 = DownloadTask(mediaId: "tt200", streamURL: "https://cdn.example.com/3.mkv", fileName: "3.mkv", mediaTitle: "Movie B")
        await stubManager.setDownloads([task1, task2, task3])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()
        #expect(vm.groups.count == 2)

        await vm.removeAll(mediaId: "tt100")
        #expect(vm.groups.count == 1)
        #expect(vm.groups.first?.mediaId == "tt200")
        #expect(vm.tasks.count == 1)
    }

    @Test
    @MainActor
    func removeAllErrorSurfacesMessage() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv")
        await stubManager.setDownloads([task])
        await stubManager.setRemoveError(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "remove-all-error"]))

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.removeAll(mediaId: "tt100")

        #expect(vm.errorMessage == "remove-all-error")
    }

    // MARK: - Play File

    @Test
    @MainActor
    func playFileIgnoresNonCompletedTask() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", status: .downloading)

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        vm.playFile(task)

        // Should not crash or set a session for non-completed downloads
        #expect(appState.activePlayerSession == nil)
    }

    @Test
    @MainActor
    func playFileIgnoresTaskWithNoDestination() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", status: .completed, destinationPath: nil)

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        vm.playFile(task)

        #expect(appState.activePlayerSession == nil)
    }

    // MARK: - Group Ordering

    @Test
    @MainActor
    func groupsOrderedByMostRecentUpdate() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let oldDate = Date(timeIntervalSinceReferenceDate: 1000)
        let newDate = Date(timeIntervalSinceReferenceDate: 2000)

        let task1 = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", mediaTitle: "Old Movie", updatedAt: oldDate)
        let task2 = DownloadTask(mediaId: "tt200", streamURL: "https://cdn.example.com/2.mkv", fileName: "2.mkv", mediaTitle: "New Movie", updatedAt: newDate)
        await stubManager.setDownloads([task1, task2])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()

        #expect(vm.groups.count == 2)
        #expect(vm.groups[0].mediaId == "tt200") // newer first
        #expect(vm.groups[1].mediaId == "tt100")
    }

    @Test
    @MainActor
    func groupUsesFirstTaskPosterPath() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task1 = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/1.mkv", fileName: "1.mkv", mediaTitle: "Movie", posterPath: "/poster.jpg")
        await stubManager.setDownloads([task1])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()

        #expect(vm.groups.first?.posterPath == "/poster.jpg")
        #expect(vm.groups.first?.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342/poster.jpg")
    }

    // MARK: - Cancellation Safety

    @Test
    @MainActor
    func cancelledLoadDoesNotPublishCancellationAsError() async {
        let appState = AppState()
        let manager = CancellableBlockingDownloadManager()
        let vm = DownloadsViewModel(appState: appState, downloadManager: manager)
        let baselineTask = DownloadTask(mediaId: "baseline", streamURL: "https://cdn.example.com/baseline.mkv", fileName: "baseline.mkv")
        vm.tasks = [baselineTask]

        let loadTask = Task { await vm.load() }
        await manager.waitForFirstListStart()
        loadTask.cancel()
        await loadTask.value

        #expect(vm.tasks.map(\.id) == [baselineTask.id])
        #expect(vm.errorMessage == nil)
    }

    @Test
    @MainActor
    func cancelledOlderLoadCannotOverwriteNewerLoadResults() async {
        let appState = AppState()
        let staleTask = DownloadTask(mediaId: "stale", streamURL: "https://cdn.example.com/stale.mkv", fileName: "stale.mkv")
        let freshTask = DownloadTask(mediaId: "fresh", streamURL: "https://cdn.example.com/fresh.mkv", fileName: "fresh.mkv")
        let manager = NonCooperativeBlockingDownloadManager(
            firstResult: [staleTask],
            secondResult: [freshTask]
        )
        let vm = DownloadsViewModel(appState: appState, downloadManager: manager)

        let olderLoad = Task { await vm.load() }
        await manager.waitForFirstListStart()
        olderLoad.cancel()

        let newerLoad = Task { await vm.load() }
        await newerLoad.value

        await manager.unblockFirstList()
        await olderLoad.value

        #expect(vm.tasks.map(\.id) == [freshTask.id])
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Mixed Media Types

    @Test
    @MainActor
    func mixedMovieAndSeriesGroupsSeparately() async {
        let appState = AppState()
        let stubManager = StubDownloadManager()

        let movie = DownloadTask(mediaId: "tt100", streamURL: "https://cdn.example.com/movie.mkv", fileName: "movie.mkv", mediaTitle: "Movie", mediaType: "movie")
        let ep1 = DownloadTask(mediaId: "tt200", streamURL: "https://cdn.example.com/s01e01.mkv", fileName: "s01e01.mkv", mediaTitle: "Series", mediaType: "series", seasonNumber: 1, episodeNumber: 1)
        let ep2 = DownloadTask(mediaId: "tt200", streamURL: "https://cdn.example.com/s01e02.mkv", fileName: "s01e02.mkv", mediaTitle: "Series", mediaType: "series", seasonNumber: 1, episodeNumber: 2)
        await stubManager.setDownloads([movie, ep1, ep2])

        let vm = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await vm.load()

        #expect(vm.groups.count == 2)
        let movieGroup = vm.groups.first(where: { $0.mediaType == "movie" })
        let seriesGroup = vm.groups.first(where: { $0.mediaType == "series" })

        #expect(movieGroup?.tasks.count == 1)
        #expect(seriesGroup?.tasks.count == 2)
    }

    // MARK: - Exhaustive Mutation Tests (preserved from original)

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<30), full: Array(0..<30)))
    @MainActor
    func loadAndMutationsReloadState(index: Int) async {
        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt\(index)", streamURL: "https://cdn.example.com/\(index).mkv", fileName: "\(index).mkv")
        await stubManager.setDownloads([task])

        let viewModel = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await viewModel.load()
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.groups.count == 1)

        await viewModel.cancel(task)
        #expect(viewModel.tasks.first?.status == .cancelled)

        await viewModel.retry(task)
        #expect(viewModel.tasks.first?.status == .queued)

        await viewModel.remove(task)
        #expect(viewModel.tasks.isEmpty)
        #expect(viewModel.groups.isEmpty)
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<30), full: Array(0..<30)))
    @MainActor
    func retryAndRemoveErrorsSurface(index: Int) async {
        let sampleError = NSError(domain: "test", code: index, userInfo: [NSLocalizedDescriptionKey: "sample-\(index)"])

        let appState = AppState()
        let stubManager = StubDownloadManager()
        let task = DownloadTask(mediaId: "tt\(index)", streamURL: "https://cdn.example.com/\(index).mkv", fileName: "\(index).mkv")
        await stubManager.setDownloads([task])
        await stubManager.setRetryError(sampleError)

        let viewModel = DownloadsViewModel(appState: appState, downloadManager: stubManager)
        await viewModel.retry(task)
        #expect(viewModel.errorMessage?.contains("sample-") == true)

        await stubManager.setRetryError(nil)
        await stubManager.setRemoveError(sampleError)
        await viewModel.remove(task)
        #expect(viewModel.errorMessage?.contains("sample-") == true)
    }
}

// MARK: - Test Helpers

private actor FailingDownloadManager: DownloadManaging {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func listDownloads() async throws -> [DownloadTask] {
        throw error
    }

    func cancelDownload(id: String) async {}
    func retryDownload(id: String) async throws { throw error }
    func removeDownload(id: String) async throws { throw error }
    func removeDownloads(mediaId: String) async throws { throw error }
}

private actor CancellableBlockingDownloadManager: DownloadManaging {
    private var listCalls = 0
    private var firstListContinuation: CheckedContinuation<[DownloadTask], Error>?
    private var firstListStartedContinuation: CheckedContinuation<Void, Never>?

    func listDownloads() async throws -> [DownloadTask] {
        listCalls += 1
        if listCalls == 1 {
            return try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        firstListContinuation = continuation
                        firstListStartedContinuation?.resume()
                        firstListStartedContinuation = nil
                    }
                },
                onCancel: {
                    Task { await self.resumeFirstListIfNeeded(throwing: CancellationError()) }
                }
            )
        }

        return []
    }

    func waitForFirstListStart() async {
        if firstListContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            firstListStartedContinuation = continuation
        }
    }

    private func resumeFirstListIfNeeded(throwing error: Error) {
        firstListContinuation?.resume(throwing: error)
        firstListContinuation = nil
    }

    func cancelDownload(id: String) async {}
    func retryDownload(id: String) async throws {}
    func removeDownload(id: String) async throws {}
    func removeDownloads(mediaId: String) async throws {}
}

private actor NonCooperativeBlockingDownloadManager: DownloadManaging {
    private let firstResult: [DownloadTask]
    private let secondResult: [DownloadTask]

    private var listCalls = 0
    private var firstListContinuation: CheckedContinuation<[DownloadTask], Never>?
    private var firstListStartedContinuation: CheckedContinuation<Void, Never>?

    init(firstResult: [DownloadTask], secondResult: [DownloadTask]) {
        self.firstResult = firstResult
        self.secondResult = secondResult
    }

    func listDownloads() async throws -> [DownloadTask] {
        listCalls += 1
        if listCalls == 1 {
            return await withCheckedContinuation { continuation in
                firstListContinuation = continuation
                firstListStartedContinuation?.resume()
                firstListStartedContinuation = nil
            }
        }

        return secondResult
    }

    func waitForFirstListStart() async {
        if firstListContinuation != nil {
            return
        }

        await withCheckedContinuation { continuation in
            firstListStartedContinuation = continuation
        }
    }

    func unblockFirstList() {
        firstListContinuation?.resume(returning: firstResult)
        firstListContinuation = nil
    }

    func cancelDownload(id: String) async {}
    func retryDownload(id: String) async throws {}
    func removeDownload(id: String) async throws {}
    func removeDownloads(mediaId: String) async throws {}
}
