import Foundation

actor AllDebridService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .allDebrid
    private let apiToken: String
    private let baseURL = "https://api.alldebrid.com/v4"
    private let session: URLSession
    private let agent = "VPStudio"

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    func validateToken() async throws -> Bool {
        let _: ADResponse<ADUser> = try await request(path: "/user", params: [:])
        return true
    }

    func getAccountInfo() async throws -> DebridAccountInfo {
        let response: ADResponse<ADUser> = try await request(path: "/user", params: [:])
        let user = response.data
        return DebridAccountInfo(
            username: user.user?.username ?? "Unknown",
            email: user.user?.email,
            premiumExpiry: nil,
            isPremium: user.user?.isPremium ?? false
        )
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        guard !hashes.isEmpty else { return [:] }
        let params = hashes.enumerated().reduce(into: [String: String]()) { result, pair in
            result["magnets[\(pair.offset)]"] = pair.element
        }
        let response: ADResponse<ADInstantResponse> = try await request(path: "/magnet/instant", params: params)

        var result: [String: CacheStatus] = hashes.reduce(into: [String: CacheStatus]()) { partialResult, hash in
            partialResult[hash.lowercased()] = .notCached
        }
        if let magnets = response.data.magnets {
            for magnet in magnets {
                let hash = (magnet.hash ?? "").lowercased()
                guard !hash.isEmpty else { continue }
                if magnet.instant == true {
                    result[hash] = .cached(fileId: nil, fileName: nil, fileSize: nil)
                } else {
                    result[hash] = .notCached
                }
            }
        }
        return result
    }

    func addMagnet(hash: String) async throws -> String {
        let magnet = "magnet:?xt=urn:btih:\(hash)"
        let params = ["magnets[0]": magnet]
        let response: ADResponse<ADUploadResponse> = try await request(path: "/magnet/upload", params: params, method: "POST")
        guard let id = response.data.magnets?.first?.id else {
            throw DebridError.invalidHash(hash)
        }
        return String(id)
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {
        // AllDebrid auto-selects files
    }

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        let params = ["id": torrentId]
        let response: ADResponse<ADMagnetStatus> = try await request(path: "/magnet/status", params: params)
        let status = response.data

        guard status.statusCode == 4 else {
            throw DebridError.fileNotReady(status.status ?? "processing")
        }

        guard let link = status.links?.first?.link else {
            throw DebridError.torrentNotFound(torrentId)
        }

        let url = try await unrestrict(link: link)
        let fileName = status.filename ?? "Unknown"

        return StreamInfo(
            streamURL: url,
            quality: VideoQuality.parse(from: fileName),
            codec: VideoCodec.parse(from: fileName),
            audio: AudioFormat.parse(from: fileName),
            source: SourceType.parse(from: fileName),
            hdr: HDRFormat.parse(from: fileName),
            fileName: fileName,
            sizeBytes: status.size,
            debridService: serviceType.rawValue
        )
    }

    func unrestrict(link: String) async throws -> URL {
        let params = ["link": link]
        let response: ADResponse<ADUnlockResponse> = try await request(path: "/link/unlock", params: params)
        guard let urlStr = response.data.link, let url = URL(string: urlStr) else {
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

    private func request<T: Decodable>(path: String, params: [String: String], method: String = "GET") async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw DebridError.networkError("Invalid request URL")
        }
        var allParams = params
        allParams["agent"] = agent

        if method == "GET" {
            components.queryItems = allParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            throw DebridError.networkError("Invalid request URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        if method == "POST" {
            let body = allParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? $0.value)" }.joined(separator: "&")
            request.httpBody = Data(body.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DebridError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw DebridError.unauthorized
        case 429:
            throw DebridError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8) ?? ""
            throw DebridError.httpError(httpResponse.statusCode, message)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - AllDebrid API Models

private struct ADResponse<T: Decodable & Sendable>: Sendable {
    let status: String
    let data: T
}
extension ADResponse: Decodable {}

private struct ADUser: Sendable {
    let user: ADUserInfo?
}
extension ADUser: Decodable {}

private struct ADUserInfo: Sendable {
    let username: String?
    let email: String?
    let isPremium: Bool?
}
extension ADUserInfo: Decodable {}

private struct ADInstantResponse: Sendable {
    let magnets: [ADInstantMagnet]?
}
extension ADInstantResponse: Decodable {}

private struct ADInstantMagnet: Sendable {
    let hash: String?
    let instant: Bool?
}
extension ADInstantMagnet: Decodable {}

private struct ADUploadResponse: Sendable {
    let magnets: [ADUploadedMagnet]?
}
extension ADUploadResponse: Decodable {}

private struct ADUploadedMagnet: Sendable {
    let id: Int
}
extension ADUploadedMagnet: Decodable {}

private struct ADMagnetStatus: Sendable {
    let id: Int?
    let filename: String?
    let size: Int64?
    let status: String?
    let statusCode: Int?
    let links: [ADLink]?
}
extension ADMagnetStatus: Decodable {}

private struct ADLink: Sendable {
    let link: String?
    let filename: String?
    let size: Int64?
}
extension ADLink: Decodable {}

private struct ADUnlockResponse: Sendable {
    let link: String?
    let filename: String?
    let filesize: Int64?
}
extension ADUnlockResponse: Decodable {}
