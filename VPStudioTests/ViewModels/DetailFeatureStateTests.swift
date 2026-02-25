import Testing
@testable import VPStudio

// MARK: - ViewState & LoadingPhase

@Suite("ViewState and LoadingPhase")
struct ViewStateTests {

    @Test func idleEquality() {
        #expect(ViewState.idle == .idle)
    }

    @Test func loadedEquality() {
        #expect(ViewState.loaded == .loaded)
    }

    @Test func loadingEquality() {
        #expect(ViewState.loading(.detail) == .loading(.detail))
        #expect(ViewState.loading(.torrentSearch) == .loading(.torrentSearch))
    }

    @Test func loadingInequality() {
        #expect(ViewState.loading(.detail) != .loading(.torrentSearch))
    }

    @Test func errorEquality() {
        #expect(ViewState.error(.unknown("x")) == .error(.unknown("x")))
    }

    @Test func idleNotEqualLoaded() {
        #expect(ViewState.idle != .loaded)
    }

    @Test func allLoadingPhasesAreDistinct() {
        let phases: [LoadingPhase] = [
            .detail, .seasonEpisodes, .torrentSearch,
            .streamResolution, .downloadQueue, .librarySync
        ]
        let unique = Set(phases.map(\.rawValue))
        #expect(unique.count == phases.count)
    }
}

// MARK: - TorrentSearchState

@Suite("TorrentSearchState", .serialized)
struct TorrentSearchStateTests {

    @Test @MainActor
    func initialStateIsEmpty() {
        let state = TorrentSearchState()
        #expect(state.results.isEmpty)
        #expect(state.remainingResultCount == 0)
        #expect(state.canLoadMoreResults == false)
        #expect(state.didSearch == false)
        #expect(state.lastSearchEpisodeId == nil)
        #expect(state.lastSearchContextKey == nil)
    }

    @Test @MainActor
    func setSearchResultsPublishesInitialBatchWindow() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 6), initialBatchSize: 2)

        #expect(state.results.map(\.infoHash) == ["hash-0", "hash-1"])
        #expect(state.remainingResultCount == 4)
        #expect(state.canLoadMoreResults)
    }

    @Test @MainActor
    func setSearchResultsClampsInitialBatchToAvailableResults() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 3), initialBatchSize: 10)

        #expect(state.results.count == 3)
        #expect(state.remainingResultCount == 0)
        #expect(state.canLoadMoreResults == false)
    }

    @Test @MainActor
    func revealMoreResultsAppendsBatchAndUpdatesRemainingCount() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 8), initialBatchSize: 3)

        let didReveal = state.revealMoreResults(batchSize: 2)

        #expect(didReveal)
        #expect(state.results.map(\.infoHash) == ["hash-0", "hash-1", "hash-2", "hash-3", "hash-4"])
        #expect(state.remainingResultCount == 3)
        #expect(state.canLoadMoreResults)
    }

    @Test @MainActor
    func revealMoreResultsStopsAtEndAndReturnsFalseWhenFullyVisible() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 4), initialBatchSize: 3)

        let firstReveal = state.revealMoreResults(batchSize: 10)
        let secondReveal = state.revealMoreResults(batchSize: 1)

        #expect(firstReveal)
        #expect(secondReveal == false)
        #expect(state.results.count == 4)
        #expect(state.remainingResultCount == 0)
        #expect(state.canLoadMoreResults == false)
    }

    @Test @MainActor
    func revealMoreResultsWithNonPositiveBatchIsNoOp() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 5), initialBatchSize: 2)

        let zeroBatchReveal = state.revealMoreResults(batchSize: 0)
        let negativeBatchReveal = state.revealMoreResults(batchSize: -1)

        #expect(zeroBatchReveal == false)
        #expect(negativeBatchReveal == false)
        #expect(state.results.count == 2)
        #expect(state.remainingResultCount == 3)
    }

    @Test @MainActor
    func setSearchResultsResetsPreviouslyExpandedWindow() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 20), initialBatchSize: 5)
        _ = state.revealMoreResults(batchSize: 5)
        #expect(state.results.count == 10)

        state.setSearchResults(makeTorrentResults(count: 4), initialBatchSize: 2)

        #expect(state.results.map(\.infoHash) == ["hash-0", "hash-1"])
        #expect(state.remainingResultCount == 2)
        #expect(state.canLoadMoreResults)
    }

    @Test @MainActor
    func directResultsAssignmentRemainsBackwardCompatible() {
        let state = TorrentSearchState()
        state.results = makeTorrentResults(count: 7)

        #expect(state.results.count == 7)
        #expect(state.remainingResultCount == 0)
        #expect(state.canLoadMoreResults == false)
    }

    @Test @MainActor
    func markCompletedSearchSetsDIdSearch() {
        let state = TorrentSearchState()
        state.markCompletedSearch(episodeId: nil, contextKey: "tt123-movie")
        #expect(state.didSearch)
    }

    @Test @MainActor
    func markCompletedSearchSetsContextKey() {
        let state = TorrentSearchState()
        state.markCompletedSearch(episodeId: nil, contextKey: "tt123-s1e1")
        #expect(state.lastSearchContextKey == "tt123-s1e1")
    }

    @Test @MainActor
    func markCompletedSearchSetsEpisodeId() {
        let state = TorrentSearchState()
        state.markCompletedSearch(episodeId: "ep-1-2", contextKey: "tt123-s1e2")
        #expect(state.lastSearchEpisodeId == "ep-1-2")
    }

    @Test @MainActor
    func markCompletedSearchWithNilEpisodeId() {
        let state = TorrentSearchState()
        state.markCompletedSearch(episodeId: nil, contextKey: "movie-key")
        #expect(state.lastSearchEpisodeId == nil)
    }

    @Test @MainActor
    func markCompletedSearchOverwritesPreviousValues() {
        let state = TorrentSearchState()
        state.markCompletedSearch(episodeId: "ep-1", contextKey: "key-1")
        state.markCompletedSearch(episodeId: "ep-2", contextKey: "key-2")
        #expect(state.lastSearchEpisodeId == "ep-2")
        #expect(state.lastSearchContextKey == "key-2")
    }

    @Test @MainActor
    func invalidateForEpisodeChangeClearsResults() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 9), initialBatchSize: 3)
        _ = state.revealMoreResults(batchSize: 3)
        state.markCompletedSearch(episodeId: "ep-1", contextKey: "key-1")

        state.invalidateForEpisodeChange()

        #expect(state.results.isEmpty)
        #expect(state.remainingResultCount == 0)
        #expect(state.canLoadMoreResults == false)
        // didSearch and context key are intentionally NOT cleared by invalidate
        // (the search freshness check uses them to detect stale results)
        #expect(state.didSearch)
    }

    @Test @MainActor
    func invalidateOnEmptyStateIsIdempotent() {
        let state = TorrentSearchState()
        state.invalidateForEpisodeChange()
        state.invalidateForEpisodeChange()
        #expect(state.results.isEmpty)
        #expect(state.remainingResultCount == 0)
        #expect(state.canLoadMoreResults == false)
    }

    @Test @MainActor
    func allHashesReturnsHashesFromAllResults() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 5), initialBatchSize: 2)
        #expect(state.allHashes == ["hash-0", "hash-1", "hash-2", "hash-3", "hash-4"])
    }

    @Test @MainActor
    func updateCacheStatusMarksMatchingResultsCached() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 4), initialBatchSize: 3)

        let cacheResults: [String: (CacheStatus, DebridServiceType)] = [
            "hash-1": (.cached(fileId: nil, fileName: nil, fileSize: nil), .realDebrid),
            "hash-3": (.cached(fileId: nil, fileName: nil, fileSize: nil), .allDebrid),
        ]
        state.updateCacheStatus(cacheResults)

        #expect(state.results[0].isCached == false)
        #expect(state.results[1].isCached == true)
        #expect(state.results[1].cachedOnService == DebridServiceType.realDebrid.rawValue)
        #expect(state.results[2].isCached == false)
    }

    @Test @MainActor
    func updateCacheStatusIsNoOpForEmptyResults() {
        let state = TorrentSearchState()
        state.setSearchResults(makeTorrentResults(count: 2), initialBatchSize: 2)
        state.updateCacheStatus([:])
        #expect(state.results[0].isCached == false)
        #expect(state.results[1].isCached == false)
    }

    @Test @MainActor
    func updateCacheStatusDoesNotDowngradeAlreadyCachedResults() {
        let state = TorrentSearchState()
        var results = makeTorrentResults(count: 2)
        results[0].isCached = true
        results[0].cachedOnService = DebridServiceType.realDebrid.rawValue
        state.setSearchResults(results, initialBatchSize: 2)

        let cacheResults: [String: (CacheStatus, DebridServiceType)] = [
            "hash-0": (.notCached, .allDebrid),
        ]
        state.updateCacheStatus(cacheResults)

        #expect(state.results[0].isCached == true)
        #expect(state.results[0].cachedOnService == DebridServiceType.realDebrid.rawValue)
    }

    private func makeTorrentResults(count: Int) -> [TorrentResult] {
        (0..<count).map { index in
            Fixtures.torrent(
                hash: "hash-\(index)",
                title: "Result.\(index).1080p"
            )
        }
    }
}

// MARK: - DebridResolverState

@Suite("DebridResolverState", .serialized)
struct DebridResolverStateTests {

    @Test @MainActor
    func initialStateIsEmpty() {
        let state = DebridResolverState()
        #expect(state.streams.isEmpty)
    }

    @Test @MainActor
    func appendStreamIfNeededAddsNewStream() {
        let state = DebridResolverState()
        let stream = Fixtures.stream(fileName: "movie.mkv")
        state.appendStreamIfNeeded(stream)
        #expect(state.streams.count == 1)
        #expect(state.streams.first?.id == stream.id)
    }

    @Test @MainActor
    func appendStreamIfNeededIgnoresDuplicate() {
        let state = DebridResolverState()
        let stream = Fixtures.stream(fileName: "movie.mkv")
        state.appendStreamIfNeeded(stream)
        state.appendStreamIfNeeded(stream)
        #expect(state.streams.count == 1)
    }

    @Test @MainActor
    func appendStreamIfNeededAllowsDifferentStreams() {
        let state = DebridResolverState()
        let s1 = Fixtures.stream(url: "https://cdn.example.com/a.mkv", fileName: "a.mkv")
        let s2 = Fixtures.stream(url: "https://cdn.example.com/b.mkv", fileName: "b.mkv")
        state.appendStreamIfNeeded(s1)
        state.appendStreamIfNeeded(s2)
        #expect(state.streams.count == 2)
    }

    @Test @MainActor
    func clearStreamsEmptiesArray() {
        let state = DebridResolverState()
        state.appendStreamIfNeeded(Fixtures.stream(fileName: "a.mkv"))
        state.appendStreamIfNeeded(Fixtures.stream(url: "https://cdn.example.com/b.mkv", fileName: "b.mkv"))
        state.clearStreams()
        #expect(state.streams.isEmpty)
    }

    @Test @MainActor
    func clearStreamsIsIdempotent() {
        let state = DebridResolverState()
        state.clearStreams()
        state.clearStreams()
        #expect(state.streams.isEmpty)
    }

    @Test @MainActor
    func appendAfterClearAddsStream() {
        let state = DebridResolverState()
        let stream = Fixtures.stream(fileName: "movie.mkv")
        state.appendStreamIfNeeded(stream)
        state.clearStreams()
        state.appendStreamIfNeeded(stream)
        #expect(state.streams.count == 1)
    }
}

// MARK: - MediaLibraryState

@Suite("MediaLibraryState", .serialized)
struct MediaLibraryStateTests {

    @Test @MainActor
    func initialStateDefaults() {
        let state = MediaLibraryState()
        #expect(state.watchHistory == nil)
        #expect(state.isInWatchlist == false)
        #expect(state.isInFavorites == false)
        #expect(state.watchlistFolders.isEmpty)
        #expect(state.favoriteFolders.isEmpty)
        #expect(state.statusMessage == nil)
    }

    @Test @MainActor
    func statusMessageCanBeSetAndCleared() {
        let state = MediaLibraryState()
        state.statusMessage = "Added to watchlist."
        #expect(state.statusMessage == "Added to watchlist.")
        state.statusMessage = nil
        #expect(state.statusMessage == nil)
    }

    @Test @MainActor
    func isInWatchlistCanBeToggled() {
        let state = MediaLibraryState()
        state.isInWatchlist = true
        #expect(state.isInWatchlist)
        state.isInWatchlist = false
        #expect(state.isInWatchlist == false)
    }

    @Test @MainActor
    func isInFavoritesCanBeToggled() {
        let state = MediaLibraryState()
        state.isInFavorites = true
        #expect(state.isInFavorites)
        state.isInFavorites = false
        #expect(state.isInFavorites == false)
    }
}

// MARK: - DetailViewModel ViewState Computed Properties

@Suite("DetailViewModel - ViewState Computed Properties", .serialized)
struct DetailViewModelViewStateTests {

    @Test @MainActor
    func errorComputedPropertyReturnsNilWhenIdle() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .idle
        #expect(viewModel.error == nil)
    }

    @Test @MainActor
    func errorComputedPropertyReturnsNilWhenLoaded() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loaded
        #expect(viewModel.error == nil)
    }

    @Test @MainActor
    func errorComputedPropertyReturnsNilWhenLoading() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loading(.detail)
        #expect(viewModel.error == nil)
    }

    @Test @MainActor
    func settingErrorTransitionsToErrorState() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.error = .unknown("Test error")
        #expect(viewModel.viewState == .error(.unknown("Test error")))
        #expect(viewModel.error == .unknown("Test error"))
    }

    @Test @MainActor
    func clearingErrorFromErrorStateTransitionsToIdle() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.error = .indexer(.queryFailed("oops"))
        #expect(viewModel.viewState == .error(.indexer(.queryFailed("oops"))))

        viewModel.error = nil
        #expect(viewModel.viewState == .idle)
    }

    @Test @MainActor
    func clearingErrorWhenNotInErrorStateIsNoOp() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loaded
        viewModel.error = nil
        #expect(viewModel.viewState == .loaded)
    }

    @Test @MainActor
    func isLoadingDetailTrueWhenLoadingDetail() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loading(.detail)
        #expect(viewModel.isLoadingDetail)
    }

    @Test @MainActor
    func isLoadingDetailTrueWhenLoadingSeasonEpisodes() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loading(.seasonEpisodes)
        #expect(viewModel.isLoadingDetail)
    }

    @Test @MainActor
    func isLoadingDetailFalseWhenLoadingTorrents() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loading(.torrentSearch)
        #expect(viewModel.isLoadingDetail == false)
    }

    @Test @MainActor
    func isLoadingTorrentsTrueWhenLoadingTorrentSearch() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loading(.torrentSearch)
        #expect(viewModel.isLoadingTorrents)
    }

    @Test @MainActor
    func isResolvingStreamTrueWhenStreamResolution() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loading(.streamResolution)
        #expect(viewModel.isResolvingStream)
    }

    @Test @MainActor
    func isResolvingStreamTrueWhenDownloadQueue() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loading(.downloadQueue)
        #expect(viewModel.isResolvingStream)
    }

    @Test @MainActor
    func loadingPhaseReturnsNilWhenNotLoading() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .idle
        #expect(viewModel.loadingPhase == nil)
    }

    @Test @MainActor
    func loadingPhaseReturnsCurrentPhase() {
        let appState = AppState()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.viewState = .loading(.librarySync)
        #expect(viewModel.loadingPhase == .librarySync)
    }
}
