import Foundation
import Testing
@testable import VPStudio

fileprivate func writeTempSubtitle(
    content: String,
    fileExtension: String = "srt",
    encoding: String.Encoding = .utf8,
    prependBOM: Bool = false
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(fileExtension)

    guard let encodedContent = content.data(using: encoding) else {
        throw NSError(
            domain: "VPPlayerEngineSubtitleTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to encode test subtitle using \(encoding)"]
        )
    }

    var data = Data()
    if prependBOM {
        switch encoding {
        case .utf8:
            data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        case .utf16BigEndian:
            data.append(contentsOf: [0xFE, 0xFF])
        case .utf16, .utf16LittleEndian:
            data.append(contentsOf: [0xFF, 0xFE])
        default:
            break
        }
    }
    data.append(encodedContent)

    try data.write(to: url, options: .atomic)
    return url
}

// MARK: - Subtitle Loading Tests

@Suite("VPPlayerEngine - Subtitle Loading")
struct VPPlayerEngineSubtitleLoadingTests {

    /// Creates a temporary SRT file and returns its file URL.
    private func writeTempSRT(content: String) throws -> URL {
        try writeTempSubtitle(content: content)
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

    private let latin1SRT = """
    1
    00:00:01,000 --> 00:00:04,000
    Café au lait
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
        #expect(engine.subtitlesEnabled)
    }

    @Test @MainActor func loadExternalSubtitlesDecodesUTF16SubtitleFiles() throws {
        let engine = VPPlayerEngine()
        let url = try writeTempSubtitle(
            content: sampleSRT,
            encoding: .utf16LittleEndian,
            prependBOM: true
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let subtitle = Subtitle(
            id: "test-sub-utf16",
            language: "en",
            fileName: "movie.srt",
            url: url.absoluteString,
            format: .srt
        )

        engine.loadExternalSubtitles([subtitle])
        engine.updateSubtitleText(at: 2.0)

        #expect(engine.subtitleTracks.count == 1)
        #expect(engine.selectedSubtitleTrack == 0)
        #expect(engine.currentSubtitleText == "Hello, world!")
    }

    @Test @MainActor func loadExternalSubtitlesDecodesLatin1SubtitleFiles() throws {
        let engine = VPPlayerEngine()
        let url = try writeTempSubtitle(content: latin1SRT, encoding: .isoLatin1)
        defer { try? FileManager.default.removeItem(at: url) }

        let subtitle = Subtitle(
            id: "test-sub-latin1",
            language: "fr",
            fileName: "movie.srt",
            url: url.absoluteString,
            format: .srt
        )

        engine.loadExternalSubtitles([subtitle])
        engine.updateSubtitleText(at: 2.0)

        #expect(engine.subtitleTracks.count == 1)
        #expect(engine.selectedSubtitleTrack == 0)
        #expect(engine.currentSubtitleText == "Café au lait")
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
        #expect(engine.subtitlesEnabled)
    }

    @Test @MainActor func loadExternalSubtitlesWithEmptyArrayClearsState() {
        let engine = VPPlayerEngine()
        engine.currentSubtitleText = "Old text"

        engine.loadExternalSubtitles([])

        #expect(engine.subtitleTracks.isEmpty)
        #expect(engine.selectedSubtitleTrack == -1)
        #expect(engine.currentSubtitleText == nil)
        #expect(engine.subtitlesEnabled == false)
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

    @Test @MainActor func loadExternalSubtitlesSkipsUnsupportedFormats() throws {
        let engine = VPPlayerEngine()
        let url = try writeTempSRT(content: sampleSRT)
        defer { try? FileManager.default.removeItem(at: url) }

        let unsupported = Subtitle(
            id: "unsupported",
            language: "en",
            fileName: "movie.txt",
            url: url.absoluteString,
            format: .unknown
        )
        let supported = Subtitle(
            id: "supported",
            language: "en",
            fileName: "movie.srt",
            url: url.absoluteString,
            format: .srt
        )

        engine.loadExternalSubtitles([unsupported, supported])

        #expect(engine.subtitleTracks.count == 1)
        #expect(engine.subtitleTracks[0].name == "movie.srt")
        #expect(engine.subtitlesEnabled)
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
