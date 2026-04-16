import Testing
import CoreGraphics
@testable import VPStudio

@Suite("Player Video Layout")
struct PlayerVideoLayoutTests {

    // MARK: - VideoFittingPolicy

    @Test("16:9 video in wider container fits to height")
    func fittedSize16x9InWiderContainer() {
        // Container is 2.5:1 (wider than 16:9 ≈ 1.78:1) — should fit to height
        let container = CGSize(width: 2500, height: 1000)
        let ratio: CGFloat = 16.0 / 9.0
        let result = VideoFittingPolicy.fittedSize(for: container, ratio: ratio)

        #expect(result.height == 1000)
        let expectedWidth = 1000 * ratio
        #expect(abs(result.width - expectedWidth) < 0.01)
    }

    @Test("16:9 video in taller container fits to width")
    func fittedSize16x9InTallerContainer() {
        // Container is 1:1 (taller relative to 16:9) — should fit to width
        let container = CGSize(width: 1000, height: 1000)
        let ratio: CGFloat = 16.0 / 9.0
        let result = VideoFittingPolicy.fittedSize(for: container, ratio: ratio)

        #expect(result.width == 1000)
        let expectedHeight = 1000 / ratio
        #expect(abs(result.height - expectedHeight) < 0.01)
    }

    @Test("4:3 video in 16:9 container fits to height")
    func fittedSize4x3InWideContainer() {
        // Container is 16:9 (wider than 4:3 ≈ 1.33:1) — should fit to height
        let container = CGSize(width: 1920, height: 1080)
        let ratio: CGFloat = 4.0 / 3.0
        let result = VideoFittingPolicy.fittedSize(for: container, ratio: ratio)

        #expect(result.height == 1080)
        let expectedWidth = 1080 * ratio
        #expect(abs(result.width - expectedWidth) < 0.01)
    }

    @Test("Perfect aspect ratio match uses full container")
    func fittedSizePerfectMatch() {
        let container = CGSize(width: 1920, height: 1080)
        let ratio: CGFloat = 1920.0 / 1080.0
        let result = VideoFittingPolicy.fittedSize(for: container, ratio: ratio)

        #expect(abs(result.width - 1920) < 0.01)
        #expect(abs(result.height - 1080) < 0.01)
    }

    @Test("Zero height container returns container size unchanged")
    func fittedSizeZeroHeightReturnsContainer() {
        let container = CGSize(width: 1920, height: 0)
        let result = VideoFittingPolicy.fittedSize(for: container, ratio: 16.0 / 9.0)
        #expect(result == container)
    }

    @Test("Zero ratio returns container size unchanged")
    func fittedSizeZeroRatioReturnsContainer() {
        let container = CGSize(width: 1920, height: 1080)
        let result = VideoFittingPolicy.fittedSize(for: container, ratio: 0)
        #expect(result == container)
    }

    // MARK: - PlayerCinematicChromePolicy

    @Test("Window corner radius is positive")
    func windowCornerRadiusIsPositive() {
        #expect(PlayerCinematicChromePolicy.windowCornerRadius > 0)
    }
}
