import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VPStudio

@Suite("HDRI Orientation Analyzer")
struct HDRIOrientationAnalyzerTests {
    @Test
    func detectScreenYawReturnsNilForUnreadableImage() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        let yaw = await HDRIOrientationAnalyzer.detectScreenYaw(at: url)

        #expect(yaw == nil)
    }

    @Test
    func detectScreenYawFindsBrightScreenRegionAndReturnsOppositeOffset() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("synthetic-panorama.png")
        let width = 120
        let height = 60
        let brightRange = 82..<96
        try writePanorama(
            url: imageURL,
            width: width,
            height: height,
            brightColumns: brightRange
        )

        let yaw = try #require(await HDRIOrientationAnalyzer.detectScreenYaw(at: imageURL))
        let brightCenter = Float((brightRange.lowerBound + brightRange.upperBound - 1) / 2)
        let expectedScreenYaw = (brightCenter / Float(width - 1) - 0.5) * 360.0

        #expect(abs(yaw + expectedScreenYaw) < 20)
    }

    private func writePanorama(
        url: URL,
        width: Int,
        height: Int,
        brightColumns: Range<Int>
    ) throws {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 12, count: height * bytesPerRow)

        for y in 0..<height {
            let rowBase = y * bytesPerRow
            for x in 0..<width {
                let index = rowBase + x * 4
                let isScreenBand = (Int(Double(height) * 0.22)..<Int(Double(height) * 0.46)).contains(y)
                let isBrightColumn = brightColumns.contains(x)
                let value: UInt8 = isScreenBand && isBrightColumn ? 255 : 12
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
                pixels[index + 3] = 255
            }
        }

        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))

        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
