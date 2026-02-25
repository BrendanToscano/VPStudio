import Testing
import Foundation
@testable import VPStudio

// MARK: - StereoMode Detection Tests

@Suite("VPPlayerEngine - Stereo Mode Detection")
struct StereoModeDetectionTests {

    @MainActor
    private func detectMode(title: String) -> VPPlayerEngine.StereoMode {
        let engine = VPPlayerEngine()
        engine.updateStereoMode(from: title)
        return engine.stereoMode
    }

    @Test @MainActor func detectsSideBySideFromSBS() {
        #expect(detectMode(title: "Movie.2025.1080p.SBS.BluRay") == .sideBySide)
    }

    @Test @MainActor func detectsSideBySideFromHyphenated() {
        #expect(detectMode(title: "Movie.2025.Side-By-Side.1080p") == .sideBySide)
    }

    @Test @MainActor func detectsSideBySideFromDotSeparated() {
        #expect(detectMode(title: "Movie.2025.Side.By.Side.1080p") == .sideBySide)
    }

    @Test @MainActor func detectsSideBySideFromHalfSBS() {
        #expect(detectMode(title: "Movie.Half-SBS.1080p") == .sideBySide)
    }

    @Test @MainActor func detectsSideBySideFromHSBS() {
        #expect(detectMode(title: "Movie.HSBS.4K") == .sideBySide)
    }

    @Test @MainActor func detectsOverUnderFromOU() {
        #expect(detectMode(title: "Movie.2025.1080p.OU.BluRay") == .overUnder)
    }

    @Test @MainActor func detectsOverUnderFromHyphenated() {
        #expect(detectMode(title: "Movie.Over-Under.1080p") == .overUnder)
    }

    @Test @MainActor func detectsOverUnderFromDotSeparated() {
        #expect(detectMode(title: "Movie.Over.Under.1080p") == .overUnder)
    }

    @Test @MainActor func detectsOverUnderFromHOU() {
        #expect(detectMode(title: "Movie.HOU.4K") == .overUnder)
    }

    @Test @MainActor func detectsOverUnderFromTAB() {
        #expect(detectMode(title: "Movie.TAB.1080p") == .overUnder)
    }

    @Test @MainActor func detectsMVHEVC() {
        #expect(detectMode(title: "Movie.MV-HEVC.2160p") == .mvHevc)
    }

    @Test @MainActor func detectsSpatialAsMVHEVC() {
        #expect(detectMode(title: "Movie.Spatial.Video.2025") == .mvHevc)
    }

    @Test @MainActor func detects180VR() {
        #expect(detectMode(title: "Experience.180.VR.4K") == .sphere180)
    }

    @Test @MainActor func detects180With3D() {
        #expect(detectMode(title: "Experience.180.3D.4K") == .sphere180)
    }

    @Test @MainActor func detects360VR() {
        #expect(detectMode(title: "Experience.360VR.4K") == .sphere360)
    }

    @Test @MainActor func detects360Video() {
        #expect(detectMode(title: "Experience.360 video.4K") == .sphere360)
    }

    @Test @MainActor func detects360Degree() {
        #expect(detectMode(title: "Experience.360\u{00B0}.4K") == .sphere360)
    }

    @Test @MainActor func doesNotClassify360pAs360Video() {
        #expect(detectMode(title: "Movie.360p.DVDRip") == .mono)
    }

    @Test @MainActor func defaultsToMonoForRegularContent() {
        #expect(detectMode(title: "Movie.2025.1080p.BluRay.x265.Atmos") == .mono)
    }

    @Test @MainActor func defaultsToMonoBeforeUpdate() {
        let engine = VPPlayerEngine()
        #expect(engine.stereoMode == .mono)
    }
}

// MARK: - is3DContent Tests

@Suite("VPPlayerEngine - 3D Content Flag")
struct VPPlayerEngine3DContentTests {

    @Test @MainActor func is3DContentTrueForSBS() {
        let engine = VPPlayerEngine()
        engine.updateStereoMode(from: "Movie.SBS.1080p")
        #expect(engine.is3DContent == true)
    }

    @Test @MainActor func is3DContentTrueForOverUnder() {
        let engine = VPPlayerEngine()
        engine.updateStereoMode(from: "Movie.OU.1080p")
        #expect(engine.is3DContent == true)
    }

    @Test @MainActor func is3DContentTrueForMVHEVC() {
        let engine = VPPlayerEngine()
        engine.updateStereoMode(from: "Movie.MV-HEVC.4K")
        #expect(engine.is3DContent == true)
    }

    @Test @MainActor func is3DContentFalseForMono() {
        let engine = VPPlayerEngine()
        engine.updateStereoMode(from: "Movie.1080p.BluRay")
        #expect(engine.is3DContent == false)
    }
}

// MARK: - Format Time Tests

@Suite("VPPlayerEngine - Time Formatting")
struct VPPlayerEngineFormatTimeTests {

    @Test @MainActor func formatsZeroSeconds() {
        let engine = VPPlayerEngine()
        #expect(engine.currentTimeFormatted == "0:00")
    }

    @Test @MainActor func formatsSecondsOnly() {
        let engine = VPPlayerEngine()
        engine.currentTime = 45
        #expect(engine.currentTimeFormatted == "0:45")
    }

    @Test @MainActor func formatsMinutesAndSeconds() {
        let engine = VPPlayerEngine()
        engine.currentTime = 125 // 2:05
        #expect(engine.currentTimeFormatted == "2:05")
    }

    @Test @MainActor func formatsHoursMinutesSeconds() {
        let engine = VPPlayerEngine()
        engine.currentTime = 3661 // 1:01:01
        #expect(engine.currentTimeFormatted == "1:01:01")
    }

    @Test @MainActor func formatsDurationField() {
        let engine = VPPlayerEngine()
        engine.duration = 7200 // 2:00:00
        #expect(engine.durationFormatted == "2:00:00")
    }

    @Test @MainActor func formatsRemainingTime() {
        let engine = VPPlayerEngine()
        engine.currentTime = 3600
        engine.duration = 7200
        #expect(engine.remainingFormatted == "1:00:00")
    }

    @Test @MainActor func remainingDoesNotGoNegative() {
        let engine = VPPlayerEngine()
        engine.currentTime = 8000
        engine.duration = 7200
        #expect(engine.remainingFormatted == "0:00")
    }

    @Test @MainActor func handlesNonFiniteValues() {
        let engine = VPPlayerEngine()
        engine.currentTime = .infinity
        #expect(engine.currentTimeFormatted == "0:00")

        engine.currentTime = .nan
        #expect(engine.currentTimeFormatted == "0:00")
    }

    @Test @MainActor func formatsLargeDurations() {
        let engine = VPPlayerEngine()
        engine.duration = 36000 // 10:00:00
        #expect(engine.durationFormatted == "10:00:00")
    }
}

// MARK: - Progress Percent Tests

@Suite("VPPlayerEngine - Progress Percent")
struct VPPlayerEngineProgressTests {

    @Test @MainActor func progressIsZeroWhenDurationIsZero() {
        let engine = VPPlayerEngine()
        engine.currentTime = 50
        engine.duration = 0
        #expect(engine.progressPercent == 0)
    }

    @Test @MainActor func progressCalculatesCorrectly() {
        let engine = VPPlayerEngine()
        engine.currentTime = 30
        engine.duration = 60
        #expect(abs(engine.progressPercent - 0.5) < 0.001)
    }

    @Test @MainActor func progressAt100Percent() {
        let engine = VPPlayerEngine()
        engine.currentTime = 100
        engine.duration = 100
        #expect(abs(engine.progressPercent - 1.0) < 0.001)
    }
}

// MARK: - Playback Rate Tests

@Suite("VPPlayerEngine - Playback Rate")
struct VPPlayerEngineRateTests {

    @Test @MainActor func setRateUpdatesPlaybackRate() {
        let engine = VPPlayerEngine()
        engine.setRate(1.5)
        #expect(engine.playbackRate == 1.5)
    }

    @Test @MainActor func cycleRateFromDefault() {
        let engine = VPPlayerEngine()
        // Default is 1.0, next should be 1.25
        engine.cycleRate()
        #expect(engine.playbackRate == 1.25)
    }

    @Test @MainActor func cycleRateWrapsAround() {
        let engine = VPPlayerEngine()
        engine.setRate(2.0)
        engine.cycleRate()
        #expect(engine.playbackRate == 0.5) // wraps back to beginning
    }

    @Test @MainActor func cycleRateFromNonStandardResetsTo1() {
        let engine = VPPlayerEngine()
        engine.setRate(1.1) // not in the rate list
        engine.cycleRate()
        #expect(engine.playbackRate == 1.0)
    }

    @Test @MainActor func cycleRateProgression() {
        let engine = VPPlayerEngine()
        let expectedRates: [Float] = [1.25, 1.5, 2.0, 0.5, 0.75, 1.0]
        for expected in expectedRates {
            engine.cycleRate()
            #expect(engine.playbackRate == expected)
        }
    }
}

// MARK: - Track Selection Tests

@Suite("VPPlayerEngine - Track Selection")
struct VPPlayerEngineTrackSelectionTests {

    @Test @MainActor func selectSubtitleTrackDisablesClearsText() {
        let engine = VPPlayerEngine()
        engine.currentSubtitleText = "Some text"
        engine.selectSubtitleTrack(-1)
        #expect(engine.selectedSubtitleTrack == -1)
        #expect(engine.currentSubtitleText == nil)
    }

    @Test @MainActor func selectAudioTrackUpdatesIndex() {
        let engine = VPPlayerEngine()
        engine.selectAudioTrack(2)
        #expect(engine.selectedAudioTrack == 2)
    }

    @Test @MainActor func selectSubtitleTrackRejectsInvalidIndex() {
        let engine = VPPlayerEngine()
        // No subtitle tracks loaded, so index 5 is out of bounds
        engine.selectSubtitleTrack(5)
        // Should remain unchanged from default (not crash)
        #expect(engine.selectedSubtitleTrack == -1)
    }
}

// MARK: - Chapter Navigation Tests

@Suite("VPPlayerEngine - Chapter Navigation")
struct VPPlayerEngineChapterTests {

    private static let sampleChapters: [VPPlayerEngine.ChapterInfo] = [
        .init(id: 0, title: "Opening", startTime: 0, endTime: 60),
        .init(id: 1, title: "Act 1", startTime: 60, endTime: 300),
        .init(id: 2, title: "Act 2", startTime: 300, endTime: 600),
        .init(id: 3, title: "Finale", startTime: 600, endTime: 900),
    ]

    @Test @MainActor func loadChaptersSortsByStartTime() {
        let engine = VPPlayerEngine()
        let unsorted: [VPPlayerEngine.ChapterInfo] = [
            .init(id: 2, title: "Middle", startTime: 200, endTime: 400),
            .init(id: 0, title: "Start", startTime: 0, endTime: 100),
            .init(id: 1, title: "Early", startTime: 100, endTime: 200),
        ]
        engine.loadChapters(unsorted)
        #expect(engine.chapters.count == 3)
        #expect(engine.chapters[0].title == "Start")
        #expect(engine.chapters[1].title == "Early")
        #expect(engine.chapters[2].title == "Middle")
    }

    @Test @MainActor func loadEmptyChaptersClears() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        #expect(engine.chapters.count == 4)
        engine.loadChapters([])
        #expect(engine.chapters.isEmpty)
    }

    @Test @MainActor func currentChapterFindsCorrectChapter() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)

        #expect(engine.currentChapter(at: 30)?.title == "Opening")
        #expect(engine.currentChapter(at: 60)?.title == "Act 1")
        #expect(engine.currentChapter(at: 150)?.title == "Act 1")
        #expect(engine.currentChapter(at: 450)?.title == "Act 2")
        #expect(engine.currentChapter(at: 700)?.title == "Finale")
    }

    @Test @MainActor func currentChapterReturnsNilWhenNoChapters() {
        let engine = VPPlayerEngine()
        #expect(engine.currentChapter(at: 50) == nil)
    }

    @Test @MainActor func nextChapterTimeReturnsNextStart() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        engine.currentTime = 30 // In "Opening"
        #expect(engine.nextChapterTime() == 60)
    }

    @Test @MainActor func nextChapterTimeReturnsNilAtLastChapter() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        engine.currentTime = 700 // In "Finale" (last chapter)
        #expect(engine.nextChapterTime() == nil)
    }

    @Test @MainActor func nextChapterTimeReturnsNilWithNoChapters() {
        let engine = VPPlayerEngine()
        engine.currentTime = 50
        #expect(engine.nextChapterTime() == nil)
    }

    @Test @MainActor func previousChapterRestartsCurrent() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        engine.currentTime = 70 // 10s into "Act 1" (starts at 60) → more than 3s in
        #expect(engine.previousChapterTime() == 60) // Restarts "Act 1"
    }

    @Test @MainActor func previousChapterGoesBackWhenNearStart() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        engine.currentTime = 62 // 2s into "Act 1" → less than 3s
        #expect(engine.previousChapterTime() == 0) // Goes back to "Opening"
    }

    @Test @MainActor func previousChapterAtFirstChapterRestartsIt() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)
        engine.currentTime = 1 // 1s into "Opening" → less than 3s, but no previous
        #expect(engine.previousChapterTime() == 0) // Restarts "Opening"
    }

    @Test @MainActor func previousChapterReturnsNilWithNoChapters() {
        let engine = VPPlayerEngine()
        engine.currentTime = 50
        #expect(engine.previousChapterTime() == nil)
    }

    @Test @MainActor func chapterNavigationWalksFullSequence() {
        let engine = VPPlayerEngine()
        engine.loadChapters(Self.sampleChapters)

        // Walk forward through all chapters
        engine.currentTime = 0
        #expect(engine.nextChapterTime() == 60)

        engine.currentTime = 60
        #expect(engine.nextChapterTime() == 300)

        engine.currentTime = 300
        #expect(engine.nextChapterTime() == 600)

        engine.currentTime = 600
        #expect(engine.nextChapterTime() == nil) // Last chapter
    }
}
