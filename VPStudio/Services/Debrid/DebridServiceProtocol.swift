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
    var isPremium: Bool?
}

protocol DebridServiceProtocol: Sendable {
    var serviceType: DebridServiceType { get }

    func validateToken() async throws -> Bool
    func getAccountInfo() async throws -> DebridAccountInfo
    func checkCache(hashes: [String]) async throws -> [String: CacheStatus]
    func addMagnet(hash: String) async throws -> String
    func selectFiles(torrentId: String, fileIds: [Int]) async throws
    func selectMatchingEpisodeFile(
        torrentId: String,
        seasonNumber: Int,
        episodeNumber: Int,
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?
    ) async throws -> Bool
    func cleanupRemoteTransfer(torrentId: String) async throws
    func getStreamURL(torrentId: String) async throws -> StreamInfo
    func unrestrict(link: String) async throws -> URL
}

extension DebridServiceProtocol {
    func selectMatchingEpisodeFile(
        torrentId: String,
        seasonNumber: Int,
        episodeNumber: Int,
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?
    ) async throws -> Bool {
        let _ = torrentId
        let _ = seasonNumber
        let _ = episodeNumber
        let _ = resolvedFileNameHint
        let _ = resolvedFileSizeHint
        return false
    }

    func cleanupRemoteTransfer(torrentId: String) async throws {
        let _ = torrentId
    }
}

enum DebridHashValidator {
    private static let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    static func normalizedInfoHash(_ hash: String) -> String? {
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 40 || trimmed.count == 64 else {
            return nil
        }

        guard trimmed.unicodeScalars.allSatisfy({ hexCharacters.contains($0) }) else {
            return nil
        }

        return trimmed.lowercased()
    }

    static func validatedInfoHash(_ hash: String) throws -> String {
        guard let normalized = normalizedInfoHash(hash) else {
            throw DebridError.invalidHash(hash)
        }
        return normalized
    }
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

enum DebridHTTPExecutor {
    private static let initialBackoffNanoseconds: UInt64 = 250_000_000
    private static let maximumBackoffNanoseconds: UInt64 = 5_000_000_000
    private static let maxAttempts = 4

    static func data(
        for request: URLRequest,
        session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        try await dataWithRetry(for: request, session: session, attempt: 0)
    }

    private static func dataWithRetry(
        for request: URLRequest,
        session: URLSession,
        attempt: Int
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DebridError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 429 else {
            return (data, httpResponse)
        }

        guard attempt < maxAttempts - 1 else {
            throw DebridError.rateLimited
        }

        let retryAfterNanoseconds = retryDelayNanoseconds(
            from: httpResponse.value(forHTTPHeaderField: "Retry-After"),
            attempt: attempt
        )
        try await Task.sleep(nanoseconds: retryAfterNanoseconds)
        return try await dataWithRetry(for: request, session: session, attempt: attempt + 1)
    }

    private static func retryDelayNanoseconds(from retryAfter: String?, attempt: Int) -> UInt64 {
        let exponentialDelay = min(
            maximumBackoffNanoseconds,
            initialBackoffNanoseconds * UInt64(1 << min(attempt, 5))
        )

        guard let retryAfter else {
            return exponentialDelay
        }

        let trimmed = retryAfter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let retryAfterSeconds = TimeInterval(trimmed), retryAfterSeconds > 0 else {
            return exponentialDelay
        }

        let retryAfterDelay = UInt64((retryAfterSeconds * 1_000_000_000).rounded())
        return min(maximumBackoffNanoseconds, max(exponentialDelay, retryAfterDelay))
    }
}
