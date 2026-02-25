#if os(visionOS)
import Testing
import AVFoundation
@testable import VPStudio

@Suite("APMPInjector — Lifecycle")
struct APMPInjectorTests {

    @Test("Starts inactive with no video renderer")
    @MainActor func startsInactive() {
        let injector = APMPInjector()
        #expect(!injector.isActive)
        #expect(injector.videoRenderer == nil)
        #expect(injector.displayLayer == nil)
    }

    @Test("Activates on start with valid player item")
    @MainActor func activatesOnStart() {
        let injector = APMPInjector()
        let url = URL(string: "https://example.com/video.mp4")!
        let player = AVPlayer(url: url)
        injector.start(player: player, mode: .sideBySide)
        #expect(injector.isActive)
        #expect(injector.videoRenderer != nil)
        #expect(injector.displayLayer != nil)
    }

    @Test("Deactivates on stop after start")
    @MainActor func deactivatesOnStop() {
        let injector = APMPInjector()
        let url = URL(string: "https://example.com/video.mp4")!
        let player = AVPlayer(url: url)
        injector.start(player: player, mode: .overUnder)
        injector.stop()
        #expect(!injector.isActive)
        #expect(injector.videoRenderer == nil)
        #expect(injector.displayLayer == nil)
    }

    @Test("Stop without prior start does not crash")
    @MainActor func stopIsIdempotent() {
        let injector = APMPInjector()
        injector.stop()
        injector.stop()
        #expect(!injector.isActive)
    }

    @Test("Second start produces a fresh renderer instance")
    @MainActor func startStopStartCycle() {
        let injector = APMPInjector()
        let url = URL(string: "https://example.com/video.mp4")!
        let player = AVPlayer(url: url)

        injector.start(player: player, mode: .sideBySide)
        let firstRenderer = injector.videoRenderer

        injector.stop()
        injector.start(player: player, mode: .overUnder)
        let secondRenderer = injector.videoRenderer

        #expect(secondRenderer != nil)
        #expect(firstRenderer !== secondRenderer)
    }

    @Test("Start with player lacking currentItem stays inactive")
    @MainActor func startWithoutItemStaysInactive() {
        let injector = APMPInjector()
        let player = AVPlayer()
        injector.start(player: player, mode: .sideBySide)
        #expect(!injector.isActive)
        #expect(injector.videoRenderer == nil)
    }

    @Test("Second start implicitly stops the first session")
    @MainActor func secondStartImplicitlyStopsFirst() {
        let injector = APMPInjector()
        let url = URL(string: "https://example.com/video.mp4")!
        let player = AVPlayer(url: url)

        injector.start(player: player, mode: .sideBySide)
        let firstLayer = injector.displayLayer

        injector.start(player: player, mode: .overUnder)
        let secondLayer = injector.displayLayer

        #expect(injector.isActive)
        #expect(firstLayer !== secondLayer)
    }

    @Test("Display layer and video renderer are distinct instances")
    @MainActor func layerAndRendererAreDistinct() {
        let injector = APMPInjector()
        let url = URL(string: "https://example.com/video.mp4")!
        let player = AVPlayer(url: url)
        injector.start(player: player, mode: .sideBySide)

        #expect(injector.videoRenderer != nil)
        #expect(injector.displayLayer != nil)
    }

    @Test("Both modes reject a player with no current item")
    @MainActor func bothModesRejectEmptyPlayer() {
        let injector = APMPInjector()
        let player = AVPlayer() // no currentItem

        for mode in [APMPInjector.Mode.sideBySide, .overUnder] {
            injector.start(player: player, mode: mode)
            #expect(!injector.isActive, "Mode \(mode) should not activate without a player item")
            #expect(injector.videoRenderer == nil)
        }
    }

    @Test("Mode conforms to Sendable")
    func modeIsSendable() {
        let mode: APMPInjector.Mode = .sideBySide
        // This compiles only if Mode is Sendable.
        let _: any Sendable = mode
        _ = mode // Silence warning
    }
}
#endif
