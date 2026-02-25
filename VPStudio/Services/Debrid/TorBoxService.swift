import Foundation

actor TorBoxService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .torBox
    private let apiToken: String
    private let baseURL = "https://api.torbox.app/v1/api"
    private let session: URLSession

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
        let magnet = "magnet:?xt=urn:btih:\(hash)"
        let body = "magnet=\(magnet.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? magnet)"
        let response: TBResponse<TBCreateResponse> = try await request(method: "POST", path: "/torrents/createtorrent", body: body)
        guard let id = response.data?.torrentId else { throw DebridError.invalidHash(hash) }
        return String(id)
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {}

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        let response: TBResponse<TBTorrentInfo> = try await request(
            method: "GET",
            path: "/torrents/mylist",
            queryItems: [URLQueryItem(name: "id", value: torrentId)]
        )
        guard let torrent = response.data else { throw DebridError.torrentNotFound(torrentId) }
        guard torrent.downloadFinished == true else { throw DebridError.fileNotReady("downloading") }

        // Pick largest file (most likely the video) instead of hardcoding file_id=0
        let fileId: String
        if let files = torrent.files,
           let largest = files.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }),
           let id = largest.id
        {
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
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DebridError.networkError("Invalid response")
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

        return try JSONDecoder().decode(T.self, from: data)
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
