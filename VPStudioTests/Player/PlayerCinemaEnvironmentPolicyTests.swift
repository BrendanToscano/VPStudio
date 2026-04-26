import Foundation
import Testing
@testable import VPStudio

@Suite("Player Cinema Environment Policy")
struct PlayerCinemaEnvironmentPolicyTests {
    @Test
    func cinemaEnvironmentRequiresAVPlayerEngineAndInstance() {
        #expect(PlayerCinemaEnvironmentPolicy.canOpen(activeEngine: .avPlayer, hasAVPlayer: true))
        #expect(!PlayerCinemaEnvironmentPolicy.canOpen(activeEngine: .avPlayer, hasAVPlayer: false))
        #expect(!PlayerCinemaEnvironmentPolicy.canOpen(activeEngine: .ksPlayer, hasAVPlayer: true))
        #expect(!PlayerCinemaEnvironmentPolicy.canOpen(activeEngine: .ksPlayer, hasAVPlayer: false))
        #expect(!PlayerCinemaEnvironmentPolicy.canOpen(activeEngine: nil, hasAVPlayer: true))
    }

    @Test
    func cinemaEnvironmentUsesMenuDismissalDelayBeforeOpeningFromMenus() {
        #expect(PlayerCinemaEnvironmentPolicy.menuDismissalDelay == .milliseconds(180))
    }

    @Test
    func unavailableMessageStaysUserActionable() {
        #expect(PlayerCinemaEnvironmentPolicy.unavailableMessage == "Cinema Environment requires AVPlayer playback.")
    }

    @Test
    func environmentAssetIconDistinguishesPanoramasFromModelAssets() {
        #expect(PlayerCinemaEnvironmentPolicy.iconName(forAssetPath: "/tmp/theater.hdr") == "pano")
        #expect(PlayerCinemaEnvironmentPolicy.iconName(forAssetPath: "/tmp/THEATER.EXR") == "pano")
        #expect(PlayerCinemaEnvironmentPolicy.iconName(forAssetPath: "/tmp/room.usdz") == "cube.transparent")
        #expect(PlayerCinemaEnvironmentPolicy.iconName(forAssetPath: "/tmp/environment") == "cube.transparent")
    }
}
