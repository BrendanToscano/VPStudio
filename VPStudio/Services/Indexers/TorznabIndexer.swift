import Foundation

struct TorznabIndexer: TorrentIndexer {
    let name: String
    private let baseURL: String
    private let endpointPath: String
    private let apiKey: String?
    private let categoryFilter: String?
    private let apiKeyTransport: IndexerConfig.APIKeyTransport
    private let session: URLSession

    init(
        name: String,
        baseURL: String,
        endpointPath: String = "/api",
        apiKey: String? = nil,
        categoryFilter: String? = nil,
        apiKeyTransport: IndexerConfig.APIKeyTransport = .query,
        session: URLSession = .shared
    ) {
        self.name = name
        self.baseURL = baseURL
        self.endpointPath = endpointPath
        self.apiKey = apiKey
        self.categoryFilter = categoryFilter
        self.apiKeyTransport = apiKeyTransport
        self.session = session
    }

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        if isProwlarrEndpoint {
            let request = try buildRequest(queryItems: [
                URLQueryItem(name: "type", value: prowlarrSearchType(for: type)),
                URLQueryItem(name: "query", value: prowlarrStructuredQuery(
                    imdbId: imdbId,
                    type: type,
                    season: season,
                    episode: episode
                )),
            ])
            return try await fetchResults(from: request)
        }

        let request = try buildRequest(queryItems: [
            URLQueryItem(name: "t", value: "search"),
            URLQueryItem(name: "imdbid", value: imdbId),
            URLQueryItem(name: "season", value: season.map(String.init)),
            URLQueryItem(name: "ep", value: episode.map(String.init)),
        ])
        return try await fetchResults(from: request)
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        let request: URLRequest
        if isProwlarrEndpoint {
            request = try buildRequest(queryItems: [
                URLQueryItem(name: "type", value: prowlarrSearchType(for: type)),
                URLQueryItem(name: "query", value: query),
            ])
        } else {
            request = try buildRequest(queryItems: [
                URLQueryItem(name: "t", value: "search"),
                URLQueryItem(name: "q", value: query),
            ])
        }
        return try await fetchResults(from: request)
    }

    private var isProwlarrEndpoint: Bool {
        endpointPath.lowercased().contains("/api/v1/search")
    }

    private func prowlarrSearchType(for type: MediaType) -> String {
        switch type {
        case .movie:
            return "moviesearch"
        case .series:
            return "tvsearch"
        }
    }

    private func prowlarrStructuredQuery(
        imdbId: String,
        type: MediaType,
        season: Int?,
        episode: Int?
    ) -> String {
        var tokens = ["{ImdbId:\(imdbId)}"]
        if type == .series {
            if let season {
                tokens.append("{Season:\(season)}")
            }
            if let episode {
                tokens.append("{Episode:\(episode)}")
            }
        }
        return tokens.joined(separator: " ")
    }

    private func fetchResults(from request: URLRequest) async throws -> [TorrentResult] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let xml = String(data: data, encoding: .utf8) ?? ""
        if xml.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            return parseTorznabXML(xml)
        }
        return parseProwlarrJSON(data)
    }

    private func parseTorznabXML(_ xml: String) -> [TorrentResult] {
        var results: [TorrentResult] = []
        let items = xml.components(separatedBy: "<item>")

        for item in items.dropFirst() {
            guard let title = extractTag("title", from: item),
                  let hash = extractAttribute("value", tag: "torznab:attr", name: "infohash", from: item) else { continue }

            let size = extractAttribute("value", tag: "torznab:attr", name: "size", from: item).flatMap { Int64($0) } ?? 0
            let seeders = extractAttribute("value", tag: "torznab:attr", name: "seeders", from: item).flatMap { Int($0) } ?? 0
            let leechers = extractAttribute("value", tag: "torznab:attr", name: "peers", from: item).flatMap { Int($0) } ?? 0

            results.append(TorrentResult.fromSearch(
                infoHash: hash,
                title: title,
                sizeBytes: size,
                seeders: seeders,
                leechers: leechers,
                indexerName: name
            ))
        }
        return results
    }

    private func parseProwlarrJSON(_ data: Data) -> [TorrentResult] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }

        let items: [[String: Any]]
        if let array = object as? [[String: Any]] {
            items = array
        } else if let dict = object as? [String: Any],
                  let records = dict["results"] as? [[String: Any]] {
            items = records
        } else {
            return []
        }

        return items.compactMap { item in
            let title = (item["title"] as? String) ?? (item["name"] as? String) ?? "Unknown"
            let infoHash = (item["infoHash"] as? String)
                ?? (item["hash"] as? String)
                ?? JSONValueParsing.extractInfoHash(from: item["magnetUrl"] as? String)
            guard let infoHash, !infoHash.isEmpty else { return nil }

            let size = JSONValueParsing.parseInt64(item["size"]) ?? 0
            let seeders = JSONValueParsing.parseInt(item["seeders"]) ?? 0
            let peers = JSONValueParsing.parseInt(item["peers"]) ?? JSONValueParsing.parseInt(item["leechers"]) ?? 0
            let magnetURL = item["magnetUrl"] as? String

            return TorrentResult.fromSearch(
                infoHash: infoHash,
                title: title,
                sizeBytes: size,
                seeders: seeders,
                leechers: peers,
                indexerName: name,
                magnetURI: magnetURL
            )
        }
    }

    private func buildRequest(queryItems: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else {
            throw URLError(.badURL)
        }

        let endpoint = endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch (basePath.isEmpty, endpoint.isEmpty) {
        case (true, false):
            components.path = "/\(endpoint)"
        case (false, true):
            components.path = "/\(basePath)"
        case (false, false):
            components.path = "/\(basePath)/\(endpoint)"
        default:
            components.path = ""
        }

        var merged: [URLQueryItem] = []
        for item in queryItems where item.value != nil {
            merged.append(item)
        }

        if let categoryFilter, !categoryFilter.isEmpty {
            merged.append(URLQueryItem(name: "cat", value: categoryFilter))
        }
        if apiKeyTransport == .query,
           let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            merged.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        components.queryItems = merged

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if apiKeyTransport == .header,
           let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        return request
    }

    private func extractTag(_ tag: String, from xml: String) -> String? {
        // Handle CDATA: <tag><![CDATA[content]]></tag>
        let cdataPattern = "<\(tag)>\\s*<!\\[CDATA\\[(.*?)\\]\\]>\\s*</\(tag)>"
        if let regex = try? NSRegularExpression(pattern: cdataPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
           let range = Range(match.range(at: 1), in: xml) {
            return String(xml[range])
        }

        // Plain text: <tag>content</tag> with XML entity decoding
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex) else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private func extractAttribute(_ attr: String, tag: String, name: String, from xml: String) -> String? {
        let patterns = [
            "<\(tag)[^>]*?name=\"\(name)\"[^>]*?\(attr)=\"([^\"]*)\"",
            "<\(tag)[^>]*?\(attr)=\"([^\"]*)\"[^>]*?name=\"\(name)\"",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
                  let range = Range(match.range(at: 1), in: xml) else { continue }
            return String(xml[range])
        }
        return nil
    }

}
