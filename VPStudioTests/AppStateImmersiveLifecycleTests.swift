import Testing
@testable import VPStudio

@Suite(.serialized)
struct AppStateImmersiveLifecycleTests {
    @Test
    @MainActor
    func transitionLockPreventsOverlappingImmersiveRequests() {
        let appState = AppState()

        #expect(appState.beginImmersiveTransition())
        #expect(appState.beginImmersiveTransition() == false)

        appState.cancelImmersiveTransition()
        #expect(appState.beginImmersiveTransition())
    }

    @Test
    @MainActor
    func suspensionDismissQueuesSingleRestoreRequest() {
        let appState = AppState()
        appState.immersiveSpaceDidAppear(.hdriSkybox)
        appState.stageImmersiveDismiss(reason: .suspension)
        appState.immersiveSpaceDidDisappear()

        #expect(appState.consumeSuspendedImmersiveRestoreRequest())
        #expect(appState.consumeSuspendedImmersiveRestoreRequest() == false)
    }

    @Test
    @MainActor
    func memoryPressureDismissDoesNotAutoRestore() {
        let appState = AppState()
        appState.immersiveSpaceDidAppear(.customEnvironment)
        appState.stageImmersiveDismiss(reason: .memoryPressure)
        appState.immersiveSpaceDidDisappear()

        #expect(appState.consumeSuspendedImmersiveRestoreRequest() == false)
    }

    @Test
    @MainActor
    func immersiveAppearResetsTransitionState() {
        let appState = AppState()

        #expect(appState.beginImmersiveTransition())
        appState.stageImmersiveDismiss(reason: .suspension)
        appState.immersiveSpaceDidAppear(.customEnvironment)

        #expect(appState.isImmersiveSpaceOpen)
        #expect(appState.isImmersiveTransitionInFlight == false)
        #expect(appState.consumeSuspendedImmersiveRestoreRequest() == false)
    }
}
