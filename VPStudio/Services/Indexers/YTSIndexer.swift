import Foundation

struct YTSIndexer: TorrentIndexer {
    let name = "YTS"
    static let apiBaseURLs = [
        "https://yts.torrentbay.st/api/v2",
        "https://yts.mx/api/v2",
        "https://yts.bz/api/v2",
    ]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        guard type == .movie else { return [] }
        let ytsResponse = try await fetchResponse(queryTerm: imdbId)
        return mapResults(from: ytsResponse)
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        guard type == .movie else { return [] }
        let ytsResponse = try await fetchResponse(queryTerm: query)
        return mapResults(from: ytsResponse)
    }

    private func fetchResponse(queryTerm: String) async throws -> YTSResponse {
        var lastError: Error = URLError(.badServerResponse)
        var lastEmptyResponse: YTSResponse?

        for baseURL in Self.apiBaseURLs {
            let url: URL
            do {
                url = try buildSearchURL(baseURL: baseURL, queryTerm: queryTerm)
            } catch {
                lastError = error
                continue
            }

            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let ytsResponse = try decoder.decode(YTSResponse.self, from: data)
                if let movies = ytsResponse.data?.movies, !movies.isEmpty {
                    return ytsResponse
                }
                lastEmptyResponse = ytsResponse
            } catch let cancellationError as CancellationError {
                throw cancellationError
            } catch {
                lastError = error
            }
        }

        if let lastEmptyResponse { return lastEmptyResponse }
        throw lastError
    }

    private func mapResults(from response: YTSResponse) -> [TorrentResult] {
        var results: [TorrentResult] = []

        for movie in response.data?.movies ?? [] {
            for torrent in movie.torrents ?? [] {
                guard let hash = torrent.hash, !hash.isEmpty else { continue }

                let displayTitle = movie.titleLong ?? movie.title ?? "Unknown"
                let qualityBadge = torrent.quality.map { $0.isEmpty ? "" : " [\($0)]" } ?? ""
                let typeBadge = torrent.type.map { $0.isEmpty ? "" : " [\($0)]" } ?? ""

                results.append(
                    TorrentResult.fromSearch(
                        infoHash: hash,
                        title: "\(displayTitle)\(qualityBadge)\(typeBadge)",
                        sizeBytes: torrent.sizeBytes ?? 0,
                        seeders: torrent.seeds ?? 0,
                        leechers: torrent.peers ?? 0,
                        indexerName: name
                    )
                )
            }
        }

        return results
    }

    private func buildSearchURL(baseURL: String, queryTerm: String) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/list_movies.json") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "query_term", value: queryTerm),
            URLQueryItem(name: "limit", value: "20"),
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}

private struct YTSResponse: Decodable {
    let status: String?
    let data: YTSData?
}

private struct YTSData: Decodable {
    let movieCount: Int?
    let movies: [YTSMovie]?
}

private struct YTSMovie: Decodable {
    let title: String?
    let titleLong: String?
    let year: Int?
    let imdbCode: String?
    let torrents: [YTSTorrent]?
}

private struct YTSTorrent: Decodable {
    let hash: String?
    let quality: String?
    let type: String?
    let seeds: Int?
    let peers: Int?
    let size: String?
    let sizeBytes: Int64?
}
