import Foundation
import Testing
@testable import VPStudio

@Suite("PlayerStreamLinkRecovery")
struct PlayerStreamLinkRecoveryTests {
    @Test func returnsNilWithoutRecoveryContextOrQAOverride() {
        let stream = Fixtures.stream()

        #expect(
            PlayerStreamLinkRecovery.refreshPlan(
                for: stream,
                priorAttempts: 0,
                qaRefreshURL: nil
            ) == nil
        )
    }

    @Test func infersPreferredServiceFromResolvedStreamWhenMissing() {
        let context = StreamRecoveryContext(infoHash: "ABC123")
        let stream = Fixtures.stream(
            debridService: DebridServiceType.allDebrid.rawValue,
            recoveryContext: context
        )

        let plan = PlayerStreamLinkRecovery.refreshPlan(
            for: stream,
            priorAttempts: 0,
            qaRefreshURL: nil
        )

        guard case let .reResolve(refreshedContext)? = plan else {
            Issue.record("Expected a debrid re-resolve refresh plan")
            return
        }

        #expect(refreshedContext.infoHash == "abc123")
        #expect(refreshedContext.preferredService == .allDebrid)
    }

    @Test func preservesEpisodeContextForRefresh() {
        let context = StreamRecoveryContext(
            infoHash: "hash-episode",
            preferredService: .realDebrid,
            seasonNumber: 2,
            episodeNumber: 7
        )
        let stream = Fixtures.stream(recoveryContext: context)

        let plan = PlayerStreamLinkRecovery.refreshPlan(
            for: stream,
            priorAttempts: 0,
            qaRefreshURL: nil
        )

        guard case let .reResolve(refreshedContext)? = plan else {
            Issue.record("Expected a debrid re-resolve refresh plan")
            return
        }

        #expect(refreshedContext.seasonNumber == 2)
        #expect(refreshedContext.episodeNumber == 7)
        #expect(refreshedContext.preferredService == .realDebrid)
    }

    @Test func logicalAttemptKeyStaysStableAcrossResolvedPathChanges() {
        let context = StreamRecoveryContext(
            infoHash: "hash-episode",
            preferredService: .realDebrid,
            seasonNumber: 2,
            episodeNumber: 7
        )
        let original = Fixtures.stream(
            url: "https://cdn.example.com/direct/original.mkv?token=expired",
            recoveryContext: context
        )
        let refreshed = Fixtures.stream(
            url: "https://cdn.example.com/direct/refreshed.mkv?token=fresh",
            recoveryContext: context
        )

        #expect(
            PlayerStreamLinkRecovery.attemptTrackingKey(for: original) ==
            PlayerStreamLinkRecovery.attemptTrackingKey(for: refreshed)
        )
    }

    @Test func logicalAttemptKeyUsesResolvedDebridServiceWhenContextHasNoPreference() {
        let context = StreamRecoveryContext(
            infoHash: "hash-no-preference",
            seasonNumber: nil,
            episodeNumber: nil
        )
        let stream = Fixtures.stream(
            debridService: DebridServiceType.offcloud.rawValue,
            recoveryContext: context
        )

        #expect(
            PlayerStreamLinkRecovery.attemptTrackingKey(for: stream) ==
            "offcloud|hash-no-preference|s-|e-"
        )
    }

    @Test func logicalAttemptKeyFallsBackToResolvedStreamIdentityWithoutRecoveryContext() {
        let original = Fixtures.stream(url: "https://cdn.example.com/direct/original.mkv?token=expired")
        let refreshed = Fixtures.stream(url: "https://cdn.example.com/direct/refreshed.mkv?token=fresh")

        #expect(
            PlayerStreamLinkRecovery.attemptTrackingKey(for: original) == original.id
        )
        #expect(
            PlayerStreamLinkRecovery.attemptTrackingKey(for: refreshed) == refreshed.id
        )
        #expect(
            PlayerStreamLinkRecovery.attemptTrackingKey(for: original) !=
            PlayerStreamLinkRecovery.attemptTrackingKey(for: refreshed)
        )
    }

    @Test func defaultRefreshPlanWrapperUsesRuntimeQAConfigurationAndReturnsNilWithoutContext() {
        let stream = Fixtures.stream()

        #expect(PlayerStreamLinkRecovery.refreshPlan(for: stream, priorAttempts: 0) == nil)
    }

    @Test func qaSampleOverrideCanSwapInFreshTokenizedURL() {
        let originalURL = URL(string: "https://qa.example.com/stream.mp4?token=expired")!
        let refreshedURL = URL(string: "https://qa.example.com/stream.mp4?token=fresh")!
        let stream = Fixtures.stream(
            url: originalURL.absoluteString,
            debridService: "qa-sample"
        )

        let plan = PlayerStreamLinkRecovery.refreshPlan(
            for: stream,
            priorAttempts: 0,
            qaRefreshURL: refreshedURL
        )

        guard case let .replace(replacement)? = plan else {
            Issue.record("Expected a QA replacement refresh plan")
            return
        }

        #expect(replacement.streamURL == refreshedURL)
        #expect(replacement.id == stream.id)
        #expect(replacement.recoveryContext == stream.recoveryContext)
    }

    @Test func qaSampleOverrideCanRetryUsingSameResolvedURL() {
        let originalURL = URL(string: "https://qa.example.com/stream.mp4?token=stable")!
        let stream = Fixtures.stream(
            url: originalURL.absoluteString,
            debridService: "qa-sample"
        )

        let plan = PlayerStreamLinkRecovery.refreshPlan(
            for: stream,
            priorAttempts: 0,
            qaRefreshURL: originalURL
        )

        guard case let .replace(replacement)? = plan else {
            Issue.record("Expected a QA replacement refresh plan even when the URL stays the same")
            return
        }

        #expect(replacement.streamURL == originalURL)
        #expect(replacement.id == stream.id)
    }

    @Test func blocksRepeatedRefreshAttemptsForSameLogicalStream() {
        let context = StreamRecoveryContext(infoHash: "hash-1", preferredService: .realDebrid)
        let stream = Fixtures.stream(recoveryContext: context)

        #expect(
            PlayerStreamLinkRecovery.refreshPlan(
                for: stream,
                priorAttempts: 1,
                qaRefreshURL: nil
            ) == nil
        )
    }
}
