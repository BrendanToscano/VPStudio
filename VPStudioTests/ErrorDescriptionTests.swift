import Foundation
import Testing
@testable import VPStudio

// MARK: - AIError Description Tests

@Suite("AIError - Descriptions")
struct AIErrorDescriptionTests {

    @Test func noProviderConfiguredHasDescription() {
        let err = AIError.noProviderConfigured
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func invalidResponseHasDescription() {
        let err = AIError.invalidResponse
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func httpErrorIncludesCodeAndMessage() {
        let err = AIError.httpError(429, "Too Many Requests")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("429") == true)
        #expect(desc?.contains("Too Many Requests") == true)
    }

    @Test func rateLimitedHasDescription() {
        let err = AIError.rateLimited
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func allCasesHaveNonNilDescriptions() {
        let cases: [AIError] = [
            .noProviderConfigured,
            .invalidResponse,
            .httpError(500, "Server Error"),
            .rateLimited,
        ]
        for err in cases {
            #expect(err.errorDescription != nil, "Missing description for \(err)")
        }
    }
}

// MARK: - DebridError Description Tests

@Suite("DebridError - Descriptions")
struct DebridErrorDescriptionTests {

    @Test func unauthorizedHasDescription() {
        let err = DebridError.unauthorized
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func notPremiumHasDescription() {
        let err = DebridError.notPremium
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func invalidHashIncludesHash() {
        let err = DebridError.invalidHash("abc123def456")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("abc123def456") == true)
    }

    @Test func torrentNotFoundIncludesId() {
        let err = DebridError.torrentNotFound("torrent-789")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("torrent-789") == true)
    }

    @Test func fileNotReadyIncludesMessage() {
        let err = DebridError.fileNotReady("still processing")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("still processing") == true)
    }

    @Test func rateLimitedHasDescription() {
        let err = DebridError.rateLimited
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func httpErrorIncludesCodeAndMessage() {
        let err = DebridError.httpError(503, "Service Unavailable")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("503") == true)
        #expect(desc?.contains("Service Unavailable") == true)
    }

    @Test func networkErrorIncludesMessage() {
        let err = DebridError.networkError("connection reset")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("connection reset") == true)
    }

    @Test func timeoutHasDescription() {
        let err = DebridError.timeout
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func allCasesHaveNonNilDescriptions() {
        let cases: [DebridError] = [
            .unauthorized,
            .notPremium,
            .invalidHash("hash"),
            .torrentNotFound("id"),
            .fileNotReady("msg"),
            .rateLimited,
            .httpError(400, "Bad Request"),
            .networkError("err"),
            .timeout,
        ]
        for err in cases {
            #expect(err.errorDescription != nil, "Missing description for \(err)")
        }
    }
}

// MARK: - TraktError Description Tests

@Suite("TraktError - Descriptions")
struct TraktErrorDescriptionTests {

    @Test func invalidURLHasDescription() {
        let err = TraktError.invalidURL
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func httpErrorIncludesCode() {
        let err = TraktError.httpError(500)
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("500") == true)
    }

    @Test func unauthorizedHasDescription() {
        let err = TraktError.unauthorized
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func notConnectedHasDescription() {
        let err = TraktError.notConnected
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func allCasesHaveNonNilDescriptions() {
        let cases: [TraktError] = [
            .invalidURL,
            .httpError(401),
            .unauthorized,
            .notConnected,
        ]
        for err in cases {
            #expect(err.errorDescription != nil, "Missing description for \(err)")
        }
    }
}

// MARK: - SubtitleError Description Tests

@Suite("SubtitleError - Descriptions")
struct SubtitleErrorDescriptionTests {

    @Test func invalidURLHasDescription() {
        let err = SubtitleError.invalidURL
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func httpErrorIncludesCode() {
        let err = SubtitleError.httpError(403)
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("403") == true)
    }

    @Test func unauthorizedHasDescription() {
        let err = SubtitleError.unauthorized
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func decodingFailedHasDescription() {
        let err = SubtitleError.decodingFailed
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func invalidDownloadURLHasDescription() {
        let err = SubtitleError.invalidDownloadURL
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func noSubtitlesFoundHasDescription() {
        let err = SubtitleError.noSubtitlesFound
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func allCasesHaveNonNilDescriptions() {
        let cases: [SubtitleError] = [
            .invalidURL,
            .httpError(500),
            .unauthorized,
            .decodingFailed,
            .invalidDownloadURL,
            .noSubtitlesFound,
        ]
        for err in cases {
            #expect(err.errorDescription != nil, "Missing description for \(err)")
        }
    }
}

// MARK: - SecretStoreError Description Tests

@Suite("SecretStoreError - Descriptions")
struct SecretStoreErrorDescriptionTests {

    @Test func unexpectedStatusIncludesStatusAndOperation() {
        let err = SecretStoreError.unexpectedStatus(-25300, operation: "read")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("-25300") == true)
        #expect(desc?.contains("read") == true)
    }

    @Test func invalidSecretDataHasDescription() {
        let err = SecretStoreError.invalidSecretData
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test func allCasesHaveNonNilDescriptions() {
        let cases: [SecretStoreError] = [
            .unexpectedStatus(0, operation: "add"),
            .invalidSecretData,
        ]
        for err in cases {
            #expect(err.errorDescription != nil, "Missing description for \(err)")
        }
    }

    @Test func differentOperationsAppearInDescription() {
        let operations = ["add", "update", "delete", "read", "deleteAll"]
        for op in operations {
            let err = SecretStoreError.unexpectedStatus(-1, operation: op)
            #expect(err.errorDescription?.contains(op) == true, "Operation '\(op)' missing from description")
        }
    }
}

// MARK: - PlayerEngineError Description Tests

@Suite("PlayerEngineError - Descriptions")
struct PlayerEngineErrorDescriptionTests {

    @Test func invalidStreamURLIncludesValue() {
        let err = PlayerEngineError.invalidStreamURL("not://valid")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("not://valid") == true)
    }

    @Test func startupTimeoutIncludesEngineName() {
        let ksErr = PlayerEngineError.startupTimeout(.ksPlayer)
        #expect(ksErr.errorDescription?.contains("KSPlayer") == true)

        let avErr = PlayerEngineError.startupTimeout(.avPlayer)
        #expect(avErr.errorDescription?.contains("AVPlayer") == true)
    }

    @Test func initializationFailedIncludesEngineAndMessage() {
        let err = PlayerEngineError.initializationFailed(.ksPlayer, "codec not supported")
        let desc = err.errorDescription
        #expect(desc != nil)
        #expect(desc?.contains("KSPlayer") == true)
        #expect(desc?.contains("codec not supported") == true)
    }

    @Test func allCasesHaveNonNilDescriptions() {
        let cases: [PlayerEngineError] = [
            .invalidStreamURL("url"),
            .startupTimeout(.avPlayer),
            .initializationFailed(.ksPlayer, "msg"),
        ]
        for err in cases {
            #expect(err.errorDescription != nil, "Missing description for \(err)")
        }
    }
}
