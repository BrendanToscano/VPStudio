import Foundation
import Observation

protocol DetailMetadataProviding: Sendable {
    func getDetail(id: String, type: MediaType) async throws -> MediaItem
    func getSeasons(tmdbId: Int) async throws -> [Season]
    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode]
}

protocol DetailIndexerManaging: Sendable {
    func initialize() async throws
    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult]
    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult]
}

protocol DetailDebridManaging: Sendable {
    func checkCacheAcrossServices(hashes: [String]) async throws -> [String: (CacheStatus, DebridServiceType)]
    func resolveStream(hash: String, preferredService: DebridServiceType?) async throws -> StreamInfo
}

protocol DetailDownloadManaging: Sendable {
    func enqueueDownload(stream: StreamInfo, mediaId: String, episodeId: String?, mediaTitle: String, mediaType: String, posterPath: String?, seasonNumber: Int?, episodeNumber: Int?, episodeTitle: String?) async throws -> DownloadTask
}

extension TMDBService: DetailMetadataProviding {}
extension IndexerManager: DetailIndexerManaging {}
extension DebridManager: DetailDebridManaging {}
extension DownloadManager: DetailDownloadManaging {}

@Observable
@MainActor
final class DetailViewModel {
    private static let torrentResultBatchSize = 10

    var mediaItem: MediaItem?
    var seasons: [Season] = []
    var episodes: [Episode] = []
    var selectedSeason: Int = 1
    var selectedEpisode: Episode?
    let torrentSearch = TorrentSearchState()
    let debridResolver = DebridResolverState()
    let mediaLibrary = MediaLibraryState()
    var viewState: ViewState = .idle
    var feedbackScaleMode: FeedbackScaleMode = .likeDislike
    var currentFeedbackValue: Double?
    var aiAnalysis: AIPersonalizedAnalysis?
    var isLoadingAIAnalysis = false
    var aiAnalysisError: String?
    var downloadStates: [String: DownloadButtonState] = [:]
    var episodeWatchStates: [String: WatchHistory] = [:]
    private var downloadTaskIdsByHash: [String: String] = [:]

    // Backward-compatible mirrors for tests/callers that still bind old fields.
    var torrents: [TorrentResult] {
        get { torrentSearch.results }
        set { torrentSearch.setSearchResults(newValue, initialBatchSize: newValue.count) }
    }

    var streams: [StreamInfo] {
        get { debridResolver.streams }
        set { debridResolver.streams = newValue }
    }

    var didSearch: Bool {
        get { torrentSearch.didSearch }
        set { torrentSearch.didSearch = newValue }
    }

    var lastSearchEpisodeId: String? {
        get { torrentSearch.lastSearchEpisodeId }
        set { torrentSearch.lastSearchEpisodeId = newValue }
    }

    var lastSearchContextKey: String? {
        get { torrentSearch.lastSearchContextKey }
        set { torrentSearch.lastSearchContextKey = newValue }
    }

    var watchHistory: WatchHistory? {
        get { mediaLibrary.watchHistory }
        set { mediaLibrary.watchHistory = newValue }
    }

    var isInWatchlist: Bool {
        get { mediaLibrary.isInWatchlist }
        set { mediaLibrary.isInWatchlist = newValue }
    }

    var isInFavorites: Bool {
        get { mediaLibrary.isInFavorites }
        set { mediaLibrary.isInFavorites = newValue }
    }

    var watchlistFolders: [LibraryFolder] {
        get { mediaLibrary.watchlistFolders }
        set { mediaLibrary.watchlistFolders = newValue }
    }

    var favoriteFolders: [LibraryFolder] {
        get { mediaLibrary.favoriteFolders }
        set { mediaLibrary.favoriteFolders = newValue }
    }

    var libraryStatusMessage: String? {
        get { mediaLibrary.statusMessage }
        set { mediaLibrary.statusMessage = newValue }
    }

    var error: AppError? {
        get {
            guard case .error(let appError) = viewState else { return nil }
            return appError
        }
        set {
            guard let newValue else {
                if case .error = viewState {
                    viewState = .idle
                }
                return
            }
            viewState = .error(newValue)
        }
    }

    var isLoadingDetail: Bool { isLoading(.detail) || isLoading(.seasonEpisodes) }
    var isLoadingTorrents: Bool { isLoading(.torrentSearch) }
    var isResolvingStream: Bool { isLoading(.streamResolution) || isLoading(.downloadQueue) }
    var currentFeedbackSummary: String? {
        guard let currentFeedbackValue else { return nil }
        return feedbackScaleMode.format(currentFeedbackValue)
    }
    var loadingPhase: LoadingPhase? {
        guard case .loading(let phase) = viewState else { return nil }
        return phase
    }

    private let appState: AppState
    private let metadataProviderFactory: @Sendable (String) -> any DetailMetadataProviding
    private let indexerManager: any DetailIndexerManaging
    private let debridManager: any DetailDebridManaging
    private let downloadManager: any DetailDownloadManaging
    private var previewContext: MediaPreview?
    private var searchTask: Task<Void, Never>?
    private var cacheEnrichmentTask: Task<Void, Never>?

    var requiresFreshEpisodeSearch: Bool {
        guard mediaItem?.type == .series else { return false }
        guard torrentSearch.didSearch else { return false }
        guard let mediaItem else { return false }
        let currentContext = searchContextKey(
            mediaID: mediaItem.id,
            season: selectedSeason,
            episode: selectedEpisode?.episodeNumber
        )
        return currentContext != torrentSearch.lastSearchContextKey
    }

    var canLoadMoreTorrents: Bool { torrentSearch.canLoadMoreResults }
    var remainingTorrentCount: Int { torrentSearch.remainingResultCount }
    var nextTorrentBatchCount: Int { min(Self.torrentResultBatchSize, remainingTorrentCount) }

    init(
        appState: AppState,
        metadataProviderFactory: (@Sendable (String) -> any DetailMetadataProviding)? = nil,
        indexerManager: (any DetailIndexerManaging)? = nil,
        debridManager: (any DetailDebridManaging)? = nil,
        downloadManager: (any DetailDownloadManaging)? = nil
    ) {
        self.appState = appState
        self.metadataProviderFactory = metadataProviderFactory ?? { apiKey in
            TMDBService(apiKey: apiKey)
        }
        self.indexerManager = indexerManager ?? appState.indexerManager
        self.debridManager = debridManager ?? appState.debridManager
        self.downloadManager = downloadManager ?? appState.downloadManager
    }

    func setPreviewContext(_ preview: MediaPreview) {
        previewContext = preview
    }

    func cancelInFlightWork() {
        searchTask?.cancel()
        searchTask = nil
        cacheEnrichmentTask?.cancel()
        cacheEnrichmentTask = nil
    }

    func loadMoreTorrentResults() {
        _ = torrentSearch.revealMoreResults(batchSize: Self.torrentResultBatchSize)
    }

    func loadDetail(preview: MediaPreview, apiKey: String) async {
        previewContext = preview
        beginLoading(.detail)

        let service = metadataProviderFactory(apiKey)

        do {
            let detailID = preview.tmdbId.map(String.init) ?? preview.id
            let item = try await service.getDetail(id: detailID, type: preview.type)
            self.mediaItem = item

            // Cache in database
            try? await appState.database.saveMediaItem(item)

            // Load watch history
            mediaLibrary.watchHistory = try? await appState.database.fetchWatchHistory(mediaId: item.id)

            // Load seasons for TV shows
            if preview.type == .series, let tmdbId = item.tmdbId {
                seasons = try await service.getSeasons(tmdbId: tmdbId)
                if let firstSeason = seasons.first {
                    selectedSeason = firstSeason.seasonNumber
                    episodes = try await service.getEpisodes(tmdbId: tmdbId, season: firstSeason.seasonNumber)
                    selectedEpisode = episodes.first
                    await loadEpisodeWatchStates()
                }
            }

            async let libraryState: Void = refreshLibraryState()
            async let feedbackState: Void = refreshFeedbackState()
            _ = await (libraryState, feedbackState)
            markLoaded()
        } catch {
            setError(error, fallback: .network(.transport(error.localizedDescription)))
            async let libraryState: Void = refreshLibraryState()
            async let feedbackState: Void = refreshFeedbackState()
            _ = await (libraryState, feedbackState)
        }
    }

    func loadSeason(_ seasonNumber: Int, apiKey: String) async {
        guard let tmdbId = mediaItem?.tmdbId else { return }
        selectedSeason = seasonNumber
        beginLoading(.seasonEpisodes)
        let service = metadataProviderFactory(apiKey)
        do {
            episodes = try await service.getEpisodes(tmdbId: tmdbId, season: seasonNumber)
            selectedEpisode = episodes.first
            await loadEpisodeWatchStates()
            invalidateSearchResultsForEpisodeChange()
            markLoaded()
        } catch {
            setError(error, fallback: .network(.transport(error.localizedDescription)))
        }
    }

    func selectEpisode(_ episode: Episode) {
        guard selectedEpisode?.id != episode.id else { return }
        cancelInFlightWork()
        selectedEpisode = episode
        invalidateSearchResultsForEpisodeChange()
    }

    func searchTorrents() async {
        guard let item = mediaItem else { return }
        searchTask?.cancel()
        cacheEnrichmentTask?.cancel()
        beginLoading(.torrentSearch)

        searchTask = Task {
            do {
                try Task.checkCancellation()
                try await indexerManager.initialize()

                let season: Int? = item.type == .series ? selectedSeason : nil
                let episode: Int? = item.type == .series ? selectedEpisode?.episodeNumber : nil
                let searchedEpisodeId = item.type == .series ? selectedEpisode?.id : nil
                let contextKey = searchContextKey(mediaID: item.id, season: season, episode: episode)

                var results: [TorrentResult] = []
                var primaryError: Error?

                if item.id.hasPrefix("tt") {
                    do {
                        results = try await indexerManager.search(
                            imdbId: item.id,
                            type: item.type,
                            season: season,
                            episode: episode
                        )
                    } catch {
                        primaryError = error
                    }
                }

                try Task.checkCancellation()

                if results.isEmpty {
                    do {
                        results = try await indexerManager.searchByQuery(
                            query: buildQuery(for: item, season: season, episode: episode),
                            type: item.type
                        )
                    } catch {
                        if let primaryError {
                            throw primaryError
                        }
                        throw error
                    }
                }

                try Task.checkCancellation()
                results = await sortTorrentsByPreferences(results)
                let latestContext = searchContextKey(
                    mediaID: item.id,
                    season: item.type == .series ? selectedSeason : nil,
                    episode: item.type == .series ? selectedEpisode?.episodeNumber : nil
                )
                guard latestContext == contextKey else { return }
                torrentSearch.setSearchResults(results, initialBatchSize: Self.torrentResultBatchSize)
                torrentSearch.markCompletedSearch(episodeId: searchedEpisodeId, contextKey: contextKey)
                markLoaded()

                self.startCacheEnrichment(contextKey: contextKey)
            } catch is CancellationError {
                // Silently discard cancelled search — a newer search is in progress.
            } catch {
                setError(error, fallback: .indexer(.queryFailed(error.localizedDescription)))
            }
        }
        await searchTask?.value
    }

    private static let cacheBatchSize = 20

    private func startCacheEnrichment(contextKey: String) {
        cacheEnrichmentTask?.cancel()
        let hashes = torrentSearch.allHashes
        guard !hashes.isEmpty else { return }

        cacheEnrichmentTask = Task { [debridManager, weak self] in
            for batchStart in stride(from: 0, to: hashes.count, by: Self.cacheBatchSize) {
                try? Task.checkCancellation()
                guard !Task.isCancelled else { return }

                let batchEnd = min(batchStart + Self.cacheBatchSize, hashes.count)
                let batch = Array(hashes[batchStart..<batchEnd])

                guard let cacheResults = try? await debridManager.checkCacheAcrossServices(hashes: batch) else {
                    continue
                }
                guard !Task.isCancelled else { return }
                guard self?.torrentSearch.lastSearchContextKey == contextKey else { return }
                self?.torrentSearch.updateCacheStatus(cacheResults)
            }
        }
    }

    func resolveStream(torrent: TorrentResult) async -> StreamInfo? {
        beginLoading(.streamResolution)
        defer { finishLoadingIfNeeded(for: .streamResolution) }

        do {
            let preferredService = torrent.cachedOnService.flatMap(DebridServiceType.init(rawValue:))
            let stream = try await debridManager.resolveStream(
                hash: torrent.infoHash,
                preferredService: preferredService
            )
            debridResolver.appendStreamIfNeeded(stream)
            return stream
        } catch {
            setError(error, fallback: .debrid(.networkError(error.localizedDescription)))
            return nil
        }
    }

    func queueDownload(torrent: TorrentResult) async {
        guard let item = mediaItem else { return }
        let hash = torrent.infoHash
        let episodeId = item.type == .series ? selectedEpisode?.id : nil
        downloadStates[hash] = .resolving
        beginLoading(.downloadQueue)
        defer { finishLoadingIfNeeded(for: .downloadQueue) }

        do {
            let preferredService = torrent.cachedOnService.flatMap(DebridServiceType.init(rawValue:))
            let stream = try await debridManager.resolveStream(
                hash: torrent.infoHash,
                preferredService: preferredService
            )
            guard mediaItem?.id == item.id else { return }
            downloadStates[hash] = .downloading
            let enqueuedTask = try await downloadManager.enqueueDownload(
                stream: stream,
                mediaId: item.id,
                episodeId: episodeId,
                mediaTitle: item.title,
                mediaType: item.type.rawValue,
                posterPath: item.posterPath,
                seasonNumber: item.type == .series ? selectedEpisode?.seasonNumber : nil,
                episodeNumber: item.type == .series ? selectedEpisode?.episodeNumber : nil,
                episodeTitle: item.type == .series ? selectedEpisode?.title : nil
            )
            downloadTaskIdsByHash[hash] = enqueuedTask.id
            mediaLibrary.statusMessage = "Added to downloads."
            NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
        } catch {
            downloadStates[hash] = .failed
            setError(error, fallback: .debrid(.networkError(error.localizedDescription)))
        }
    }

    func downloadState(for torrent: TorrentResult) -> DownloadButtonState {
        downloadStates[torrent.infoHash] ?? .idle
    }

    func refreshDownloadStates() async {
        guard !downloadTaskIdsByHash.isEmpty else { return }
        let allTasks = (try? await appState.downloadManager.listDownloads()) ?? []
        let taskById = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })

        for (hash, taskId) in downloadTaskIdsByHash {
            guard let task = taskById[taskId] else { continue }
            switch task.status {
            case .completed:
                downloadStates[hash] = .completed
            case .failed, .cancelled:
                downloadStates[hash] = .failed
            case .downloading, .resolving, .queued:
                downloadStates[hash] = .downloading
            }
        }
    }

    func toggleWatchlist() async {
        await toggleLibraryMembership(for: .watchlist)
    }

    func toggleFavorites() async {
        await toggleLibraryMembership(for: .favorites)
    }

    func addOrMoveToLibrary(
        listType: UserLibraryEntry.ListType,
        folderId: String,
        folderName: String? = nil
    ) async {
        let mediaIdentifier = mediaItem?.id ?? previewContext?.id
        guard let mediaIdentifier else {
            mediaLibrary.statusMessage = "Library update failed: missing media identifier."
            return
        }

        beginLoading(.librarySync)
        defer { finishLoadingIfNeeded(for: .librarySync) }

        do {
            let resolvedFolderID: String
            if folderId.isEmpty {
                resolvedFolderID = try await appState.database.fetchSystemLibraryFolderID(listType: listType)
            } else {
                resolvedFolderID = folderId
            }

            let alreadyInList = try await appState.database.isInLibrary(mediaId: mediaIdentifier, listType: listType)
            let targetFolderName = folderName ?? resolvedFolderName(for: listType, folderId: resolvedFolderID)
            let isRootFolder = targetFolderName.localizedCaseInsensitiveCompare(listType.displayName) == .orderedSame

            if alreadyInList {
                guard listType.supportsFolders else { return }
                try await appState.database.moveLibraryEntry(
                    mediaId: mediaIdentifier,
                    listType: listType,
                    toFolderId: resolvedFolderID
                )

                mediaLibrary.statusMessage = isRootFolder
                    ? "Moved within \(listType.displayName)."
                    : "Moved to \(targetFolderName) in \(listType.displayName)."
            } else {
                let entry = UserLibraryEntry(
                    id: "\(mediaIdentifier)-\(listType.rawValue)",
                    mediaId: mediaIdentifier,
                    folderId: resolvedFolderID,
                    listType: listType,
                    addedAt: Date()
                )
                try await appState.database.addToLibrary(entry)
                mediaLibrary.statusMessage = isRootFolder
                    ? "Added to \(listType.displayName.lowercased())."
                    : "Added to \(targetFolderName) in \(listType.displayName)."
            }

            await refreshLibraryState()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            handleLibraryError(error, fallbackPrefix: "Library update failed")
        }
    }

    func removeFromLibrary(listType: UserLibraryEntry.ListType) async {
        let mediaIdentifier = mediaItem?.id ?? previewContext?.id
        guard let mediaIdentifier else {
            mediaLibrary.statusMessage = "Library update failed: missing media identifier."
            return
        }

        beginLoading(.librarySync)
        defer { finishLoadingIfNeeded(for: .librarySync) }

        do {
            try await appState.database.removeFromLibrary(mediaId: mediaIdentifier, listType: listType)
            mediaLibrary.statusMessage = "Removed from \(listType.displayName.lowercased())."
            await refreshLibraryState()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            handleLibraryError(error, fallbackPrefix: "Library update failed")
        }
    }

    func reloadLibraryState() async {
        await refreshLibraryState()
    }

    func submitFeedback(value: Double) async {
        let mediaIdentifier = mediaItem?.id ?? previewContext?.id
        guard let mediaIdentifier else {
            mediaLibrary.statusMessage = "Rating failed: missing media identifier."
            return
        }

        beginLoading(.librarySync)
        defer { finishLoadingIfNeeded(for: .librarySync) }

        do {
            let selectedScale = (try? await appState.settingsManager.getFeedbackScaleMode()) ?? .likeDislike
            let canonicalScale = selectedScale.canonicalMode
            let clampedValue = canonicalScale.clamp(value)
            let normalized = canonicalScale.normalizedValue(clampedValue)
            let title = mediaItem?.title ?? previewContext?.title ?? "Untitled"

            let event = TasteEvent(
                userId: "default",
                mediaId: mediaIdentifier,
                episodeId: nil,
                eventType: .rated,
                signalStrength: normalized,
                watchedState: nil,
                feedbackScale: canonicalScale,
                feedbackValue: clampedValue,
                source: .manual,
                metadata: ["title": title]
            )
            try await appState.database.saveTasteEvent(event)

            feedbackScaleMode = canonicalScale
            currentFeedbackValue = clampedValue
            mediaLibrary.statusMessage = "Saved rating: \(canonicalScale.format(clampedValue))."

            NotificationCenter.default.post(name: .tasteProfileDidChange, object: nil)
        } catch {
            let appError = AppError(error, fallback: .unknown("Rating update failed: \(error.localizedDescription)"))
            mediaLibrary.statusMessage = appError.errorDescription
            viewState = .error(appError)
        }
    }

    func clearFeedback() async {
        let mediaIdentifier = mediaItem?.id ?? previewContext?.id
        guard let mediaIdentifier else {
            mediaLibrary.statusMessage = "Clear rating failed: missing media identifier."
            return
        }

        beginLoading(.librarySync)
        defer { finishLoadingIfNeeded(for: .librarySync) }

        do {
            try await appState.database.deleteLatestTasteRating(mediaId: mediaIdentifier)
            currentFeedbackValue = nil
            mediaLibrary.statusMessage = "Rating cleared."
            NotificationCenter.default.post(name: .tasteProfileDidChange, object: nil)
        } catch {
            let appError = AppError(error, fallback: .unknown("Clear rating failed: \(error.localizedDescription)"))
            mediaLibrary.statusMessage = appError.errorDescription
            viewState = .error(appError)
        }
    }

    func reloadFeedbackState() async {
        await refreshFeedbackState()
    }

    func fetchAIAnalysis() async {
        guard let item = mediaItem else { return }
        isLoadingAIAnalysis = true
        aiAnalysisError = nil

        do {
            let analysis = try await appState.aiAssistantManager.getPersonalizedAnalysis(
                title: item.title,
                year: item.year,
                type: item.type,
                genres: item.genres ?? [],
                overview: item.overview
            )
            aiAnalysis = analysis
        } catch let error as AIError {
            switch error {
            case .noProviderConfigured:
                aiAnalysisError = "No AI provider configured. Set one up in Settings \u{2192} AI Assistant."
            default:
                aiAnalysisError = error.localizedDescription
            }
        } catch {
            aiAnalysisError = error.localizedDescription
        }

        isLoadingAIAnalysis = false
    }

    func loadEpisodeWatchStates() async {
        guard let mediaItem, mediaItem.type == .series else { return }
        episodeWatchStates = (try? await appState.database.fetchEpisodeWatchStates(mediaId: mediaItem.id)) ?? [:]
    }

    func toggleEpisodeWatched(_ episode: Episode) async {
        guard let mediaItem else { return }
        if episodeWatchStates[episode.id]?.isCompleted == true {
            try? await appState.database.markEpisodeUnwatched(mediaId: mediaItem.id, episodeId: episode.id)
            episodeWatchStates.removeValue(forKey: episode.id)
        } else {
            try? await appState.database.markEpisodeWatched(
                mediaId: mediaItem.id,
                episodeId: episode.id,
                title: episode.displayTitle
            )
            await loadEpisodeWatchStates()
        }
    }

    func markSeasonWatched() async {
        guard let mediaItem else { return }
        for episode in episodes {
            if episodeWatchStates[episode.id]?.isCompleted != true {
                try? await appState.database.markEpisodeWatched(
                    mediaId: mediaItem.id,
                    episodeId: episode.id,
                    title: episode.displayTitle
                )
            }
        }
        await loadEpisodeWatchStates()
    }

    func markSeasonUnwatched() async {
        guard let mediaItem else { return }
        for episode in episodes {
            try? await appState.database.markEpisodeUnwatched(mediaId: mediaItem.id, episodeId: episode.id)
        }
        episodeWatchStates = episodeWatchStates.filter { !episodes.map(\.id).contains($0.key) }
    }

    func makePlayerSessionRequest(stream: StreamInfo, preview: MediaPreview) -> PlayerSessionRequest {
        let title = mediaItem?.title ?? preview.title
        let mediaIdentifier = mediaItem?.id ?? preview.id
        let activeEpisodeId = (mediaItem?.type == .series ? selectedEpisode?.id : nil)
        let streamPool = PlayerSessionRouting.sessionStreams(
            primary: stream,
            available: debridResolver.streams
        )

        return PlayerSessionRequest(
            stream: stream,
            availableStreams: streamPool,
            mediaTitle: title,
            mediaId: mediaIdentifier,
            episodeId: activeEpisodeId
        )
    }

    private func toggleLibraryMembership(for listType: UserLibraryEntry.ListType) async {
        let mediaIdentifier = mediaItem?.id ?? previewContext?.id
        guard let mediaIdentifier else {
            mediaLibrary.statusMessage = "Library update failed: missing media identifier."
            return
        }

        beginLoading(.librarySync)
        defer { finishLoadingIfNeeded(for: .librarySync) }

        do {
            let alreadyInList = try await appState.database.isInLibrary(mediaId: mediaIdentifier, listType: listType)
            if alreadyInList {
                try await appState.database.removeFromLibrary(mediaId: mediaIdentifier, listType: listType)
                mediaLibrary.statusMessage = "Removed from \(listType.displayName.lowercased())."
            } else {
                let rootFolderID = try await appState.database.fetchSystemLibraryFolderID(listType: listType)
                let entry = UserLibraryEntry(
                    id: "\(mediaIdentifier)-\(listType.rawValue)",
                    mediaId: mediaIdentifier,
                    folderId: rootFolderID,
                    listType: listType,
                    addedAt: Date()
                )
                try await appState.database.addToLibrary(entry)
                mediaLibrary.statusMessage = "Added to \(listType.displayName.lowercased())."
            }

            await refreshLibraryState()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            handleLibraryError(error, fallbackPrefix: "Library update failed")
        }
    }

    private func refreshLibraryState() async {
        guard let mediaIdentifier = mediaItem?.id ?? previewContext?.id else { return }

        async let watchlistMembership = appState.database.isInLibrary(mediaId: mediaIdentifier, listType: .watchlist)
        async let favoritesMembership = appState.database.isInLibrary(mediaId: mediaIdentifier, listType: .favorites)
        async let watchlistFolders = appState.database.fetchAllLibraryFolders(listType: .watchlist)
        async let favoriteFolders = appState.database.fetchAllLibraryFolders(listType: .favorites)

        mediaLibrary.isInWatchlist = (try? await watchlistMembership) ?? false
        mediaLibrary.isInFavorites = (try? await favoritesMembership) ?? false
        mediaLibrary.watchlistFolders = sortedFolders((try? await watchlistFolders) ?? [])
        mediaLibrary.favoriteFolders = sortedFolders((try? await favoriteFolders) ?? [])
    }

    private func refreshFeedbackState() async {
        let selectedScale = (try? await appState.settingsManager.getFeedbackScaleMode()) ?? .likeDislike
        feedbackScaleMode = selectedScale.canonicalMode

        guard let mediaIdentifier = mediaItem?.id ?? previewContext?.id else {
            currentFeedbackValue = nil
            return
        }

        guard let latestRating = try? await appState.database.fetchLatestTasteRating(mediaId: mediaIdentifier),
              let eventValue = latestRating.feedbackValue else {
            currentFeedbackValue = nil
            return
        }

        let sourceScale = latestRating.feedbackScale?.canonicalMode ?? feedbackScaleMode
        let normalized = sourceScale.normalizedValue(eventValue)
        currentFeedbackValue = feedbackScaleMode.value(fromNormalized: normalized)
    }

    private func sortedFolders(_ folders: [LibraryFolder]) -> [LibraryFolder] {
        folders.sorted { lhs, rhs in
            if lhs.isSystem != rhs.isSystem {
                return lhs.isSystem
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func resolvedFolderName(for listType: UserLibraryEntry.ListType, folderId: String) -> String {
        let folders: [LibraryFolder]
        switch listType {
        case .watchlist:
            folders = mediaLibrary.watchlistFolders
        case .favorites:
            folders = mediaLibrary.favoriteFolders
        case .history:
            folders = []
        }
        return folders.first(where: { $0.id == folderId })?.name ?? listType.displayName
    }

    private func handleLibraryError(_ error: Error, fallbackPrefix: String) {
        let appError = AppError(error, fallback: .unknown("\(fallbackPrefix): \(error.localizedDescription)"))
        mediaLibrary.statusMessage = appError.errorDescription
        viewState = .error(appError)
    }

    private func buildQuery(for item: MediaItem, season: Int?, episode: Int?) -> String {
        var query = item.title
        if item.type == .series, let season, let episode {
            query += " S\(String(format: "%02d", season))E\(String(format: "%02d", episode))"
        } else if let year = item.year {
            query += " \(year)"
        }
        return query
    }

    private func invalidateSearchResultsForEpisodeChange() {
        torrentSearch.invalidateForEpisodeChange()
        debridResolver.clearStreams()
        clearError()
    }

    private func setError(_ error: Error, fallback: AppError) {
        viewState = .error(AppError(error, fallback: fallback))
    }

    func searchContextKey(mediaID: String, season: Int?, episode: Int?) -> String {
        guard mediaItem?.type == .series else {
            return mediaID
        }
        let seasonPart = season.map(String.init) ?? "0"
        let episodePart = episode.map(String.init) ?? "0"
        return "\(mediaID)-s\(seasonPart)e\(episodePart)"
    }

    private func sortTorrentsByPreferences(_ torrents: [TorrentResult]) async -> [TorrentResult] {
        let preferredQuality = (try? await appState.settingsManager.getPreferredQuality()) ?? .hd1080p
        let preferCached = (try? await appState.settingsManager.getBool(key: SettingsKeys.preferCachedStreams, default: true)) ?? true
        let preferAtmos = (try? await appState.settingsManager.getBool(key: SettingsKeys.preferAtmosAudio, default: true)) ?? true
        let hdrRaw = (try? await appState.settingsManager.getString(key: SettingsKeys.preferredHDRFormat)) ?? HDRPreference.auto.rawValue
        let hdrPreference = HDRPreference(rawValue: hdrRaw) ?? .auto

        return await TorrentRanking.sortConcurrently(
            torrents,
            preferredQuality: preferredQuality,
            preferCached: preferCached,
            preferAtmos: preferAtmos,
            hdrPreference: hdrPreference
        )
    }

    func isLoading(_ phase: LoadingPhase) -> Bool {
        loadingPhase == phase
    }

    private func beginLoading(_ phase: LoadingPhase) {
        viewState = .loading(phase)
    }

    private func markLoaded() {
        viewState = .loaded
    }

    private func finishLoadingIfNeeded(for phase: LoadingPhase) {
        guard case .loading(let activePhase) = viewState, activePhase == phase else { return }
        viewState = .loaded
    }

    private func clearError() {
        if case .error = viewState {
            viewState = .idle
        }
    }
}
