import CoreGraphics
import Foundation
import ImageIO

/// Analyzes an equirectangular HDRI panorama to find the yaw offset that
/// brings the most prominent screen-like region (the cinema screen) to face
/// the viewer at 0°.
///
/// ## How it works
///
/// An equirectangular image maps the full sphere to a 2:1 rectangle:
/// - Horizontal axis → longitude (yaw).  x=0 → −180°, x=W/2 → 0°, x=W → +180°
/// - Vertical axis   → latitude (pitch). y=0 → +90° (top), y=H/2 → 0° (equator)
///
/// Cinema screens are large, very bright, rectangular features located above the
/// equator in the panorama.  The algorithm:
///   1. Decodes a small tone-mapped LDR thumbnail (512 px wide) — safe because
///      CGImageSource applies Reinhard-style tone mapping automatically when
///      `kCGImageSourceShouldAllowFloat` is false.
///   2. Accumulates luminance per column across the vertical band that
///      corresponds to ~+5° – +55° latitude (where screens appear in
///      cinema panoramas, not the ceiling or floor).
///   3. Applies a box-smoothing pass (wrapping at the panorama seam) to suppress
///      individual light fixtures and reflections in favour of the large bright
///      rectangle of the screen.
///   4. Finds the peak column, converts its x position to a yaw angle, and
///      returns the negated value so the skybox rotation brings the screen to 0°.
///
/// Because each HDRI is different, the detection is run once on import and the
/// result is persisted in `EnvironmentAsset.hdriYawOffset`.
struct HDRIOrientationAnalyzer {

    // MARK: - Public API

    /// Detects the yaw offset (degrees) needed to front-face the main bright
    /// region of the HDRI.  Runs the heavy image decode off the main actor.
    /// Returns `nil` if the image cannot be read or analysed.
    static func detectScreenYaw(at url: URL) async -> Float? {
        await Task.detached(priority: .userInitiated) {
            analyzeSync(url: url)
        }.value
    }

    // MARK: - Core analysis (nonisolated, safe to run on any thread)

    nonisolated private static func analyzeSync(url: URL) -> Float? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        // Request a small LDR thumbnail.  CGImageSource applies tone-mapping
        // when kCGImageSourceShouldAllowFloat is false, giving a sensible 8-bit
        // representation of the HDR values.
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOptions as CFDictionary
        ) else { return nil }

        return screenYaw(in: thumb)
    }

    // MARK: - Pixel analysis

    private static func screenYaw(in image: CGImage) -> Float? {
        let w = image.width
        let h = image.height
        guard w > 1, h > 1 else { return nil }

        // Render into an RGBA8 bitmap so we can read pixel values safely.
        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

        // Vertical analysis band.
        //
        // Equirectangular latitude formula: lat = (0.5 − y/H) × 180°
        //   +55° latitude → y ≈ H × (0.5 − 55/180) ≈ H × 0.194
        //   + 5° latitude → y ≈ H × (0.5 − 5/180)  ≈ H × 0.472
        //
        // This band covers the portion of the sphere where the cinema screen
        // faces you — well above the floor and below the ceiling.
        let topY    = Int(Double(h) * 0.19)
        let bottomY = Int(Double(h) * 0.50)

        // Accumulate luminance per column inside the band.
        var columnLuminance = [Float](repeating: 0, count: w)
        for y in topY ..< bottomY {
            let rowBase = y * bytesPerRow
            for x in 0 ..< w {
                let p = rowBase + x * 4
                let r = Float(pixels[p])
                let g = Float(pixels[p + 1])
                let b = Float(pixels[p + 2])
                // ITU-R BT.709 luminance
                columnLuminance[x] += 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
        }

        // Box-smooth with wrap-around to suppress point lights and reflections
        // while preserving the broad bright rectangle of the screen.
        // Window ≈ 1/10 of image width.
        let smoothed = boxSmooth(columnLuminance, halfWidth: max(1, w / 10))

        guard let peakCol = smoothed.indices.max(by: { smoothed[$0] < smoothed[$1] }) else {
            return nil
        }

        // Convert peak column → longitude (yaw angle of the screen centre).
        // x=0 → −180°, x=W/2 → 0°, x=W−1 → +180°
        let screenYawDeg = (Float(peakCol) / Float(w - 1) - 0.5) * 360.0

        // Negate: the skybox `hdriYawOffset` rotates the sphere, so we need to
        // rotate by the opposite angle to bring the screen to face the user at 0°.
        return -screenYawDeg
    }

    // MARK: - Box smooth (wraps around the panorama seam)

    /// Wrapping box filter — treats the column array as circular so the
    /// panorama seam at x=0/x=W doesn't create a brightness discontinuity.
    private static func boxSmooth(_ values: [Float], halfWidth h: Int) -> [Float] {
        let n = values.count
        guard n > 0, h > 0 else { return values }
        var out = [Float](repeating: 0, count: n)
        for i in 0 ..< n {
            var sum: Float = 0
            let count = 2 * h + 1
            for d in -h ... h {
                let j = ((i + d) % n + n) % n
                sum += values[j]
            }
            out[i] = sum / Float(count)
        }
        return out
    }
}
