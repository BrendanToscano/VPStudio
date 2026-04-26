import Foundation
import SwiftUI
import Testing
@testable import VPStudio

@Suite("ViewModel Task Lifecycle")
struct ViewModelTaskLifecycleTests {
    @Test
    func searchViewModelExposesCancellationHookForInFlightTasks() throws {
        let source = try contents(of: "VPStudio/ViewModels/Search/SearchViewModel.swift")
        #expect(source.contains("func cancelInFlightWork()"))
        #expect(source.contains("searchTask?.cancel()"))
        #expect(source.contains("searchTask = nil"))
        #expect(source.contains("loadMoreTask?.cancel()"))
        #expect(source.contains("loadMoreTask = nil"))
    }

    @Test
    func detailViewModelExposesCancellationHook() throws {
        let source = try contents(of: "VPStudio/ViewModels/Detail/DetailViewModel.swift")
        #expect(source.contains("searchTask?.cancel()"))
        #expect(source.contains("func cancelInFlightWork()"))
        #expect(source.contains("searchTask = nil"))
    }

    @Test
    func detailViewCancelsViewModelWorkOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("viewModel?.cancelInFlightWork()"))
        #expect(source.contains("tmdbReloadTask?.cancel()"))
        #expect(source.contains("libraryReloadTask?.cancel()"))
        #expect(source.contains("feedbackReloadTask?.cancel()"))
        #expect(source.contains("streamResolutionTask?.cancel()"))
    }

    @Test
    func searchViewCancelsViewModelWorkOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Search/SearchView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("viewModel.cancelInFlightWork()"))
    }

    @Test
    func detailViewCoalescesNotificationDrivenReloadTasks() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        #expect(source.contains("tmdbReloadTask?.cancel()"))
        #expect(source.contains("tmdbReloadTask = Task { await reloadDetailForLatestTMDBKey() }"))
        #expect(source.contains("libraryReloadTask?.cancel()"))
        #expect(source.contains("libraryReloadTask = Task { await vm.reloadLibraryState() }"))
        #expect(source.contains(".watchHistoryDidChange"))
        #expect(source.contains("feedbackReloadTask?.cancel()"))
        #expect(source.contains("feedbackReloadTask = Task { await vm.reloadFeedbackState() }"))
    }

    @Test
    func detailViewCoalescesStreamResolutionWorkPerSelection() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        #expect(source.contains("@State private var streamResolutionTask: Task<Void, Never>?"))
        #expect(source.contains("streamResolutionTask?.cancel()"))
        #expect(source.contains("streamResolutionTask = Task {"))
        #expect(source.contains("guard !Task.isCancelled else { return }"))
    }

    @Test
    func detailViewKeysInitialTaskToPreviewIdentity() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        #expect(source.contains(".task(id: previewTaskIdentity)"))
        #expect(source.contains("var previewTaskIdentity: String"))
        #expect(source.contains("preview.type.rawValue"))
        #expect(source.contains("preview.id"))
        #expect(source.contains("preview.tmdbId.map(String.init)"))
        #expect(source.contains("preview.episodeId"))
        #expect(source.contains("preview.seasonNumber.map(String.init)"))
        #expect(source.contains("preview.episodeNumber.map(String.init)"))
    }

    @Test
    func detailViewWiresBatchedTorrentRowsAndLoadMoreControl() throws {
        // Torrents section may live in DetailView.swift or extracted DetailTorrentsSection.swift
        let mainSource = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        let torrentSource = (try? contents(of: "VPStudio/Views/Windows/Detail/DetailTorrentsSection.swift")) ?? ""
        let source = mainSource + "\n" + torrentSource
        let hasResultLoop =
            source.contains("ForEach(vm.torrentSearch.results)") ||
            source.contains("ForEach(viewModel.torrentSearch.results)") ||
            source.contains("ForEach(Array(vm.torrentSearch.results.enumerated())")
        #expect(hasResultLoop)
        let hasLoadMoreCheck =
            source.contains("if vm.canLoadMoreTorrents") ||
            source.contains("if viewModel.canLoadMoreTorrents")
        #expect(hasLoadMoreCheck)
        let hasShownCount =
            source.contains("let shownCount = vm.torrentSearch.results.count") ||
            source.contains("let shownCount = viewModel.torrentSearch.results.count")
        #expect(hasShownCount)
        let hasTotalCount =
            source.contains("let totalCount = shownCount + vm.remainingTorrentCount") ||
            source.contains("let totalCount = shownCount + viewModel.remainingTorrentCount")
        #expect(hasTotalCount)
        let hasLoadMore =
            source.contains("vm.loadMoreTorrentResults()") ||
            source.contains("viewModel.loadMoreTorrentResults()")
        #expect(hasLoadMore)
        let hasNextBatch =
            source.contains("vm.nextTorrentBatchCount") ||
            source.contains("viewModel.nextTorrentBatchCount")
        #expect(hasNextBatch)
        let hasRemaining =
            source.contains("vm.remainingTorrentCount") ||
            source.contains("viewModel.remainingTorrentCount")
        #expect(hasRemaining)
    }

    @Test
    func detailViewEpisodeSelectionKeepsEpisodeContextAndTriggersSearch() throws {
        let layoutSource = try contents(of: "VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift")
        let seasonsSource = (try? contents(of: "VPStudio/Views/Windows/Detail/DetailSeasonsSection.swift")) ?? ""
        let source = layoutSource + "\n" + seasonsSource
        let seasonsSectionBody: String
        if layoutSource.contains("private func episodesSection()") {
            let episodesBody = try functionBody(containing: "private func episodesSection()", in: layoutSource)
            let episodeCardBody = try functionBody(containing: "private func episodeCard(", in: layoutSource)
            seasonsSectionBody = episodesBody + "\n" + episodeCardBody
        } else {
            seasonsSectionBody = source
        }

        let hasEpisodeLoop = containsIgnoringWhitespace(
            seasonsSectionBody,
            "ForEach(viewModel.episodes) { episode in"
        ) || containsIgnoringWhitespace(
            seasonsSectionBody,
            "ForEach(vm.episodes) { episode in"
        )
        #expect(hasEpisodeLoop)
        let hasSelectEpisode = seasonsSectionBody.contains("vm.selectEpisode(episode)") ||
            seasonsSectionBody.contains("viewModel.selectEpisode(episode)")
        #expect(hasSelectEpisode)
        let hasSearchCall = seasonsSectionBody.contains("vm.searchTorrents()") ||
            seasonsSectionBody.contains("viewModel.searchTorrents()")
        #expect(hasSearchCall)

        if hasSearchCall {
            let selectToken = seasonsSectionBody.contains("viewModel.selectEpisode(episode)") ? "viewModel.selectEpisode(episode)" : "vm.selectEpisode(episode)"
            let selectRange = try requiredRange(of: selectToken, in: seasonsSectionBody)
            let searchToken = seasonsSectionBody.contains("viewModel.searchTorrents()") ? "viewModel.searchTorrents()" : "vm.searchTorrents()"
            let searchRange = try requiredRange(of: searchToken, in: seasonsSectionBody)
            #expect(selectRange.lowerBound < searchRange.lowerBound)
        }
    }

    @Test
    func detailViewKeysRenderedLayoutToPreviewIdentityAndAvoidsForcedResultScroll() throws {
        let detailSource = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        let layoutSource = try contents(of: "VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift")

        let detailContentBody = try functionBody(containing: "func detailContent(", in: detailSource)
        #expect(detailContentBody.contains(".id(previewTaskIdentity)"))
        #expect(layoutSource.contains("ScrollView {"))
        #expect(!layoutSource.contains("ScrollViewReader"))
        #expect(!layoutSource.contains(".scrollTo("))
    }

    @Test
    func searchViewCoalescesTMDBReloadTask() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Search/SearchView.swift")
        #expect(source.contains("tmdbReloadTask?.cancel()"))
        #expect(source.contains("tmdbReloadTask = Task { await reloadTMDBConfigurationAndSearch() }"))
    }

    @Test
    func searchViewUsesBrowseAwareEmptyStateCopy() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Search/SearchView.swift")
        #expect(source.contains("ExploreEmptyView(query: emptyStateQuery)"))
        #expect(source.contains("private var emptyStateQuery: String"))
    }

    @Test
    func contentViewDoesNotPostMainWindowPlayerDismissalNotification() throws {
        let source = try contents(of: "VPStudio/Views/Windows/ContentView.swift")
        #expect(!source.contains("NotificationCenter.default.post(name: .mainWindowDidActivate, object: nil)"))
        #expect(!source.contains("dismissWindow(id: \"player\")"))
        #expect(!source.contains("terminateActivePlayerSession()"))
    }

    @Test
    func quickStartPromptRoutesSkipSetupToLibraryAndOnlyShowsOnDiscover() throws {
        let source = try contents(of: "VPStudio/Views/Windows/ContentView.swift")
        #expect(source.contains("Label(QuickStartPromptPolicy.skipSetupTitle, systemImage: \"books.vertical.fill\")"))
        #expect(source.contains("QuickStartPromptPolicy.skipSetupDestination"))
        #expect(source.contains("appState.selectedTab = QuickStartPromptPolicy.skipSetupDestination"))
        #expect(source.contains("appState.isShowingSetup = true"))
        #expect(source.contains("if isShowingQuickStartPrompt, state.selectedTab == .discover"))
    }

    @Test
    func detailViewSupportsResumePlaybackInitialIntent() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        #expect(source.contains("enum DetailInitialAction"))
        #expect(source.contains("let initialAction: DetailInitialAction"))
        #expect(source.contains("func runInitialActionIfNeeded(_ vm: DetailViewModel) async"))
        #expect(source.contains("guard initialAction == .resumePlayback else { return }"))
        #expect(source.contains("await vm.searchTorrents()"))
        #expect(source.contains("await openPlayer(for: stream, vm: vm)"))
    }

    @Test
    func contentViewConfiguresDiscoverViewModelWithTheSharedDatabase() throws {
        let source = try contents(of: "VPStudio/Views/Windows/ContentView.swift")
        #expect(source.contains("discoverViewModel.configure(database: appState.database)"))
    }

    @Test
    func playerViewHandlesDedicatedPlayerDismissalFromThePlayerLifecycle() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("dismissWindow(id: \"player\")"))
        #expect(source.contains("PlayerLifecyclePolicy.closesDedicatedPlayerWindowOnBack"))
        #expect(source.contains("PlayerLifecyclePolicy.dismissesCurrentPresentationOnBack"))
    }

    @Test
    func downloadsViewCoalescesNotificationReloadsAndCancelsOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Downloads/DownloadsView.swift")
        #expect(source.contains("@State private var reloadTask: Task<Void, Never>?"))
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("reloadTask?.cancel()"))
        #expect(source.contains("reloadTask = Task {"))
        #expect(source.contains("await vm.load()"))
        #expect(source.contains("await performQADownloadActionIfNeeded(vm)"))
    }

    @Test
    func downloadsViewRequiresConfirmationBeforeRemovingSingleTask() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Downloads/DownloadsView.swift")
        #expect(source.contains("confirmDeleteTaskID = task.id"))
        #expect(source.contains(".confirmationDialog("))
        #expect(source.contains("Delete Download?"))
        #expect(source.contains("Task { await vm.remove(task) }"))
    }

    @Test
    func imdbImportPreviewStagingDoesNotAutoImport() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/IMDbImportSettingsView.swift")
        #expect(source.contains(".fileImporter("))
        #expect(source.contains("selectedFileURL = url"))
        #expect(source.contains("await analyzeCSVHeaders(url: url)"))
        #expect(source.contains("previewDetected = true"))
        #expect(source.contains("isShowingPreview = false"))
    }

    @Test
    func seriesDetailEpisodeCardsUseSemanticButtonsAndAccessibility() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift")
        #expect(source.contains("private func episodeCard(episode: Episode) -> some View"))
        #expect(source.contains("return Button {"))
        #expect(source.contains("viewModel.selectEpisode(episode)"))
        #expect(source.contains(".contextMenu {"))
        #expect(source.contains(".accessibilityLabel(SeriesDetailPresentationPolicy.episodeAccessibilityLabel("))
        #expect(source.contains("Press and hold for watched options."))
    }

    @Test
    func environmentPreviewCardCancelsThumbnailDecodingWork() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Discover/EnvironmentPreviewRow.swift")
        #expect(source.contains("@State private var thumbnailLoadTask: Task<Void, Never>?"))
        #expect(source.contains("thumbnailLoadTask?.cancel()"))
        #expect(source.contains("withTaskCancellationHandler"))
        #expect(source.contains("decodeTask.cancel()"))
        #expect(source.contains(".onDisappear"))
    }

    private func functionBody(containing signatureToken: String, in source: String) throws -> String {
        guard let signatureRange = source.range(of: signatureToken) else {
            throw NSError(
                domain: "ViewModelTaskLifecycleTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing signature token: \(signatureToken)"]
            )
        }

        guard let openingBrace = source.range(
            of: "{",
            range: signatureRange.upperBound..<source.endIndex
        )?.lowerBound else {
            throw NSError(
                domain: "ViewModelTaskLifecycleTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing opening brace for signature token: \(signatureToken)"]
            )
        }

        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let bodyStart = source.index(after: openingBrace)
                    return String(source[bodyStart..<cursor])
                }
            }
            cursor = source.index(after: cursor)
        }

        throw NSError(
            domain: "ViewModelTaskLifecycleTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Missing closing brace for signature token: \(signatureToken)"]
        )
    }

    private func requiredRange(of token: String, in source: String) throws -> Range<String.Index> {
        guard let range = source.range(of: token) else {
            throw NSError(
                domain: "ViewModelTaskLifecycleTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Missing token: \(token)"]
            )
        }
        return range
    }

    private func firstCapture(in source: String, pattern: String) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern)
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        guard let match = regex.firstMatch(in: source, range: fullRange), match.numberOfRanges > 1 else {
            throw NSError(
                domain: "ViewModelTaskLifecycleTests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Missing regex capture for pattern: \(pattern)"]
            )
        }

        let captureRange = match.range(at: 1)
        guard captureRange.location != NSNotFound else {
            throw NSError(
                domain: "ViewModelTaskLifecycleTests",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Missing capture group 1 for pattern: \(pattern)"]
            )
        }
        return nsSource.substring(with: captureRange)
    }

    private func containsIgnoringWhitespace(_ source: String, _ snippet: String) -> Bool {
        normalizedWhitespace(source).contains(normalizedWhitespace(snippet))
    }

    private func normalizedWhitespace(_ source: String) -> String {
        source
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func contents(of relativePath: String) throws -> String {
        let absolutePath = repoRootURL().appendingPathComponent(relativePath).path
        return try String(contentsOfFile: absolutePath, encoding: .utf8)
    }

    private func repoRootURL() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return url
    }
}
