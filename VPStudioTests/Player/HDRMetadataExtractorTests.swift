import AVFoundation
import CoreMedia
import Testing
@testable import VPStudio

@Suite("HDR Metadata Extractor")
struct HDRMetadataExtractorTests {
    @MainActor
    @Test
    func extractReturnsNilForUnreadableAsset() async {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/vpstudio-missing-hdr-source.mov"))

        let metadata = await HDRMetadataExtractor.extract(from: asset)

        #expect(metadata == nil)
    }

    @Test
    func pqFormatDescriptionParsesMasteringAndLightLevelMetadata() throws {
        let formatDescription = try makeVideoFormatDescription(
            codec: fourCC("hvc1"),
            transferFunction: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String,
            colorPrimaries: kCVImageBufferColorPrimaries_ITU_R_2020 as String,
            masteringDisplayColorVolume: masteringDisplayColorVolume(maxNits: 1_000, minNits: 0.005),
            contentLightLevelInfo: contentLightLevelInfo(maxCLL: 1_200, maxFALL: 420)
        )

        let metadata = HDRMetadataExtractor.extractFromFormatDescription(formatDescription)

        #expect(metadata.isHDR)
        #expect(!metadata.isDolbyVision)
        #expect(metadata.transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
        #expect(metadata.colorPrimaries == kCVImageBufferColorPrimaries_ITU_R_2020 as String)
        #expect(metadata.maxDisplayLuminance == 1_000)
        #expect(metadata.minDisplayLuminance == 0.005)
        #expect(metadata.maxContentLightLevel == 1_200)
        #expect(metadata.maxFrameAverageLightLevel == 420)
    }

    @Test
    func hlgFormatDescriptionIsHdrWithoutOptionalPayloads() throws {
        let formatDescription = try makeVideoFormatDescription(
            codec: fourCC("hvc1"),
            transferFunction: "ITU_R_2100_HLG",
            colorPrimaries: nil,
            masteringDisplayColorVolume: Data([0, 1, 2]),
            contentLightLevelInfo: Data([0, 1, 2])
        )

        let metadata = HDRMetadataExtractor.extractFromFormatDescription(formatDescription)

        #expect(metadata.isHDR)
        #expect(!metadata.isDolbyVision)
        #expect(metadata.transferFunction == "ITU_R_2100_HLG")
        #expect(metadata.colorPrimaries == nil)
        #expect(metadata.maxDisplayLuminance == nil)
        #expect(metadata.minDisplayLuminance == nil)
        #expect(metadata.maxContentLightLevel == nil)
        #expect(metadata.maxFrameAverageLightLevel == nil)
    }

    @Test
    func dolbyVisionCodecMarksHdrEvenWithoutHdrTransferFunction() throws {
        let formatDescription = try makeVideoFormatDescription(
            codec: fourCC("dvhe"),
            transferFunction: nil,
            colorPrimaries: nil
        )

        let metadata = HDRMetadataExtractor.extractFromFormatDescription(formatDescription)

        #expect(metadata.isHDR)
        #expect(metadata.isDolbyVision)
    }

    @Test(arguments: ["dvh1", "dvhe", "dva1", "dvav"])
    func allDolbyVisionCodecTagsMarkHdr(codecTag: String) throws {
        let formatDescription = try makeVideoFormatDescription(
            codec: fourCC(codecTag),
            transferFunction: kCVImageBufferTransferFunction_ITU_R_709_2 as String,
            colorPrimaries: nil
        )

        let metadata = HDRMetadataExtractor.extractFromFormatDescription(formatDescription)

        #expect(metadata.isHDR)
        #expect(metadata.isDolbyVision)
    }

    @Test(arguments: [
        kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String,
        kCVImageBufferTransferFunction_ITU_R_2100_HLG as String,
    ])
    func coreVideoHdrTransferConstantsMarkHdr(transferFunction: String) throws {
        let formatDescription = try makeVideoFormatDescription(
            codec: fourCC("hvc1"),
            transferFunction: transferFunction,
            colorPrimaries: nil
        )

        let metadata = HDRMetadataExtractor.extractFromFormatDescription(formatDescription)

        #expect(metadata.isHDR)
        #expect(!metadata.isDolbyVision)
        #expect(metadata.transferFunction == transferFunction)
    }

    @Test
    func sdrFormatDescriptionWithoutHdrSignalsIsNotHdr() throws {
        let formatDescription = try makeVideoFormatDescription(
            codec: fourCC("avc1"),
            transferFunction: kCVImageBufferTransferFunction_ITU_R_709_2 as String,
            colorPrimaries: kCVImageBufferColorPrimaries_ITU_R_709_2 as String
        )

        let metadata = HDRMetadataExtractor.extractFromFormatDescription(formatDescription)

        #expect(!metadata.isHDR)
        #expect(!metadata.isDolbyVision)
        #expect(metadata.transferFunction == kCVImageBufferTransferFunction_ITU_R_709_2 as String)
        #expect(metadata.colorPrimaries == kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
    }

    private func makeVideoFormatDescription(
        codec: CMVideoCodecType,
        transferFunction: String?,
        colorPrimaries: String?,
        masteringDisplayColorVolume: Data? = nil,
        contentLightLevelInfo: Data? = nil
    ) throws -> CMFormatDescription {
        var extensions: [String: Any] = [:]
        if let transferFunction {
            extensions[kCVImageBufferTransferFunctionKey as String] = transferFunction
        }
        if let colorPrimaries {
            extensions[kCVImageBufferColorPrimariesKey as String] = colorPrimaries
        }
        if let masteringDisplayColorVolume {
            extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] = masteringDisplayColorVolume
        }
        if let contentLightLevelInfo {
            extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] = contentLightLevelInfo
        }

        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codec,
            width: 3840,
            height: 2160,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &formatDescription
        )

        #expect(status == noErr)
        return try #require(formatDescription)
    }

    private func masteringDisplayColorVolume(maxNits: Float, minNits: Float) -> Data {
        var data = Data(repeating: 0, count: 16)
        appendBigEndian(UInt32((maxNits * 10_000).rounded()), to: &data)
        appendBigEndian(UInt32((minNits * 10_000).rounded()), to: &data)
        return data
    }

    private func contentLightLevelInfo(maxCLL: UInt16, maxFALL: UInt16) -> Data {
        var data = Data()
        appendBigEndian(maxCLL, to: &data)
        appendBigEndian(maxFALL, to: &data)
        return data
    }

    private func appendBigEndian(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private func appendBigEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private func fourCC(_ string: String) -> FourCharCode {
        var code: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            code = (code << 8) | FourCharCode(char)
        }
        return code
    }
}
