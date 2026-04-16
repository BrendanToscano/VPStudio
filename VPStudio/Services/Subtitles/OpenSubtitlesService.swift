import Foundation

/// OpenSubtitles.com REST API client
actor OpenSubtitlesService {
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    private let apiKey: String
    private let baseURL = "https://api.opensubtitles.com/api/v1"
    private let session: URLSession
    private var authToken: String?
    private var lastRequestDate: Date?
    private var nextAllowedRequestDate: Date?
    private let minimumRequestInterval: TimeInterval = 0.15

    init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        self.session = session ?? Self.defaultSession
    }

    // MARK: - Authentication

    func login(username: String, password: String) async throws -> String {
        let body: [String: String] = ["username": username, "password": password]
        let response: LoginResponse = try await post(path: "/login", body: body)
        authToken = response.token
        return response.token
    }

    // MARK: - Search

    func search(imdbId: String? = nil, tmdbId: Int? = nil, query: String? = nil,
                season: Int? = nil, episode: Int? = nil, languages: [String] = ["en"]) async throws -> [Subtitle] {
        var params: [String: String] = [
            "languages": languages.joined(separator: ","),
        ]
        if let imdbId { params["imdb_id"] = imdbId.replacingOccurrences(of: "tt", with: "") }
        if let tmdbId { params["tmdb_id"] = String(tmdbId) }
        if let query { params["query"] = query }
        if let season { params["season_number"] = String(season) }
        if let episode { params["episode_number"] = String(episode) }

        let response: SubtitleSearchResponse = try await get(path: "/subtitles", params: params)
        return response.data.compactMap { usableSubtitle(from: $0) }
    }

    func searchByHash(movieHash: String, movieSize: Int64) async throws -> [Subtitle] {
        let params: [String: String] = [
            "moviehash": movieHash,
            "moviebytesize": String(movieSize),
        ]
        let response: SubtitleSearchResponse = try await get(path: "/subtitles", params: params)
        return response.data.compactMap { usableSubtitle(from: $0) }
    }

    // MARK: - Download

    func getDownloadURL(fileId: Int) async throws -> URL {
        let body: [String: Any] = ["file_id": fileId]
        let response: DownloadResponse = try await post(path: "/download", body: body)
        guard let url = URL(string: response.link) else {
            throw SubtitleError.invalidDownloadURL
        }
        return url
    }

    func downloadSubtitle(fileId: Int) async throws -> String {
        let url = try await getDownloadURL(fileId: fileId)
        let request = URLRequest(url: url)
        let (data, _) = try await sendRequest(request)
        guard let content = decodeSubtitleContent(from: data) else {
            throw SubtitleError.decodingFailed
        }
        return content
    }

    func downloadFirstMatch(
        query: String,
        languages: [String] = ["en"]
    ) async throws -> Subtitle {
        let candidates = try await search(query: query, languages: languages)
        guard let selected = candidates.first(where: { $0.fileId != nil && $0.isSupportedSubtitle }),
              let fileId = selected.fileId else {
            throw SubtitleError.noSubtitlesFound
        }

        let content = try await downloadSubtitle(fileId: fileId)
        let fileURL = try writeTemporarySubtitleFile(
            content: content,
            fileName: selected.fileName,
            format: selected.format
        )

        var hydrated = selected
        hydrated.url = fileURL.absoluteString
        return hydrated
    }

    // MARK: - Networking

    private func get<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw SubtitleError.invalidURL
        }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else { throw SubtitleError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("VPStudio v1.0", forHTTPHeaderField: "User-Agent")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await sendRequest(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(path: String, body: Any) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw SubtitleError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("VPStudio v1.0", forHTTPHeaderField: "User-Agent")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await sendRequest(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            try await waitForRequestSlot()

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SubtitleError.httpError(0)
            }

            switch http.statusCode {
            case 200...299:
                lastRequestDate = Date()
                return (data, http)
            case 401:
                authToken = nil
                throw SubtitleError.unauthorized
            case 429:
                let delay = retryAfterDelay(from: http) ?? minimumRequestInterval
                nextAllowedRequestDate = Date().addingTimeInterval(max(delay, minimumRequestInterval))
                if attempt < 2 {
                    continue
                }
                throw SubtitleError.httpError(429)
            default:
                throw SubtitleError.httpError(http.statusCode)
            }
        }
    }

    private func waitForRequestSlot() async throws {
        let now = Date()
        let earliestAllowed = max(
            nextAllowedRequestDate ?? now,
            lastRequestDate?.addingTimeInterval(minimumRequestInterval) ?? now
        )
        let delay = earliestAllowed.timeIntervalSince(now)
        if delay > 0 {
            try await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
        }
    }

    private func retryAfterDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return Double(value).map { max($0, 0) }
    }

    private func usableSubtitle(from item: SubtitleItem) -> Subtitle? {
        let attr = item.attributes
        let supportedFile = attr.files.first(where: { SubtitleFormat.parse(from: $0.fileName).isSupportedSubtitle })
        let file = supportedFile ?? attr.files.first
        let fileName = file?.fileName ?? attr.release ?? "Unknown"
        let format = file.map { SubtitleFormat.parse(from: $0.fileName) } ?? SubtitleFormat.parse(from: fileName)
        guard format.isSupportedSubtitle else { return nil }

        return Subtitle(
            id: String(item.id),
            language: attr.language,
            fileName: fileName,
            url: "",
            format: format,
            fileId: file?.fileId,
            rating: attr.ratings,
            downloadCount: attr.downloadCount,
            isHearingImpaired: attr.hearingImpaired
        )
    }

    private func decodeSubtitleContent(from data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1]
        for encoding in encodings {
            if encoding == .isoLatin1 && !isLikelyTextSubtitleData(data) {
                continue
            }
            if let content = String(data: data, encoding: encoding) {
                return content.trimmingLeadingBOM()
            }
        }
        return nil
    }

    private func isLikelyTextSubtitleData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        var controlCount = 0
        for byte in data {
            if byte == 0 { return false }
            if byte < 0x20, byte != 0x09, byte != 0x0A, byte != 0x0D {
                controlCount += 1
            }
        }
        return Double(controlCount) / Double(data.count) < 0.05
    }

    private func writeTemporarySubtitleFile(
        content: String,
        fileName: String,
        format: SubtitleFormat
    ) throws -> URL {
        let resolved = format == .unknown ? SubtitleFormat.parse(from: fileName) : format
        let extensionForFile = resolved == .unknown ? "srt" : resolved.rawValue

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(extensionForFile)
        try content.trimmingLeadingBOM().write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Response Models

private struct LoginResponse: Sendable {
    let token: String
}
extension LoginResponse: Decodable {}

private struct SubtitleSearchResponse: Sendable {
    let data: [SubtitleItem]
}
extension SubtitleSearchResponse: Decodable {}

private struct SubtitleItem: Sendable {
    let id: Int
    let attributes: SubtitleAttributes
}
extension SubtitleItem: Decodable {}

private struct SubtitleAttributes: Sendable {
    let language: String
    let release: String?
    let ratings: Double
    let downloadCount: Int
    let hearingImpaired: Bool
    let files: [SubtitleFile]

    enum CodingKeys: String, CodingKey {
        case language, release, ratings, files
        case downloadCount = "download_count"
        case hearingImpaired = "hearing_impaired"
    }
}
extension SubtitleAttributes: Decodable {}

private struct SubtitleFile: Sendable {
    let fileId: Int
    let fileName: String

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case fileName = "file_name"
    }
}
extension SubtitleFile: Decodable {}

private struct DownloadResponse: Sendable {
    let link: String
}
extension DownloadResponse: Decodable {}

// MARK: - Errors

enum SubtitleError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case unauthorized
    case decodingFailed
    case invalidDownloadURL
    case noSubtitlesFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid subtitle API URL"
        case .httpError(let code): return "Subtitle API error: HTTP \(code)"
        case .unauthorized: return "OpenSubtitles authorization expired"
        case .decodingFailed: return "Failed to decode subtitle content"
        case .invalidDownloadURL: return "Invalid subtitle download URL"
        case .noSubtitlesFound: return "No subtitles found"
        }
    }
}

private extension String {
    func trimmingLeadingBOM() -> String {
        guard let first = unicodeScalars.first,
              first == UnicodeScalar(0xFEFF) else {
            return self
        }
        return String(dropFirst())
    }
}

private extension OpenSubtitlesService {
    static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(interval, 0) * 1_000_000_000)
    }
}
