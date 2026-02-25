import Foundation

actor DebridLinkService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .debridLink
    private let apiToken: String
    private let baseURL = "https://debrid-link.com/api/v2"
    private let session: URLSession

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
        let magnet = "magnet:?xt=urn:btih:\(hash)"
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

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {}

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        var listComponents = URLComponents()
        listComponents.queryItems = [URLQueryItem(name: "ids", value: torrentId)]
        let listQuery = listComponents.percentEncodedQuery ?? ""
        let response: DLResponse<[DLTorrentInfo]> = try await request(method: "GET", path: "/seedbox/list?\(listQuery)")
        guard let torrent = response.value?.first else { throw DebridError.torrentNotFound(torrentId) }
        guard torrent.downloadPercent == 100, let link = torrent.files?.first?.downloadUrl else {
            throw DebridError.fileNotReady("downloading")
        }
        guard let url = URL(string: link) else { throw DebridError.networkError("Invalid URL") }
        let fileName = torrent.name ?? "Unknown"
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

    private func formBody(_ items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }
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

private struct DLFile: Sendable { let name: String?; let size: Int64?; let downloadUrl: String? }
extension DLFile: Decodable {}

private struct DLAddResponse: Sendable { let id: String? }
extension DLAddResponse: Decodable {}

private struct DLTorrentInfo: Sendable { let name: String?; let totalSize: Int64?; let downloadPercent: Int?; let files: [DLFile]? }
extension DLTorrentInfo: Decodable {}
