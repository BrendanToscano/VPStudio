import Foundation

struct APIBayIndexer: TorrentIndexer {
    let name = "APiBay"
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? "https://apibay.org"
        self.session = session
    }

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        var query = imdbId
        if let season, let episode {
            query += " S\(String(format: "%02d", season))E\(String(format: "%02d", episode))"
            return try await fetchResults(query: query, type: type, season: season, episode: episode)
        }
        return try await fetchResults(query: query, type: type, season: nil, episode: nil)
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        let context = episodeContext(from: query)
        return try await fetchResults(
            query: query,
            type: type,
            season: context?.season,
            episode: context?.episode
        )
    }

    private func fetchResults(query: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        let url = try buildSearchURL(query: query)

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let torrents = try JSONDecoder().decode([APIBayTorrent].self, from: data)
        guard !torrents.isEmpty, torrents.first?.name != "No results returned" else {
            return []
        }

        let zeroHash = String(repeating: "0", count: 40)
        return torrents.compactMap { torrent -> TorrentResult? in
            guard torrent.id != "0",
                  !torrent.infoHash.isEmpty,
                  torrent.infoHash != zeroHash else { return nil }
            if let season, let episode {
                guard EpisodeTokenMatcher.matches(title: torrent.name, season: season, episode: episode) else { return nil }
            }
            return TorrentResult.fromSearch(
                infoHash: torrent.infoHash,
                title: torrent.name,
                sizeBytes: Int64(torrent.size) ?? 0,
                seeders: Int(torrent.seeders) ?? 0,
                leechers: Int(torrent.leechers) ?? 0,
                indexerName: name
            )
        }
    }

    private func episodeContext(from query: String) -> (season: Int, episode: Int)? {
        let lower = query.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"s(\d{1,2})e(\d{1,3})"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              let seasonRange = Range(match.range(at: 1), in: lower),
              let episodeRange = Range(match.range(at: 2), in: lower),
              let season = Int(lower[seasonRange]),
              let episode = Int(lower[episodeRange]) else {
            return nil
        }
        return (season, episode)
    }

    private func buildSearchURL(query: String) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/q.php") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "cat", value: "0"),
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}

private struct APIBayTorrent: Decodable {
    let id: String
    let name: String
    let infoHash: String
    let size: String
    let seeders: String
    let leechers: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case infoHash = "info_hash"
        case size, seeders, leechers
    }
}
