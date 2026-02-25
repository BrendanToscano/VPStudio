import CoreFoundation
import Testing
@testable import VPStudio

@Suite("Quick Options Pill Content")
struct QuickOptionsPillContentTests {
    @Test func quickActionsMaxWidthFitsInDock() {
        #expect(PlayerCinematicChromePolicy.quickActionsMaxWidth <= PlayerCinematicChromePolicy.controlsDockMaxWidth)
    }

    @Test func quickActionsNarrowerThanTransport() {
        #expect(PlayerCinematicChromePolicy.quickActionsMaxWidth < PlayerCinematicChromePolicy.transportCardMaxWidth)
    }

    @Test func transportInternalSpacingIsPositive() {
        #expect(PlayerCinematicChromePolicy.transportInternalSpacing > 0)
    }
}
