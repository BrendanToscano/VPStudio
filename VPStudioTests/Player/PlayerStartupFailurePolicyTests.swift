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
}
