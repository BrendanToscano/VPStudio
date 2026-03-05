#if os(visionOS)
import AVFoundation
import CoreMedia
import CoreVideo
import os
import QuartzCore

private let logger = Logger(subsystem: "com.vpstudio", category: "APMPInjector")

/// Injects spatial-video metadata into frames from an `AVPlayer` item so that
/// an `AVSampleBufferVideoRenderer` (used by RealityKit `VideoMaterial`) and an
/// `AVSampleBufferDisplayLayer` (used in the PlayerView window) both receive
/// properly-tagged sample buffers for side-by-side or over-under 3D content.
///
/// ## Stereo Tagging
/// Each sample buffer's format description includes `ProjectionKind`,
/// `ViewPackingKind`, `HasLeftStereoEyeView`, `HasRightStereoEyeView`, and
/// `HeroStereoEye` extensions matching the configured `Mode`. This tells the
/// visionOS spatial compositor how to present the two eye views.
///
/// ## Buffer Isolation
/// The renderer and display layer each receive their own `CMSampleBuffer`
/// instance (backed by the same pixel buffer). This prevents one consumer's
/// lifecycle from affecting the other.
@MainActor
final class APMPInjector {
    enum Mode: Sendable { case sideBySide, overUnder }

    private(set) var isActive = false
    private(set) var videoRenderer: AVSampleBufferVideoRenderer?
    private(set) var displayLayer: AVSampleBufferDisplayLayer?

    private var displayLink: CADisplayLink?
    private var displayLinkTarget: DisplayLinkTarget?
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var weakPlayer: AVPlayer?
    /// Strong reference to the player item that owns our `videoOutput`.
    /// Stored directly so `stop()` can reliably remove the output even if the
    /// player's `currentItem` has changed since `start()`.
    private var trackedItem: AVPlayerItem?

    @MainActor deinit {
        stop()
    }

    func start(player: AVPlayer, mode: Mode) {
        stop()
        guard let item = player.currentItem else { return }
        weakPlayer = player
        trackedItem = item

        let output = AVPlayerItemVideoOutput(outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        videoOutput = output

        let renderer = AVSampleBufferVideoRenderer()
        videoRenderer = renderer

        let layer = AVSampleBufferDisplayLayer()
        displayLayer = layer

        let target = DisplayLinkTarget(output: output, renderer: renderer, layer: layer, mode: mode)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        displayLinkTarget = target
        isActive = true
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
        if let item = trackedItem, let output = videoOutput {
            item.remove(output)
        }
        videoOutput = nil
        trackedItem = nil
        weakPlayer = nil
        videoRenderer?.flush()
        videoRenderer = nil
        displayLayer?.sampleBufferRenderer.flush()
        displayLayer = nil
        isActive = false
    }
}

// MARK: - CADisplayLink trampoline (avoids retain cycle)

/// `NSObject` subclass used as the `CADisplayLink` target.
/// Holds strong references to the output and renderers so they survive even if
/// `APMPInjector` is stopped and released during a tick. Marked
/// `@unchecked Sendable` because its internal mutable state (the renderers) is
/// only ever accessed from the main run-loop callback.
private final class DisplayLinkTarget: NSObject, @unchecked Sendable {
    let output: AVPlayerItemVideoOutput
    let renderer: AVSampleBufferVideoRenderer
    let layer: AVSampleBufferDisplayLayer
    let mode: APMPInjector.Mode

    /// Cached stereo format description. Built once on first frame to avoid
    /// re-creating it every tick.
    private var stereoFormatDesc: CMVideoFormatDescription?
    private var cachedWidth: Int = 0
    private var cachedHeight: Int = 0

    init(
        output: AVPlayerItemVideoOutput,
        renderer: AVSampleBufferVideoRenderer,
        layer: AVSampleBufferDisplayLayer,
        mode: APMPInjector.Mode
    ) {
        self.output = output
        self.renderer = renderer
        self.layer = layer
        self.mode = mode
    }

    @objc func tick(_ link: CADisplayLink) {
        // Use link.timestamp (current vsync) rather than targetTimestamp
        // (next vsync prediction) for accurate current-frame sampling.
        let itemTime = output.itemTime(forHostTime: link.timestamp)
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }
        injectFrame(pixelBuffer: pixelBuffer, itemTime: itemTime)
    }

    private func injectFrame(pixelBuffer: CVPixelBuffer, itemTime: CMTime) {
        let formatDesc = stereoFormatDescription(for: pixelBuffer)
        guard let formatDesc else { return }

        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: itemTime,
            decodeTimeStamp: .invalid
        )

        // Create separate sample buffers for each consumer so their
        // lifecycles don't interfere with each other (P1-IM-002).
        // OSStatus returns are now checked (P1-046).
        var rendererBuffer: CMSampleBuffer?
        let rendererStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &rendererBuffer
        )

        var layerBuffer: CMSampleBuffer?
        let layerStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &layerBuffer
        )

        if rendererStatus == noErr, let rendererBuffer {
            renderer.enqueue(rendererBuffer)
        }

        let layerRenderer = layer.sampleBufferRenderer
        if layerStatus == noErr, let layerBuffer, layerRenderer.isReadyForMoreMediaData {
            layerRenderer.enqueue(layerBuffer)
        }
    }

    /// Returns a `CMVideoFormatDescription` with stereo packing extensions
    /// matching the configured `mode`. Cached after the first call and
    /// invalidated if the pixel buffer dimensions change.
    private func stereoFormatDescription(for pixelBuffer: CVPixelBuffer) -> CMVideoFormatDescription? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        if let cached = stereoFormatDesc, width == cachedWidth, height == cachedHeight {
            return cached
        }

        cachedWidth = width
        cachedHeight = height

        // Build extensions dictionary with stereo metadata.
        // These keys are read by the visionOS spatial compositor via
        // AVSampleBufferVideoRenderer to determine eye-view layout.
        var extensions: [String: Any] = [
            "ProjectionKind": "Rectilinear",
            "HasLeftStereoEyeView": true,
            "HasRightStereoEyeView": true,
            "HeroStereoEye": "Left",
        ]
        switch mode {
        case .sideBySide:
            extensions["ViewPackingKind"] = "SideBySide"
        case .overUnder:
            extensions["ViewPackingKind"] = "OverUnder"
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var desc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: CMVideoCodecType(pixelFormat),
            width: Int32(width),
            height: Int32(height),
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &desc
        )

        if status == noErr {
            stereoFormatDesc = desc
        } else {
            // Reset caches so the next frame retries from scratch.
            stereoFormatDesc = nil
            cachedWidth = 0
            cachedHeight = 0
            logger.warning(
                "Failed to create stereo format description: OSStatus \(status), \(width)x\(height)"
            )
        }
        return desc
    }
}
#endif
