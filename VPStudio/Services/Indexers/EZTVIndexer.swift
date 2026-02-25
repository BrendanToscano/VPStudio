import Foundation

struct EZTVIndexer: TorrentIndexer {
    let name = "EZTV"
    private let baseURL = "https://eztvx.to/api"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        guard type == .series else { return [] }
        let cleanId = imdbId.replacingOccurrences(of: "tt", with: "")
        guard !cleanId.isEmpty else { return [] }

        var results: [TorrentResult] = []
        let maxPages = 3

        for page in 1...maxPages {
            let url = try buildURL(queryItems: [
                URLQueryItem(name: "imdb_id", value: cleanId),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
            ])

            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                break
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let eztvResponse = try decoder.decode(EZTVResponse.self, from: data)

            guard let torrents = eztvResponse.torrents, !torrents.isEmpty else { break }

            for torrent in torrents {
                guard let hash = torrent.hash, !hash.isEmpty else { continue }

                if let season, let epSeason = torrent.season.flatMap({ Int($0) }), epSeason != 0, epSeason != season { continue }
                if let episode, let epNum = torrent.episode.flatMap({ Int($0) }), epNum != 0, epNum != episode { continue }
                if let season, let episode {
                    let titleForMatch = torrent.title ?? torrent.filename ?? ""
                    guard EpisodeTokenMatcher.matches(title: titleForMatch, season: season, episode: episode) else { continue }
                }

                let title = torrent.title ?? torrent.filename ?? "Unknown"
                let sizeBytes = torrent.sizeBytes.flatMap { Int64($0) } ?? 0

                results.append(TorrentResult.fromSearch(
                    infoHash: hash,
                    title: title,
                    sizeBytes: sizeBytes,
                    seeders: torrent.seeds ?? 0,
                    leechers: torrent.peers ?? 0,
                    indexerName: name,
                    magnetURI: torrent.magnetUrl
                ))
            }

            if torrents.count < 100 { break }
        }

        return results
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        guard type == .series else { return [] }
        let url = try buildURL(queryItems: [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: "100"),
        ])

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let eztvResponse = try decoder.decode(EZTVResponse.self, from: data)

        return (eztvResponse.torrents ?? []).compactMap { torrent -> TorrentResult? in
            guard let hash = torrent.hash, !hash.isEmpty else { return nil }
            return TorrentResult.fromSearch(
                infoHash: hash,
                title: torrent.title ?? "Unknown",
                sizeBytes: torrent.sizeBytes.flatMap { Int64($0) } ?? 0,
                seeders: torrent.seeds ?? 0,
                leechers: torrent.peers ?? 0,
                indexerName: name,
                magnetURI: torrent.magnetUrl
            )
        }
    }

    private func buildURL(queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/get-torrents") else {
            throw URLError(.badURL)
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

}

private struct EZTVResponse: Decodable { let torrents: [EZTVTorrent]? }
private struct EZTVTorrent: Decodable {
    let hash: String?; let filename: String?; let title: String?
    let season: String?; let episode: String?
    let seeds: Int?; let peers: Int?; let sizeBytes: String?; let magnetUrl: String?
}
