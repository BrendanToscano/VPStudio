import Foundation
import ImageIO
import Testing
@testable import VPStudio

struct AppIconAssetTests {
    private static let iconLayerPaths: [String] = [
        "VPStudio/Assets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/front.png",
        "VPStudio/Assets.xcassets/AppIcon.solidimagestack/Middle.solidimagestacklayer/Content.imageset/middle.png",
        "VPStudio/Assets.xcassets/AppIcon.solidimagestack/Back.solidimagestacklayer/Content.imageset/back.png",
    ]

    @Test(arguments: iconLayerPaths)
    func appIconLayersExistAndAreExpectedSize(relativePath: String) {
        let fileURL = repoRootURL().appendingPathComponent(relativePath)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            Issue.record("Could not read image properties for \(relativePath)")
            return
        }

        #expect(width == 1024)
        #expect(height == 1024)
    }

    @Test
    func duplicateResourceAssetCatalogIsRemoved() {
        let duplicateCatalog = repoRootURL().appendingPathComponent("VPStudio/Resources/Assets.xcassets")
        #expect(FileManager.default.fileExists(atPath: duplicateCatalog.path) == false)
    }

    @Test
    func backLayerIsFullyOpaque() {
        let backLayer = repoRootURL()
            .appendingPathComponent("VPStudio/Assets.xcassets/AppIcon.solidimagestack/Back.solidimagestacklayer/Content.imageset/back.png")
        #expect(FileManager.default.fileExists(atPath: backLayer.path))

        guard let source = CGImageSourceCreateWithURL(backLayer as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let providerData = image.dataProvider?.data,
              let bytePointer = CFDataGetBytePtr(providerData) else {
            Issue.record("Could not load back icon layer data")
            return
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        guard bytesPerPixel >= 4 else {
            Issue.record("Unexpected pixel format for back icon layer")
            return
        }

        let dataLength = CFDataGetLength(providerData)
        var index = 3
        while index < dataLength {
            let alpha = bytePointer[index]
            if alpha != 255 {
                Issue.record("Back layer contains a non-opaque pixel (alpha=\(alpha))")
                return
            }
            index += bytesPerPixel
        }
    }

    private func repoRootURL() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return url
    }
}
