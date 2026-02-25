import Testing
@testable import VPStudio

@Suite("Player Lifecycle Policy")
struct PlayerLifecyclePolicyTests {
    @Test
    func closesDedicatedPlayerWindowOnBackMatchesPlatform() {
        #if os(macOS) || os(visionOS)
        #expect(PlayerLifecyclePolicy.closesDedicatedPlayerWindowOnBack == true)
        #else
        #expect(PlayerLifecyclePolicy.closesDedicatedPlayerWindowOnBack == false)
        #endif
    }

    @Test
    func closesDedicatedPlayerWindowOnBackIsConsistent() {
        // Validates that both test paths agree with the single canonical property.
        let value = PlayerLifecyclePolicy.closesDedicatedPlayerWindowOnBack
        #if os(macOS) || os(visionOS)
        #expect(value == true)
        #else
        #expect(value == false)
        #endif
    }
}
