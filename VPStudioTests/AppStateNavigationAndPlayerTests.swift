import Foundation
import AVFoundation
import Testing
@testable import VPStudio

// MARK: - AppState Navigation State

@Suite("AppState - Navigation State", .serialized)
struct AppStateNavigationStateTests {

    @Test @MainActor
    func defaultTabIsDiscover() {
        let appState = AppState()
        #expect(appState.selectedTab == .discover)
    }

    @Test @MainActor
    func tabSelectionRoundTrips() {
        let appState = AppState()
        for tab in SidebarTab.allCases {
            appState.selectedTab = tab
            #expect(appState.selectedTab == tab)
        }
    }

    @Test @MainActor
    func isShowingSetupDefaultsFalse() {
        let appState = AppState()
        #expect(appState.isShowingSetup == false)
        #expect(appState.setupRecommendationNeeded == false)
    }
}

// MARK: - AppState Player Session State

@Suite("AppState - Player Session State", .serialized)
struct AppStatePlayerSessionStateTests {

    @Test @MainActor
    func activePlayerSessionIsNilByDefault() {
        let appState = AppState()
        #expect(appState.activePlayerSession == nil)
    }

    @Test @MainActor
    func activePlayerSessionCanBeSet() {
        let appState = AppState()
        let stream = Fixtures.stream(fileName: "movie.mkv")
        let preview = Fixtures.mediaPreview()
        let viewModel = DetailViewModel(appState: appState)
        let request = viewModel.makePlayerSessionRequest(stream: stream, preview: preview)

        appState.activePlayerSession = request
        #expect(appState.activePlayerSession?.mediaId == request.mediaId)

        appState.activePlayerSession = nil
        #expect(appState.activePlayerSession == nil)
    }

    @Test @MainActor
    func fullscreenBySessionIDStartsEmpty() {
        let appState = AppState()
        #expect(appState.fullscreenBySessionID.isEmpty)
    }

    @Test @MainActor
    func fullscreenBySessionIDTracksMultipleSessions() {
        let appState = AppState()
        let id1 = UUID()
        let id2 = UUID()

        appState.fullscreenBySessionID[id1] = true
        appState.fullscreenBySessionID[id2] = false

        #expect(appState.fullscreenBySessionID[id1] == true)
        #expect(appState.fullscreenBySessionID[id2] == false)
        #expect(appState.fullscreenBySessionID.count == 2)
    }

    @Test @MainActor
    func isMainWindowSuppressedForPlayerDefaultsFalse() {
        let appState = AppState()
        #expect(appState.isMainWindowSuppressedForPlayer == false)
    }

    @Test @MainActor
    func isMainWindowSuppressedForPlayerCanBeToggled() {
        let appState = AppState()
        appState.isMainWindowSuppressedForPlayer = true
        #expect(appState.isMainWindowSuppressedForPlayer)
        appState.isMainWindowSuppressedForPlayer = false
        #expect(appState.isMainWindowSuppressedForPlayer == false)
    }

    @Test @MainActor
    func releasePlayerResourcesClearsPlaybackBridgeOnlyWhenRequested() {
        let appState = AppState()
        let stream = Fixtures.stream(fileName: "movie.mkv")
        let preview = Fixtures.mediaPreview()
        let viewModel = DetailViewModel(appState: appState)
        let request = viewModel.makePlayerSessionRequest(stream: stream, preview: preview)
        appState.activePlayerSession = request
        appState.fullscreenBySessionID[request.id] = true
        appState.activeAVPlayer = AVPlayer()
        appState.activeVideoRenderer = AVSampleBufferVideoRenderer()

        appState.releasePlayerResources(clearSession: false, sessionID: request.id)

        #expect(appState.activeAVPlayer == nil)
        #expect(appState.activeVideoRenderer == nil)
        #expect(appState.activePlayerSession?.id == request.id)
        #expect(appState.fullscreenBySessionID[request.id] == true)
    }

    @Test @MainActor
    func releasePlayerResourcesClearsSessionAndFullscreenState() {
        let appState = AppState()
        let stream = Fixtures.stream(fileName: "movie.mkv")
        let preview = Fixtures.mediaPreview()
        let viewModel = DetailViewModel(appState: appState)
        let request = viewModel.makePlayerSessionRequest(stream: stream, preview: preview)
        appState.activePlayerSession = request
        appState.fullscreenBySessionID[request.id] = true
        appState.activeAVPlayer = AVPlayer()
        appState.activeVideoRenderer = AVSampleBufferVideoRenderer()

        appState.releasePlayerResources(clearSession: true, sessionID: request.id)

        #expect(appState.activeAVPlayer == nil)
        #expect(appState.activeVideoRenderer == nil)
        #expect(appState.activePlayerSession == nil)
        #expect(appState.fullscreenBySessionID[request.id] == nil)
    }
}

// MARK: - AppState Immersive Dismiss Reason Coverage

@Suite("AppState - Immersive Dismiss Reasons", .serialized)
struct AppStateImmersiveDismissReasonTests {

    @Test @MainActor
    func userInitiatedDismissDoesNotQueueRestore() {
        let appState = AppState()
        appState.immersiveSpaceDidAppear(.hdriSkybox)
        appState.stageImmersiveDismiss(reason: .userInitiated)
        appState.immersiveSpaceDidDisappear()

        #expect(appState.consumeSuspendedImmersiveRestoreRequest() == false)
    }

    @Test @MainActor
    func switchingEnvironmentDismissDoesNotQueueRestore() {
        let appState = AppState()
        appState.immersiveSpaceDidAppear(.hdriSkybox)
        appState.stageImmersiveDismiss(reason: .switchingEnvironment)
        appState.immersiveSpaceDidDisappear()

        #expect(appState.consumeSuspendedImmersiveRestoreRequest() == false)
    }

    @Test @MainActor
    func playerClosedDismissDoesNotQueueRestore() {
        let appState = AppState()
        appState.immersiveSpaceDidAppear(.customEnvironment)
        appState.stageImmersiveDismiss(reason: .playerClosed)
        appState.immersiveSpaceDidDisappear()

        #expect(appState.consumeSuspendedImmersiveRestoreRequest() == false)
    }

    @Test @MainActor
    func suspensionWhenSpaceNotOpenDoesNotQueueRestore() {
        let appState = AppState()
        // Space was never opened, so shouldRestore should remain false
        appState.stageImmersiveDismiss(reason: .suspension)
        appState.immersiveSpaceDidDisappear()

        #expect(appState.consumeSuspendedImmersiveRestoreRequest() == false)
    }

    @Test @MainActor
    func suspensionWhenTransitionInFlightQueuesRestore() {
        let appState = AppState()
        // Transition started but space not fully open yet
        #expect(appState.beginImmersiveTransition())
        appState.stageImmersiveDismiss(reason: .suspension)
        appState.immersiveSpaceDidDisappear()

        #expect(appState.consumeSuspendedImmersiveRestoreRequest())
    }

    @Test @MainActor
    func stageImmersiveDismissPreservesEnvironmentBeforeDisappear() {
        let appState = AppState()
        appState.immersiveSpaceDidAppear(.hdriSkybox)
        appState.stageImmersiveDismiss(reason: .suspension)

        // Before disappear, space should still be open
        #expect(appState.isImmersiveSpaceOpen)
        #expect(appState.activeEnvironment == .hdriSkybox)
    }
}

// MARK: - AppState Activate Environment Asset

@Suite("AppState - Activate Environment Asset", .serialized)
struct AppStateActivateEnvironmentAssetTests {

    @Test @MainActor
    func activateEnvironmentAssetUpdatesSelectedAsset() async {
        let asset = EnvironmentAsset(
            id: "env-test",
            name: "Test Environment",
            sourceType: .imported,
            assetPath: "test.hdr",
            isActive: false
        )

        // Use a real EnvironmentCatalogManager backed by an in-memory DB
        // We only test that selectedEnvironmentAsset is updated (fire-and-forget for persistence)
        let appState = AppState()
        await appState.activateEnvironmentAsset(asset)

        #expect(appState.selectedEnvironmentAsset?.id == "env-test")
    }
}

// MARK: - AppState Reload Indexers Failure

@Suite("AppState - Reload Indexers Failure", .serialized)
struct AppStateReloadIndexersFailureTests {

    @Test @MainActor
    func reloadIndexersSwallowsErrorSilently() async {
        struct HookError: Error {}
        let appState = AppState(
            testHooks: .init(
                initializeIndexers: { throw HookError() }
            )
        )

        // Should not throw — errors are swallowed
        await appState.reloadIndexers()
        // If we reach here, the error was handled silently
        #expect(Bool(true))
    }

    @Test @MainActor
    func reloadIndexersDoesNotPostNotificationOnFailure() async {
        struct HookError: Error {}
        final class NotificationFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false

            func markPosted() {
                lock.lock()
                value = true
                lock.unlock()
            }

            func wasPosted() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }

        let didPost = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .indexersDidChange,
            object: nil,
            queue: nil
        ) { _ in
            didPost.markPosted()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let appState = AppState(
            testHooks: .init(
                initializeIndexers: { throw HookError() }
            )
        )

        await appState.reloadIndexers()
        #expect(didPost.wasPosted() == false)
    }
}
