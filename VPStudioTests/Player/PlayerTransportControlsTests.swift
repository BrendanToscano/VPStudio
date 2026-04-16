import Foundation
import SwiftUI
import Testing
@testable import VPStudio

// MARK: - Buffered Percent Tests

@Suite("VPPlayerEngine - Buffered Percent")
struct BufferedPercentTests {

    @Test @MainActor func defaultBufferedPercentIsZero() {
        let engine = VPPlayerEngine()
        #expect(engine.bufferedPercent == 0)
    }

    @Test @MainActor func bufferedPercentAcceptsValidValues() {
        let engine = VPPlayerEngine()
        engine.bufferedPercent = 0.5
        #expect(engine.bufferedPercent == 0.5)
    }

    @Test @MainActor func bufferedPercentCanReachOne() {
        let engine = VPPlayerEngine()
        engine.bufferedPercent = 1.0
        #expect(engine.bufferedPercent == 1.0)
    }

    @Test @MainActor func bufferedPercentPreservesAfterTimeUpdate() {
        let engine = VPPlayerEngine()
        engine.bufferedPercent = 0.7
        engine.currentTime = 100
        engine.duration = 200
        #expect(engine.bufferedPercent == 0.7)
    }
}

// MARK: - Chapter Title in Top Info Bar

@Suite("VPPlayerEngine - Chapter at Current Time")
struct ChapterCurrentTimeTests {

    private static let sampleChapters: [VPPlayerEngine.ChapterInfo] = [
        .init(id: 0, title: "Intro", startTime: 0, endTime: 30),
        .init(id: 1, title: "Main Feature", startTime: 30, endTime: 300),
        .init(id: 2, title: "Credits", startTime: 300, endTime: 360),
    ]

    @Test @MainActor func chapterTitleAtStartShowsIntro() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        engine.currentTime = 5
        let chapter = engine.currentChapter(at: engine.currentTime)
        #expect(chapter?.title == "Intro")
    }

    @Test @MainActor func chapterTitleMidwayShowsMainFeature() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        engine.currentTime = 150
        let chapter = engine.currentChapter(at: engine.currentTime)
        #expect(chapter?.title == "Main Feature")
    }

    @Test @MainActor func chapterTitleNearEndShowsCredits() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        engine.currentTime = 330
        let chapter = engine.currentChapter(at: engine.currentTime)
        #expect(chapter?.title == "Credits")
    }

    @Test @MainActor func noChapterTitleWhenNoChaptersLoaded() {
        let engine = VPPlayerEngine()
        engine.currentTime = 50
        #expect(engine.currentChapter(at: engine.currentTime) == nil)
    }

    @Test @MainActor func chapterBoundaryReturnsNewChapter() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        // Exactly at boundary of chapter 1
        let chapter = engine.currentChapter(at: 30)
        #expect(chapter?.title == "Main Feature")
    }
}

// MARK: - Chapter Tick Position Calculation

@Suite("Chapter Tick Position Math")
struct ChapterTickPositionTests {

    @Test func tickPositionIsProportionalToStartTime() {
        let barWidth: Double = 800
        let duration: Double = 1000
        let chapterStart: Double = 250

        let tickX = barWidth * (chapterStart / duration)
        #expect(abs(tickX - 200) < 0.001)
    }

    @Test func tickPositionAtZeroIsZero() {
        let barWidth: Double = 800
        let duration: Double = 1000

        let tickX = barWidth * (0.0 / duration)
        #expect(tickX == 0)
    }

    @Test func tickPositionAtEndMatchesBarWidth() {
        let barWidth: Double = 800
        let duration: Double = 1000

        let tickX = barWidth * (1000.0 / duration)
        #expect(abs(tickX - 800) < 0.001)
    }

    @Test func multipleTicksAreMonotonicallyIncreasing() {
        let barWidth: Double = 600
        let duration: Double = 900
        let starts: [Double] = [0, 60, 300, 600]

        var prevX: Double = -1
        for start in starts {
            let tickX = barWidth * (start / duration)
            #expect(tickX > prevX)
            prevX = tickX
        }
    }
}

// MARK: - Scrub Percent Clamping

@Suite("Scrub Percent Clamping")
struct ScrubPercentClampingTests {

    private func clampedPercent(_ locationX: Double, barWidth: Double) -> Double {
        max(0, min(1, locationX / max(barWidth, 1)))
    }

    @Test func normalScrubValueIsClamped() {
        let result = clampedPercent(400, barWidth: 800)
        #expect(abs(result - 0.5) < 0.001)
    }

    @Test func scrubBeyondRightEdgeClampedToOne() {
        let result = clampedPercent(900, barWidth: 800)
        #expect(result == 1.0)
    }

    @Test func scrubBeyondLeftEdgeClampedToZero() {
        let result = clampedPercent(-50, barWidth: 800)
        #expect(result == 0.0)
    }

    @Test func zeroBarWidthDoesNotDivideByZero() {
        let result = clampedPercent(100, barWidth: 0)
        #expect(result <= 1.0)
        #expect(result >= 0.0)
    }

    @Test func scrubTimeFromPercent() {
        let duration: Double = 7200
        let percent = 0.25
        let scrubTime = duration * percent
        #expect(abs(scrubTime - 1800) < 0.001)
    }

    @Test func scrubTimeAtBoundaries() {
        let duration: Double = 3600
        #expect(duration * 0.0 == 0)
        #expect(duration * 1.0 == 3600)
    }
}

// MARK: - Playback State Overlay Logic

@Suite("Startup Overlay State Logic")
struct StartupOverlayStateTests {

    /// Simulates the overlay decision logic from PlayerView
    private enum OverlayKind: Equatable {
        case failure
        case loadingOverlay
        case inlineRebuffer
        case none
    }

    private func overlayKind(
        playbackState: PlayerPlaybackState,
        hasPlayedOnce: Bool
    ) -> OverlayKind {
        if playbackState == .failed {
            return .failure
        } else if playbackState != .playing && !hasPlayedOnce {
            return .loadingOverlay
        } else if playbackState == .buffering && hasPlayedOnce {
            return .inlineRebuffer
        }
        return .none
    }

    @Test func preparingBeforeFirstPlayShowsLoadingOverlay() {
        #expect(overlayKind(playbackState: .preparing, hasPlayedOnce: false) == .loadingOverlay)
    }

    @Test func bufferingBeforeFirstPlayShowsLoadingOverlay() {
        #expect(overlayKind(playbackState: .buffering, hasPlayedOnce: false) == .loadingOverlay)
    }

    @Test func playingShowsNothing() {
        #expect(overlayKind(playbackState: .playing, hasPlayedOnce: true) == .none)
    }

    @Test func playingFirstTimeShowsNothing() {
        #expect(overlayKind(playbackState: .playing, hasPlayedOnce: false) == .none)
    }

    @Test func rebufferAfterPlayShowsInline() {
        #expect(overlayKind(playbackState: .buffering, hasPlayedOnce: true) == .inlineRebuffer)
    }

    @Test func failureAlwaysShowsFailure() {
        #expect(overlayKind(playbackState: .failed, hasPlayedOnce: false) == .failure)
        #expect(overlayKind(playbackState: .failed, hasPlayedOnce: true) == .failure)
    }

    @Test func preparingAfterPreviousPlayShowsNothing() {
        // After first play, preparing again (stream switch) but hasPlayedOnce is true
        // This shows neither loading nor inline — the preparePlayback resets hasPlayedOnce
        #expect(overlayKind(playbackState: .preparing, hasPlayedOnce: true) == .none)
    }
}

// MARK: - Controls Auto-Hide Guard Logic

@Suite("Controls Auto-Hide Guards")
struct ControlsAutoHideGuardTests {

    private func shouldHideControls(
        playbackState: PlayerPlaybackState,
        isScrubbing: Bool,
        isShowingSubtitlePicker: Bool,
        isShowingAudioPicker: Bool
    ) -> Bool {
        guard playbackState == .playing else { return false }
        guard !isScrubbing else { return false }
        guard !isShowingSubtitlePicker && !isShowingAudioPicker else { return false }
        return true
    }

    @Test func hidesWhenPlayingNormally() {
        #expect(shouldHideControls(
            playbackState: .playing,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false
        ) == true)
    }

    @Test func doesNotHideDuringScrubbing() {
        #expect(shouldHideControls(
            playbackState: .playing,
            isScrubbing: true,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false
        ) == false)
    }

    @Test func doesNotHideWhenSubtitlePickerOpen() {
        #expect(shouldHideControls(
            playbackState: .playing,
            isScrubbing: false,
            isShowingSubtitlePicker: true,
            isShowingAudioPicker: false
        ) == false)
    }

    @Test func doesNotHideWhenAudioPickerOpen() {
        #expect(shouldHideControls(
            playbackState: .playing,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: true
        ) == false)
    }

    @Test func doesNotHideWhenNotPlaying() {
        #expect(shouldHideControls(
            playbackState: .buffering,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false
        ) == false)
    }

    @Test func doesNotHideWhenPreparing() {
        #expect(shouldHideControls(
            playbackState: .preparing,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false
        ) == false)
    }

    @Test func doesNotHideWithMultipleBlockers() {
        #expect(shouldHideControls(
            playbackState: .playing,
            isScrubbing: true,
            isShowingSubtitlePicker: true,
            isShowingAudioPicker: true
        ) == false)
    }
}

// MARK: - Engine State for Transport Display

@Suite("VPPlayerEngine - Transport Display State")
struct EngineTransportDisplayTests {

    @Test @MainActor func progressPercentWithBufferedRange() {
        let engine = VPPlayerEngine()
        engine.duration = 100
        engine.currentTime = 25
        engine.bufferedPercent = 0.6

        #expect(abs(engine.progressPercent - 0.25) < 0.001)
        #expect(engine.bufferedPercent == 0.6)
        // Buffered should always be >= progress in practice
        #expect(engine.bufferedPercent >= engine.progressPercent)
    }

    @Test @MainActor func chapterSkipButtonsShouldAppearWhenChaptersLoaded() {
        let engine = VPPlayerEngine()
        #expect(engine.chapters.isEmpty)

        engine.loadChapters([
            .init(id: 0, title: "A", startTime: 0, endTime: 50),
            .init(id: 1, title: "B", startTime: 50, endTime: 100),
        ])
        #expect(!engine.chapters.isEmpty)
    }

    @Test @MainActor func is3DContentDrivesGlassTagVisibility() {
        let engine = VPPlayerEngine()
        #expect(!engine.is3DContent)

        engine.updateStereoMode(from: "Movie.SBS.1080p")
        #expect(engine.is3DContent)
    }

    @Test @MainActor func currentTitlePropertySetAndRead() {
        let engine = VPPlayerEngine()
        #expect(engine.currentTitle == nil)

        engine.currentTitle = "Test Movie"
        #expect(engine.currentTitle == "Test Movie")
    }
}

// MARK: - Transport Environment Control Policy

@Suite("Player Transport Controls - Environment Placement Policy")
struct PlayerTransportControlsPolicyTests {

    @Test func defaultsToLeftNavigationOnly() {
        #expect(PlayerTransportControlsPolicy.showsRightTransportEnvironmentControl() == false)
    }

    @Test func leftNavigationPlacementHidesRightTransportControl() {
        #expect(PlayerTransportControlsPolicy.showsRightTransportEnvironmentControl(
            placement: .leftNavigation
        ) == false)
    }

    @Test func rightTransportPlacementShowsRightTransportControl() {
        #expect(PlayerTransportControlsPolicy.showsRightTransportEnvironmentControl(
            placement: .rightTransportControls
        ) == true)
    }
}

// MARK: - Play/Pause Control Presentation Mapping

@Suite("Player Transport Controls - Play/Pause Presentation")
struct PlayerPlayPauseControlPresentationTests {

    @Test func mapsPlayingToPausePresentation() {
        let presentation = PlayerControlPresentationMapper.playPause(for: .playing)

        #expect(presentation.symbolName == "pause.fill")
        #expect(presentation.label == "Pause")
        #expect(presentation.accessibilityValue == "Playing")
    }

    @Test func mapsPausedToPlayPresentation() {
        let presentation = PlayerControlPresentationMapper.playPause(for: .paused)

        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.label == "Play")
        #expect(presentation.accessibilityValue == "Paused")
    }

    @Test func mapsBufferingToPlayPresentationWithBufferingAccessibilityValue() {
        let presentation = PlayerControlPresentationMapper.playPause(for: .buffering)

        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.label == "Play")
        #expect(presentation.accessibilityValue == "Buffering")
    }

    @Test func mapsPreparingToPlayPresentationWithPreparingAccessibilityValue() {
        let presentation = PlayerControlPresentationMapper.playPause(for: .preparing)

        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.label == "Play")
        #expect(presentation.accessibilityValue == "Preparing")
    }

    @Test func mapsFailedToPlayPresentationWithFailedAccessibilityValue() {
        let presentation = PlayerControlPresentationMapper.playPause(for: .failed)

        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.label == "Play")
        #expect(presentation.accessibilityValue == "Failed")
    }

    @Test func derivesPlayingStateFromPlaybackStateWhenCurrentlyPlaying() {
        let state = PlayerPlayPauseControlState.from(
            playbackState: .playing,
            isCurrentlyPlaying: true
        )
        let presentation = PlayerControlPresentationMapper.playPause(
            playbackState: .playing,
            isCurrentlyPlaying: true
        )

        #expect(state == .playing)
        #expect(presentation.symbolName == "pause.fill")
        #expect(presentation.label == "Pause")
        #expect(presentation.accessibilityValue == "Playing")
    }

    @Test func derivesPausedStateFromPlaybackStateWhenNotCurrentlyPlaying() {
        let state = PlayerPlayPauseControlState.from(
            playbackState: .playing,
            isCurrentlyPlaying: false
        )
        let presentation = PlayerControlPresentationMapper.playPause(
            playbackState: .playing,
            isCurrentlyPlaying: false
        )

        #expect(state == .paused)
        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.label == "Play")
        #expect(presentation.accessibilityValue == "Paused")
    }

    @Test func preservesNonPlayingPlaybackStatesWhenDerivingControlState() {
        #expect(PlayerPlayPauseControlState.from(
            playbackState: .preparing,
            isCurrentlyPlaying: true
        ) == .preparing)

        #expect(PlayerPlayPauseControlState.from(
            playbackState: .buffering,
            isCurrentlyPlaying: true
        ) == .buffering)

        #expect(PlayerPlayPauseControlState.from(
            playbackState: .failed,
            isCurrentlyPlaying: true
        ) == .failed)
    }
}

// MARK: - Cinematic Chrome Layout Policy

@Suite("Player Cinematic Chrome Policy")
struct PlayerCinematicChromePolicyTests {

    @Test func primaryTransportButtonUsesDesignToken() {
        #expect(PlayerCinematicChromePolicy.primaryTransportButtonSize == 56)
    }

    @Test func controlsDockLayoutTokensStayStable() {
        #expect(PlayerCinematicChromePolicy.controlsDockMaxWidth == 860)
        #expect(PlayerCinematicChromePolicy.quickActionsMaxWidth == 640)
        #expect(PlayerCinematicChromePolicy.transportCardMaxWidth == 780)
        #expect(PlayerCinematicChromePolicy.controlsDockSpacing == 8)
        #expect(PlayerCinematicChromePolicy.controlsDockHorizontalPadding == 18)
        #expect(PlayerCinematicChromePolicy.controlsDockBottomPadding == 18)
        #expect(PlayerCinematicChromePolicy.transportCardHorizontalPadding == 20)
        #expect(PlayerCinematicChromePolicy.transportCardVerticalPadding == 12)
    }

    @Test func transportButtonAndProgressTokensStayStable() {
        #expect(PlayerCinematicChromePolicy.topBarButtonSize == 42)
        #expect(PlayerCinematicChromePolicy.secondaryTransportButtonSize == 48)
        #expect(PlayerCinematicChromePolicy.progressBarIdleHeight == 4)
        #expect(PlayerCinematicChromePolicy.progressBarScrubbingHeight == 8)
    }
}

// MARK: - Cinematic Visual Policy

@Suite("Player Cinematic Visual Policy")
struct PlayerCinematicVisualPolicyTests {

    @Test func topBarSymbolsUseModernIconSet() {
        #expect(PlayerCinematicVisualPolicy.backSymbolName == "chevron.left")
        #expect(PlayerCinematicVisualPolicy.menuSymbolName == "ellipsis")
    }

    @Test func quickActionSymbolsUseFilledVariants() {
        #expect(PlayerCinematicVisualPolicy.subtitlesSymbolName == "captions.bubble.fill")
        #expect(PlayerCinematicVisualPolicy.audioSymbolName == "speaker.wave.2.fill")
        #expect(PlayerCinematicVisualPolicy.qualitySymbolName == "line.3.horizontal.decrease.circle.fill")
        #expect(PlayerCinematicVisualPolicy.streamListSymbolName == "rectangle.stack.badge.play.fill")
    }

    @Test func chapterSymbolsUseModernCircularVariants() {
        #expect(PlayerCinematicVisualPolicy.previousChapterSymbolName == "backward.end.fill")
        #expect(PlayerCinematicVisualPolicy.nextChapterSymbolName == "forward.end.fill")
    }

    @Test func iconSurfaceOpacityTokensStayWithinAccessibleRange() {
        #expect(PlayerCinematicVisualPolicy.iconSurfaceBorderOpacity > 0.25)
        #expect(PlayerCinematicVisualPolicy.iconSurfaceHighlightOpacity > 0.20)
        #expect(PlayerCinematicVisualPolicy.iconSurfaceShadowOpacity >= 0.40)
    }

    @Test func progressOpacityTokensStayWithinVisibleRange() {
        #expect(PlayerCinematicVisualPolicy.progressTrackOpacity >= 0.18)
        #expect(PlayerCinematicVisualPolicy.progressBufferedOpacity > PlayerCinematicVisualPolicy.progressTrackOpacity)
        #expect(PlayerCinematicVisualPolicy.timeLabelOpacity >= 0.74)
    }

    @Test func scrimTokensStayBalanced() {
        #expect(PlayerCinematicVisualPolicy.topScrimOpacity >= 0.25)
        #expect(PlayerCinematicVisualPolicy.bottomScrimOpacity <= 0.35)
    }
}
