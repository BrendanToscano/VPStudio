import Foundation
import Testing
@testable import VPStudio

@Suite("PlayerLoadingStatus — Phase Model")
struct PlayerLoadingStatusTests {

    // MARK: - Status Messages

    @Test func connectingPhaseHasCorrectMessage() {
        let phase = PlayerLoadingPhase.connecting
        #expect(phase.statusMessage == "Connecting to stream\u{2026}")
    }

    @Test func bufferingPhaseHasCorrectMessage() {
        let phase = PlayerLoadingPhase.buffering
        #expect(phase.statusMessage == "Buffering video data\u{2026}")
    }

    @Test func preparingVideoPhaseHasCorrectMessage() {
        let phase = PlayerLoadingPhase.preparingVideo
        #expect(phase.statusMessage == "Preparing video\u{2026}")
    }

    @Test func switchingEnginePhaseHasCorrectMessage() {
        let phase = PlayerLoadingPhase.switchingEngine
        #expect(phase.statusMessage == "Switching to alternate player engine\u{2026}")
    }

    @Test func retryingStreamPhaseHasCorrectMessage() {
        let phase = PlayerLoadingPhase.retryingStream
        #expect(phase.statusMessage == "Trying next stream\u{2026}")
    }

    @Test func readyPhaseHasCorrectMessage() {
        let phase = PlayerLoadingPhase.ready
        #expect(phase.statusMessage == "Starting playback")
    }

    @Test func failedPhaseUsesProvidedMessage() {
        let phase = PlayerLoadingPhase.failed("Server returned 403")
        #expect(phase.statusMessage == "Server returned 403")
    }

    @Test func failedPhaseWithEmptyMessageFallsBack() {
        let phase = PlayerLoadingPhase.failed("")
        #expect(phase.statusMessage == "Playback failed")
    }

    // MARK: - Failover Explanation

    @Test func switchingEngineHasFailoverExplanation() {
        let phase = PlayerLoadingPhase.switchingEngine
        let explanation = phase.failoverExplanation
        #expect(explanation != nil)
        #expect(explanation!.contains("KSPlayer"))
        #expect(explanation!.contains("compatibility"))
    }

    @Test func nonSwitchingPhasesHaveNoFailoverExplanation() {
        let phases: [PlayerLoadingPhase] = [
            .connecting, .buffering, .preparingVideo,
            .retryingStream, .ready, .failed("err"),
        ]
        for phase in phases {
            #expect(phase.failoverExplanation == nil, "Phase \(phase) should not have failover explanation")
        }
    }

    // MARK: - Phase Classification

    @Test func loadingPhasesAreMarkedAsLoading() {
        let loadingPhases: [PlayerLoadingPhase] = [
            .connecting, .buffering, .preparingVideo,
            .switchingEngine, .retryingStream,
        ]
        for phase in loadingPhases {
            #expect(phase.isLoading, "\(phase) should be loading")
            #expect(!phase.isTerminal, "\(phase) should not be terminal")
        }
    }

    @Test func terminalPhasesAreMarkedCorrectly() {
        #expect(PlayerLoadingPhase.ready.isTerminal)
        #expect(!PlayerLoadingPhase.ready.isLoading)
        #expect(PlayerLoadingPhase.failed("x").isTerminal)
        #expect(!PlayerLoadingPhase.failed("x").isLoading)
    }

    // MARK: - Phase Kind

    @Test func phaseKindStripsAssociatedValues() {
        #expect(PlayerLoadingPhase.connecting.kind == .connecting)
        #expect(PlayerLoadingPhase.buffering.kind == .buffering)
        #expect(PlayerLoadingPhase.preparingVideo.kind == .preparingVideo)
        #expect(PlayerLoadingPhase.switchingEngine.kind == .switchingEngine)
        #expect(PlayerLoadingPhase.retryingStream.kind == .retryingStream)
        #expect(PlayerLoadingPhase.ready.kind == .ready)
        #expect(PlayerLoadingPhase.failed("any").kind == .failed)
    }

    // MARK: - Phase Transitions

    @Test func connectingCanTransitionToBufferingOrFailed() {
        let valid = PlayerLoadingPhase.connecting.validNextPhases
        #expect(valid.contains(.buffering))
        #expect(valid.contains(.failed))
        #expect(!valid.contains(.ready))
        #expect(!valid.contains(.connecting))
    }

    @Test func bufferingCanTransitionToReadyOrSwitching() {
        let valid = PlayerLoadingPhase.buffering.validNextPhases
        #expect(valid.contains(.ready))
        #expect(valid.contains(.switchingEngine))
        #expect(valid.contains(.failed))
        #expect(valid.contains(.preparingVideo))
    }

    @Test func preparingVideoCanReachReadyOrFail() {
        let valid = PlayerLoadingPhase.preparingVideo.validNextPhases
        #expect(valid.contains(.ready))
        #expect(valid.contains(.failed))
        #expect(valid.contains(.switchingEngine))
        #expect(!valid.contains(.connecting))
    }

    @Test func switchingEngineCanReenterConnecting() {
        let valid = PlayerLoadingPhase.switchingEngine.validNextPhases
        #expect(valid.contains(.connecting))
        #expect(valid.contains(.buffering))
        #expect(valid.contains(.failed))
    }

    @Test func retryingStreamCanReenterConnecting() {
        let valid = PlayerLoadingPhase.retryingStream.validNextPhases
        #expect(valid.contains(.connecting))
        #expect(valid.contains(.buffering))
        #expect(valid.contains(.ready))
    }

    @Test func readyIsTerminalWithNoValidTransitions() {
        let valid = PlayerLoadingPhase.ready.validNextPhases
        #expect(valid.isEmpty)
    }

    @Test func failedCanOnlyTransitionToConnecting() {
        let valid = PlayerLoadingPhase.failed("err").validNextPhases
        #expect(valid == [.connecting])
    }

    // MARK: - Equatable

    @Test func equatableWorksForSimpleCases() {
        #expect(PlayerLoadingPhase.connecting == PlayerLoadingPhase.connecting)
        #expect(PlayerLoadingPhase.connecting != PlayerLoadingPhase.buffering)
    }

    @Test func equatableWorksForFailedWithMessage() {
        #expect(PlayerLoadingPhase.failed("a") == PlayerLoadingPhase.failed("a"))
        #expect(PlayerLoadingPhase.failed("a") != PlayerLoadingPhase.failed("b"))
    }
}
