import AVFoundation
import CoreMedia
import os

private let logger = Logger(subsystem: "com.vpstudio", category: "HDRMetadata")

// MARK: - HDR Display Metadata

/// Mastering-display and content-light-level metadata extracted from the
/// first video track of an `AVAsset`.  All fields are optional because SDR
/// content carries none of them.
struct HDRDisplayMetadata: Sendable, Equatable {
    /// Peak luminance of the mastering display (nits).
    var maxDisplayLuminance: Float?
    /// Minimum luminance of the mastering display (nits).
    var minDisplayLuminance: Float?
    /// Maximum Content Light Level (MaxCLL, nits).
    var maxContentLightLevel: Float?
    /// Maximum Frame-Average Light Level (MaxFALL, nits).
    var maxFrameAverageLightLevel: Float?
    /// Color primaries string, e.g. `"ITU_R_2020"`.
    var colorPrimaries: String?
    /// Transfer function string, e.g. `"SMPTE_ST_2084_PQ"` or `"ITU_R_2100_HLG"`.
    var transferFunction: String?
    /// `true` when the transfer function indicates a high-dynamic-range EOTF.
    var isHDR: Bool
    /// `true` when the content signals Dolby Vision via its codec type.
    var isDolbyVision: Bool
}

// MARK: - Extractor

/// Reads HDR mastering-display metadata from `AVAsset` video tracks.
///
/// Usage:
/// ```swift
/// let metadata = await HDRMetadataExtractor.extract(from: player.currentItem!.asset)
/// ```
enum HDRMetadataExtractor {

    /// Extract HDR metadata from the first video track of an asset.
    /// Returns `nil` only when no video track can be loaded.
    @MainActor
    static func extract(from asset: AVAsset) async -> HDRDisplayMetadata? {
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            logger.warning("Failed to load video tracks for HDR metadata: \(error.localizedDescription)")
            return nil
        }
        guard let videoTrack = tracks.first else {
            logger.debug("No video track found; skipping HDR metadata extraction.")
            return nil
        }

        let formatDescriptions: [CMFormatDescription]
        do {
            formatDescriptions = try await videoTrack.load(.formatDescriptions)
        } catch {
            logger.warning("Failed to load format descriptions: \(error.localizedDescription)")
            return nil
        }
        guard let formatDesc = formatDescriptions.first else {
            logger.debug("No format descriptions available on video track.")
            return nil
        }

        return extractFromFormatDescription(formatDesc)
    }

    // MARK: - Format-description parsing

    /// Build `HDRDisplayMetadata` from a single `CMFormatDescription`.
    static func extractFromFormatDescription(_ formatDesc: CMFormatDescription) -> HDRDisplayMetadata {
        let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] ?? [:]

        // -- Color primaries & transfer function ----------------------------------

        let colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
        let transferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String

        let isHDR = Self.isHDRTransferFunction(transferFunction)
        let isDolbyVision = Self.isDolbyVisionCodec(formatDesc)

        // -- Mastering Display Color Volume (MDCV) --------------------------------

        var maxDisplayLuminance: Float?
        var minDisplayLuminance: Float?

        if let mdcvData = extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] as? Data {
            let parsed = parseMasteringDisplayColorVolume(mdcvData)
            maxDisplayLuminance = parsed.maxLuminance
            minDisplayLuminance = parsed.minLuminance
        }

        // -- Content Light Level Info (CLLI) --------------------------------------

        var maxCLL: Float?
        var maxFALL: Float?

        if let clliData = extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] as? Data {
            let parsed = parseContentLightLevelInfo(clliData)
            maxCLL = parsed.maxCLL
            maxFALL = parsed.maxFALL
        }

        let metadata = HDRDisplayMetadata(
            maxDisplayLuminance: maxDisplayLuminance,
            minDisplayLuminance: minDisplayLuminance,
            maxContentLightLevel: maxCLL,
            maxFrameAverageLightLevel: maxFALL,
            colorPrimaries: colorPrimaries,
            transferFunction: transferFunction,
            isHDR: isHDR || isDolbyVision,
            isDolbyVision: isDolbyVision
        )

        if metadata.isHDR {
            let pri = colorPrimaries ?? "n/a"
            let tf = transferFunction ?? "n/a"
            let maxD = maxDisplayLuminance.map { "\($0)" } ?? "n/a"
            let cllStr = maxCLL.map { "\($0)" } ?? "n/a"
            let fallStr = maxFALL.map { "\($0)" } ?? "n/a"
            logger.info("HDR metadata — DV: \(isDolbyVision), primaries: \(pri), transfer: \(tf), maxDisplay: \(maxD) nits, MaxCLL: \(cllStr), MaxFALL: \(fallStr)")
        } else {
            let tf = transferFunction ?? "n/a"
            logger.debug("Content is SDR (transfer: \(tf)).")
        }

        return metadata
    }

    // MARK: - Private Helpers

    /// SEI-style Mastering Display Colour Volume (MDCV) payload as defined by
    /// SMPTE ST 2086.  The binary blob is 24 bytes:
    ///   - 3 x (x,y) display primaries — each pair is 2 x UInt16 (big-endian)
    ///   - 1 x (x,y) white point       — 2 x UInt16
    ///   - max luminance                — UInt32
    ///   - min luminance                — UInt32
    ///
    /// Luminance values are in units of 0.0001 cd/m^2.
    private static func parseMasteringDisplayColorVolume(_ data: Data) -> (maxLuminance: Float?, minLuminance: Float?) {
        // 6 UInt16 (primaries) + 2 UInt16 (white point) + 2 UInt32 (luminance) = 24 bytes
        guard data.count >= 24 else { return (nil, nil) }
        let maxRaw = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 16, as: UInt32.self).bigEndian
        }
        let minRaw = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 20, as: UInt32.self).bigEndian
        }
        // Convert from 0.0001 cd/m^2 to nits
        return (Float(maxRaw) / 10_000.0, Float(minRaw) / 10_000.0)
    }

    /// Content Light Level Information (CLLI) is 4 bytes:
    ///   - MaxCLL  — UInt16 (big-endian), cd/m^2
    ///   - MaxFALL — UInt16 (big-endian), cd/m^2
    private static func parseContentLightLevelInfo(_ data: Data) -> (maxCLL: Float?, maxFALL: Float?) {
        guard data.count >= 4 else { return (nil, nil) }
        let cll = data.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 0, as: UInt16.self).bigEndian
        }
        let fall = data.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 2, as: UInt16.self).bigEndian
        }
        return (Float(cll), Float(fall))
    }

    /// Returns `true` when the transfer function indicates PQ or HLG.
    private static func isHDRTransferFunction(_ tf: String?) -> Bool {
        guard let tf else { return false }
        // CoreVideo constants: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
        // kCVImageBufferTransferFunction_ITU_R_2100_HLG
        let hdrFunctions: Set<String> = [
            "SMPTE_ST_2084_PQ",
            "ITU_R_2100_HLG",
            // Some containers report the full CoreVideo constant name:
            kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String,
            kCVImageBufferTransferFunction_ITU_R_2100_HLG as String,
        ]
        return hdrFunctions.contains(tf)
    }

    /// Detects Dolby Vision by inspecting the codec type (fourCC).
    private static func isDolbyVisionCodec(_ formatDesc: CMFormatDescription) -> Bool {
        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
        // Dolby Vision FourCC codes: 'dvh1', 'dvhe', 'dva1', 'dvav'
        let dvCodecs: Set<FourCharCode> = [
            fourCC("dvh1"),
            fourCC("dvhe"),
            fourCC("dva1"),
            fourCC("dvav"),
        ]
        return dvCodecs.contains(codecType)
    }

    /// Convert a 4-character ASCII string to a `FourCharCode`.
    private static func fourCC(_ string: String) -> FourCharCode {
        var code: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            code = (code << 8) | FourCharCode(char)
        }
        return code
    }
}
