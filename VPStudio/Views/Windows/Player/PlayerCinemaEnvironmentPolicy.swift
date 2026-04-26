import Foundation

enum PlayerCinemaEnvironmentPolicy {
    static let menuDismissalDelay: Duration = .milliseconds(180)
    static let unavailableMessage = "Cinema Environment requires AVPlayer playback."

    static func canOpen(activeEngine: PlayerEngineKind?, hasAVPlayer: Bool) -> Bool {
        activeEngine == .avPlayer && hasAVPlayer
    }

    static func iconName(forAssetPath assetPath: String) -> String {
        let ext = URL(fileURLWithPath: assetPath).pathExtension.lowercased()
        return ["hdr", "exr"].contains(ext) ? "pano" : "cube.transparent"
    }
}
