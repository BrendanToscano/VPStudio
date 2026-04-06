import Foundation

struct ZileanIndexer: TorrentIndexer {
    let name = "Zilean"
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        var queryItems = [URLQueryItem(name: "imdbId", value: imdbId)]
        if let season { queryItems.append(URLQueryItem(name: "season", value: String(season))) }
        if let episode { queryItems.append(URLQueryItem(name: "episode", value: String(episode))) }

        let url = try buildURL(path: "/dmm/filtered", queryItems: queryItems)
        let results = try await fetchResults(from: url)
        return filter(results: results, season: season, episode: episode)
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        let context = EpisodeTokenMatcher.context(fromQuery: query)
        let url = try buildURL(path: "/dmm/search", queryItems: [
            URLQueryItem(name: "query", value: query),
        ])
        let results = try await fetchResults(from: url)
        return filter(results: results, season: context?.season, episode: context?.episode)
    }

    private func fetchResults(from url: URL) async throws -> [TorrentResult] {
        let (data, response) = try await session.data(from: url)
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

    private func filter(results: [TorrentResult], season: Int?, episode: Int?) -> [TorrentResult] {
        guard let season, let episode else { return results }
        return results.filter { result in
            EpisodeTokenMatcher.matches(title: result.title, season: season, episode: episode)
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
        return url
    }
}

private struct ZileanItem: Decodable {
    let infoHash: String?
    let rawTitle: String?
    let size: Int64?
}
