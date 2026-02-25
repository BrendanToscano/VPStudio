import Foundation

actor EasyNewsService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .easyNews
    private let apiToken: String
    private let baseURL = "https://members.easynews.com"
    private let session: URLSession

    init(apiToken: String, session: URLSession = .shared) {
        self.apiToken = apiToken
        self.session = session
    }

    func validateToken() async throws -> Bool {
        guard let url = URL(string: baseURL) else {
            throw DebridError.networkError("Invalid base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue("Basic \(apiToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DebridError.networkError("Invalid response")
        }

        switch http.statusCode {
        case 200 ... 299:
            return true
        case 401, 403:
            return false
        default:
            throw DebridError.httpError(http.statusCode, "EasyNews validation failed")
        }
    }

    func getAccountInfo() async throws -> DebridAccountInfo {
        DebridAccountInfo(username: "EasyNews User", email: nil, premiumExpiry: nil, isPremium: true)
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        // EasyNews is Usenet-based, no torrent cache checking
        hashes.reduce(into: [:]) { $0[$1.lowercased()] = .unknown }
    }

    func addMagnet(hash: String) async throws -> String {
        // EasyNews doesn't use magnets — this service works differently
        // Search is done by filename/query against Usenet
        throw DebridError.networkError("EasyNews uses Usenet search, not magnet links")
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {}

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        throw DebridError.fileNotReady("EasyNews stream resolution requires search-based flow")
    }

    func unrestrict(link: String) async throws -> URL {
        guard let url = URL(string: link) else { throw DebridError.networkError("Invalid URL") }
        return url
    }
}
