import SwiftUI
import AVKit
#if os(macOS)
import AppKit

struct AVPlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = videoGravity
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.controlsStyle = .none
        nsView.videoGravity = videoGravity
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player = nil
    }
}
#elseif canImport(UIKit)
import UIKit

struct AVPlayerSurfaceView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> AVPlayerSurfaceUIView {
        let view = AVPlayerSurfaceUIView()
        view.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: AVPlayerSurfaceUIView, context: Context) {
        uiView.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }

    static func dismantleUIView(_ uiView: AVPlayerSurfaceUIView, coordinator: ()) {
        uiView.player = nil
    }
}

final class AVPlayerSurfaceUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = self.layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer backing layer.")
        }
        return layer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
        }
    }
}
#endif
