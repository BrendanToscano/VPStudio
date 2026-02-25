import Foundation
import Testing
@testable import VPStudio

// MARK: - AppError Initialization Mapping

@Suite("AppError - Initialization Mapping")
struct AppErrorInitMappingTests {

    @Test func appErrorPassesThroughUnchanged() {
        let original = AppError.unknown("original")
        let mapped = AppError(original)
        #expect(mapped == original)
    }

    @Test func debridErrorMappedToDebridCase() {
        let debrid = DebridError.unauthorized
        let mapped = AppError(debrid)
        #expect(mapped == .debrid(.unauthorized))
    }

    @Test func debridErrorInvalidHashMapped() {
        let debrid = DebridError.invalidHash("abc123")
        let mapped = AppError(debrid)
        #expect(mapped == .debrid(.invalidHash("abc123")))
    }

    @Test func indexerManagerErrorMapped() {
        let indexerErr = IndexerManagerError.allIndexersFailed("no results")
        let mapped = AppError(indexerErr)
        #expect(mapped == .indexer(.allIndexersFailed("no results")))
    }

    @Test func playerEngineErrorInvalidURLMapped() {
        let playerErr = PlayerEngineError.invalidStreamURL("bad://url")
        let mapped = AppError(playerErr)
        #expect(mapped == .player(.invalidStreamURL("bad://url")))
    }

    @Test func playerEngineErrorStartupTimeoutMapped() {
        let playerErr = PlayerEngineError.startupTimeout(.avPlayer)
        let mapped = AppError(playerErr)
        #expect(mapped == .player(.startupTimeout(.avPlayer)))
    }

    @Test func playerEngineErrorInitializationFailedMapped() {
        let playerErr = PlayerEngineError.initializationFailed(.ksPlayer, "failed to init")
        let mapped = AppError(playerErr)
        #expect(mapped == .player(.initializationFailed(.ksPlayer, "failed to init")))
    }

    @Test func urlErrorTimedOutMapped() {
        let urlErr = URLError(.timedOut)
        let mapped = AppError(urlErr)
        #expect(mapped == .network(.timeout))
    }

    @Test func urlErrorNotConnectedMapped() {
        let urlErr = URLError(.notConnectedToInternet)
        let mapped = AppError(urlErr)
        #expect(mapped == .network(.offline))
    }

    @Test func urlErrorNetworkConnectionLostMapped() {
        let urlErr = URLError(.networkConnectionLost)
        let mapped = AppError(urlErr)
        #expect(mapped == .network(.offline))
    }

    @Test func urlErrorOtherCodeMappedToTransport() {
        let urlErr = URLError(.cannotConnectToHost)
        let mapped = AppError(urlErr)
        if case .network(.transport) = mapped { } else {
            Issue.record("Expected .network(.transport), got \(mapped)")
        }
    }

    @Test func decodingErrorMappedToNetworkInvalidResponse() {
        struct Dummy: Decodable {}
        let decodingErr = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "test"))
        let mapped = AppError(decodingErr)
        #expect(mapped == .network(.invalidResponse))
    }

    @Test func tmdbErrorUnauthorizedMapped() {
        let tmdbErr = TMDBError.unauthorized
        let mapped = AppError(tmdbErr)
        #expect(mapped == .network(.unauthorized))
    }

    @Test func tmdbErrorNotFoundMapped() {
        let tmdbErr = TMDBError.notFound("tt9999")
        let mapped = AppError(tmdbErr)
        #expect(mapped == .network(.notFound("tt9999")))
    }

    @Test func tmdbErrorRateLimitedMapped() {
        let tmdbErr = TMDBError.rateLimited
        let mapped = AppError(tmdbErr)
        #expect(mapped == .network(.rateLimited))
    }

    @Test func tmdbErrorHttpError401MappedToUnauthorized() {
        let tmdbErr = TMDBError.httpError(401, "Unauthorized")
        let mapped = AppError(tmdbErr)
        #expect(mapped == .network(.unauthorized))
    }

    @Test func tmdbErrorHttpError404MappedToNotFound() {
        let tmdbErr = TMDBError.httpError(404, "Not Found")
        let mapped = AppError(tmdbErr)
        #expect(mapped == .network(.notFound("Not Found")))
    }

    @Test func tmdbErrorHttpError429MappedToRateLimited() {
        let tmdbErr = TMDBError.httpError(429, "Too Many Requests")
        let mapped = AppError(tmdbErr)
        #expect(mapped == .network(.rateLimited))
    }

    @Test func tmdbErrorHttpErrorOtherMappedToServer() {
        let tmdbErr = TMDBError.httpError(500, "Internal Server Error")
        let mapped = AppError(tmdbErr)
        #expect(mapped == .network(.server(statusCode: 500, message: "Internal Server Error")))
    }

    @Test func unknownErrorWithFallbackUsesFallback() {
        struct Mystery: Error, LocalizedError {
            var errorDescription: String? { nil }
        }
        let fallback = AppError.unknown("custom fallback")
        let mapped = AppError(Mystery(), fallback: fallback)
        #expect(mapped == fallback)
    }

    @Test func unknownErrorWithoutFallbackUsesLocalizedDescription() {
        struct Mystery: Error {}
        let mapped = AppError(Mystery())
        if case .unknown = mapped { } else {
            Issue.record("Expected .unknown, got \(mapped)")
        }
    }

    @Test func unknownErrorWithLocalizedErrorDescription() {
        struct Named: LocalizedError {
            var errorDescription: String? { "named error" }
        }
        let mapped = AppError(Named())
        #expect(mapped == .unknown("named error"))
    }
}

// MARK: - NetworkError Descriptions and Suggestions

@Suite("NetworkError - Descriptions")
struct NetworkErrorDescriptionTests {

    @Test func invalidURLDescription() {
        let err = NetworkError.invalidURL("bad://url")
        #expect(err.errorDescription?.contains("bad://url") == true)
    }

    @Test func unauthorizedDescription() {
        let err = NetworkError.unauthorized
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func notFoundDescription() {
        let err = NetworkError.notFound("resource-123")
        #expect(err.errorDescription?.contains("resource-123") == true)
    }

    @Test func rateLimitedDescription() {
        let err = NetworkError.rateLimited
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func timeoutDescription() {
        let err = NetworkError.timeout
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func offlineDescription() {
        let err = NetworkError.offline
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func invalidResponseDescription() {
        let err = NetworkError.invalidResponse
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func serverDescription() {
        let err = NetworkError.server(statusCode: 503, message: "Service Unavailable")
        #expect(err.errorDescription?.contains("503") == true)
    }

    @Test func transportDescription() {
        let err = NetworkError.transport("SSL error")
        #expect(err.errorDescription?.contains("SSL error") == true)
    }
}

// MARK: - IndexerError Descriptions and Suggestions

@Suite("IndexerError - Descriptions")
struct IndexerErrorDescriptionTests {

    @Test func allIndexersFailedDescription() {
        let err = IndexerError.allIndexersFailed("timeout on all")
        #expect(err.errorDescription?.contains("timeout on all") == true)
    }

    @Test func queryFailedDescription() {
        let err = IndexerError.queryFailed("bad query")
        #expect(err.errorDescription?.contains("bad query") == true)
    }

    @Test func notConfiguredDescription() {
        let err = IndexerError.notConfigured
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func allIndexersFailedRecoverySuggestion() {
        let err = IndexerError.allIndexersFailed("x")
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func notConfiguredRecoverySuggestion() {
        let err = IndexerError.notConfigured
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func queryFailedRecoverySuggestion() {
        let err = IndexerError.queryFailed("x")
        #expect(err.recoverySuggestion?.isEmpty == false)
    }
}

// MARK: - PlayerError Descriptions and Suggestions

@Suite("PlayerError - Descriptions")
struct PlayerErrorDescriptionTests {

    @Test func invalidStreamURLDescription() {
        let err = PlayerError.invalidStreamURL("bad://url")
        #expect(err.errorDescription?.contains("bad://url") == true)
    }

    @Test func startupTimeoutDescriptionContainsEngineName() {
        let err = PlayerError.startupTimeout(.avPlayer)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func initializationFailedDescriptionContainsEngineName() {
        let err = PlayerError.initializationFailed(.ksPlayer, "HEVC error")
        #expect(err.errorDescription?.contains("HEVC error") == true)
    }

    @Test func unsupportedFormatDescription() {
        let err = PlayerError.unsupportedFormat("AV1")
        #expect(err.errorDescription?.contains("AV1") == true)
    }

    @Test func playbackFailedDescription() {
        let err = PlayerError.playbackFailed("stall")
        #expect(err.errorDescription?.contains("stall") == true)
    }

    @Test func allCasesHaveRecoverySuggestion() {
        let cases: [PlayerError] = [
            .invalidStreamURL("x"),
            .startupTimeout(.avPlayer),
            .initializationFailed(.ksPlayer, "x"),
            .unsupportedFormat("x"),
            .playbackFailed("x"),
        ]
        for err in cases {
            #expect(err.recoverySuggestion?.isEmpty == false, "Missing suggestion for \(err)")
        }
    }
}

// MARK: - AppError Recovery Suggestions (Debrid)

@Suite("AppError - Debrid Recovery Suggestions")
struct AppErrorDebridRecoverySuggestionsTests {

    @Test func unauthorizedHasSuggestion() {
        let err = AppError.debrid(.unauthorized)
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func notPremiumHasSuggestion() {
        let err = AppError.debrid(.notPremium)
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func invalidHashHasSuggestion() {
        let err = AppError.debrid(.invalidHash("abc"))
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func torrentNotFoundHasSuggestion() {
        let err = AppError.debrid(.torrentNotFound("id"))
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func fileNotReadyHasSuggestion() {
        let err = AppError.debrid(.fileNotReady("processing"))
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func rateLimitedHasSuggestion() {
        let err = AppError.debrid(.rateLimited)
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func httpErrorHasSuggestion() {
        let err = AppError.debrid(.httpError(503, "Service Unavailable"))
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func networkErrorHasSuggestion() {
        let err = AppError.debrid(.networkError("timeout"))
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func timeoutHasSuggestion() {
        let err = AppError.debrid(.timeout)
        #expect(err.recoverySuggestion?.isEmpty == false)
    }
}

// MARK: - AppError unknown recovery suggestion

@Suite("AppError - Unknown Recovery Suggestion")
struct AppErrorUnknownTests {

    @Test func unknownHasRecoverySuggestion() {
        let err = AppError.unknown("something went wrong")
        #expect(err.recoverySuggestion?.isEmpty == false)
    }

    @Test func unknownErrorDescriptionIsMessage() {
        let err = AppError.unknown("custom message")
        #expect(err.errorDescription == "custom message")
    }
}
