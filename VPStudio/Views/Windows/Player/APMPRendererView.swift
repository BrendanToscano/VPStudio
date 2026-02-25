#if os(visionOS)
import SwiftUI
import AVFoundation
import QuartzCore

/// `UIViewRepresentable` that displays frames from an `AVSampleBufferDisplayLayer`.
/// Used in `PlayerView` when APMP stereo injection is active, so the 2D window
/// also shows the processed (metadata-tagged) video frames.
struct APMPRendererView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> APMPDisplayView {
        let view = APMPDisplayView()
        view.setDisplayLayer(displayLayer)
        return view
    }

    func updateUIView(_ uiView: APMPDisplayView, context: Context) {
        uiView.setDisplayLayer(displayLayer)
    }

    static func dismantleUIView(_ uiView: APMPDisplayView, coordinator: ()) {
        uiView.clearDisplayLayer()
    }
}

final class APMPDisplayView: UIView {
    private var hostedLayer: AVSampleBufferDisplayLayer?

    func setDisplayLayer(_ newLayer: AVSampleBufferDisplayLayer) {
        guard newLayer !== hostedLayer else { return }
        hostedLayer?.removeFromSuperlayer()
        hostedLayer = newLayer
        newLayer.videoGravity = .resizeAspect
        newLayer.frame = bounds
        layer.addSublayer(newLayer)
    }

    func clearDisplayLayer() {
        hostedLayer?.sampleBufferRenderer.flush()
        hostedLayer?.removeFromSuperlayer()
        hostedLayer = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedLayer?.frame = bounds
    }

    deinit {
        clearDisplayLayer()
    }
}
#endif
