import Testing
@testable import VPStudio

@Suite("Spatial Audio Manager")
@MainActor
struct SpatialAudioManagerTests {
    @Test
    func initialStateIsWindowedAndRefreshable() {
        let manager = SpatialAudioManager()

        #expect(manager.isImmersiveMode == false)
        manager.refreshSpatialCapabilities()

        #if os(macOS)
        #expect(manager.isSpatialAudioAvailable == false)
        #endif
    }

    @Test
    func enteringAndExitingImmersiveModeTogglesState() {
        let manager = SpatialAudioManager()

        manager.enterImmersiveMode()
        #expect(manager.isImmersiveMode)

        manager.exitImmersiveMode()
        #expect(manager.isImmersiveMode == false)
    }

    @Test
    func immersiveModeTransitionsAreIdempotent() {
        let manager = SpatialAudioManager()

        manager.enterImmersiveMode()
        manager.enterImmersiveMode()
        #expect(manager.isImmersiveMode)

        manager.exitImmersiveMode()
        manager.exitImmersiveMode()
        #expect(!manager.isImmersiveMode)
    }
}
