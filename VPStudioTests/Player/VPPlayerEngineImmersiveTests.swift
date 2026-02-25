import Testing
@testable import VPStudio

@Suite("VPPlayerEngine — Immersive Controls Properties")
struct VPPlayerEngineImmersiveTests {

    @Test("currentTitle defaults to nil")
    @MainActor func currentTitleDefaultsToNil() {
        let engine = VPPlayerEngine()
        #expect(engine.currentTitle == nil)
    }

    @Test("currentTitle can be set and read")
    @MainActor func currentTitleRoundTrip() {
        let engine = VPPlayerEngine()
        engine.currentTitle = "Dune: Part Two"
        #expect(engine.currentTitle == "Dune: Part Two")
    }

    @Test("currentTitle can be cleared")
    @MainActor func currentTitleCanBeCleared() {
        let engine = VPPlayerEngine()
        engine.currentTitle = "Movie"
        engine.currentTitle = nil
        #expect(engine.currentTitle == nil)
    }

    @Test("progressPercent returns 0 when duration is 0")
    @MainActor func progressPercentZeroDuration() {
        let engine = VPPlayerEngine()
        engine.currentTime = 50
        engine.duration = 0
        #expect(engine.progressPercent == 0)
    }

    @Test("progressPercent returns correct ratio")
    @MainActor func progressPercentCorrectRatio() {
        let engine = VPPlayerEngine()
        engine.currentTime = 30
        engine.duration = 120
        #expect(engine.progressPercent == 0.25)
    }

    @Test("cycleRate cycles through predefined rates")
    @MainActor func cycleRateProgresses() {
        let engine = VPPlayerEngine()
        engine.setRate(1.0)
        engine.cycleRate()
        #expect(engine.playbackRate == 1.25)
        engine.cycleRate()
        #expect(engine.playbackRate == 1.5)
        engine.cycleRate()
        #expect(engine.playbackRate == 2.0)
        engine.cycleRate()
        #expect(engine.playbackRate == 0.5)
        engine.cycleRate()
        #expect(engine.playbackRate == 0.75)
        engine.cycleRate()
        #expect(engine.playbackRate == 1.0)
    }

    @Test("cycleRate resets unknown rate to 1.0")
    @MainActor func cycleRateResetsUnknown() {
        let engine = VPPlayerEngine()
        engine.setRate(3.0) // Not in the standard list
        engine.cycleRate()
        #expect(engine.playbackRate == 1.0)
    }

    @Test("cycleRate does NOT reset known rates to 1.0")
    @MainActor func cycleRateDoesNotResetKnownRates() {
        let engine = VPPlayerEngine()
        // Verify each known mid-cycle rate advances to the next, not back to 1.0
        let expectedTransitions: [(Float, Float)] = [
            (1.25, 1.5), (1.5, 2.0), (2.0, 0.5), (0.5, 0.75), (0.75, 1.0),
        ]
        for (start, expected) in expectedTransitions {
            engine.setRate(start)
            engine.cycleRate()
            #expect(engine.playbackRate == expected,
                    "Rate \(start) should advance to \(expected), not reset to 1.0")
        }
    }

    @Test("currentChapter returns nil with no chapters")
    @MainActor func currentChapterNilWithEmpty() {
        let engine = VPPlayerEngine()
        engine.currentTime = 30
        #expect(engine.currentChapter(at: engine.currentTime) == nil)
    }

    @Test("currentChapter returns correct chapter")
    @MainActor func currentChapterFindsCorrect() {
        let engine = VPPlayerEngine()
        engine.loadChapters([
            .init(id: 0, title: "Intro", startTime: 0, endTime: 60),
            .init(id: 1, title: "Act 1", startTime: 60, endTime: 180),
            .init(id: 2, title: "Act 2", startTime: 180, endTime: 300),
        ])
        engine.currentTime = 90
        let chapter = engine.currentChapter(at: engine.currentTime)
        #expect(chapter?.title == "Act 1")
    }

    @Test("nextChapterTime returns nil when in last chapter")
    @MainActor func nextChapterNilAtEnd() {
        let engine = VPPlayerEngine()
        engine.loadChapters([
            .init(id: 0, title: "Only Chapter", startTime: 0, endTime: 300),
        ])
        engine.currentTime = 150
        #expect(engine.nextChapterTime() == nil)
    }

    @Test("previousChapterTime restarts current if >3s in")
    @MainActor func previousChapterRestartsIfDeep() {
        let engine = VPPlayerEngine()
        engine.loadChapters([
            .init(id: 0, title: "Ch1", startTime: 0, endTime: 60),
            .init(id: 1, title: "Ch2", startTime: 60, endTime: 120),
        ])
        engine.currentTime = 70 // 10s into Ch2
        #expect(engine.previousChapterTime() == 60) // Restart Ch2
    }
}
