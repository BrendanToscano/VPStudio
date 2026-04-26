import Foundation

actor PremiumizeService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .premiumize
    private let apiToken: String
    private let baseURL = "https://www.premiumize.me/api"
    private let session: URLSession
    private var episodeSelectionByTorrent: [String: EpisodeSelectionRequest] = [:]

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
        let normalizedHash = try DebridHashValidator.validatedInfoHash(hash)
        let magnet = "magnet:?xt=urn:btih:\(normalizedHash)"
        let body = "src=\(magnet.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? magnet)"
        let response: PMTransferResponse = try await request(path: "/transfer/create", method: "POST", body: body)
        return response.id ?? normalizedHash
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        let _ = torrentId
        let _ = fileIds
        episodeSelectionByTorrent.removeValue(forKey: torrentId)
        // Premiumize does not expose per-file selection in this flow.
        // Treat selection as a no-op so callers can use the shared debrid path
        // without special-casing this provider or turning a recoverable path
        // into a hard failure.
    }

    func selectMatchingEpisodeFile(
        torrentId: String,
        seasonNumber: Int,
        episodeNumber: Int,
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?
    ) async throws -> Bool {
        let selectionRequest = EpisodeSelectionRequest(
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            resolvedFileNameHint: resolvedFileNameHint,
            resolvedFileSizeHint: resolvedFileSizeHint
        )
        episodeSelectionByTorrent[torrentId] = selectionRequest

        let response: PMTransferInfoResponse = try await request(path: "/transfer/list")
        guard let transfer = response.transfers?.first(where: { $0.id == torrentId }) else {
            return true
        }

        if let resolvedFileNameHint,
           Self.normalizedFileName(transfer.name) == Self.normalizedFileName(resolvedFileNameHint) {
            return true
        }

        if let transferName = transfer.name,
           EpisodeTokenMatcher.matches(title: transferName, season: seasonNumber, episode: episodeNumber) {
            return true
        }

        episodeSelectionByTorrent.removeValue(forKey: torrentId)
        return false
    }

    func cleanupRemoteTransfer(torrentId: String) async throws {
        episodeSelectionByTorrent.removeValue(forKey: torrentId)
        let body = "id=\(torrentId.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? torrentId)"
        let response: PMTransferDeleteResponse = try await request(
            path: "/transfer/delete",
            method: "POST",
            body: body
        )
        guard response.status == nil || response.status == "success" else {
            throw DebridError.networkError(response.message ?? "Premiumize rejected remote cleanup")
        }
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        // For Premiumize, use direct download via transfer info
        let response: PMTransferInfoResponse = try await request(path: "/transfer/list")
        guard let transfer = response.transfers?.first(where: { $0.id == torrentId }) else {
            throw DebridError.torrentNotFound(torrentId)
        }
        if let selectionRequest = episodeSelectionByTorrent[torrentId] {
            if let resolvedFileNameHint = selectionRequest.resolvedFileNameHint {
                guard Self.normalizedFileName(transfer.name) == Self.normalizedFileName(resolvedFileNameHint) else {
                    episodeSelectionByTorrent.removeValue(forKey: torrentId)
                    throw DebridError.networkError("Premiumize could not deterministically select the requested episode file.")
                }
            } else if let transferName = transfer.name,
                      !EpisodeTokenMatcher.matches(title: transferName, season: selectionRequest.seasonNumber, episode: selectionRequest.episodeNumber) {
                episodeSelectionByTorrent.removeValue(forKey: torrentId)
                throw DebridError.networkError("Premiumize could not deterministically select the requested episode file.")
            }
        }
        guard transfer.status == "finished", let link = transfer.link else {
            throw DebridError.fileNotReady(transfer.status ?? "unknown")
        }
        guard let url = URL(string: link) else {
            throw DebridError.networkError("Invalid URL")
        }
        let fileName = transfer.name ?? "Unknown"
        episodeSelectionByTorrent.removeValue(forKey: torrentId)
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

private struct EpisodeSelectionRequest: Sendable {
    let seasonNumber: Int
    let episodeNumber: Int
    let resolvedFileNameHint: String?
    let resolvedFileSizeHint: Int64?
}

private struct PMAccountResponse: Sendable {
    let status: String?
    let customerId: String?
    let premiumUntil: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case customerId = "customer_id"
        case premiumUntil = "premium_until"
    }
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

private struct PMTransferDeleteResponse: Sendable {
    let status: String?
    let message: String?
}
extension PMTransferDeleteResponse: Decodable {}
