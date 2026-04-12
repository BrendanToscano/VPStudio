import Foundation

actor OffcloudService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .offcloud
    private let apiToken: String
    private let baseURL = "https://offcloud.com/api"
    private let fallbackBaseURL = "https://offcloud.com"
    private let session: URLSession
    private var selectedFileIDsByTorrent: [String: Set<Int>] = [:]
    private var episodeSelectionByTorrent: [String: EpisodeSelectionRequest] = [:]

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    func validateToken() async throws -> Bool {
        do {
            let _: [OCAnyHistoryItem] = try await request(
                method: "GET",
                path: "/cloud/history"
            )
            return true
        } catch DebridError.unauthorized {
            return false
        }
    }

    func getAccountInfo() async throws -> DebridAccountInfo {
        let _: [OCAnyHistoryItem] = try await request(
            method: "GET",
            path: "/cloud/history"
        )
        return DebridAccountInfo(username: "Offcloud User", email: nil, premiumExpiry: nil, isPremium: true)
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        guard !hashes.isEmpty else { return [:] }

        let normalized = hashes.map { $0.lowercased() }
        let response: OCCacheResponse = try await request(
            method: "POST",
            path: "/cache",
            jsonBody: ["hashes": normalized]
        )
        let cached = Set((response.cachedItems ?? []).map { $0.lowercased() })

        return normalized.reduce(into: [String: CacheStatus]()) { result, hash in
            result[hash] = cached.contains(hash)
                ? .cached(fileId: nil, fileName: nil, fileSize: nil)
                : .notCached
        }
    }

    func addMagnet(hash: String) async throws -> String {
        let normalizedHash = try DebridHashValidator.validatedInfoHash(hash)
        let magnet = "magnet:?xt=urn:btih:\(normalizedHash)"
        let decoded: OCAddResponse = try await request(
            method: "POST",
            path: "/cloud",
            jsonBody: ["url": magnet]
        )
        return decoded.requestId ?? normalizedHash
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        if fileIds.isEmpty {
            clearSelectionState(for: torrentId)
            return
        }
        selectedFileIDsByTorrent[torrentId] = Set(fileIds)
        episodeSelectionByTorrent.removeValue(forKey: torrentId)
    }

    func selectMatchingEpisodeFile(
        torrentId: String,
        seasonNumber: Int,
        episodeNumber: Int,
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?
    ) async throws -> Bool {
        episodeSelectionByTorrent[torrentId] = EpisodeSelectionRequest(
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            resolvedFileNameHint: resolvedFileNameHint,
            resolvedFileSizeHint: resolvedFileSizeHint
        )
        return true
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        let statusResponse: OCStatusResponse = try await request(
            method: "POST",
            path: "/cloud/status",
            jsonBody: ["requestId": torrentId]
        )
        let episodeSelection = episodeSelectionByTorrent[torrentId]

        let status = statusResponse.status?.lowercased() ?? "unknown"
        guard status == "downloaded" else {
            throw DebridError.fileNotReady(status)
        }

        if let direct = statusResponse.url, let directURL = URL(string: direct) {
            let directFileName = resolvedDisplayFileName(
                linkFileName: directURL.lastPathComponent.removingPercentEncoding ?? directURL.lastPathComponent,
                statusFileName: statusResponse.fileName
            )
            guard isDeterministicEpisodeMatch(
                fileName: directFileName,
                request: episodeSelection
            ) else {
                clearSelectionState(for: torrentId)
                throw DebridError.networkError("Offcloud could not deterministically select the requested episode file.")
            }
            clearSelectionState(for: torrentId)
            let fileName = statusResponse.fileName ?? directURL.lastPathComponent
            let q = VideoQuality.parse(from: fileName)
            let c = VideoCodec.parse(from: fileName)
            let a = AudioFormat.parse(from: fileName)
            let s = SourceType.parse(from: fileName)
            let h = HDRFormat.parse(from: fileName)
            return StreamInfo(
                streamURL: directURL,
                quality: q,
                codec: c,
                audio: a,
                source: s,
                hdr: h,
                fileName: fileName,
                sizeBytes: nil,
                debridService: serviceType.rawValue
            )
        }

        let links: [String] = try await request(
            method: "GET",
            path: "/cloud/explore/\(torrentId)"
        )
        let selectedIDs = selectedFileIDsByTorrent[torrentId] ?? []
        let selectedLink = links.enumerated().first(where: { pair in
            selectedIDs.contains(pair.offset + 1)
        })?.element ?? bestEpisodeMatch(in: links, request: episodeSelection)
        guard let link = selectedLink ?? fallbackSelectedLink(in: links, request: episodeSelection) else {
            clearSelectionState(for: torrentId)
            if episodeSelection != nil {
                throw DebridError.networkError("Offcloud could not deterministically select the requested episode file.")
            }
            throw DebridError.networkError("No download link")
        }
        guard let streamURL = URL(string: link) else {
            clearSelectionState(for: torrentId)
            throw DebridError.networkError("Invalid URL")
        }

        clearSelectionState(for: torrentId)
        let linkFileName = streamURL.lastPathComponent.removingPercentEncoding ?? streamURL.lastPathComponent
        let fileName = resolvedDisplayFileName(
            linkFileName: linkFileName,
            statusFileName: statusResponse.fileName
        )
        let q = VideoQuality.parse(from: fileName)
        let c = VideoCodec.parse(from: fileName)
        let a = AudioFormat.parse(from: fileName)
        let s = SourceType.parse(from: fileName)
        let h = HDRFormat.parse(from: fileName)
        return StreamInfo(
            streamURL: streamURL,
            quality: q,
            codec: c,
            audio: a,
            source: s,
            hdr: h,
            fileName: fileName,
            sizeBytes: nil,
            debridService: serviceType.rawValue
        )
    }

    func unrestrict(link: String) async throws -> URL {
        guard let url = URL(string: link) else { throw DebridError.networkError("Invalid URL") }
        return url
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) async throws -> T {
        let primaryURL = try buildURL(base: baseURL, path: path, queryItems: queryItems)
        var (data, http) = try await send(
            to: primaryURL,
            method: method,
            jsonBody: jsonBody
        )

        // Compatibility fallback: some environments/stubs serve Offcloud endpoints without /api prefix.
        if http.statusCode == 404 {
            let fallbackURL = try buildURL(base: fallbackBaseURL, path: path, queryItems: queryItems)
            if fallbackURL != primaryURL {
                (data, http) = try await send(
                    to: fallbackURL,
                    method: method,
                    jsonBody: jsonBody
                )
            }
        }

        switch http.statusCode {
        case 200...299:
            break
        case 401:
            throw DebridError.unauthorized
        case 429:
            throw DebridError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8) ?? ""
            throw DebridError.httpError(http.statusCode, message)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            throw DebridError.networkError("Invalid Offcloud response: \(error.localizedDescription)")
        }
    }

    private func buildURL(base: String, path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: base + path) else {
            throw DebridError.networkError("Invalid request URL")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw DebridError.networkError("Invalid request URL")
        }
        return url
    }

    private func send(
        to url: URL,
        method: String,
        jsonBody: [String: Any]?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, http) = try await DebridHTTPExecutor.data(for: request, session: session)
        return (data, http)
    }

    private func clearSelectionState(for torrentId: String) {
        selectedFileIDsByTorrent.removeValue(forKey: torrentId)
        episodeSelectionByTorrent.removeValue(forKey: torrentId)
    }

    private func preferredVideoLink(from links: [String]) -> String? {
        let videoExtensions = ["mkv", "mp4", "m4v", "avi", "mov", "webm"]
        if let video = links.first(where: { link in
            guard let ext = URL(string: link)?.pathExtension.lowercased() else { return false }
            return videoExtensions.contains(ext)
        }) {
            return video
        }
        return links.first
    }

    private func bestEpisodeMatch(in links: [String], request: EpisodeSelectionRequest?) -> String? {
        guard let request else { return nil }

        if let exact = bestExactMatch(in: links, request: request) {
            return exact
        }

        let matchingLinks = links.filter { link in
            let fileName = URL(string: link)?.lastPathComponent.removingPercentEncoding
                ?? URL(fileURLWithPath: link).lastPathComponent
            return EpisodeTokenMatcher.matches(
                title: fileName,
                season: request.seasonNumber,
                episode: request.episodeNumber
            )
        }

        if matchingLinks.count == 1 {
            return matchingLinks[0]
        }

        if !matchingLinks.isEmpty {
            return matchingLinks.max(by: { estimatedFileSize(from: $0) < estimatedFileSize(from: $1) })
        }

        if links.count == 1 {
            return links.first
        }

        return nil
    }

    private func fallbackSelectedLink(in links: [String], request: EpisodeSelectionRequest?) -> String? {
        if request != nil {
            return bestEpisodeMatch(in: links, request: request)
        }
        return preferredVideoLink(from: links)
    }

    private func bestExactMatch(in links: [String], request: EpisodeSelectionRequest) -> String? {
        guard let normalizedHint = Self.normalizedFileName(request.resolvedFileNameHint) else {
            return nil
        }

        let matches = links.filter { link in
            let fileName = URL(string: link)?.lastPathComponent.removingPercentEncoding
                ?? URL(fileURLWithPath: link).lastPathComponent
            return Self.normalizedFileName(fileName) == normalizedHint
        }
        guard !matches.isEmpty else { return nil }

        if let resolvedFileSizeHint = request.resolvedFileSizeHint,
           let exactSize = matches.first(where: { estimatedFileSize(from: $0) == resolvedFileSizeHint }) {
            return exactSize
        }

        return matches.max(by: { estimatedFileSize(from: $0) < estimatedFileSize(from: $1) })
    }

    private func isDeterministicEpisodeMatch(fileName: String, request: EpisodeSelectionRequest?) -> Bool {
        guard let request else { return true }

        if let normalizedHint = Self.normalizedFileName(request.resolvedFileNameHint) {
            return Self.normalizedFileName(fileName) == normalizedHint
        }

        return EpisodeTokenMatcher.matches(
            title: fileName,
            season: request.seasonNumber,
            episode: request.episodeNumber
        )
    }

    private func estimatedFileSize(from link: String) -> Int64 {
        Int64(URLComponents(string: link)?
            .queryItems?
            .first(where: { $0.name == "size" })?
            .value ?? "") ?? 0
    }

    private static func normalizedFileName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent.lowercased()
    }

    private func resolvedDisplayFileName(linkFileName: String, statusFileName: String?) -> String {
        let normalizedStatusFileName = statusFileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let linkName = linkFileName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedStatusFileName, !normalizedStatusFileName.isEmpty {
            let genericBaseNames = Set(["video", "download", "file", "stream"])
            let linkBaseName = URL(fileURLWithPath: linkName).deletingPathExtension().lastPathComponent.lowercased()
            if linkName.isEmpty || genericBaseNames.contains(linkBaseName) {
                return normalizedStatusFileName
            }
        }

        if !linkName.isEmpty {
            return linkName
        }

        return statusFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? linkFileName
    }
}

private struct EpisodeSelectionRequest: Sendable {
    let seasonNumber: Int
    let episodeNumber: Int
    let resolvedFileNameHint: String?
    let resolvedFileSizeHint: Int64?
}

private struct OCAddResponse: Sendable {
    let requestId: String?
    let status: String?
}
extension OCAddResponse: Decodable {}

private struct OCStatusResponse: Sendable {
    let requestId: String?
    let fileName: String?
    let status: String?
    let url: String?
}
extension OCStatusResponse: Decodable {}

private struct OCCacheResponse: Sendable {
    let cachedItems: [String]?
}
extension OCCacheResponse: Decodable {}

private struct OCAnyHistoryItem: Decodable, Sendable {}
