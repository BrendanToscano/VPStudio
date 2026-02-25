import Foundation
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
    func searchViewCancelsViewModelWorkOnDisappearAndBeforeReplacement() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Search/SearchView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("viewModel.cancelInFlightWork()"))
        #expect(source.contains("let shouldSearch = !existingQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty\n        viewModel.cancelInFlightWork()"))
    }

    @Test
    func detailViewCoalescesNotificationDrivenReloadTasks() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        #expect(source.contains("tmdbReloadTask?.cancel()"))
        #expect(source.contains("tmdbReloadTask = Task { await reloadDetailForLatestTMDBKey() }"))
        #expect(source.contains("libraryReloadTask?.cancel()"))
        #expect(source.contains("libraryReloadTask = Task { await vm.reloadLibraryState() }"))
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
    }

    @Test
    func detailViewWiresBatchedTorrentRowsAndLoadMoreControl() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        let hasResultLoop =
            source.contains("ForEach(vm.torrentSearch.results)") ||
            source.contains("ForEach(Array(vm.torrentSearch.results.enumerated())")
        #expect(hasResultLoop)
        #expect(source.contains("if vm.canLoadMoreTorrents"))
        #expect(source.contains("let shownCount = vm.torrentSearch.results.count"))
        #expect(source.contains("let totalCount = shownCount + vm.remainingTorrentCount"))
        #expect(source.contains("vm.loadMoreTorrentResults()"))
        #expect(source.contains("vm.nextTorrentBatchCount"))
        #expect(source.contains("vm.remainingTorrentCount"))
    }

    @Test
    func detailViewProvidesInlineEpisodeFindStreamsActionWithEpisodeContext() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        let seasonsSectionBody = try functionBody(containing: "func seasonsSection(", in: source)

        #expect(containsIgnoringWhitespace(
            seasonsSectionBody,
            "ForEach(vm.episodes) { episode in"
        ))
        #expect(seasonsSectionBody.contains("Find Streams"))
        #expect(seasonsSectionBody.contains("vm.selectEpisode(episode)"))
        let hasSearchCall = seasonsSectionBody.contains("vm.searchTorrents()")
        #expect(hasSearchCall)

        if hasSearchCall {
            let selectRange = try requiredRange(of: "vm.selectEpisode(episode)", in: seasonsSectionBody)
            let searchRange = try requiredRange(of: "vm.searchTorrents()", in: seasonsSectionBody)
            #expect(selectRange.lowerBound < searchRange.lowerBound)
        }
    }

    @Test
    func detailViewUsesScrollViewReaderAndScrollsToAnchoredStreamResults() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Detail/DetailView.swift")
        let detailContentBody = try functionBody(containing: "func detailContent(", in: source)

        #expect(detailContentBody.contains("ScrollViewReader"))
        #expect(detailContentBody.contains("ScrollView"))
        let hasScrollToCall = source.contains(".scrollTo(")
        #expect(hasScrollToCall)

        if hasScrollToCall {
            let scrollTarget = try firstCapture(
                in: source,
                pattern: #"\.scrollTo\(\s*("[^"]+"|[A-Za-z_][A-Za-z0-9_\.]*)"#
            )
            #expect(containsIgnoringWhitespace(source, ".id(\(scrollTarget))"))
        }
    }

    @Test
    func searchViewCoalescesTMDBReloadTask() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Search/SearchView.swift")
        #expect(source.contains("tmdbReloadTask?.cancel()"))
        #expect(source.contains("tmdbReloadTask = Task { await reloadTMDBConfigurationAndSearch() }"))
    }

    @Test
    func downloadsViewCoalescesNotificationReloadsAndCancelsOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Downloads/DownloadsView.swift")
        #expect(source.contains("@State private var reloadTask: Task<Void, Never>?"))
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("reloadTask?.cancel()"))
        #expect(source.contains("reloadTask = Task { await vm.load() }"))
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
