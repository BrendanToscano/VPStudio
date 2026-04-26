import Foundation
import Testing
@testable import VPStudio

@Suite("Player Policy Regression Coverage")
struct PlayerPolicyRegressionTests {
    @Test func playerViewPolicyTitlesCoverEveryPlaybackState() {
        #expect(PlayerViewPolicy.playbackStateTitle(for: .preparing) == "Preparing Playback")
        #expect(PlayerViewPolicy.playbackStateTitle(for: .buffering) == "Buffering")
        #expect(PlayerViewPolicy.playbackStateTitle(for: .playing) == "Playing")
        #expect(PlayerViewPolicy.playbackStateTitle(for: .failed) == "Playback Failed")
    }

    @Test func playerViewPolicyRejectsStaleAsyncMutations() {
        let activePreparationID = UUID()
        let stalePreparationID = UUID()

        #expect(PlayerViewPolicy.preparePlaybackShouldRun(
            requestedPreparationID: activePreparationID,
            activePreparationID: activePreparationID
        ))
        #expect(!PlayerViewPolicy.preparePlaybackShouldRun(
            requestedPreparationID: stalePreparationID,
            activePreparationID: activePreparationID
        ))
        #expect(!PlayerViewPolicy.preparePlaybackShouldRun(
            requestedPreparationID: activePreparationID,
            activePreparationID: nil
        ))
        #expect(PlayerViewPolicy.audioTrackRefreshShouldRun(
            requestedStreamID: "stream-a",
            currentStreamID: "stream-a"
        ))
        #expect(!PlayerViewPolicy.audioTrackRefreshShouldRun(
            requestedStreamID: "stream-a",
            currentStreamID: "stream-b"
        ))
        #expect(!PlayerViewPolicy.audioTrackRefreshShouldRun(
            requestedStreamID: "stream-a",
            currentStreamID: nil
        ))
    }

    @Test func playerViewPolicyClampsAbsoluteRelativeAndPercentSeeks() {
        #expect(PlayerViewPolicy.clampedSeekTarget(time: -5, duration: 120) == 0)
        #expect(PlayerViewPolicy.clampedSeekTarget(time: 80, duration: 120) == 80)
        #expect(PlayerViewPolicy.clampedSeekTarget(time: 240, duration: 120) == 120)

        #expect(PlayerViewPolicy.clampedSeekTarget(currentTime: 15, offset: -30, duration: 120) == 0)
        #expect(PlayerViewPolicy.clampedSeekTarget(currentTime: 15, offset: 30, duration: 120) == 45)
        #expect(PlayerViewPolicy.clampedSeekTarget(currentTime: 115, offset: 30, duration: 120) == 120)

        #expect(PlayerViewPolicy.clampedSeekTarget(percent: -0.5, duration: 200) == 0)
        #expect(PlayerViewPolicy.clampedSeekTarget(percent: 0.25, duration: 200) == 50)
        #expect(PlayerViewPolicy.clampedSeekTarget(percent: 1.5, duration: 200) == 200)
    }

    @Test func playerViewPolicyScrubberAccessibilityUsesLiveOrScrubTime() {
        #expect(PlayerViewPolicy.scrubberAccessibilityValue(
            currentTime: 65,
            duration: 0,
            isScrubbing: false,
            scrubTime: 120
        ) == "1:05")

        #expect(PlayerViewPolicy.scrubberAccessibilityValue(
            currentTime: 65,
            duration: 180,
            isScrubbing: false,
            scrubTime: 120
        ) == "1:05 of 3:00")

        #expect(PlayerViewPolicy.scrubberAccessibilityValue(
            currentTime: 65,
            duration: 180,
            isScrubbing: true,
            scrubTime: 120
        ) == "2:00 of 3:00")
    }

    @Test func playPausePresentationMapsEveryPlaybackState() {
        let preparing = PlayerControlPresentationMapper.playPause(
            playbackState: .preparing,
            isCurrentlyPlaying: false
        )
        let buffering = PlayerControlPresentationMapper.playPause(
            playbackState: .buffering,
            isCurrentlyPlaying: false
        )
        let playing = PlayerControlPresentationMapper.playPause(
            playbackState: .playing,
            isCurrentlyPlaying: true
        )
        let paused = PlayerControlPresentationMapper.playPause(
            playbackState: .playing,
            isCurrentlyPlaying: false
        )
        let failed = PlayerControlPresentationMapper.playPause(
            playbackState: .failed,
            isCurrentlyPlaying: false
        )

        #expect(preparing == PlayerControlPresentation(symbolName: "play.fill", label: "Play", accessibilityValue: "Preparing"))
        #expect(buffering == PlayerControlPresentation(symbolName: "play.fill", label: "Play", accessibilityValue: "Buffering"))
        #expect(playing == PlayerControlPresentation(symbolName: "pause.fill", label: "Pause", accessibilityValue: "Playing"))
        #expect(paused == PlayerControlPresentation(symbolName: "play.fill", label: "Play", accessibilityValue: "Paused"))
        #expect(failed == PlayerControlPresentation(symbolName: "play.fill", label: "Play", accessibilityValue: "Failed"))
    }

    @Test func controlsOnlyAutoHideWhenPlayingAndUnblocked() {
        #expect(PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ))

        #expect(!PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .buffering,
            isPlaying: true,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ))

        #expect(!PlayerControlVisibilityPolicy.shouldAutoHide(
            playbackState: .playing,
            isPlaying: false,
            isScrubbing: false,
            isShowingSubtitlePicker: false,
            isShowingAudioPicker: false,
            isControlsLocked: false
        ))
    }

    @Test func modalPlayerInteractionsBlockAutoHideIndividually() {
        let blockers: [(scrubbing: Bool, subtitles: Bool, audio: Bool, locked: Bool)] = [
            (true, false, false, false),
            (false, true, false, false),
            (false, false, true, false),
            (false, false, false, true),
        ]

        for blocker in blockers {
            #expect(!PlayerControlVisibilityPolicy.shouldAutoHide(
                playbackState: .playing,
                isPlaying: true,
                isScrubbing: blocker.scrubbing,
                isShowingSubtitlePicker: blocker.subtitles,
                isShowingAudioPicker: blocker.audio,
                isControlsLocked: blocker.locked
            ))
        }
    }

    @Test func everyControlReappearTriggerIsEnabled() {
        for trigger in PlayerControlVisibilityPolicy.ReappearTrigger.allCases {
            #expect(PlayerControlVisibilityPolicy.shouldReappear(for: trigger))
        }
    }

    @Test func bufferingTextUsesPercentOnlyForPartialProgress() {
        #expect(PlayerBufferingPolicy.rebufferText(bufferedPercent: 0) == "Rebuffering\u{2026}")
        #expect(PlayerBufferingPolicy.rebufferText(bufferedPercent: 0.004) == "Buffering... 0%")
        #expect(PlayerBufferingPolicy.rebufferText(bufferedPercent: 0.999) == "Buffering... 99%")
        #expect(PlayerBufferingPolicy.rebufferText(bufferedPercent: 1) == "Rebuffering\u{2026}")
        #expect(PlayerBufferingPolicy.rebufferText(bufferedPercent: -0.2) == "Rebuffering\u{2026}")
        #expect(PlayerBufferingPolicy.rebufferText(bufferedPercent: 1.2) == "Rebuffering\u{2026}")
    }

    @Test func qualityToastOnlyAppearsWhenQualityChangesExactly() {
        #expect(PlayerBufferingPolicy.qualityChangeMessage(from: "1080p", to: "4K") == "Quality: 1080p \u{2192} 4K")
        #expect(PlayerBufferingPolicy.qualityChangeMessage(from: "4K", to: "4K") == nil)
        #expect(PlayerBufferingPolicy.qualityChangeMessage(from: "4K", to: "4k") == "Quality: 4K \u{2192} 4k")
        #expect(PlayerBufferingPolicy.qualityToastDuration == 3.0)
        #expect(PlayerBufferingPolicy.showsControlsLock)
    }

    @Test func doubleTapZonesHaveInclusiveOuterBoundariesAndDeadCenter() {
        let width = 1_000.0
        let leftBoundary = width * PlayerGesturePolicy.doubleTapZoneFraction
        let rightBoundary = width * (1 - PlayerGesturePolicy.doubleTapZoneFraction)

        #expect(PlayerGesturePolicy.doubleTapSeekOffset(tapX: leftBoundary, surfaceWidth: width) == -10)
        #expect(PlayerGesturePolicy.doubleTapSeekOffset(tapX: leftBoundary + 0.001, surfaceWidth: width) == nil)
        #expect(PlayerGesturePolicy.doubleTapSeekOffset(tapX: rightBoundary - 0.001, surfaceWidth: width) == nil)
        #expect(PlayerGesturePolicy.doubleTapSeekOffset(tapX: rightBoundary, surfaceWidth: width) == 30)
    }

    @Test func doubleTapRejectsInvalidSurfaceWidths() {
        #expect(PlayerGesturePolicy.doubleTapSeekOffset(tapX: 10, surfaceWidth: 0) == nil)
        #expect(PlayerGesturePolicy.doubleTapSeekOffset(tapX: 10, surfaceWidth: -100) == nil)
    }

    @Test func scrubVelocityThresholdIsExclusiveForFineScrubbing() {
        let slow = PlayerScrubPolicy.scrubPercentDelta(
            translationX: 80,
            velocityX: PlayerScrubPolicy.fineScrubVelocityThreshold - 0.001,
            barWidth: 800
        )
        let threshold = PlayerScrubPolicy.scrubPercentDelta(
            translationX: 80,
            velocityX: PlayerScrubPolicy.fineScrubVelocityThreshold,
            barWidth: 800
        )
        let fastNegative = PlayerScrubPolicy.scrubPercentDelta(
            translationX: -80,
            velocityX: -PlayerScrubPolicy.fineScrubVelocityThreshold,
            barWidth: 800
        )

        #expect(abs(slow - 0.025) < 0.0001)
        #expect(abs(threshold - 0.1) < 0.0001)
        #expect(abs(fastNegative - -0.1) < 0.0001)
    }

    @Test func chapterSnapDistanceUsesExpectedClampBoundaries() {
        let minimumDuration = PlayerScrubPolicy.chapterSnapMinimumSeconds / PlayerScrubPolicy.chapterSnapThresholdFraction
        let maximumDuration = PlayerScrubPolicy.chapterSnapMaximumSeconds / PlayerScrubPolicy.chapterSnapThresholdFraction

        #expect(PlayerScrubPolicy.chapterSnapDistance(duration: minimumDuration - 1) == PlayerScrubPolicy.chapterSnapMinimumSeconds)
        #expect(abs(PlayerScrubPolicy.chapterSnapDistance(duration: minimumDuration + 1) - ((minimumDuration + 1) * PlayerScrubPolicy.chapterSnapThresholdFraction)) < 0.0001)
        #expect(abs(PlayerScrubPolicy.chapterSnapDistance(duration: maximumDuration - 1) - ((maximumDuration - 1) * PlayerScrubPolicy.chapterSnapThresholdFraction)) < 0.0001)
        #expect(PlayerScrubPolicy.chapterSnapDistance(duration: maximumDuration + 1) == PlayerScrubPolicy.chapterSnapMaximumSeconds)
    }
}

@Suite("Player Stream Model Regression Coverage")
struct PlayerStreamModelRegressionTests {
    @Test func streamIdentityIgnoresTokenQueryAndFragment() {
        let expired = Fixtures.stream(
            url: "https://cdn.example.com/movie.mkv?token=expired#old",
            fileName: "movie.mkv"
        )
        let refreshed = Fixtures.stream(
            url: "https://cdn.example.com/movie.mkv?token=fresh#new",
            fileName: "movie.mkv"
        )

        #expect(expired.id == refreshed.id)
    }

    @Test func streamIdentityKeepsDifferentTransportPathsDistinct() {
        let first = Fixtures.stream(
            url: "https://cdn.example.com/path-a/movie.mkv?token=fresh",
            fileName: "movie.mkv"
        )
        let second = Fixtures.stream(
            url: "https://cdn.example.com/path-b/movie.mkv?token=fresh",
            fileName: "movie.mkv"
        )

        #expect(first.id != second.id)
    }

    @Test func streamSizeStringFormatsMegabytesAndGigabytes() {
        let megabytes = Fixtures.stream(sizeBytes: 500 * 1_048_576)
        let gigabytes = Fixtures.stream(sizeBytes: Int64(1.5 * 1_073_741_824))
        let unknown = Fixtures.stream(sizeBytes: nil)

        #expect(megabytes.sizeString == "500 MB")
        #expect(gigabytes.sizeString == "1.5 GB")
        #expect(unknown.sizeString == "")
    }

    @Test func qualityBadgeOmitsUnknownAndSdrParts() {
        let rich = Fixtures.stream(
            quality: .uhd4k,
            codec: .h265,
            audio: .atmos,
            hdr: .dolbyVision
        )
        let unknown = Fixtures.stream(
            quality: .unknown,
            codec: .unknown,
            audio: .unknown,
            hdr: .sdr
        )

        #expect(rich.qualityBadge == "4K / DV / H.265 / Atmos")
        #expect(unknown.qualityBadge == "")
    }

    @Test func recoveryContextNormalizesHashAndOptionalFields() throws {
        let context = try #require(StreamRecoveryContext(
            infoHash: "  ABCDEF  ",
            torrentId: "  torrent-1  ",
            resolvedDebridService: "  realdebrid  ",
            resolvedFileName: "  file.mkv  ",
            resolvedFileSizeBytes: 42
        ))

        #expect(context.infoHash == "abcdef")
        #expect(context.torrentId == "torrent-1")
        #expect(context.resolvedDebridService == "realdebrid")
        #expect(context.resolvedFileName == "file.mkv")
        #expect(context.resolvedFileSizeBytes == 42)
    }

    @Test func recoveryContextRejectsEmptyHashAndNonPositiveResolvedSize() throws {
        #expect(StreamRecoveryContext(infoHash: "   ") == nil)

        let zero = try #require(StreamRecoveryContext(
            infoHash: "abc",
            resolvedFileSizeBytes: 0
        ))
        let negative = try #require(StreamRecoveryContext(
            infoHash: "abc",
            resolvedFileSizeBytes: -1
        ))

        #expect(zero.resolvedFileSizeBytes == nil)
        #expect(negative.resolvedFileSizeBytes == nil)
    }

    @Test func enrichedRecoveryContextPersistsResolvedPlaybackMetadata() throws {
        let original = try #require(StreamRecoveryContext(
            infoHash: "hash",
            preferredService: .realDebrid,
            seasonNumber: 1,
            episodeNumber: 2,
            torrentId: "torrent"
        ))

        let enriched = original.enrichedForDownloadPersistence(
            fileName: "Episode.mkv",
            sizeBytes: 1_234,
            debridService: DebridServiceType.premiumize.rawValue
        )

        #expect(enriched.infoHash == original.infoHash)
        #expect(enriched.preferredService == .realDebrid)
        #expect(enriched.seasonNumber == 1)
        #expect(enriched.episodeNumber == 2)
        #expect(enriched.torrentId == "torrent")
        #expect(enriched.resolvedFileName == "Episode.mkv")
        #expect(enriched.resolvedFileSizeBytes == 1_234)
        #expect(enriched.resolvedDebridService == DebridServiceType.premiumize.rawValue)
    }

    @Test func qaRefreshReplacementTakesPrecedenceOverRecoveryContext() throws {
        let context = try #require(StreamRecoveryContext(infoHash: "hash", preferredService: .realDebrid))
        let freshURL = URL(string: "https://qa.example.com/fresh.mkv?token=1")!
        let stream = Fixtures.stream(
            debridService: "qa-sample",
            recoveryContext: context
        )

        let plan = PlayerStreamLinkRecovery.refreshPlan(
            for: stream,
            priorAttempts: 0,
            qaRefreshURL: freshURL
        )

        guard case let .replace(replacement)? = plan else {
            Issue.record("Expected QA replacement to win over re-resolve context")
            return
        }
        #expect(replacement.streamURL == freshURL)
        #expect(replacement.recoveryContext == context)
    }

    @Test func startupRefreshIsBlockedAfterPriorRefreshAttempt() throws {
        let context = try #require(StreamRecoveryContext(infoHash: "hash", preferredService: .realDebrid))
        let stream = Fixtures.stream(recoveryContext: context)
        let error = PlayerEngineError.initializationFailed(.avPlayer, "HTTP 403: expired token")

        #expect(!PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
            after: error,
            stream: stream,
            priorRefreshAttempts: 1
        ))
    }

    @Test func startupRefreshMatchesInvalidStreamURLForbiddenMessage() throws {
        let context = try #require(StreamRecoveryContext(infoHash: "hash", preferredService: .realDebrid))
        let stream = Fixtures.stream(recoveryContext: context)

        #expect(PlayerStartupFailurePolicy.shouldSkipRemainingEnginesAndRefreshCurrentStream(
            after: PlayerEngineError.invalidStreamURL("Forbidden signed URL"),
            stream: stream,
            priorRefreshAttempts: 0
        ))
    }
}
