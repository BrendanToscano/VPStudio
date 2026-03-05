import Foundation

/// Represents a selectable file from a torrent with metadata for smart ranking
struct TorrentFile: Sendable, Identifiable {
    let id: Int  // File index in RD API (1-based)
    let path: String
    let sizeBytes: Int64
    
    var fileName: String {
        (path as NSString).lastPathComponent
    }
    
    var fileExtension: String {
        (path as NSString).pathExtension.lowercased()
    }
    
    var isVideoFile: Bool {
        Self.videoExtensions.contains(fileExtension)
    }
    
    var isSampleFile: Bool {
        let lowerPath = path.lowercased()
        return lowerPath.contains("sample") || lowerPath.contains("trailer") || 
               lowerPath.contains("bonus") || lowerPath.contains("extra")
    }
    
    /// Minimum valid video file size (500MB) - below this is likely a sample
    static let minimumValidVideoSize: Int64 = 500_000_000
    
    var isValidVideoSize: Bool {
        sizeBytes >= Self.minimumValidVideoSize
    }
    
    private static let videoExtensions: Set<String> = [
        "mkv", "mp4", "avi", "mov", "wmv", "flv", "webm", "m4v", "ts"
    ]
}

/// File selection strategy based on media type
enum FileSelectionStrategy: Sendable {
    case movie
    case episode(season: Int, episode: Int)
    case all
    
    /// Matches episode pattern in filename (S01E01, 1x01, etc.)
    func matches(episode: Int, season: Int, fileName: String) -> Bool {
        let lower = fileName.lowercased()
        
        // SxxExx pattern
        let sPattern = #"s(\d{1,2})[ex](\d{1,2})"#
        if let regex = try? NSRegularExpression(pattern: sPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            if let sRange = Range(match.range(at: 1), in: lower),
               let eRange = Range(match.range(at: 2), in: lower),
               let fileSeason = Int(lower[sRange]),
               let fileEpisode = Int(lower[eRange]) {
                return fileSeason == season && fileEpisode == episode
            }
        }
        
        // 1x01 pattern
        let xPattern = #"(\d{1,2})[x](\d{1,2})"#
        if let regex = try? NSRegularExpression(pattern: xPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            if let sRange = Range(match.range(at: 1), in: lower),
               let eRange = Range(match.range(at: 2), in: lower),
               let fileSeason = Int(lower[sRange]),
               let fileEpisode = Int(lower[eRange]) {
                return fileSeason == season && fileEpisode == episode
            }
        }
        
        return false
    }
}

actor RealDebridService: DebridServiceProtocol {
    let serviceType: DebridServiceType = .realDebrid
    private let apiToken: String
    private let baseURL = "https://api.real-debrid.com/rest/1.0"
    private let session: URLSession
    
    /// In-flight tasks map to deduplicate concurrent addMagnet calls for the same hash
    private var inFlightAddMagnetTasks: [String: Task<String, Error>] = [:]

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
            username: user.username,
            email: user.email,
            premiumExpiry: expiry,
            isPremium: user.type == "premium"
        )
    }

    /// Validates that a string looks like a hex info-hash (40 or 64 hex chars).
    /// Prevents path-traversal or URL corruption when hashes are embedded in URL paths.
    private static let hexHashPattern = try! NSRegularExpression(pattern: "^[0-9a-fA-F]{40,64}$")

    private static func isValidHexHash(_ hash: String) -> Bool {
        let range = NSRange(hash.startIndex..<hash.endIndex, in: hash)
        return hexHashPattern.firstMatch(in: hash, range: range) != nil
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
        // Deduplicate: if there's already an in-flight task for this hash, await it
        if let existingTask = inFlightAddMagnetTasks[hash.lowercased()] {
            return try await existingTask.value
        }
        
        // Create new task for this hash
        let task = Task<String, Error> {
            try await self.addMagnetInternal(hash: hash)
        }
        
        inFlightAddMagnetTasks[hash.lowercased()] = task
        
        do {
            let result = try await task.value
            inFlightAddMagnetTasks[hash.lowercased()] = nil
            return result
        } catch {
            inFlightAddMagnetTasks[hash.lowercased()] = nil
            throw error
        }
    }

    /// Internal implementation of addMagnet - called by the deduplicated wrapper
    private func addMagnetInternal(hash: String) async throws -> String {
        // Check if torrent already exists
        let existing: [RDTorrentInfo] = try await request(method: "GET", path: "/torrents?limit=2500")
        if let found = existing.first(where: { $0.hash?.lowercased() == hash.lowercased() }) {
            return found.id
        }

        let magnet = "magnet:?xt=urn:btih:\(hash)"
        let body = "magnet=\(magnet.addingPercentEncoding(withAllowedCharacters: Self.formEncodingAllowed) ?? magnet)"
        let response: RDAddMagnetResponse = try await request(method: "POST", path: "/torrents/addMagnet", body: body)
        return response.id
    }

    /// Fetches the list of files available in a torrent
    func getTorrentFiles(torrentId: String) async throws -> [TorrentFile] {
        let response: RDFilesResponse = try await request(method: "GET", path: "/torrents/files/\(torrentId)")
        
        return response.files.enumerated().map { index, file in
            TorrentFile(
                id: index + 1,  // RD uses 1-based indexing for file selection
                path: file.path ?? "",
                sizeBytes: Int64(file.size ?? 0)
            )
        }
    }

    /// Selects files using smart ranking based on media type
    /// - Parameters:
    ///   - torrentId: The torrent ID
    ///   - strategy: Movie, episode (with season/episode numbers), or all files
    /// - Returns: Array of selected file IDs
    func selectFilesSmart(torrentId: String, strategy: FileSelectionStrategy) async throws -> [Int] {
        let files = try await getTorrentFiles(torrentId: torrentId)
        
        // Filter to valid video files based on strategy
        let selectedFiles: [TorrentFile]
        
        switch strategy {
        case .all:
            // Select all valid video files (non-samples)
            selectedFiles = files.filter { $0.isVideoFile && !$0.isSampleFile }
            
        case .movie:
            // For movies: prefer largest valid video file, exclude samples
            let validVideos = files.filter { $0.isVideoFile && !$0.isSampleFile && $0.isValidVideoSize }
            if validVideos.isEmpty {
                // Fallback: include smaller files if no valid size found
                selectedFiles = files.filter { $0.isVideoFile && !$0.isSampleFile }
            } else {
                // Sort by size descending and pick the largest
                selectedFiles = validVideos.sorted { $0.sizeBytes > $1.sizeBytes }
            }
            
        case .episode(let season, let episode):
            // For episodes: try to find matching SxxExx pattern first
            let matchingFiles = files.filter { file in
                file.isVideoFile && 
                !file.isSampleFile &&
                strategy.matches(episode: episode, season: season, fileName: file.fileName)
            }
            
            if !matchingFiles.isEmpty {
                // Found matching episode - pick largest valid one
                let validMatching = matchingFiles.filter { $0.isValidVideoSize }
                if validMatching.isEmpty {
                    selectedFiles = matchingFiles.sorted { $0.sizeBytes > $1.sizeBytes }
                } else {
                    selectedFiles = validMatching.sorted { $0.sizeBytes > $1.sizeBytes }
                }
            } else {
                // No exact match - fallback to largest valid video file
                let validVideos = files.filter { $0.isVideoFile && !$0.isSampleFile && $0.isValidVideoSize }
                if validVideos.isEmpty {
                    selectedFiles = files.filter { $0.isVideoFile && !$0.isSampleFile }
                } else {
                    selectedFiles = validVideos.sorted { $0.sizeBytes > $1.sizeBytes }
                }
            }
        }
        
        // Return just the file IDs (take top 3 to handle multi-part releases)
        return Array(selectedFiles.prefix(3).map(\.id))
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
        guard let url = URL(string: response.download) else {
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
    let username: String
    let email: String
    let type: String
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
    let id: String
    let filename: String?
    let hash: String?
    let bytes: Int64?
    let status: String?
    let links: [String]?
}
extension RDTorrentInfo: Decodable {}

private struct RDUnrestrictResponse: Sendable {
    let id: String
    let filename: String
    let download: String
    let filesize: Int64?
}
extension RDUnrestrictResponse: Decodable {}

/// Response model for torrent files endpoint
private struct RDFilesResponse: Sendable {
    let files: [RDFile]
}

private struct RDFile: Sendable {
    let path: String?
    let size: Int64?
}
extension RDFile: Decodable {}
extension RDFilesResponse: Decodable {}

private struct EmptyResponse: Sendable {}
extension EmptyResponse: Decodable {}
