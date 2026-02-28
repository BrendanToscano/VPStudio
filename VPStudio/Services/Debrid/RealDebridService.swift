import Foundation

actor RealDebridService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .realDebrid
    private let apiToken: String
    private let baseURL = "https://api.real-debrid.com/rest/1.0"
    private let session: URLSession

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    func validateToken() async throws -> Bool {
        let _: RDUserResponse = try await request(method: "GET", path: "/user")
        return true
    }

    func getAccountInfo() async throws -> DebridAccountInfo {
        let user: RDUserResponse = try await request(method: "GET", path: "/user")
        let formatter = ISO8601DateFormatter()
        let expiry = user.expiration.flatMap { formatter.date(from: $0) }
        return DebridAccountInfo(
            username: user.username ?? "Unknown",
            email: user.email,
            premiumExpiry: expiry,
            isPremium: user.type == "premium"
        )
    }

    /// Validates that a string looks like a hex info-hash (40 or 64 hex chars).
    /// Prevents path-traversal or URL corruption when hashes are embedded in URL paths.
    private static var hexHashPattern: NSRegularExpression? {
        try? NSRegularExpression(pattern: "^[0-9a-fA-F]{40,64}$")
    }

    private static func isValidHexHash(_ hash: String) -> Bool {
        guard let pattern = hexHashPattern else { return false }
        let range = NSRange(hash.startIndex..<hash.endIndex, in: hash)
        return pattern.firstMatch(in: hash, range: range) != nil
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        guard !hashes.isEmpty else { return [:] }

        // Filter to valid hex hashes to prevent path injection via crafted hash values.
        let validHashes = hashes.filter { Self.isValidHexHash($0) }
        guard !validHashes.isEmpty else { return [:] }

        // Batch hashes to keep URL under ~2000 chars. Each hash is 40 chars + 1 separator.
        // Path prefix "/torrents/instantAvailability/" = 30 chars, so ~48 hashes per batch.
        let batchSize = 48
        var result: [String: CacheStatus] = [:]

        for batchStart in stride(from: 0, to: validHashes.count, by: batchSize) {
            let batch = Array(validHashes[batchStart ..< min(batchStart + batchSize, validHashes.count)])
            let hashStr = batch.joined(separator: "/")
            let response: [String: [RDCacheVariant]] = try await request(
                method: "GET",
                path: "/torrents/instantAvailability/\(hashStr)"
            )

            for hash in batch {
                let lowered = hash.lowercased()
                if let variants = response[lowered], !variants.isEmpty {
                    result[lowered] = .cached(fileId: nil, fileName: nil, fileSize: nil)
                } else {
                    result[lowered] = .notCached
                }
            }
        }
        return result
    }

    func addMagnet(hash: String) async throws -> String {
        // Check if torrent already exists
        let existing: [RDTorrentInfo] = try await request(method: "GET", path: "/torrents?limit=2500")
        if let found = existing.first(where: { $0.hash?.lowercased() == hash.lowercased() }), let id = found.id {
            return id
        }

        let magnet = "magnet:?xt=urn:btih:\(hash)"
        let body = "magnet=\(magnet.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? magnet)"
        let response: RDAddMagnetResponse = try await request(method: "POST", path: "/torrents/addMagnet", body: body)
        guard let id = response.id else {
            throw DebridError.invalidHash(hash)
        }
        return id
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        let ids = fileIds.isEmpty ? "all" : fileIds.map(String.init).joined(separator: ",")
        let body = "files=\(ids)"
        do {
            let _: EmptyResponse = try await request(method: "POST", path: "/torrents/selectFiles/\(torrentId)", body: body)
        } catch is DecodingError {
            // 204 No Content — file selection succeeded
        }
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        let info: RDTorrentInfo = try await request(method: "GET", path: "/torrents/info/\(torrentId)")

        guard info.status == "downloaded" else {
            throw DebridError.fileNotReady(info.status ?? "unknown")
        }

        guard let links = info.links, let firstLink = links.first else {
            throw DebridError.torrentNotFound(torrentId)
        }

        let unrestricted = try await unrestrict(link: firstLink)
        let fileName = info.filename ?? "Unknown"

        return StreamInfo(
            streamURL: unrestricted,
            quality: VideoQuality.parse(from: fileName),
            codec: VideoCodec.parse(from: fileName),
            audio: AudioFormat.parse(from: fileName),
            source: SourceType.parse(from: fileName),
            hdr: HDRFormat.parse(from: fileName),
            fileName: fileName,
            sizeBytes: info.bytes,
            debridService: serviceType.rawValue
        )
    }

    func unrestrict(link: String) async throws -> URL {
        let body = "link=\(link.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? link)"
        let response: RDUnrestrictResponse = try await request(method: "POST", path: "/unrestrict/link", body: body)
        guard let download = response.download, let url = URL(string: download) else {
            throw DebridError.networkError("Invalid unrestrict URL")
        }
        return url
    }

    private static let formEncodingAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return allowed
    }()

    // MARK: - HTTP

    private func request<T: Decodable>(method: String, path: String, body: String? = nil) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw DebridError.networkError("Invalid request URL")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        if let body {
            urlRequest.httpBody = Data(body.utf8)
            urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DebridError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw DebridError.unauthorized
        case 429:
            throw DebridError.rateLimited
        default:
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw DebridError.httpError(httpResponse.statusCode, msg)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Real-Debrid API Models

private struct RDUserResponse: Sendable {
    let username: String?
    let email: String?
    let type: String?
    let expiration: String?
}
extension RDUserResponse: Decodable {}

private struct RDCacheVariant: Sendable {}
extension RDCacheVariant: Decodable {}

private struct RDAddMagnetResponse: Sendable {
    let id: String
    let uri: String?
}
extension RDAddMagnetResponse: Decodable {}

private struct RDTorrentInfo: Sendable {
    let id: String?
    let filename: String?
    let hash: String?
    let bytes: Int64?
    let status: String?
    let links: [String]?
}
extension RDTorrentInfo: Decodable {}

private struct RDUnrestrictResponse: Sendable {
    let id: String?
    let filename: String?
    let download: String?
    let filesize: Int64?
}
extension RDUnrestrictResponse: Decodable {}

private struct EmptyResponse: Sendable {}
extension EmptyResponse: Decodable {}
