import Foundation

enum PlayerCapabilityEvaluator {
    static func warnings(for stream: StreamInfo) -> [String] {
        var warnings: [String] = []

        if stream.quality == .uhd4k {
            warnings.append("4K source detected. Output quality depends on display, network, and decoder limits.")
        }

        if stream.hdr != .sdr {
            warnings.append("HDR source (\(stream.hdr.rawValue)) detected. Tone-mapping depends on device and playback pipeline.")
        }

        if stream.audio.spatialAudioHint {
            warnings.append("Spatial/Atmos-like audio detected. Final output depends on route and system audio capabilities.")
        }

        return warnings
    }
}
