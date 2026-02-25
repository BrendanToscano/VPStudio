import CoreFoundation
import Testing
@testable import VPStudio

@Suite("Transport Button Layout")
struct TransportButtonLayoutTests {
    @Test func primaryButtonIsLargerThanSecondary() {
        #expect(PlayerCinematicChromePolicy.primaryTransportButtonSize > PlayerCinematicChromePolicy.secondaryTransportButtonSize)
    }

    @Test func primaryToSecondaryRatio() {
        let ratio = PlayerCinematicChromePolicy.primaryTransportButtonSize / PlayerCinematicChromePolicy.secondaryTransportButtonSize
        #expect(ratio >= 1.1 && ratio <= 2.5)
    }

    @Test func transportCardFitsWithinDock() {
        #expect(PlayerCinematicChromePolicy.transportCardMaxWidth <= PlayerCinematicChromePolicy.controlsDockMaxWidth)
    }

    @Test func skipIntervalsAreSymmetric() {
        #expect(PlayerCinematicChromePolicy.skipBackInterval == PlayerCinematicChromePolicy.skipForwardInterval)
    }
}
