import Foundation

struct TorznabIndexer: TorrentIndexer {
    let name: String
    private let baseURL: String
    private let endpointPath: String
    private let apiKey: String?
    private let categoryFilter: String?
    private let apiKeyTransport: IndexerConfig.APIKeyTransport
    private let session: URLSession
    private static let requestLimiter = IndexerRequestLimiter()

    init(
        name: String,
        baseURL: String,
        endpointPath: String = "/api",
        apiKey: String? = nil,
        categoryFilter: String? = nil,
        apiKeyTransport: IndexerConfig.APIKeyTransport = .header,
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
        let episodeContext = type == .series ? EpisodeTokenMatcher.context(fromQuery: query) : nil
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
        let results = try await fetchResults(from: request)
        guard type == .series, let episodeContext else {
            return results
        }
        return results.filter {
            EpisodeTokenMatcher.matchesIfPresent(
                title: $0.title,
                season: episodeContext.season,
                episode: episodeContext.episode
            )
        }
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
        let (data, response) = try await Self.requestLimiter.data(for: request, session: session)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if dataLooksLikeJSON(data) {
            return try parseProwlarrJSON(data)
        }

        do {
            return try parseTorznabXML(data)
        } catch let error as IndexerParseError {
            if case .invalidPayload(_, let reason) = error,
               reason.localizedCaseInsensitiveContains("malformed xml") {
                return try parseProwlarrJSON(data)
            }
            throw error
        } catch {
            return try parseProwlarrJSON(data)
        }
    }

    private func parseTorznabXML(_ data: Data) throws -> [TorrentResult] {
        let parser = XMLParser(data: data)
        let delegate = TorznabXMLParserDelegate(indexerName: name)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let reason = parser.parserError.map { $0.localizedDescription } ?? "unknown XML parser error"
            throw IndexerParseError.invalidPayload(
                indexer: name,
                reason: "malformed XML payload (\(reason))"
            )
        }

        let results = delegate.results
        let trimmed = delegate.rawText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if results.isEmpty,
           (trimmed.hasPrefix("<html") || trimmed.contains("<!doctype html")) {
            throw IndexerParseError.invalidPayload(
                indexer: name,
                reason: "expected Torznab XML but received HTML"
            )
        }

        return results
    }

    private func parseProwlarrJSON(_ data: Data) throws -> [TorrentResult] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw IndexerParseError.invalidPayload(
                indexer: name,
                reason: "malformed JSON payload"
            )
        }

        let items: [[String: Any]]
        if let array = object as? [[String: Any]] {
            items = array
        } else if let dict = object as? [String: Any],
                  let records = dict["results"] as? [[String: Any]] {
            items = records
        } else {
            throw IndexerParseError.invalidPayload(
                indexer: name,
                reason: "JSON payload missing a results array"
            )
        }

        let results: [TorrentResult] = items.compactMap { item in
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

        if !items.isEmpty, results.isEmpty {
            throw IndexerParseError.invalidPayload(
                indexer: name,
                reason: "JSON payload did not include any usable torrent hashes"
            )
        }

        return results
    }

    private func dataLooksLikeJSON(_ data: Data) -> Bool {
        let bytes = data.stripLeadingBOMAndWhitespace()
        guard let first = bytes.first else { return false }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
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
        guard url.scheme?.lowercased() == "https" else {
            throw URLError(.unsupportedURL)
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

}

private final class TorznabXMLParserDelegate: NSObject, XMLParserDelegate {
    struct ParsedItem {
        var title: String?
        var infoHash: String?
        var magnetURI: String?
        var link: String?
        var guid: String?
        var enclosureURL: String?
        var size: Int64 = 0
        var seeders: Int = 0
        var leechers: Int = 0
    }

    private static let textElements: Set<String> = ["title", "link", "guid"]

    let indexerName: String
    private(set) var results: [TorrentResult] = []
    private(set) var rawText = ""

    private var currentItem: ParsedItem?
    private var currentElement: String?
    private var currentCharacters = ""

    init(indexerName: String) {
        self.indexerName = indexerName
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        rawText += string
        guard let currentElement,
              currentItem != nil,
              Self.textElements.contains(currentElement) else { return }
        currentCharacters += string
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String : String] = [:]) {
        rawText += "<\(elementName)>"
        let lower = elementName.lowercased()
        currentElement = lower

        if lower == "item" {
            currentItem = ParsedItem()
            currentCharacters = ""
            return
        }

        guard currentItem != nil else { return }

        if lower == "enclosure",
           let url = attributeDict["url"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty {
            let decodedURL = decodeCommonEntities(in: url)
            guard var item = currentItem else { return }
            item.enclosureURL = decodedURL
            if item.infoHash == nil {
                item.infoHash = resolvedInfoHash(from: decodedURL)
            }
            if item.magnetURI == nil, decodedURL.lowercased().hasPrefix("magnet:") {
                item.magnetURI = decodedURL
            }
            currentItem = item
            return
        }

        guard lower.hasSuffix(":attr") || lower == "attr" else { return }
        guard let name = attributeDict["name"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let value = attributeDict["value"]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

        let decodedValue = decodeCommonEntities(in: value)
        guard var item = currentItem else { return }
        switch name {
        case "infohash":
            item.infoHash = decodedValue
        case "magneturl", "magneturi":
            item.magnetURI = decodedValue
            if item.infoHash == nil {
                item.infoHash = resolvedInfoHash(from: decodedValue)
            }
        case "downloadurl":
            if item.infoHash == nil {
                item.infoHash = resolvedInfoHash(from: decodedValue)
            }
            if item.magnetURI == nil, decodedValue.lowercased().hasPrefix("magnet:") {
                item.magnetURI = decodedValue
            }
        case "size":
            item.size = Int64(decodedValue) ?? 0
        case "seeders":
            item.seeders = Int(decodedValue) ?? 0
        case "peers", "leechers":
            item.leechers = Int(decodedValue) ?? 0
        default:
            break
        }
        currentItem = item
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        rawText += "</\(elementName)>"
        let lower = elementName.lowercased()

        if lower == "title" {
            currentItem?.title = decodeCommonEntities(in: currentCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            currentCharacters = ""
        } else if lower == "link" {
            currentItem?.link = decodeCommonEntities(in: currentCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            currentCharacters = ""
        } else if lower == "guid" {
            currentItem?.guid = decodeCommonEntities(in: currentCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            currentCharacters = ""
        } else if lower == "item" {
            if let item = currentItem,
               let title = item.title, !title.isEmpty,
               let infoHash = resolvedInfoHash(for: item), !infoHash.isEmpty {
                results.append(TorrentResult.fromSearch(
                    infoHash: infoHash,
                    title: title,
                    sizeBytes: item.size,
                    seeders: item.seeders,
                    leechers: item.leechers,
                    indexerName: indexerName,
                    magnetURI: preferredMagnetURI(for: item)
                ))
            }
            currentItem = nil
            currentCharacters = ""
        }

        if currentElement == lower {
            currentElement = nil
        }
    }

    private func resolvedInfoHash(for item: ParsedItem) -> String? {
        if let infoHash = item.infoHash?.trimmingCharacters(in: .whitespacesAndNewlines), !infoHash.isEmpty {
            return infoHash
        }

        let candidates = [item.magnetURI, item.enclosureURL, item.link, item.guid]
        for candidate in candidates {
            if let resolved = resolvedInfoHash(from: candidate) {
                return resolved
            }
        }
        return nil
    }

    private func preferredMagnetURI(for item: ParsedItem) -> String? {
        let candidates = [item.magnetURI, item.enclosureURL, item.link, item.guid]
        return candidates.first { candidate in
            guard let candidate else { return false }
            return candidate.lowercased().hasPrefix("magnet:")
        } ?? nil
    }

    private func resolvedInfoHash(from value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if isExactInfoHash(value) {
            return value.lowercased()
        }

        return JSONValueParsing.extractInfoHash(from: value)
    }

    private func isExactInfoHash(_ value: String) -> Bool {
        guard value.count == 40 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...70, 97...102:
                return true
            default:
                return false
            }
        }
    }
}

private func decodeCommonEntities(in value: String) -> String {
    var decoded = value
    let replacements: [(String, String)] = [
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&nbsp;", " "),
        ("&#39;", "'"),
        ("&#x27;", "'"),
    ]
    for (source, target) in replacements {
        decoded = decoded.replacingOccurrences(of: source, with: target)
    }

    let pattern = #"&#(x?[0-9A-Fa-f]+);"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return decoded }

    let range = NSRange(decoded.startIndex..., in: decoded)
    let matches = regex.matches(in: decoded, options: [], range: range)
    guard !matches.isEmpty else { return decoded }

    var result = decoded
    for match in matches.reversed() {
        guard let fullRange = Range(match.range, in: result),
              let captureRange = Range(match.range(at: 1), in: result) else { continue }
        let token = String(result[captureRange])
        let scalar: UInt32?
        if token.lowercased().hasPrefix("x") {
            scalar = UInt32(token.dropFirst(), radix: 16)
        } else {
            scalar = UInt32(token, radix: 10)
        }
        guard let scalar, let unicodeScalar = UnicodeScalar(scalar) else { continue }
        result.replaceSubrange(fullRange, with: String(unicodeScalar))
    }
    return result
}

private extension Data {
    func stripLeadingBOMAndWhitespace() -> [UInt8] {
        var bytes = Array(self)
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes.removeFirst(3)
        } else if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            bytes.removeFirst(2)
        } else if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            bytes.removeFirst(2)
        }

        while let first = bytes.first, first == 0x20 || first == 0x09 || first == 0x0A || first == 0x0D {
            bytes.removeFirst()
        }
        return bytes
    }
}
