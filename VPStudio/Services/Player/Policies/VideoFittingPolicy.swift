import CoreGraphics

enum VideoFittingPolicy {
    /// Returns the largest size that fits within `container` while preserving `ratio`.
    /// Falls back to the container size when `ratio` or `container.height` is non-positive.
    static func fittedSize(for container: CGSize, ratio: CGFloat) -> CGSize {
        guard container.height > 0, ratio > 0 else { return container }
        let containerRatio = container.width / container.height
        if containerRatio > ratio {
            // Container is wider — fit to height
            let height = container.height
            let width = height * ratio
            return CGSize(width: width, height: height)
        } else {
            // Container is taller — fit to width
            let width = container.width
            let height = width / ratio
            return CGSize(width: width, height: height)
        }
    }
}
