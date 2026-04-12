import Foundation

struct ZileanIndexer: TorrentIndexer {
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()
    private static let requestLimiter = IndexerRequestLimiter()

    let name = "Zilean"
    private let baseURL: String
    private let endpointPath: String
    private let session: URLSession

    init(baseURL: String, endpointPath: String = "/api", session: URLSession? = nil) {
        self.baseURL = baseURL
        self.endpointPath = endpointPath
        self.session = session ?? Self.defaultSession
    }

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        var queryItems = [URLQueryItem(name: "imdbId", value: imdbId)]
        if let season { queryItems.append(URLQueryItem(name: "season", value: String(season))) }
        if let episode { queryItems.append(URLQueryItem(name: "episode", value: String(episode))) }

        let url = try buildURL(path: endpointPath.appending("/dmm/filtered"), queryItems: queryItems)
        let results = try await fetchResults(from: url)
        return filter(results: results, season: season, episode: episode, allowUntokenizedTitles: true)
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        let context = EpisodeTokenMatcher.context(fromQuery: query)
        let url = try buildURL(path: endpointPath.appending("/dmm/search"), queryItems: [
            URLQueryItem(name: "query", value: query),
        ])
        let results = try await fetchResults(from: url)
        return filter(results: results, season: context?.season, episode: context?.episode, allowUntokenizedTitles: false)
    }

    private func fetchResults(from url: URL) async throws -> [TorrentResult] {
        let (data, response) = try await Self.requestLimiter.data(from: url, session: session)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode([ZileanItem].self, from: data)
        return items.compactMap { item -> TorrentResult? in
            guard let hash = item.infoHash, !hash.isEmpty else { return nil }
            return TorrentResult.fromSearch(
                infoHash: hash,
                title: item.rawTitle ?? "Unknown",
                sizeBytes: item.size ?? 0,
                seeders: 0,
                leechers: 0,
                indexerName: name
            )
        }
    }

    private func filter(
        results: [TorrentResult],
        season: Int?,
        episode: Int?,
        allowUntokenizedTitles: Bool
    ) -> [TorrentResult] {
        guard let season, let episode else { return results }
        return results.filter { result in
            if allowUntokenizedTitles {
                return EpisodeTokenMatcher.matchesIfPresent(title: result.title, season: season, episode: episode)
            }
            return EpisodeTokenMatcher.matches(title: result.title, season: season, episode: episode)
        }
    }

    private func buildURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        guard url.scheme?.lowercased() == "https" else {
            throw URLError(.unsupportedURL)
        }
        return url
    }
}

private struct ZileanItem: Decodable {
    let infoHash: String?
    let rawTitle: String?
    let size: Int64?
}
