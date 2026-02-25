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
        let url = try buildURL(path: "/dmm/filtered", queryItems: [
            URLQueryItem(name: "imdbId", value: imdbId),
        ])
        return try await fetchResults(from: url)
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        let url = try buildURL(path: "/dmm/search", queryItems: [
            URLQueryItem(name: "query", value: query),
        ])
        return try await fetchResults(from: url)
    }

    private func fetchResults(from url: URL) async throws -> [TorrentResult] {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let items = try JSONDecoder().decode([ZileanItem].self, from: data)
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
