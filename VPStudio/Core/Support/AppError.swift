import Foundation

enum NetworkError: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case unauthorized
    case notFound(String)
    case rateLimited
    case timeout
    case offline
    case invalidResponse
    case server(statusCode: Int, message: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .unauthorized:
            return "Unauthorized request."
        case .notFound(let resource):
            return "Not found: \(resource)"
        case .rateLimited:
            return "Request was rate limited."
        case .timeout:
            return "Request timed out."
        case .offline:
            return "No internet connection."
        case .invalidResponse:
            return "Received an invalid response."
        case .server(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .transport(let message):
            return "Network error: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Review service endpoints and API configuration in Settings."
        case .unauthorized:
            return "Verify your API key or token in Settings and try again."
        case .notFound:
            return "Refresh metadata or try a different title."
        case .rateLimited:
            return "Wait briefly, then retry."
        case .timeout, .offline, .transport:
            return "Check your connection and retry."
        case .invalidResponse, .server:
            return "Retry in a moment. If this persists, verify provider settings."
        }
    }
}

enum IndexerError: LocalizedError, Equatable, Sendable {
    case allIndexersFailed(String)
    case queryFailed(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .allIndexersFailed(let details):
            return "All indexers failed: \(details)"
        case .queryFailed(let details):
            return "Torrent search failed: \(details)"
        case .notConfigured:
            return "No active indexers are configured."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .allIndexersFailed, .notConfigured:
            return "Check indexer URLs, API keys, and activation status in Settings > Indexers."
        case .queryFailed:
            return "Try a broader query or run the search again."
        }
    }
}

enum PlayerError: LocalizedError, Equatable, Sendable {
    case invalidStreamURL(String)
    case startupTimeout(PlayerEngineKind)
    case initializationFailed(PlayerEngineKind, String)
    case unsupportedFormat(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidStreamURL(let value):
            return "Invalid stream URL: \(value)"
        case .startupTimeout(let engine):
            return "\(engine.displayName) timed out before playback started."
        case .initializationFailed(let engine, let message):
            return "\(engine.displayName) failed: \(message)"
        case .unsupportedFormat(let message):
            return "Unsupported media format: \(message)"
        case .playbackFailed(let message):
            return "Playback failed: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidStreamURL:
            return "Choose a different stream and retry playback."
        case .startupTimeout, .initializationFailed:
            return "Try a different player engine in Settings > Playback."
        case .unsupportedFormat:
            return "Try another release or a different quality/HDR format."
        case .playbackFailed:
            return "Retry playback, or switch to another stream."
        }
    }
}

enum AppError: LocalizedError, Equatable, Sendable {
    case network(NetworkError)
    case debrid(DebridError)
    case indexer(IndexerError)
    case player(PlayerError)
    case unknown(String)

    init(_ error: Error, fallback: AppError? = nil) {
        if let mapped = Self.map(error) {
            self = mapped
            return
        }

        if let fallback {
            self = fallback
            return
        }

        self = .unknown((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    var errorDescription: String? {
        switch self {
        case .network(let error):
            return error.errorDescription
        case .debrid(let error):
            return error.errorDescription
        case .indexer(let error):
            return error.errorDescription
        case .player(let error):
            return error.errorDescription
        case .unknown(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .network(let error):
            return error.recoverySuggestion
        case .debrid(let error):
            return Self.debridRecoverySuggestion(for: error)
        case .indexer(let error):
            return error.recoverySuggestion
        case .player(let error):
            return error.recoverySuggestion
        case .unknown:
            return "Try again. If the issue continues, review app configuration."
        }
    }

    private static func map(_ error: Error) -> AppError? {
        if let appError = error as? AppError {
            return appError
        }
        if let debridError = error as? DebridError {
            return .debrid(debridError)
        }
        if let indexerError = error as? IndexerManagerError {
            return .indexer(IndexerError(indexerError))
        }
        if let playerError = error as? PlayerEngineError {
            return .player(PlayerError(playerError))
        }
        if let networkError = error as? URLError {
            return .network(NetworkError(networkError))
        }
        if let tmdbError = error as? TMDBError {
            return .network(NetworkError(tmdbError))
        }
        if error is DecodingError {
            return .network(.invalidResponse)
        }
        return nil
    }

    private static func debridRecoverySuggestion(for error: DebridError) -> String {
        switch error {
        case .unauthorized:
            return "Reconnect your debrid account token in Settings > Debrid Services."
        case .notPremium:
            return "Use a premium debrid account or switch to another active provider."
        case .invalidHash:
            return "Pick another torrent result and retry stream resolution."
        case .torrentNotFound:
            return "Try a different cached source or run a new search."
        case .fileNotReady:
            return "The file is still processing. Retry shortly."
        case .rateLimited:
            return "Wait briefly, then retry."
        case .httpError:
            return "Verify debrid service availability and API token settings."
        case .networkError, .timeout:
            return "Check connectivity and retry stream resolution."
        }
    }
}

private extension NetworkError {
    init(_ error: URLError) {
        switch error.code {
        case .timedOut:
            self = .timeout
        case .notConnectedToInternet, .networkConnectionLost:
            self = .offline
        case .unsupportedURL, .badURL:
            let failingURL = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
                ?? "unknown"
            self = .invalidURL(failingURL)
        default:
            self = .transport(error.localizedDescription)
        }
    }

    init(_ error: TMDBError) {
        switch error {
        case .invalidURL(let path):
            self = .invalidURL(path)
        case .invalidResponse:
            self = .invalidResponse
        case .unauthorized:
            self = .unauthorized
        case .notFound(let id):
            self = .notFound(id)
        case .rateLimited:
            self = .rateLimited
        case .httpError(let statusCode, let message):
            switch statusCode {
            case 401:
                self = .unauthorized
            case 404:
                self = .notFound(message)
            case 429:
                self = .rateLimited
            default:
                self = .server(statusCode: statusCode, message: message)
            }
        }
    }
}

private extension IndexerError {
    init(_ error: IndexerManagerError) {
        switch error {
        case .allIndexersFailed(let details):
            self = .allIndexersFailed(details)
        }
    }
}

private extension PlayerError {
    init(_ error: PlayerEngineError) {
        switch error {
        case .invalidStreamURL(let value):
            self = .invalidStreamURL(value)
        case .startupTimeout(let engine):
            self = .startupTimeout(engine)
        case .initializationFailed(let engine, let message):
            self = .initializationFailed(engine, message)
        }
    }
}
