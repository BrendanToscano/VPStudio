import Foundation
import Testing
@testable import VPStudio

@Suite("Player Session Lifecycle")
struct PlayerSessionLifecycleTests {
    @Test
    @MainActor
    func activePlayerSessionStartsNil() {
        let appState = AppState(testHooks: .init())
        #expect(appState.activePlayerSession == nil)
        #expect(appState.activeAVPlayer == nil)
        #expect(appState.activeVideoRenderer == nil)
    }

    @Test
    @MainActor
    func terminateActivePlayerSessionClearsAllProperties() {
        let appState = AppState(testHooks: .init())
        let stream = Fixtures.stream()
        appState.activePlayerSession = PlayerSessionRequest(
            stream: stream,
            mediaTitle: "Test Movie",
            mediaId: "test-123"
        )

        appState.terminateActivePlayerSession()

        #expect(appState.activePlayerSession == nil)
        #expect(appState.activeAVPlayer == nil)
        #expect(appState.activeVideoRenderer == nil)
    }

    @Test
    @MainActor
    func setThenTerminateReturnsToNil() {
        let appState = AppState(testHooks: .init())
        let stream = Fixtures.stream()

        // Set a session
        let session = PlayerSessionRequest(
            stream: stream,
            mediaTitle: "Another Movie",
            mediaId: "test-456"
        )
        appState.activePlayerSession = session
        #expect(appState.activePlayerSession != nil)
        #expect(appState.activePlayerSession?.mediaId == "test-456")

        // Terminate
        appState.terminateActivePlayerSession()

        #expect(appState.activePlayerSession == nil)
        #expect(appState.activeAVPlayer == nil)
        #expect(appState.activeVideoRenderer == nil)
    }
}
