import Foundation
import Testing
@testable import VPStudio

// MARK: - Subtitle Loading Tests

@Suite("VPPlayerEngine - Subtitle Loading")
struct VPPlayerEngineSubtitleLoadingTests {

    /// Creates a temporary SRT file and returns its file URL.
    private func writeTempSRT(content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("srt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let sampleSRT = """
    1
    00:00:01,000 --> 00:00:04,000
    Hello, world!

    2
    00:00:05,000 --> 00:00:08,000
    Second subtitle line.

    3
    00:00:10,500 --> 00:00:13,200
    Third cue with <b>HTML</b> tags.
    """

    @Test @MainActor func loadExternalSubtitlesPopulatesTracks() throws {
        let engine = VPPlayerEngine()
        let url = try writeTempSRT(content: sampleSRT)
        defer { try? FileManager.default.removeItem(at: url) }

        let subtitle = Subtitle(
            id: "test-sub-1",
            language: "en",
            fileName: "movie.srt",
            url: url.absoluteString,
            format: .srt
        )

        engine.loadExternalSubtitles([subtitle])

        #expect(engine.subtitleTracks.count == 1)
        #expect(engine.subtitleTracks[0].name == "movie.srt")
        #expect(engine.subtitleTracks[0].language == "en")
        #expect(engine.subtitleTracks[0].codec == "srt")
    }

    @Test @MainActor func loadExternalSubtitlesAutoSelectsFirstTrack() throws {
        let engine = VPPlayerEngine()
        let url = try writeTempSRT(content: sampleSRT)
        defer { try? FileManager.default.removeItem(at: url) }

        let subtitle = Subtitle(
            id: "test-sub-1",
            language: "en",
            fileName: "movie.srt",
            url: url.absoluteString,
            format: .srt
        )

        engine.loadExternalSubtitles([subtitle])
        #expect(engine.selectedSubtitleTrack == 0)
    }

    @Test @MainActor func loadExternalSubtitlesWithEmptyArrayClearsState() {
        let engine = VPPlayerEngine()
        engine.currentSubtitleText = "Old text"

        engine.loadExternalSubtitles([])

        #expect(engine.subtitleTracks.isEmpty)
        #expect(engine.selectedSubtitleTrack == -1)
        #expect(engine.currentSubtitleText == nil)
    }

    @Test @MainActor func loadMultipleExternalSubtitles() throws {
        let engine = VPPlayerEngine()
        let url1 = try writeTempSRT(content: sampleSRT)
        let url2 = try writeTempSRT(content: sampleSRT)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let subs = [
            Subtitle(id: "sub-en", language: "en", fileName: "english.srt", url: url1.absoluteString, format: .srt),
            Subtitle(id: "sub-es", language: "es", fileName: "spanish.srt", url: url2.absoluteString, format: .srt),
        ]

        engine.loadExternalSubtitles(subs)

        #expect(engine.subtitleTracks.count == 2)
        #expect(engine.subtitleTracks[0].language == "en")
        #expect(engine.subtitleTracks[1].language == "es")
    }

    @Test @MainActor func loadSubtitleWithInvalidURLDoesNotCrash() {
        let engine = VPPlayerEngine()
        let subtitle = Subtitle(
            id: "bad-url",
            language: "en",
            fileName: "missing.srt",
            url: "file:///nonexistent/path/missing.srt",
            format: .srt
        )

        engine.loadExternalSubtitles([subtitle])

        // Track is still created (for display), but no cues are parsed
        #expect(engine.subtitleTracks.count == 1)
        // Selection still auto-selects the first track
        #expect(engine.selectedSubtitleTrack == 0)
        // No cues should have been parsed from the missing file,
        // so updateSubtitleText should produce nil text
        engine.updateSubtitleText(at: 0)
        #expect(engine.currentSubtitleText == nil, "Missing file should produce no subtitle cues")
    }
}

// MARK: - Subtitle Timing Tests

@Suite("VPPlayerEngine - Subtitle Timing")
struct VPPlayerEngineSubtitleTimingTests {

    private let sampleSRT = """
    1
    00:00:01,000 --> 00:00:04,000
    First cue.

    2
    00:00:05,000 --> 00:00:08,000
    Second cue.

    3
    00:00:10,500 --> 00:00:13,200
    Third cue.
    """

    private func writeTempSRT(content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("srt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor private func loadedEngine() throws -> VPPlayerEngine {
        let engine = VPPlayerEngine()
        let url = try writeTempSRT(content: sampleSRT)
        // Note: file persists for the duration of the test since we don't clean up
        // within this helper. The OS will clean temp files eventually.
        let subtitle = Subtitle(
            id: "timing-test",
            language: "en",
            fileName: "timing.srt",
            url: url.absoluteString,
            format: .srt
        )
        engine.loadExternalSubtitles([subtitle])
        return engine
    }

    @Test @MainActor func updateSubtitleTextShowsCorrectCueAtTime() throws {
        let engine = try loadedEngine()
        engine.updateSubtitleText(at: 2.0)
        #expect(engine.currentSubtitleText == "First cue.")
    }

    @Test @MainActor func updateSubtitleTextShowsSecondCue() throws {
        let engine = try loadedEngine()
        engine.updateSubtitleText(at: 6.0)
        #expect(engine.currentSubtitleText == "Second cue.")
    }

    @Test @MainActor func updateSubtitleTextShowsThirdCue() throws {
        let engine = try loadedEngine()
        engine.updateSubtitleText(at: 11.0)
        #expect(engine.currentSubtitleText == "Third cue.")
    }

    @Test @MainActor func updateSubtitleTextReturnsNilBetweenCues() throws {
        let engine = try loadedEngine()
        engine.updateSubtitleText(at: 4.5) // Gap between cue 1 (ends 4.0) and cue 2 (starts 5.0)
        #expect(engine.currentSubtitleText == nil)
    }

    @Test @MainActor func updateSubtitleTextReturnsNilBeforeFirstCue() throws {
        let engine = try loadedEngine()
        engine.updateSubtitleText(at: 0.5) // Before first cue starts at 1.0
        #expect(engine.currentSubtitleText == nil)
    }

    @Test @MainActor func updateSubtitleTextReturnsNilAfterLastCue() throws {
        let engine = try loadedEngine()
        engine.updateSubtitleText(at: 20.0) // After last cue ends at 13.2
        #expect(engine.currentSubtitleText == nil)
    }

    @Test @MainActor func subtitleTextSurvivesSeek() throws {
        let engine = try loadedEngine()

        // "Play" to second cue
        engine.updateSubtitleText(at: 6.0)
        #expect(engine.currentSubtitleText == "Second cue.")

        // "Seek" back to first cue
        engine.updateSubtitleText(at: 2.0)
        #expect(engine.currentSubtitleText == "First cue.")

        // "Seek" forward to third cue
        engine.updateSubtitleText(at: 11.0)
        #expect(engine.currentSubtitleText == "Third cue.")
    }

    @Test @MainActor func subtitleTextClearsWhenTrackDisabled() throws {
        let engine = try loadedEngine()
        engine.updateSubtitleText(at: 2.0)
        #expect(engine.currentSubtitleText == "First cue.")

        engine.selectSubtitleTrack(-1)
        #expect(engine.currentSubtitleText == nil)
    }

    @Test @MainActor func subtitleTextReturnsNilWhenNoTrackSelected() {
        let engine = VPPlayerEngine()
        engine.updateSubtitleText(at: 5.0)
        #expect(engine.currentSubtitleText == nil)
    }

    @Test @MainActor func subtitleTextAtExactBoundary() throws {
        let engine = try loadedEngine()

        // At exact start time
        engine.updateSubtitleText(at: 1.0)
        #expect(engine.currentSubtitleText == "First cue.")

        // At exact end time
        engine.updateSubtitleText(at: 4.0)
        #expect(engine.currentSubtitleText == "First cue.")
    }
}
