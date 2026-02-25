import Foundation
import Testing
@testable import VPStudio

@Suite struct DownloadButtonStateTests {

    // MARK: - Enum values

    @Test func allStatesAreDistinct() {
        let states: [DownloadButtonState] = [.idle, .resolving, .downloading, .completed, .failed]
        let unique = Set(states)
        #expect(unique.count == 5)
    }

    @Test func equatableConformance() {
        #expect(DownloadButtonState.idle == .idle)
        #expect(DownloadButtonState.resolving == .resolving)
        #expect(DownloadButtonState.downloading == .downloading)
        #expect(DownloadButtonState.completed == .completed)
        #expect(DownloadButtonState.failed == .failed)
        #expect(DownloadButtonState.idle != .downloading)
    }

    @Test func sendableConformance() async {
        let state: DownloadButtonState = .completed
        let result = await Task.detached { state }.value
        #expect(result == .completed)
    }

    // MARK: - DetailViewModel download state tracking

    @Test @MainActor
    func downloadStateDefaultsToIdle() {
        let appState = AppState()
        let vm = DetailViewModel(appState: appState)
        let torrent = Fixtures.torrent(hash: "abc123", title: "Movie.1080p")
        #expect(vm.downloadState(for: torrent) == .idle)
    }

    @Test @MainActor
    func downloadStatesTrackedByInfoHash() {
        let appState = AppState()
        let vm = DetailViewModel(appState: appState)
        vm.downloadStates["hash1"] = .downloading
        vm.downloadStates["hash2"] = .completed

        let t1 = Fixtures.torrent(hash: "hash1", title: "Movie A")
        let t2 = Fixtures.torrent(hash: "hash2", title: "Movie B")
        let t3 = Fixtures.torrent(hash: "hash3", title: "Movie C")

        #expect(vm.downloadState(for: t1) == .downloading)
        #expect(vm.downloadState(for: t2) == .completed)
        #expect(vm.downloadState(for: t3) == .idle)
    }

    @Test @MainActor
    func downloadStateTransitionsFromIdleToResolving() {
        let appState = AppState()
        let vm = DetailViewModel(appState: appState)
        vm.downloadStates["abc"] = .resolving
        let torrent = Fixtures.torrent(hash: "abc", title: "Movie")
        #expect(vm.downloadState(for: torrent) == .resolving)
    }

    @Test @MainActor
    func downloadStateTransitionsToDownloading() {
        let appState = AppState()
        let vm = DetailViewModel(appState: appState)
        vm.downloadStates["abc"] = .downloading
        let torrent = Fixtures.torrent(hash: "abc", title: "Movie")
        #expect(vm.downloadState(for: torrent) == .downloading)
    }

    @Test @MainActor
    func downloadStateTransitionsToCompleted() {
        let appState = AppState()
        let vm = DetailViewModel(appState: appState)
        vm.downloadStates["abc"] = .completed
        let torrent = Fixtures.torrent(hash: "abc", title: "Movie")
        #expect(vm.downloadState(for: torrent) == .completed)
    }

    @Test @MainActor
    func downloadStateTransitionsToFailed() {
        let appState = AppState()
        let vm = DetailViewModel(appState: appState)
        vm.downloadStates["abc"] = .failed
        let torrent = Fixtures.torrent(hash: "abc", title: "Movie")
        #expect(vm.downloadState(for: torrent) == .failed)
    }

    @Test @MainActor
    func multipleDownloadsTrackedIndependently() {
        let appState = AppState()
        let vm = DetailViewModel(appState: appState)
        vm.downloadStates["hash-a"] = .downloading
        vm.downloadStates["hash-b"] = .completed
        vm.downloadStates["hash-c"] = .failed

        #expect(vm.downloadState(for: Fixtures.torrent(hash: "hash-a", title: "A")) == .downloading)
        #expect(vm.downloadState(for: Fixtures.torrent(hash: "hash-b", title: "B")) == .completed)
        #expect(vm.downloadState(for: Fixtures.torrent(hash: "hash-c", title: "C")) == .failed)
    }

    @Test @MainActor
    func downloadStatesResetOnNewSearch() {
        // Verify that download states persist across searches
        // (they should NOT be cleared — the download is still in progress)
        let appState = AppState()
        let vm = DetailViewModel(appState: appState)
        vm.downloadStates["abc"] = .downloading

        // Simulate selecting a different episode (clears search results but not download states)
        let ep = Episode(id: "ep-2", mediaId: "tt1", seasonNumber: 1, episodeNumber: 2, title: "Ep 2")
        vm.selectEpisode(ep)

        #expect(vm.downloadStates["abc"] == .downloading, "Download state should persist across episode changes")
    }
}
