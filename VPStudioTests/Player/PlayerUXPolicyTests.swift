import Foundation
import Testing
@testable import VPStudio

// MARK: - PlayerScrubPolicy Tests

@Suite("PlayerScrubPolicy")
struct PlayerScrubPolicyTests {

    // MARK: Chapter Snap Distance

    @Test func chapterSnapDistanceClampedToMinimum() {
        // Very short content: proportional distance would be tiny
        let distance = PlayerScrubPolicy.chapterSnapDistance(duration: 10)
        #expect(distance == PlayerScrubPolicy.chapterSnapMinimumSeconds)
    }

    @Test func chapterSnapDistanceClampedToMaximum() {
        // Very long content: proportional distance would be huge
        let distance = PlayerScrubPolicy.chapterSnapDistance(duration: 100_000)
        #expect(distance == PlayerScrubPolicy.chapterSnapMaximumSeconds)
    }

    @Test func chapterSnapDistanceProportionalForMediumContent() {
        // 1 hour: 3600 * 0.008 = 28.8 -> clamped to max 12
        let distance = PlayerScrubPolicy.chapterSnapDistance(duration: 3600)
        #expect(distance <= PlayerScrubPolicy.chapterSnapMaximumSeconds)
        #expect(distance >= PlayerScrubPolicy.chapterSnapMinimumSeconds)
    }

    @Test func chapterSnapDistanceZeroDurationReturnsMinimum() {
        let distance = PlayerScrubPolicy.chapterSnapDistance(duration: 0)
        #expect(distance == PlayerScrubPolicy.chapterSnapMinimumSeconds)
    }

    // MARK: Nearest Chapter Snap

    @Test func nearestChapterSnapReturnsNilWhenFarFromBoundary() {
        let chapters = [
            PlayerScrubPolicy.ChapterBoundary(startTime: 60, title: "Ch1"),
            PlayerScrubPolicy.ChapterBoundary(startTime: 120, title: "Ch2"),
        ]
        let result = PlayerScrubPolicy.nearestChapterSnap(
            scrubTime: 90, chapters: chapters, duration: 200
        )
        #expect(result == nil)
    }

    @Test func nearestChapterSnapReturnsTimeWhenClose() {
        let chapters = [
            PlayerScrubPolicy.ChapterBoundary(startTime: 60, title: "Ch1"),
            PlayerScrubPolicy.ChapterBoundary(startTime: 120, title: "Ch2"),
        ]
        // scrubTime = 61 is within snap distance of chapter at 60
        let result = PlayerScrubPolicy.nearestChapterSnap(
            scrubTime: 61, chapters: chapters, duration: 200
        )
        #expect(result == 60)
    }

    @Test func nearestChapterSnapSkipsZeroStartTime() {
        let chapters = [
            PlayerScrubPolicy.ChapterBoundary(startTime: 0, title: "Start"),
            PlayerScrubPolicy.ChapterBoundary(startTime: 100, title: "Ch1"),
        ]
        // Scrubbing near 0 should NOT snap to the zero-time chapter
        let result = PlayerScrubPolicy.nearestChapterSnap(
            scrubTime: 1, chapters: chapters, duration: 200
        )
        #expect(result == nil)
    }

    @Test func nearestChapterSnapReturnsNilForEmptyChapters() {
        let result = PlayerScrubPolicy.nearestChapterSnap(
            scrubTime: 50, chapters: [], duration: 200
        )
        #expect(result == nil)
    }

    @Test func nearestChapterSnapReturnsNilForZeroDuration() {
        let chapters = [
            PlayerScrubPolicy.ChapterBoundary(startTime: 60, title: "Ch1"),
        ]
        let result = PlayerScrubPolicy.nearestChapterSnap(
            scrubTime: 60, chapters: chapters, duration: 0
        )
        #expect(result == nil)
    }

    // MARK: Fine vs Coarse Scrubbing

    @Test func fineScrubAtSlowVelocity() {
        let delta = PlayerScrubPolicy.scrubPercentDelta(
            translationX: 100, velocityX: 30, barWidth: 1000
        )
        // Should be scaled down by fineScrubScale (0.25)
        #expect(abs(delta - 0.025) < 0.001)
    }

    @Test func coarseScrubAtFastVelocity() {
        let delta = PlayerScrubPolicy.scrubPercentDelta(
            translationX: 100, velocityX: 200, barWidth: 1000
        )
        // Should be full 1:1 ratio
        #expect(abs(delta - 0.1) < 0.001)
    }

    @Test func scrubPercentDeltaZeroBarWidth() {
        let delta = PlayerScrubPolicy.scrubPercentDelta(
            translationX: 100, velocityX: 200, barWidth: 0
        )
        #expect(delta == 0)
    }

    @Test func scrubPercentDeltaNegativeTranslation() {
        let delta = PlayerScrubPolicy.scrubPercentDelta(
            translationX: -50, velocityX: 200, barWidth: 1000
        )
        #expect(delta < 0)
        #expect(abs(delta - (-0.05)) < 0.001)
    }

    // MARK: Preview Label

    @Test func previewLabelFormatsCorrectly() {
        #expect(PlayerScrubPolicy.previewLabel(for: 3661) == "1:01:01")
        #expect(PlayerScrubPolicy.previewLabel(for: 90) == "1:30")
        #expect(PlayerScrubPolicy.previewLabel(for: 0) == "0:00")
    }

    // MARK: Preview Chapter Title

    @Test func previewChapterTitleReturnsCorrectChapter() {
        let chapters = [
            PlayerScrubPolicy.ChapterBoundary(startTime: 0, title: "Intro"),
            PlayerScrubPolicy.ChapterBoundary(startTime: 60, title: "Main"),
            PlayerScrubPolicy.ChapterBoundary(startTime: 300, title: "Credits"),
        ]
        #expect(PlayerScrubPolicy.previewChapterTitle(at: 30, chapters: chapters) == "Intro")
        #expect(PlayerScrubPolicy.previewChapterTitle(at: 120, chapters: chapters) == "Main")
        #expect(PlayerScrubPolicy.previewChapterTitle(at: 350, chapters: chapters) == "Credits")
    }

    @Test func previewChapterTitleReturnsNilBeforeFirstChapter() {
        let chapters = [
            PlayerScrubPolicy.ChapterBoundary(startTime: 60, title: "Ch1"),
        ]
        #expect(PlayerScrubPolicy.previewChapterTitle(at: 30, chapters: chapters) == nil)
    }

    @Test func previewChapterTitleReturnsNilForEmptyChapters() {
        #expect(PlayerScrubPolicy.previewChapterTitle(at: 30, chapters: []) == nil)
    }
}

// MARK: - PlayerGesturePolicy Tests

@Suite("PlayerGesturePolicy")
struct PlayerGesturePolicyTests {

    // MARK: Double-Tap Seek Offset

    @Test func doubleTapLeftZoneReturnsBackwardOffset() {
        let offset = PlayerGesturePolicy.doubleTapSeekOffset(
            tapX: 50, surfaceWidth: 1000
        )
        #expect(offset == PlayerGesturePolicy.doubleTapSeekBackSeconds)
    }

    @Test func doubleTapRightZoneReturnsForwardOffset() {
        let offset = PlayerGesturePolicy.doubleTapSeekOffset(
            tapX: 950, surfaceWidth: 1000
        )
        #expect(offset == PlayerGesturePolicy.doubleTapSeekForwardSeconds)
    }

    @Test func doubleTapCenterReturnsNil() {
        let offset = PlayerGesturePolicy.doubleTapSeekOffset(
            tapX: 500, surfaceWidth: 1000
        )
        #expect(offset == nil)
    }

    @Test func doubleTapAtLeftBoundary() {
        // Exactly at the left zone boundary
        let boundary = 1000 * PlayerGesturePolicy.doubleTapZoneFraction
        let offset = PlayerGesturePolicy.doubleTapSeekOffset(
            tapX: boundary, surfaceWidth: 1000
        )
        #expect(offset == PlayerGesturePolicy.doubleTapSeekBackSeconds)
    }

    @Test func doubleTapJustPastLeftBoundary() {
        let boundary = 1000 * PlayerGesturePolicy.doubleTapZoneFraction + 1
        let offset = PlayerGesturePolicy.doubleTapSeekOffset(
            tapX: boundary, surfaceWidth: 1000
        )
        #expect(offset == nil) // In center dead zone
    }

    @Test func doubleTapZeroWidthReturnsNil() {
        let offset = PlayerGesturePolicy.doubleTapSeekOffset(
            tapX: 50, surfaceWidth: 0
        )
        #expect(offset == nil)
    }

    // MARK: Seek Direction

    @Test func seekDirectionForNegativeOffset() {
        #expect(PlayerGesturePolicy.seekDirection(for: -10) == .backward)
    }

    @Test func seekDirectionForPositiveOffset() {
        #expect(PlayerGesturePolicy.seekDirection(for: 30) == .forward)
    }

    @Test func seekDirectionForZero() {
        #expect(PlayerGesturePolicy.seekDirection(for: 0) == .forward)
    }

    // MARK: Zone Fraction

    @Test func doubleTapZoneFractionIsReasonable() {
        // Zones should cover less than half the width on each side
        #expect(PlayerGesturePolicy.doubleTapZoneFraction > 0)
        #expect(PlayerGesturePolicy.doubleTapZoneFraction < 0.5)
    }

    @Test func leftAndRightZonesDoNotOverlap() {
        let leftEnd = PlayerGesturePolicy.doubleTapZoneFraction
        let rightStart = 1 - PlayerGesturePolicy.doubleTapZoneFraction
        #expect(leftEnd < rightStart)
    }
}

// MARK: - PlayerBufferingPolicy Tests

@Suite("PlayerBufferingPolicy")
struct PlayerBufferingPolicyTests {

    // MARK: Rebuffer Text

    @Test func rebufferTextWithValidPercent() {
        let text = PlayerBufferingPolicy.rebufferText(bufferedPercent: 0.6)
        #expect(text == "Buffering... 60%")
    }

    @Test func rebufferTextWithZeroPercent() {
        let text = PlayerBufferingPolicy.rebufferText(bufferedPercent: 0)
        #expect(text == "Rebuffering\u{2026}")
    }

    @Test func rebufferTextWithFullBuffer() {
        let text = PlayerBufferingPolicy.rebufferText(bufferedPercent: 1.0)
        #expect(text == "Rebuffering\u{2026}")
    }

    @Test func rebufferTextWithSmallPercent() {
        let text = PlayerBufferingPolicy.rebufferText(bufferedPercent: 0.01)
        #expect(text == "Buffering... 1%")
    }

    @Test func rebufferTextRoundsDown() {
        let text = PlayerBufferingPolicy.rebufferText(bufferedPercent: 0.999)
        #expect(text == "Buffering... 99%")
    }

    // MARK: Quality Change Message

    @Test func qualityChangeMessageDifferentQualities() {
        let message = PlayerBufferingPolicy.qualityChangeMessage(from: "1080p", to: "4K")
        #expect(message == "Quality: 1080p \u{2192} 4K")
    }

    @Test func qualityChangeMessageSameQuality() {
        let message = PlayerBufferingPolicy.qualityChangeMessage(from: "1080p", to: "1080p")
        #expect(message == nil)
    }

    @Test func qualityChangeMessageEmptyStrings() {
        let message = PlayerBufferingPolicy.qualityChangeMessage(from: "", to: "720p")
        #expect(message != nil)
        #expect(message!.contains("720p"))
    }

    // MARK: Toast Duration

    @Test func qualityToastDurationIsPositive() {
        #expect(PlayerBufferingPolicy.qualityToastDuration > 0)
    }

    // MARK: Controls Lock

    @Test func showsControlsLockIsTrue() {
        #expect(PlayerBufferingPolicy.showsControlsLock == true)
    }
}

// MARK: - PlayerControlVisibilityPolicy Tests

@Suite("PlayerControlVisibilityPolicy")
struct PlayerControlVisibilityPolicyTests {

    // MARK: Timing Constants

    @Test func autoHideDelayIsPositive() {
        #expect(PlayerControlVisibilityPolicy.autoHideDelay > 0)
    }

    @Test func fadeOutDurationIsPositive() {
        #expect(PlayerControlVisibilityPolicy.fadeOutDuration > 0)
    }

    @Test func fadeInDurationIsPositive() {
        #expect(PlayerControlVisibilityPolicy.fadeInDuration > 0)
    }

    @Test func fadeInFasterThanFadeOut() {
        // Controls should appear quickly but fade out more slowly
        #expect(PlayerControlVisibilityPolicy.fadeInDuration <= PlayerControlVisibilityPolicy.fadeOutDuration)
    }

    // MARK: Auto-Hide Guards

    @Test func shouldAutoHideWhenPlayingNormally() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ) == true)
    }

    @Test func shouldNotAutoHideWhenPaused() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: false,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ) == false)
    }

    @Test func shouldNotAutoHideDuringScrubbing() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: true,
            isScrubbing: true,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ) == false)
    }

    @Test func shouldNotAutoHideWhenSubtitlePickerOpen() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: true,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ) == false)
    }

    @Test func shouldNotAutoHideWhenAudioPickerOpen() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: true,
            isControlsLocked: false
        ) == false)
    }

    @Test func shouldNotAutoHideWhenControlsLocked() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: true
        ) == false)
    }

    @Test func shouldNotAutoHideWhenNotPlaying() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .buffering,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ) == false)
    }

    @Test func shouldNotAutoHideWhenPreparing() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .preparing,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ) == false)
    }

    @Test func shouldNotAutoHideWhenFailed() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .failed,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ) == false)
    }

    @Test func shouldNotAutoHideWithMultipleBlockers() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: true,
            isScrubbing: true,
            isShowingSubtitlePicker: true,
            isShowingAudioPicker: true,
            isControlsLocked: true
        ) == false)
    }

    // MARK: Reappear Triggers

    @Test func allTriggersAreValid() {
        for trigger in PlayerControlVisibilityPolicy.ReappearTrigger.allCases {
            #expect(PlayerControlVisibilityPolicy.shouldReappear(for: trigger) == true)
        }
    }

    @Test func tapTriggerShowsControls() {
        #expect(PlayerControlVisibilityPolicy.shouldReappear(for: .tap) == true)
    }

    @Test func pointerMovementTriggerShowsControls() {
        #expect(PlayerControlVisibilityPolicy.shouldReappear(for: .pointerMovement) == true)
    }

    @Test func seekActionTriggerShowsControls() {
        #expect(PlayerControlVisibilityPolicy.shouldReappear(for: .seekAction) == true)
    }
}

// MARK: - PlayerControlPresentationMapper Extended Tests

@Suite("PlayerControlPresentationMapper - Play/Pause State Mapping")
struct PlayerControlPresentationMapperExtendedTests {

    @Test func playingStateMapsToPlayPauseIcon() {
        let presentation = PlayerControlPresentationMapper.playPause(
            playbackState: .playing,
            isCurrentlyPlaying: true
        )
        #expect(presentation.symbolName == "pause.fill")
        #expect(presentation.label == "Pause")
        #expect(presentation.accessibilityValue == "Playing")
    }

    @Test func pausedStateMapsToPlayIcon() {
        let presentation = PlayerControlPresentationMapper.playPause(
            playbackState: .playing,
            isCurrentlyPlaying: false
        )
        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.label == "Play")
        #expect(presentation.accessibilityValue == "Paused")
    }

    @Test func bufferingStateMapsToPlayIcon() {
        let presentation = PlayerControlPresentationMapper.playPause(
            playbackState: .buffering,
            isCurrentlyPlaying: false
        )
        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.accessibilityValue == "Buffering")
    }

    @Test func preparingStateMapsToPlayIcon() {
        let presentation = PlayerControlPresentationMapper.playPause(
            playbackState: .preparing,
            isCurrentlyPlaying: false
        )
        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.accessibilityValue == "Preparing")
    }

    @Test func failedStateMapsToPlayIcon() {
        let presentation = PlayerControlPresentationMapper.playPause(
            playbackState: .failed,
            isCurrentlyPlaying: false
        )
        #expect(presentation.symbolName == "play.fill")
        #expect(presentation.accessibilityValue == "Failed")
    }
}
