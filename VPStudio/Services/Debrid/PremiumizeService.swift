import Foundation

actor PremiumizeService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .premiumize
    private let apiToken: String
    private let baseURL = "https://www.premiumize.me/api"
    private let session: URLSession

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    func validateToken() async throws -> Bool {
        let response: PMAccountResponse = try await request(path: "/account/info")
        return response.status == "success"
    }

    func getAccountInfo() async throws -> DebridAccountInfo {
        let response: PMAccountResponse = try await request(path: "/account/info")
        return DebridAccountInfo(
            username: response.customerId ?? "Unknown",
            email: nil,
            premiumExpiry: response.premiumUntil.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) },
            isPremium: response.premiumUntil != nil
        )
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        guard !hashes.isEmpty else { return [:] }
        var cacheComponents = URLComponents()
        cacheComponents.queryItems = hashes.map { URLQueryItem(name: "items[]", value: $0) }
        let cacheQuery = cacheComponents.percentEncodedQuery ?? ""
        let response: PMCacheResponse = try await request(path: "/cache/check?\(cacheQuery)")

        var result: [String: CacheStatus] = [:]
        for (index, hash) in hashes.enumerated() {
            if index < (response.response?.count ?? 0), response.response?[index] == true {
                result[hash.lowercased()] = .cached(fileId: nil, fileName: nil, fileSize: nil)
            } else {
                result[hash.lowercased()] = .notCached
            }
        }
        return result
    }

    func addMagnet(hash: String) async throws -> String {
        let magnet = "magnet:?xt=urn:btih:\(hash)"
        let body = "src=\(magnet.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? magnet)"
        let response: PMTransferResponse = try await request(path: "/transfer/create", method: "POST", body: body)
        return response.id ?? hash
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {}

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        // For Premiumize, use direct download via transfer info
        let response: PMTransferInfoResponse = try await request(path: "/transfer/list")
        guard let transfer = response.transfers?.first(where: { $0.id == torrentId }) else {
            throw DebridError.torrentNotFound(torrentId)
        }
        guard transfer.status == "finished", let link = transfer.link else {
            throw DebridError.fileNotReady(transfer.status ?? "unknown")
        }
        guard let url = URL(string: link) else {
            throw DebridError.networkError("Invalid URL")
        }
        let fileName = transfer.name ?? "Unknown"
        return StreamInfo(
            streamURL: url,
            quality: VideoQuality.parse(from: fileName),
            codec: VideoCodec.parse(from: fileName),
            audio: AudioFormat.parse(from: fileName),
            source: SourceType.parse(from: fileName),
            hdr: HDRFormat.parse(from: fileName),
            fileName: fileName,
            sizeBytes: nil,
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

    private func request<T: Decodable>(path: String, method: String = "GET", body: String? = nil) async throws -> T {
        let urlStr = "\(baseURL)\(path)"
        guard let url = URL(string: urlStr) else {
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

private struct PMAccountResponse: Sendable {
    let status: String?
    let customerId: String?
    let premiumUntil: Int?
}
extension PMAccountResponse: Decodable {}

private struct PMCacheResponse: Sendable {
    let status: String?
    let response: [Bool]?
}
extension PMCacheResponse: Decodable {}

private struct PMTransferResponse: Sendable {
    let status: String?
    let id: String?
}
extension PMTransferResponse: Decodable {}

private struct PMTransferInfoResponse: Sendable {
    let status: String?
    let transfers: [PMTransfer]?
}
extension PMTransferInfoResponse: Decodable {}

private struct PMTransfer: Sendable {
    let id: String?
    let name: String?
    let status: String?
    let link: String?
}
extension PMTransfer: Decodable {}
