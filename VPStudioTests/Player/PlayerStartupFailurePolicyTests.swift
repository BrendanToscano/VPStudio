import Foundation
import Testing
@testable import VPStudio

@Suite("Player Startup Failure Policy")
struct PlayerStartupFailurePolicyTests {
    @Test func skipsRemainingEnginesForRecoverableHTTP403Failures() {
        let stream = Fixtures.stream(
            debridService: DebridServiceType.realDebrid.rawValue,
            recoveryContext: StreamRecoveryContext(infoHash: "ABC123", preferredService: .realDebrid)
        )
        let error = PlayerEngineError.initializationFailed(.avPlayer, "HTTP 403: expired token")

        #expect(
            PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
                after: error,
                stream: stream,
                priorRefreshAttempts: 0
            )
        )
    }

    @Test func skipsRemainingEnginesForKnownDirectLinkNSErrorCodes() {
        let stream = Fixtures.stream(
            debridService: DebridServiceType.realDebrid.rawValue,
            recoveryContext: StreamRecoveryContext(infoHash: "ABC123", preferredService: .realDebrid)
        )
        let error = NSError(domain: NSURLErrorDomain, code: -1011)

        #expect(
            PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
                after: error,
                stream: stream,
                priorRefreshAttempts: 0
            )
        )
    }

    @Test func skipsRemainingEnginesForUnderlyingDirectLinkFailures() {
        let stream = Fixtures.stream(
            debridService: DebridServiceType.realDebrid.rawValue,
            recoveryContext: StreamRecoveryContext(infoHash: "ABC123", preferredService: .realDebrid)
        )
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: -1100,
            userInfo: [NSLocalizedFailureReasonErrorKey: "File does not exist"]
        )
        let error = NSError(
            domain: "Player",
            code: 42,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        #expect(
            PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
                after: error,
                stream: stream,
                priorRefreshAttempts: 0
            )
        )
        #expect(PlayerStartupFailurePolicy.normalizedDescription(for: error).contains("file does not exist"))
    }

    @Test func skipsRemainingEnginesForDirectLinkStatusPhrases() {
        let stream = Fixtures.stream(
            debridService: DebridServiceType.realDebrid.rawValue,
            recoveryContext: StreamRecoveryContext(infoHash: "ABC123", preferredService: .realDebrid)
        )
        let messages = [
            "status code 401",
            "status=404",
            "response 410",
            "error 403",
            "permission denied"
        ]

        for message in messages {
            #expect(
                PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
                    after: PlayerEngineError.initializationFailed(.avPlayer, message),
                    stream: stream,
                    priorRefreshAttempts: 0
                ),
                "Expected direct-link refresh for \(message)"
            )
        }
    }

    @Test func doesNotSkipForStartupTimeouts() {
        let stream = Fixtures.stream(
            debridService: DebridServiceType.realDebrid.rawValue,
            recoveryContext: StreamRecoveryContext(infoHash: "ABC123", preferredService: .realDebrid)
        )

        #expect(
            PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
                after: PlayerEngineError.startupTimeout(.avPlayer),
                stream: stream,
                priorRefreshAttempts: 0
            ) == false
        )
    }

    @Test func doesNotSkipWhenNoRefreshPlanExists() {
        let stream = Fixtures.stream(recoveryContext: nil)
        let error = PlayerEngineError.initializationFailed(.avPlayer, "HTTP 403: expired token")

        #expect(
            PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
                after: error,
                stream: stream,
                priorRefreshAttempts: 0
            ) == false
        )
    }

    @Test func doesNotSkipForCompatibilityFailures() {
        let stream = Fixtures.stream(
            debridService: DebridServiceType.realDebrid.rawValue,
            recoveryContext: StreamRecoveryContext(infoHash: "ABC123", preferredService: .realDebrid)
        )
        let error = PlayerEngineError.initializationFailed(.avPlayer, "Unsupported codec profile")

        #expect(
            PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
                after: error,
                stream: stream,
                priorRefreshAttempts: 0
            ) == false
        )
    }

    @Test func normalizedDescriptionIncludesInvalidStreamURLValue() {
        let description = PlayerStartupFailurePolicy.normalizedDescription(
            for: PlayerEngineError.invalidStreamURL("https://cdn.example.com/expired.mkv")
        )

        #expect(description.contains("invalid stream url"))
        #expect(description.contains("https://cdn.example.com/expired.mkv"))
    }

    @Test func normalizedDescriptionHandlesStartupTimeoutWithoutExtraMessage() {
        let description = PlayerStartupFailurePolicy.normalizedDescription(
            for: PlayerEngineError.startupTimeout(.avPlayer)
        )

        #expect(description.contains("timed out before playback started"))
        #expect(description.contains("code=1"))
    }
}
