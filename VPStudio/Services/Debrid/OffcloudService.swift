import Foundation

actor OffcloudService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .offcloud
    private let apiToken: String
    private let baseURL = "https://offcloud.com/api"
    private let session: URLSession

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    func validateToken() async throws -> Bool {
        let _: [OCAnyHistoryItem] = try await request(
            method: "GET",
            path: "/cloud/history"
        )
        return true
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
        let magnet = "magnet:?xt=urn:btih:\(hash)"
        let decoded: OCAddResponse = try await request(
            method: "POST",
            path: "/cloud",
            jsonBody: ["url": magnet]
        )
        return decoded.requestId ?? hash
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {}

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        let statusResponse: OCStatusResponse = try await request(
            method: "POST",
            path: "/cloud/status",
            jsonBody: ["requestId": torrentId]
        )

        let status = statusResponse.status?.lowercased() ?? "unknown"
        guard status == "downloaded" else {
            throw DebridError.fileNotReady(status)
        }

        if let direct = statusResponse.url, let directURL = URL(string: direct) {
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
        guard let link = preferredVideoLink(from: links), let streamURL = URL(string: link) else {
            throw DebridError.networkError("No download link")
        }

        let fileName = statusResponse.fileName ?? streamURL.lastPathComponent
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
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            throw DebridError.networkError("Invalid Offcloud response: \(error.localizedDescription)")
        }
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
