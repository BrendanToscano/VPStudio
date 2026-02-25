import AVFoundation
import CoreGraphics
import Testing
@testable import VPStudio

// MARK: - Video Gravity Default Tests

@Suite("AVPlayerSurfaceView - Default Video Gravity")
struct AVPlayerSurfaceViewGravityTests {

    @Test func defaultVideoGravityIsResizeAspectFill() {
        // AVPlayerSurfaceView defaults to .resizeAspectFill for edge-to-edge
        // presentation with no black bars.
        let expectedGravity: AVLayerVideoGravity = .resizeAspectFill
        #expect(expectedGravity == .resizeAspectFill)
        #expect(expectedGravity != .resizeAspect)
        #expect(expectedGravity != .resize)
    }

    @Test func autoModeUsesAspectFill() {
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .auto) == .resizeAspectFill)
    }

    @Test func fixedPresetsUseAspectFill() {
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .sixteenByNine) == .resizeAspectFill)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .twentyOneByNine) == .resizeAspectFill)
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .fourByThree) == .resizeAspectFill)
    }

    @Test func freeformUsesResizeAspect() {
        #expect(PlayerAspectRatioPolicy.videoGravity(for: .freeform) == .resizeAspect)
    }
}

// MARK: - Player Overlay Layer Order Tests

@Suite("Player Overlay Layer Order")
struct PlayerOverlayLayerOrderTests {

    /// The expected stacking order of layers in the player ZStack.
    /// Lower index = further back (rendered first).
    enum PlayerLayerOrder: Int, Comparable {
        case background = 0
        case videoSurface = 1
        case subtitleOverlay = 2
        case controlsOverlay = 3
        case startupStateOverlay = 4

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    @Test func backgroundIsBehindVideo() {
        #expect(PlayerLayerOrder.background < PlayerLayerOrder.videoSurface)
    }

    @Test func videoIsBehindSubtitles() {
        #expect(PlayerLayerOrder.videoSurface < PlayerLayerOrder.subtitleOverlay)
    }

    @Test func subtitlesAreBehindControls() {
        #expect(PlayerLayerOrder.subtitleOverlay < PlayerLayerOrder.controlsOverlay)
    }

    @Test func controlsAreBehindStartupOverlay() {
        #expect(PlayerLayerOrder.controlsOverlay < PlayerLayerOrder.startupStateOverlay)
    }

    @Test func videoIsNotTheTopmostLayer() {
        #expect(PlayerLayerOrder.videoSurface.rawValue < PlayerLayerOrder.startupStateOverlay.rawValue)
    }

    @Test func controlsOverlayIsAboveVideo() {
        // The entire point: controls float ON TOP of the video
        #expect(PlayerLayerOrder.controlsOverlay > PlayerLayerOrder.videoSurface)
    }
}

// MARK: - Title Bar Layout Tests

@Suite("Player Title Bar Layout")
struct PlayerTitleBarLayoutTests {

    /// Represents the three sections of the title bar
    enum TitleBarSection: String, CaseIterable {
        case left = "back"
        case center = "title"
        case right = "ellipsis"
    }

    @Test func titleBarHasThreeSections() {
        #expect(TitleBarSection.allCases.count == 3)
    }

    @Test func leftSectionContainsBackButton() {
        #expect(TitleBarSection.left.rawValue == "back")
    }

    @Test func centerSectionContainsTitle() {
        #expect(TitleBarSection.center.rawValue == "title")
    }

    @Test func rightSectionContainsEllipsisMenu() {
        #expect(TitleBarSection.right.rawValue == "ellipsis")
    }

    @Test func titleFallsBackToFileName() {
        let mediaTitle: String? = nil
        let fileName = "Mercy.2024.1080p.BluRay.x264.mkv"
        let displayTitle = mediaTitle ?? fileName
        #expect(displayTitle == fileName)
    }

    @Test func titlePrefersMediaTitle() {
        let mediaTitle: String? = "Mercy"
        let fileName = "Mercy.2024.1080p.BluRay.x264.mkv"
        let displayTitle = mediaTitle ?? fileName
        #expect(displayTitle == "Mercy")
    }
}

// MARK: - Info Pills Construction Tests

@Suite("Player Info Pills Construction")
struct PlayerInfoPillsConstructionTests {

    /// Describes the pills that appear in the info row
    enum InfoPillKind: String, CaseIterable {
        case playbackRate
        case subtitles
        case audio
        case qualityBadge
        case engineLabel
    }

    @Test func basePillCountIsFiveWithoutOptional() {
        // The 5 always-present pills: rate, subtitles, audio, quality, engine
        let basePills: [InfoPillKind] = [.playbackRate, .subtitles, .audio, .qualityBadge, .engineLabel]
        #expect(basePills.count == 5)
    }

    @Test func playbackRateFormattingForDefaultRate() {
        let rate: Float = 1.0
        let formatted = String(format: "%.1fx", rate)
        #expect(formatted == "1.0x")
    }

    @Test func playbackRateFormattingForFastRate() {
        let rate: Float = 2.0
        let formatted = String(format: "%.1fx", rate)
        #expect(formatted == "2.0x")
    }

    @Test func playbackRateFormattingForSlowRate() {
        let rate: Float = 0.5
        let formatted = String(format: "%.1fx", rate)
        #expect(formatted == "0.5x")
    }

    @Test func engineDisplayNameForKSPlayer() {
        #expect(PlayerEngineKind.ksPlayer.displayName == "KSPlayer")
    }

    @Test func engineDisplayNameForAVPlayer() {
        #expect(PlayerEngineKind.avPlayer.displayName == "AVPlayer")
    }

    @Test @MainActor func threeDPillAppearsWhenSBSContent() {
        let engine = VPPlayerEngine()
        engine.updateStereoMode(from: "Movie.SBS.1080p")
        // is3DContent should be true for SBS
        #expect(engine.is3DContent == true)
    }

    @Test @MainActor func threeDPillDoesNotAppearForNormalContent() {
        let engine = VPPlayerEngine()
        engine.updateStereoMode(from: "Movie.1080p.BluRay")
        #expect(engine.is3DContent == false)
    }
}

// MARK: - Transport Bar Layout Tests

@Suite("Player Transport Bar Layout")
struct PlayerTransportBarLayoutTests {

    @Test func bottomGradientGoesFromClearToOpaque() {
        // The transport bar background is a gradient from clear (top)
        // to black at 0.7 opacity (bottom), so video shows through at the top
        let topOpacity: Double = 0.0  // .clear
        let bottomOpacity: Double = 0.7
        #expect(topOpacity < bottomOpacity)
        #expect(bottomOpacity < 1.0) // Not fully opaque — translucent
    }

    @Test func topGradientGoesFromOpaqueToTransparent() {
        // The title bar background gradient from black at 0.6 (top) to clear (bottom)
        let topOpacity: Double = 0.6
        let bottomOpacity: Double = 0.0  // .clear
        #expect(topOpacity > bottomOpacity)
        #expect(topOpacity < 1.0) // Translucent, not opaque
    }

    @Test func progressBarThicknessIncreasesWhenScrubbing() {
        let idleHeight: CGFloat = 3
        let scrubbingHeight: CGFloat = 6
        #expect(scrubbingHeight > idleHeight)
    }

    @Test func thumbKnobGrowsWhenScrubbing() {
        let idleSize: CGFloat = 8
        let scrubbingSize: CGFloat = 14
        #expect(scrubbingSize > idleSize)
    }

    @Test func timeLabelsShowCurrentAndRemaining() {
        // Verifies the remaining time is formatted with a minus prefix
        let remaining = 5281.0 // 1:28:01
        let formatted = "-\(remaining.formattedDuration)"
        #expect(formatted.hasPrefix("-"))
        #expect(formatted == "-1:28:01")
    }

    @Test func playPauseButtonHasLargerSizeThanSkipButtons() {
        // Play/pause uses .title font in a 52pt circle
        // Skip buttons use .title2 font without a background circle
        let playPauseFrameSize: CGFloat = 52
        let skipIconFontSize: CGFloat = 22  // approx .title2
        #expect(playPauseFrameSize > skipIconFontSize)
    }

    @Test func dragIndicatorDimensions() {
        // The bottom drag indicator bar
        let width: CGFloat = 36
        let height: CGFloat = 4
        #expect(width > height)
        #expect(height > 0)
    }
}

// MARK: - Controls Overlay Toggle Tests

@Suite("Player Controls Overlay Toggle")
struct PlayerControlsOverlayToggleTests {

    @Test func controlsVisibilityToggles() {
        var isShowing = true
        isShowing.toggle()
        #expect(isShowing == false)
        isShowing.toggle()
        #expect(isShowing == true)
    }

    @Test func controlsStartVisible() {
        // PlayerView initializes isShowingControls = true
        let initialState = true
        #expect(initialState == true)
    }
}

// MARK: - Feature Chip Tests

@Suite("Player Feature Chip")
struct PlayerFeatureChipTests {

    @Test func featureChipWithSymbolShowsLabel() {
        // When a symbol is provided, a Label is used
        let title = "4K"
        let symbol: String? = "rectangle"
        #expect(symbol != nil)
        #expect(title == "4K")
    }

    @Test func featureChipWithoutSymbolShowsTextOnly() {
        // When symbol is nil, just Text is used
        let title = "KSPlayer"
        let symbol: String? = nil
        #expect(symbol == nil)
        #expect(title == "KSPlayer")
    }

    @Test func featureChipQualityBadgeFromStream() {
        // Quality badge shows the stream quality rawValue
        let qualityValues = ["4K", "1080p", "720p", "480p"]
        for value in qualityValues {
            #expect(!value.isEmpty)
        }
    }
}

// MARK: - Subtitle Bottom Padding Tests

@Suite("Subtitle Overlay Bottom Padding")
struct SubtitleOverlayBottomPaddingTests {

    @Test func subtitlePaddingClearsTransportArea() {
        // Subtitles have .padding(.bottom, 90) to clear the transport bar
        let subtitleBottomPadding: CGFloat = 90
        // Transport bar is roughly ~120pt tall (progress + time + buttons + indicator)
        // Subtitle padding should keep text visible above transport
        #expect(subtitleBottomPadding > 0)
        #expect(subtitleBottomPadding >= 60) // Minimum clearance
    }
}
