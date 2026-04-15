import Foundation

actor TorBoxService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .torBox
    private let apiToken: String
    private let baseURL = "https://api.torbox.app/v1/api"
    private let session: URLSession
    private var selectedFileIDsByTorrent: [String: Set<Int>] = [:]

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    func validateToken() async throws -> Bool {
        let _: TBResponse<TBUser> = try await request(method: "GET", path: "/user/me")
        return true
    }

    func getAccountInfo() async throws -> DebridAccountInfo {
        let response: TBResponse<TBUser> = try await request(method: "GET", path: "/user/me")
        return DebridAccountInfo(
            username: response.data?.email ?? "Unknown",
            email: response.data?.email,
            premiumExpiry: nil,
            isPremium: response.data?.plan != nil
        )
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        guard !hashes.isEmpty else { return [:] }
        let hashParam = hashes.joined(separator: ",")
        let response: TBResponse<[TBCacheItem]> = try await request(
            method: "GET",
            path: "/torrents/checkcached",
            queryItems: [
                URLQueryItem(name: "hash", value: hashParam),
                URLQueryItem(name: "format", value: "list"),
            ]
        )
        var result: [String: CacheStatus] = [:]
        for hash in hashes {
            let lowered = hash.lowercased()
            if response.data?.contains(where: { $0.hash?.lowercased() == lowered }) == true {
                result[lowered] = .cached(fileId: nil, fileName: nil, fileSize: nil)
            } else {
                result[lowered] = .notCached
            }
        }
        return result
    }

    func addMagnet(hash: String) async throws -> String {
        let normalizedHash = try DebridHashValidator.validatedInfoHash(hash)
        let magnet = "magnet:?xt=urn:btih:\(normalizedHash)"
        let body = "magnet=\(magnet.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? magnet)"
        let response: TBResponse<TBCreateResponse> = try await request(method: "POST", path: "/torrents/createtorrent", body: body)
        guard let id = response.data?.torrentId else { throw DebridError.invalidHash(hash) }
        return String(id)
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        if fileIds.isEmpty {
            selectedFileIDsByTorrent.removeValue(forKey: torrentId)
            return
        }
        selectedFileIDsByTorrent[torrentId] = Set(fileIds)
    }

    func selectMatchingEpisodeFile(
        torrentId: String,
        seasonNumber: Int,
        episodeNumber: Int
    ) async throws -> Bool {
        let response: TBResponse<TBTorrentInfo> = try await request(
            method: "GET",
            path: "/torrents/mylist",
            queryItems: [URLQueryItem(name: "id", value: torrentId)]
        )
        guard let torrent = response.data,
              let files = torrent.files else {
            return false
        }
        return try await selectMatchingEpisodeFile(
            torrentId: torrentId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil,
            files: files
        )
    }

    func selectMatchingEpisodeFile(
        torrentId: String,
        seasonNumber: Int,
        episodeNumber: Int,
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?
    ) async throws -> Bool {
        let response: TBResponse<TBTorrentInfo> = try await request(
            method: "GET",
            path: "/torrents/mylist",
            queryItems: [URLQueryItem(name: "id", value: torrentId)]
        )
        guard let torrent = response.data,
              let files = torrent.files else {
            return false
        }
        return try await selectMatchingEpisodeFile(
            torrentId: torrentId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            resolvedFileNameHint: resolvedFileNameHint,
            resolvedFileSizeHint: resolvedFileSizeHint,
            files: files
        )
    }

    func cleanupRemoteTransfer(torrentId: String) async throws {
        selectedFileIDsByTorrent.removeValue(forKey: torrentId)

        guard let url = URL(string: baseURL + "/torrents/controltorrent") else {
            throw DebridError.networkError("Invalid request URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["torrent_id": torrentId, "operation": "delete"]
        )

        let (data, http) = try await DebridHTTPExecutor.data(for: request, session: session)
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw DebridError.unauthorized
        case 429:
            throw DebridError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8) ?? ""
            throw DebridError.httpError(http.statusCode, message)
        }
    }

    private func selectMatchingEpisodeFile(
        torrentId: String,
        seasonNumber: Int,
        episodeNumber: Int,
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?,
        files: [TBFile]
    ) async throws -> Bool {
        if let exactMatch = bestExactMatch(
            in: files,
            resolvedFileNameHint: resolvedFileNameHint,
            resolvedFileSizeHint: resolvedFileSizeHint
        ),
           let fileId = exactMatch.id {
            try await selectFiles(torrentId: torrentId, fileIds: [fileId])
            return true
        }

        let matches = files.filter { file in
            guard let name = file.name else { return false }
            return EpisodeTokenMatcher.matches(title: name, season: seasonNumber, episode: episodeNumber)
        }

        if let bestMatch = matches.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }),
           let fileId = bestMatch.id {
            try await selectFiles(torrentId: torrentId, fileIds: [fileId])
            return true
        }

        if files.count == 1, let fileId = files.first?.id {
            try await selectFiles(torrentId: torrentId, fileIds: [fileId])
            return true
        }

        return false
    }

    private func bestExactMatch(
        in files: [TBFile],
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?
    ) -> TBFile? {
        guard let normalizedHint = Self.normalizedFileName(resolvedFileNameHint) else {
            return nil
        }

        let matches = files.filter { file in
            Self.normalizedFileName(file.name) == normalizedHint
        }
        guard !matches.isEmpty else { return nil }

        if let resolvedFileSizeHint,
           let exactSize = matches.first(where: { $0.size == resolvedFileSizeHint }) {
            return exactSize
        }

        return matches.max(by: { ($0.size ?? 0) < ($1.size ?? 0) })
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        let response: TBResponse<TBTorrentInfo> = try await request(
            method: "GET",
            path: "/torrents/mylist",
            queryItems: [URLQueryItem(name: "id", value: torrentId)]
        )
        guard let torrent = response.data else { throw DebridError.torrentNotFound(torrentId) }
        guard torrent.downloadFinished == true else { throw DebridError.fileNotReady("downloading") }

        // Prefer explicitly selected files (episode-specific), fallback to largest file.
        let fileId: String
        let selectedIDs = selectedFileIDsByTorrent[torrentId] ?? []
        if let files = torrent.files,
           let selected = files.first(where: { file in
               guard let id = file.id else { return false }
               return selectedIDs.contains(id)
           }),
           let id = selected.id {
            fileId = String(id)
        } else if let files = torrent.files,
                  let largest = files.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }),
                  let id = largest.id {
            fileId = String(id)
        } else {
            fileId = "0"
        }

        let linkResponse: TBResponse<TBDownloadLink> = try await request(
            method: "GET",
            path: "/torrents/requestdl",
            queryItems: [
                URLQueryItem(name: "torrent_id", value: torrentId),
                URLQueryItem(name: "file_id", value: fileId),
            ]
        )
        guard let urlStr = linkResponse.data?.data, let url = URL(string: urlStr) else {
            throw DebridError.networkError("No download link")
        }

        selectedFileIDsByTorrent.removeValue(forKey: torrentId)
        let fileName = torrent.name ?? "Unknown"
        return StreamInfo(
            streamURL: url,
            quality: VideoQuality.parse(from: fileName),
            codec: VideoCodec.parse(from: fileName),
            audio: AudioFormat.parse(from: fileName),
            source: SourceType.parse(from: fileName),
            hdr: HDRFormat.parse(from: fileName),
            fileName: fileName,
            sizeBytes: torrent.size,
            debridService: serviceType.rawValue
        )
    }

    func unrestrict(link: String) async throws -> URL {
        guard let url = URL(string: link) else { throw DebridError.networkError("Invalid URL") }
        return url
    }

    private static let formEncodingAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return allowed
    }()

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: String? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw DebridError.networkError("Invalid request URL")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw DebridError.networkError("Invalid request URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let (data, http) = try await DebridHTTPExecutor.data(for: request, session: session)

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

        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func normalizedFileName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent.lowercased()
    }
}

private struct TBResponse<T: Decodable & Sendable>: Sendable {
    let success: Bool?
    let data: T?
}
extension TBResponse: Decodable {}

private struct TBUser: Sendable {
    let email: String?
    let plan: Int?
}
extension TBUser: Decodable {}

private struct TBCacheItem: Sendable {
    let hash: String?
    let name: String?
}
extension TBCacheItem: Decodable {}

private struct TBCreateResponse: Sendable {
    let torrentId: Int?
    enum CodingKeys: String, CodingKey { case torrentId = "torrent_id" }
}
extension TBCreateResponse: Decodable {}

private struct TBTorrentInfo: Sendable {
    let name: String?
    let size: Int64?
    let downloadFinished: Bool?
    let files: [TBFile]?
    enum CodingKeys: String, CodingKey {
        case name, size, files
        case downloadFinished = "download_finished"
    }
}
extension TBTorrentInfo: Decodable {}

private struct TBFile: Sendable {
    let id: Int?
    let name: String?
    let size: Int64?
}
extension TBFile: Decodable {}

private struct TBDownloadLink: Sendable {
    let data: String?
}
extension TBDownloadLink: Decodable {}
