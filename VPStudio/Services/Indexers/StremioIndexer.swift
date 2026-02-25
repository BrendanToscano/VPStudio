import Foundation

struct StremioIndexer: TorrentIndexer {
    let name: String
    private let baseURL: String
    private let endpointPath: String
    private let session: URLSession

    init(name: String, baseURL: String, endpointPath: String = "/manifest.json", session: URLSession = .shared) {
        self.name = name
        self.baseURL = baseURL
        self.endpointPath = endpointPath
        self.session = session
    }

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        #if DEBUG
        print("[StremioIndexer:\(name)] search() entered imdbId=\(imdbId)")
        #endif
        let mediaID = streamMediaID(imdbId: imdbId, type: type, season: season, episode: episode)
        let streamURL = try makeStreamURL(type: type, mediaID: mediaID)

        #if DEBUG
        print("[StremioIndexer:\(name)] Fetching \(streamURL.absoluteString)")
        #endif

        let (data, response) = try await session.data(from: streamURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            #if DEBUG
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[StremioIndexer:\(name)] HTTP \(code) from \(streamURL.host ?? "")")
            #endif
            throw URLError(.badServerResponse)
        }

        let results = parseStreamPayload(data)
        #if DEBUG
        print("[StremioIndexer:\(name)] Parsed \(results.count) results (data: \(data.count) bytes)")
        #endif
        return results
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        guard let imdbID = query.range(of: "tt\\d+", options: .regularExpression).map({ String(query[$0]) }) else {
            return []
        }
        return try await search(imdbId: imdbID, type: type, season: nil, episode: nil)
    }

    private func makeManifestURL() throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw URLError(.badURL)
        }

        let normalizedBase = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedEndpoint = endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch (normalizedBase.isEmpty, normalizedEndpoint.isEmpty) {
        case (true, false):
            components.path = "/\(normalizedEndpoint)"
        case (false, true):
            components.path = "/\(normalizedBase)"
        case (false, false):
            components.path = "/\(normalizedBase)/\(normalizedEndpoint)"
        default:
            components.path = "/manifest.json"
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func makeStreamURL(type: MediaType, mediaID: String) throws -> URL {
        let manifestURL = try makeManifestURL()
        let base = manifestURL.deletingLastPathComponent()
        let typePath: String = type == .movie ? "movie" : "series"
        return base
            .appendingPathComponent("stream")
            .appendingPathComponent(typePath)
            .appendingPathComponent("\(mediaID).json")
    }

    private func streamMediaID(imdbId: String, type: MediaType, season: Int?, episode: Int?) -> String {
        guard type == .series, let season, let episode else {
            return imdbId
        }
        return "\(imdbId):\(season):\(episode)"
    }

    private func parseStreamPayload(_ data: Data) -> [TorrentResult] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = object["streams"] as? [[String: Any]] else {
            #if DEBUG
            let preview = String(data: data.prefix(300), encoding: .utf8) ?? "(binary \(data.count) bytes)"
            print("[StremioIndexer:\(name)] JSON parse failed or no 'streams' key. Response preview: \(preview)")
            #endif
            return []
        }

        return streams.compactMap { stream in
            let title = (stream["title"] as? String)
                ?? (stream["name"] as? String)
                ?? "Stremio Stream"
            let urlString = (stream["url"] as? String)
                ?? (stream["externalUrl"] as? String)
                ?? ""

            let infoHash = (stream["infoHash"] as? String)
                ?? JSONValueParsing.extractInfoHash(from: urlString)
                ?? JSONValueParsing.extractInfoHash(from: stream["magnet"] as? String)
            guard let infoHash, !infoHash.isEmpty else { return nil }

            let hints = stream["behaviorHints"] as? [String: Any]
            let size = JSONValueParsing.parseInt64(hints?["videoSize"]) ?? 0
            let seeders = JSONValueParsing.parseInt(hints?["seeders"]) ?? 0
            let leechers = JSONValueParsing.parseInt(hints?["leechers"]) ?? 0

            return TorrentResult.fromSearch(
                infoHash: infoHash,
                title: title,
                sizeBytes: size,
                seeders: seeders,
                leechers: leechers,
                indexerName: name,
                magnetURI: urlString.lowercased().hasPrefix("magnet:") ? urlString : nil
            )
        }
    }

}
