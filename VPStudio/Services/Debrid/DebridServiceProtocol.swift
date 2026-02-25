import Foundation

enum CacheStatus: Sendable, Equatable {
    case cached(fileId: String?, fileName: String?, fileSize: Int64?)
    case notCached
    case unknown
}

struct DebridAccountInfo: Sendable {
    var username: String
    var email: String?
    var premiumExpiry: Date?
    var isPremium: Bool
}

protocol DebridServiceProtocol: Sendable {
    var serviceType: DebridServiceType { get }

    func validateToken() async throws -> Bool
    func getAccountInfo() async throws -> DebridAccountInfo
    func checkCache(hashes: [String]) async throws -> [String: CacheStatus]
    func addMagnet(hash: String) async throws -> String
    func selectFiles(torrentId: String, fileIds: [Int]) async throws
    func getStreamURL(torrentId: String) async throws -> StreamInfo
    func unrestrict(link: String) async throws -> URL
}

enum DebridError: LocalizedError, Equatable {
    case unauthorized
    case notPremium
    case invalidHash(String)
    case torrentNotFound(String)
    case fileNotReady(String)
    case rateLimited
    case httpError(Int, String)
    case networkError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Invalid or expired API token"
        case .notPremium: return "Premium account required"
        case .invalidHash(let hash): return "Invalid torrent hash: \(hash)"
        case .torrentNotFound(let id): return "Torrent not found: \(id)"
        case .fileNotReady(let msg): return "File not ready: \(msg)"
        case .rateLimited: return "Rate limited. Try again shortly."
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .timeout: return "Request timed out"
        }
    }
}
