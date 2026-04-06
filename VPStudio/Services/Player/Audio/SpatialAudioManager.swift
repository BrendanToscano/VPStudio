import Foundation
import AVFoundation

/// Manages spatial audio configuration for immersive and windowed playback modes.
/// Configures AVAudioSession for optimal spatial rendering on visionOS.
@Observable
final class SpatialAudioManager: @unchecked Sendable {

    private(set) var isImmersiveMode = false
    private(set) var isSpatialAudioAvailable = false

    #if !os(macOS)
    private var routeChangeObserver: NSObjectProtocol?
    private var spatialChangeObserver: NSObjectProtocol?
    #endif

    init() {
        refreshSpatialCapabilities()
        observeAudioRouteChanges()
    }

    deinit {
        #if !os(macOS)
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = spatialChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    // MARK: - Immersive Mode Transitions

    /// Call when entering immersive space. Configures audio session for spatial rendering.
    func enterImmersiveMode() {
        isImmersiveMode = true
        configureForImmersive()
    }

    /// Call when leaving immersive space. Restores standard audio session.
    func exitImmersiveMode() {
        isImmersiveMode = false
        configureForWindowed()
    }

    // MARK: - Configuration

    private func configureForImmersive() {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // Use .moviePlayback mode with spatial rendering policy
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                policy: .longFormVideo,
                options: []
            )

            // Enable multichannel content support for spatial audio passthrough
            if #available(iOS 15.0, tvOS 15.0, visionOS 1.0, *) {
                try session.setSupportsMultichannelContent(true)
            }

            // Request maximum available output channels for surround/Atmos
            let maxChannels = session.maximumOutputNumberOfChannels
            if maxChannels > 2 {
                try session.setPreferredOutputNumberOfChannels(maxChannels)
            }

            try session.setActive(true)
        } catch {
            print("[SpatialAudioManager] Failed to configure immersive audio: \(error)")
        }
        #endif

        refreshSpatialCapabilities()
    }

    private func configureForWindowed() {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            print("[SpatialAudioManager] Failed to restore windowed audio: \(error)")
        }
        #endif
    }

    // MARK: - Spatial Capability Detection

    func refreshSpatialCapabilities() {
        #if !os(macOS)
        if #available(iOS 15.0, tvOS 15.0, visionOS 1.0, *) {
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            isSpatialAudioAvailable = outputs.contains { $0.isSpatialAudioEnabled }
        } else {
            isSpatialAudioAvailable = false
        }
        #else
        isSpatialAudioAvailable = false
        #endif
    }

    // MARK: - Observers

    private func observeAudioRouteChanges() {
        #if !os(macOS)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSpatialCapabilities()
        }

        if #available(iOS 15.0, tvOS 15.0, visionOS 1.0, *) {
            spatialChangeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshSpatialCapabilities()
            }
        }
        #endif
    }
}
