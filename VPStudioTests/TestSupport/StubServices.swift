import Foundation
@testable import VPStudio

actor StubMetadataProvider: MetadataProvider, DetailMetadataProviding {
    var searchResult = MetadataSearchResult(items: [], page: 1, totalPages: 1, totalResults: 0)
    var detailResult = MediaItem(id: "tt1", type: .movie, title: "Title")
    var seasonsResult: [Season] = []
    var episodesResult: [Episode] = []
    var externalIdsResult = ExternalIds(imdbId: nil, tvdbId: nil)

    func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult { searchResult }
    func getDetail(id: String, type: MediaType) async throws -> MediaItem { detailResult }
    func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult { searchResult }
    func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult { searchResult }
    func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult { searchResult }
    func getGenres(type: MediaType) async throws -> [Genre] { [] }
    func getSeasons(tmdbId: Int) async throws -> [Season] { seasonsResult }
    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { episodesResult }
    func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { externalIdsResult }
}

actor StubIndexerManager: DetailIndexerManaging {
    var searchResults: [TorrentResult] = []
    var searchByQueryResults: [TorrentResult] = []
    var initializeError: Error?
    var searchError: Error?
    var searchByQueryError: Error?

    func initialize() async throws {
        if let initializeError { throw initializeError }
    }

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        if let searchError { throw searchError }
        return searchResults
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        if let searchByQueryError { throw searchByQueryError }
        return searchByQueryResults
    }
}

actor StubDebridManager: DetailDebridManaging {
    var cacheResults: [String: (CacheStatus, DebridServiceType)] = [:]
    var resolvedStream = Fixtures.stream()
    var resolveError: Error?

    func checkCacheAcrossServices(hashes: [String]) async throws -> [String: (CacheStatus, DebridServiceType)] {
        cacheResults
    }

    func resolveStream(hash: String, preferredService: DebridServiceType?) async throws -> StreamInfo {
        if let resolveError { throw resolveError }
        return resolvedStream
    }
}

actor StubDownloadManager: DetailDownloadManaging, DownloadManaging {
    var downloads: [DownloadTask] = []
    var enqueueError: Error?
    var retryError: Error?
    var removeError: Error?

    func setDownloads(_ tasks: [DownloadTask]) {
        downloads = tasks
    }

    func setRetryError(_ error: Error?) {
        retryError = error
    }

    func setRemoveError(_ error: Error?) {
        removeError = error
    }

    func enqueueDownload(stream: StreamInfo, mediaId: String, episodeId: String?, mediaTitle: String = "", mediaType: String = "movie", posterPath: String? = nil, seasonNumber: Int? = nil, episodeNumber: Int? = nil, episodeTitle: String? = nil) async throws -> DownloadTask {
        if let enqueueError { throw enqueueError }
        let task = DownloadTask(mediaId: mediaId, episodeId: episodeId, streamURL: stream.streamURL.absoluteString, fileName: stream.fileName, mediaTitle: mediaTitle, mediaType: mediaType, posterPath: posterPath, seasonNumber: seasonNumber, episodeNumber: episodeNumber, episodeTitle: episodeTitle)
        downloads.append(task)
        return task
    }

    func listDownloads() async throws -> [DownloadTask] { downloads }

    func cancelDownload(id: String) async {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .cancelled
        }
    }

    func retryDownload(id: String) async throws {
        if let retryError { throw retryError }
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .queued
        }
    }

    func removeDownload(id: String) async throws {
        if let removeError { throw removeError }
        downloads.removeAll { $0.id == id }
    }

    func removeDownloads(mediaId: String) async throws {
        if let removeError { throw removeError }
        downloads.removeAll { $0.mediaId == mediaId }
    }
}

struct StubAIProvider: AIProvider {
    let providerKind: AIProviderKind
    let result: Result<AIProviderResponse, Error>

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        switch result {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}

actor TestSecretStore: SecretStore {
    private var values: [String: String] = [:]

    func setSecret(_ value: String, for key: String) async throws {
        values[key] = value
    }

    func getSecret(for key: String) async throws -> String? {
        values[key]
    }

    func deleteSecret(for key: String) async throws {
        values[key] = nil
    }

    func deleteAllSecrets() async throws {
        values.removeAll()
    }
}
