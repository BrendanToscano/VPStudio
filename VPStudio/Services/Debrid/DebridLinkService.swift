import Foundation

actor DebridLinkService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .debridLink
    private let apiToken: String
    private let baseURL = "https://debrid-link.com/api/v2"
    private let session: URLSession
    private var selectedFileIDsByTorrent: [String: Set<Int>] = [:]
    private var episodeSelectionByTorrent: [String: EpisodeSelectionRequest] = [:]

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    func validateToken() async throws -> Bool {
        let _: DLResponse<DLAccountInfo> = try await request(method: "GET", path: "/account/infos")
        return true
    }

    func getAccountInfo() async throws -> DebridAccountInfo {
        let response: DLResponse<DLAccountInfo> = try await request(method: "GET", path: "/account/infos")
        return DebridAccountInfo(
            username: response.value?.pseudo ?? "Unknown",
            email: response.value?.email,
            premiumExpiry: response.value?.premiumLeft.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) },
            isPremium: (response.value?.premiumLeft ?? 0) > 0
        )
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        guard !hashes.isEmpty else { return [:] }
        var cacheComponents = URLComponents()
        cacheComponents.queryItems = [URLQueryItem(name: "url", value: hashes.joined(separator: ","))]
        let cacheQuery = cacheComponents.percentEncodedQuery ?? ""
        let response: DLResponse<[String: DLCacheResult]> = try await request(method: "GET", path: "/seedbox/cached?\(cacheQuery)")

        var result: [String: CacheStatus] = [:]
        for hash in hashes {
            if let cached = response.value?[hash.lowercased()], cached.files != nil {
                result[hash.lowercased()] = .cached(fileId: nil, fileName: nil, fileSize: nil)
            } else {
                result[hash.lowercased()] = .notCached
            }
        }
        return result
    }

    func addMagnet(hash: String) async throws -> String {
        let normalizedHash = try DebridHashValidator.validatedInfoHash(hash)
        let magnet = "magnet:?xt=urn:btih:\(normalizedHash)"
        let body = formBody([
            URLQueryItem(name: "url", value: magnet),
            URLQueryItem(name: "async", value: "true"),
        ])
        let response: DLResponse<DLAddResponse> = try await request(method: "POST", path: "/seedbox/add", body: body)
        if response.success == false {
            let reason = response.error ?? response.message ?? "Debrid-Link rejected the magnet"
            throw DebridError.networkError(reason)
        }
        guard let id = response.value?.id, !id.isEmpty else {
            throw DebridError.networkError("Debrid-Link did not return a torrent id")
        }
        return id
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        if fileIds.isEmpty {
            selectedFileIDsByTorrent.removeValue(forKey: torrentId)
            episodeSelectionByTorrent.removeValue(forKey: torrentId)
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

    func cleanupRemoteTransfer(torrentId: String) async throws {
        selectedFileIDsByTorrent.removeValue(forKey: torrentId)
        episodeSelectionByTorrent.removeValue(forKey: torrentId)
        let _: DLResponse<DLDeleteResponse> = try await request(
            method: "DELETE",
            path: "/seedbox/\(torrentId)/remove"
        )
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        var listComponents = URLComponents()
        listComponents.queryItems = [URLQueryItem(name: "ids", value: torrentId)]
        let listQuery = listComponents.percentEncodedQuery ?? ""
        let response: DLResponse<[DLTorrentInfo]> = try await request(method: "GET", path: "/seedbox/list?\(listQuery)")
        guard let torrent = response.value?.first else { throw DebridError.torrentNotFound(torrentId) }
        guard torrent.downloadPercent == 100 else {
            throw DebridError.fileNotReady("downloading")
        }

        let selectedIDs = selectedFileIDsByTorrent[torrentId] ?? []
        let episodeSelection = episodeSelectionByTorrent[torrentId]
        let selectedFile = torrent.files?.enumerated().first(where: { pair in
            if let id = pair.element.id {
                return selectedIDs.contains(id)
            }
            return selectedIDs.contains(pair.offset + 1)
        })?.element ?? bestEpisodeMatch(in: torrent.files, request: episodeSelection)

        guard let link = selectedFile?.downloadUrl ?? fallbackSelectedFile(in: torrent.files, request: episodeSelection)?.downloadUrl else {
            selectedFileIDsByTorrent.removeValue(forKey: torrentId)
            episodeSelectionByTorrent.removeValue(forKey: torrentId)
            if episodeSelection != nil {
                throw DebridError.networkError("Debrid-Link could not deterministically select the requested episode file.")
            }
            throw DebridError.torrentNotFound(torrentId)
        }
        guard let url = URL(string: link) else { throw DebridError.networkError("Invalid URL") }
        selectedFileIDsByTorrent.removeValue(forKey: torrentId)
        episodeSelectionByTorrent.removeValue(forKey: torrentId)
        let fileName = selectedFile?.name ?? selectedFile?.downloadUrl.flatMap { URL(string: $0)?.lastPathComponent } ?? torrent.name ?? "Unknown"
        return StreamInfo(
            streamURL: url,
            quality: VideoQuality.parse(from: fileName),
            codec: VideoCodec.parse(from: fileName),
            audio: AudioFormat.parse(from: fileName),
            source: SourceType.parse(from: fileName),
            hdr: HDRFormat.parse(from: fileName),
            fileName: fileName,
            sizeBytes: torrent.totalSize,
            debridService: serviceType.rawValue
        )
    }

    func unrestrict(link: String) async throws -> URL {
        guard let url = URL(string: link) else { throw DebridError.networkError("Invalid URL") }
        return url
    }

    private func request<T: Decodable>(method: String, path: String, body: String? = nil) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
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

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func formBody(_ items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }

    private func bestEpisodeMatch(in files: [DLFile]?, request: EpisodeSelectionRequest?) -> DLFile? {
        guard let files, let request else { return nil }

        if let exact = bestExactMatch(in: files, request: request) {
            return exact
        }

        let matches = files.filter { file in
            guard let name = file.name ?? file.downloadUrl.flatMap({ URL(string: $0)?.lastPathComponent }) else {
                return false
            }
            return EpisodeTokenMatcher.matches(
                title: name,
                season: request.seasonNumber,
                episode: request.episodeNumber
            )
        }

        if let match = matches.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }) {
            return match
        }

        if files.count == 1 {
            return files.first
        }

        return nil
    }

    private func fallbackSelectedFile(in files: [DLFile]?, request: EpisodeSelectionRequest?) -> DLFile? {
        if request != nil {
            return bestEpisodeMatch(in: files, request: request)
        }
        return files?.first
    }

    private func bestExactMatch(in files: [DLFile], request: EpisodeSelectionRequest) -> DLFile? {
        guard let normalizedHint = Self.normalizedFileName(request.resolvedFileNameHint) else {
            return nil
        }

        let matches = files.filter { file in
            let candidateName = file.name ?? file.downloadUrl.flatMap { URL(string: $0)?.lastPathComponent }
            return Self.normalizedFileName(candidateName) == normalizedHint
        }
        guard !matches.isEmpty else { return nil }

        if let resolvedFileSizeHint = request.resolvedFileSizeHint,
           let exactSize = matches.first(where: { $0.size == resolvedFileSizeHint }) {
            return exactSize
        }

        return matches.max(by: { ($0.size ?? 0) < ($1.size ?? 0) })
    }

    private static func normalizedFileName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent.lowercased()
    }
}

private struct EpisodeSelectionRequest: Sendable {
    let seasonNumber: Int
    let episodeNumber: Int
    let resolvedFileNameHint: String?
    let resolvedFileSizeHint: Int64?
}

private struct DLResponse<T: Decodable & Sendable>: Sendable {
    let success: Bool?
    let value: T?
    let error: String?
    let message: String?
}
extension DLResponse: Decodable {}

private struct DLAccountInfo: Sendable { let pseudo: String?; let email: String?; let premiumLeft: Int? }
extension DLAccountInfo: Decodable {}

private struct DLCacheResult: Sendable { let files: [DLFile]? }
extension DLCacheResult: Decodable {}

private struct DLFile: Sendable { let id: Int?; let name: String?; let size: Int64?; let downloadUrl: String? }
extension DLFile: Decodable {}

private struct DLAddResponse: Sendable { let id: String? }
extension DLAddResponse: Decodable {}

private struct DLDeleteResponse: Sendable {
    let removed: Int?
}
extension DLDeleteResponse: Decodable {}

private struct DLTorrentInfo: Sendable { let name: String?; let totalSize: Int64?; let downloadPercent: Int?; let files: [DLFile]? }
extension DLTorrentInfo: Decodable {}
