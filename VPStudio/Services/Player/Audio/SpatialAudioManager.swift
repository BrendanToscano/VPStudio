import Foundation
import AVFoundation
import os

/// Manages spatial audio configuration for immersive and windowed playback modes.
/// Configures AVAudioSession for optimal spatial rendering on visionOS.
@MainActor
@Observable
final class SpatialAudioManager {
    private let logger = Logger(subsystem: "com.vpstudio", category: "SpatialAudioManager")

    private(set) var isImmersiveMode = false
    private(set) var isSpatialAudioAvailable = false

    init() {
        refreshSpatialCapabilities()
        observeAudioRouteChanges()
    }

    deinit {
        #if !os(macOS)
        NotificationCenter.default.removeObserver(self)
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
            logger.error("Failed to configure immersive audio: \(error.localizedDescription, privacy: .public)")
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
            logger.error("Failed to restore windowed audio: \(error.localizedDescription, privacy: .public)")
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
        NotificationCenter.default.removeObserver(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        if #available(iOS 15.0, tvOS 15.0, visionOS 1.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSpatialPlaybackCapabilitiesChange(_:)),
                name: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification,
                object: nil
            )
        }
        #endif
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        refreshSpatialCapabilities()
    }

    @available(iOS 15.0, tvOS 15.0, visionOS 1.0, *)
    @objc private func handleSpatialPlaybackCapabilitiesChange(_ notification: Notification) {
        refreshSpatialCapabilities()
    }
}
