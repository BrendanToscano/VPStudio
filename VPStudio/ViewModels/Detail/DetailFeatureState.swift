import Foundation
import Observation

enum LoadingPhase: String, Sendable, Equatable {
    case detail
    case seasonEpisodes
    case torrentSearch
    case streamResolution
    case downloadQueue
    case librarySync
}

enum ViewState: Sendable, Equatable {
    case idle
    case loading(LoadingPhase)
    case loaded
    case error(AppError)
}

@Observable
@MainActor
final class TorrentSearchState {
    private var allResults: [TorrentResult] = []
    private var visibleResults: [TorrentResult] = []

    // `results` remains writable for compatibility with older call-sites/tests.
    // Direct assignment intentionally publishes all provided results at once.
    var results: [TorrentResult] {
        get { visibleResults }
        set {
            allResults = newValue
            visibleResults = newValue
        }
    }

    var allHashes: [String] { allResults.map(\.infoHash) }
    var remainingResultCount: Int { max(allResults.count - visibleResults.count, 0) }
    var canLoadMoreResults: Bool { remainingResultCount > 0 }

    var didSearch = false
    var lastSearchEpisodeId: String?
    var lastSearchContextKey: String?

    func setSearchResults(_ newResults: [TorrentResult], initialBatchSize: Int) {
        allResults = newResults
        visibleResults = Array(newResults.prefix(max(0, initialBatchSize)))
    }

    @discardableResult
    func revealMoreResults(batchSize: Int) -> Bool {
        guard batchSize > 0 else { return false }
        guard canLoadMoreResults else { return false }

        let nextVisibleCount = min(allResults.count, visibleResults.count + batchSize)
        guard nextVisibleCount > visibleResults.count else { return false }

        visibleResults = Array(allResults.prefix(nextVisibleCount))
        return true
    }

    func updateCacheStatus(_ cacheResults: [String: (CacheStatus, DebridServiceType)]) {
        guard !cacheResults.isEmpty else { return }
        var visibleChanged = false
        let visibleCount = visibleResults.count
        for i in allResults.indices {
            let hash = allResults[i].infoHash
            if let (status, serviceType) = cacheResults[hash], case .cached = status, !allResults[i].isCached {
                allResults[i].isCached = true
                allResults[i].cachedOnService = serviceType.rawValue
                if i < visibleCount { visibleChanged = true }
            }
        }
        guard visibleChanged else { return }
        visibleResults = Array(allResults.prefix(visibleCount))
    }

    func markCompletedSearch(episodeId: String?, contextKey: String) {
        didSearch = true
        lastSearchEpisodeId = episodeId
        lastSearchContextKey = contextKey
    }

    func invalidateForEpisodeChange() {
        allResults = []
        visibleResults = []
    }
}

@Observable
@MainActor
final class DebridResolverState {
    var streams: [StreamInfo] = []

    func appendStreamIfNeeded(_ stream: StreamInfo) {
        guard !streams.contains(where: { $0.id == stream.id }) else { return }
        streams.append(stream)
    }

    func clearStreams() {
        streams = []
    }
}

enum DownloadButtonState: Sendable, Equatable {
    case idle
    case resolving
    case downloading
    case completed
    case failed
}

@Observable
@MainActor
final class MediaLibraryState {
    var watchHistory: WatchHistory?
    var isInWatchlist = false
    var isInFavorites = false
    var watchlistFolders: [LibraryFolder] = []
    var favoriteFolders: [LibraryFolder] = []
    var statusMessage: String?
}
