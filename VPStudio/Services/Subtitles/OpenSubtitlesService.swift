import Foundation

/// OpenSubtitles.com REST API client
actor OpenSubtitlesService {
    private let apiKey: String
    private let baseURL = "https://api.opensubtitles.com/api/v1"
    private let session: URLSession
    private var authToken: String?

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
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
        return response.data.map { item in
            let attr = item.attributes
            let file = attr.files.first
            let fileName = file?.fileName ?? attr.release ?? "Unknown"
            return Subtitle(
                id: String(item.id),
                language: attr.language,
                fileName: fileName,
                url: "", // Need to call download endpoint
                format: SubtitleFormat.parse(from: fileName),
                fileId: file?.fileId,
                rating: attr.ratings,
                downloadCount: attr.downloadCount,
                isHearingImpaired: attr.hearingImpaired
            )
        }
    }

    func searchByHash(movieHash: String, movieSize: Int64) async throws -> [Subtitle] {
        let params: [String: String] = [
            "moviehash": movieHash,
            "moviebytesize": String(movieSize),
        ]
        let response: SubtitleSearchResponse = try await get(path: "/subtitles", params: params)
        return response.data.map { item in
            let attr = item.attributes
            let file = attr.files.first
            let fileName = file?.fileName ?? attr.release ?? "Unknown"
            return Subtitle(
                id: String(item.id),
                language: attr.language,
                fileName: fileName,
                url: "",
                format: SubtitleFormat.parse(from: fileName),
                fileId: file?.fileId,
                rating: attr.ratings,
                downloadCount: attr.downloadCount,
                isHearingImpaired: attr.hearingImpaired
            )
        }
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
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SubtitleError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw SubtitleError.decodingFailed
        }
        return content
    }

    func downloadFirstMatch(
        query: String,
        languages: [String] = ["en"]
    ) async throws -> Subtitle {
        let candidates = try await search(query: query, languages: languages)
        guard let selected = candidates.first(where: { $0.fileId != nil }),
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

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SubtitleError.httpError(0)
        }

        if http.statusCode == 401 {
            authToken = nil
            throw SubtitleError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw SubtitleError.httpError(http.statusCode)
        }
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

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SubtitleError.httpError(0)
        }

        if http.statusCode == 401 {
            authToken = nil
            throw SubtitleError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw SubtitleError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
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
        try content.write(to: url, atomically: true, encoding: .utf8)
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
