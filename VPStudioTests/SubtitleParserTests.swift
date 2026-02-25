import Testing
import Foundation
@testable import VPStudio

// MARK: - SRT Parsing Tests

@Suite("SubtitleParser - SRT")
struct SubtitleParserSRTTests {

    @Test func parsesBasicSRTWithMultipleCues() {
        let content = """
        1
        00:00:01,000 --> 00:00:03,500
        Hello world

        2
        00:00:05,000 --> 00:00:08,200
        Second subtitle
        """

        let cues = SubtitleParser.parseSRT(content)
        #expect(cues.count == 2)
        #expect(cues[0].id == 1)
        #expect(cues[0].text == "Hello world")
        #expect(abs(cues[0].startTime - 1.0) < 0.001)
        #expect(abs(cues[0].endTime - 3.5) < 0.001)
        #expect(cues[1].id == 2)
        #expect(cues[1].text == "Second subtitle")
        #expect(abs(cues[1].startTime - 5.0) < 0.001)
        #expect(abs(cues[1].endTime - 8.2) < 0.001)
    }

    @Test func parsesMultiLineSubtitleText() {
        let content = """
        1
        00:00:01,000 --> 00:00:03,000
        Line one
        Line two
        Line three
        """

        let cues = SubtitleParser.parseSRT(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Line one\nLine two\nLine three")
    }

    @Test func stripsHTMLTagsFromSRTText() {
        let content = """
        1
        00:00:01,000 --> 00:00:03,000
        <i>Italic text</i> and <b>bold</b>
        """

        let cues = SubtitleParser.parseSRT(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Italic text and bold")
    }

    @Test func handlesHoursMinutesSecondsMilliseconds() {
        let content = """
        1
        01:30:45,678 --> 02:15:10,123
        Late in the movie
        """

        let cues = SubtitleParser.parseSRT(content)
        #expect(cues.count == 1)
        let expectedStart = 1.0 * 3600 + 30.0 * 60 + 45.678
        let expectedEnd = 2.0 * 3600 + 15.0 * 60 + 10.123
        #expect(abs(cues[0].startTime - expectedStart) < 0.001)
        #expect(abs(cues[0].endTime - expectedEnd) < 0.001)
    }

    @Test func skipsBlocksWithInvalidFormat() {
        let content = """
        1
        00:00:01,000 --> 00:00:02,000
        Valid cue

        not-a-number
        bad timestamp
        Bad cue

        3
        00:00:05,000 --> 00:00:06,000
        Another valid cue
        """

        let cues = SubtitleParser.parseSRT(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "Valid cue")
        #expect(cues[1].text == "Another valid cue")
    }

    @Test func returnsEmptyArrayForEmptyContent() {
        let cues = SubtitleParser.parseSRT("")
        #expect(cues.isEmpty)
    }

    @Test func returnsEmptyArrayForGarbageContent() {
        let cues = SubtitleParser.parseSRT("this is not a subtitle file at all")
        #expect(cues.isEmpty)
    }

    @Test func handlesCRLFNewlines() {
        let content = "1\r\n00:00:01,000 --> 00:00:02,000\r\nHello\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nWorld\r\n"

        let cues = SubtitleParser.parseSRT(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "Hello")
        #expect(cues[1].text == "World")
    }
}

// MARK: - VTT Parsing Tests

@Suite("SubtitleParser - VTT")
struct SubtitleParserVTTTests {

    @Test func parsesBasicVTTWithHeader() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:03.500
        First cue

        00:00:05.000 --> 00:00:08.200
        Second cue
        """

        let cues = SubtitleParser.parseVTT(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "First cue")
        #expect(abs(cues[0].startTime - 1.0) < 0.001)
        #expect(abs(cues[0].endTime - 3.5) < 0.001)
        #expect(cues[1].text == "Second cue")
    }

    @Test func parsesVTTWithCueIdentifiers() {
        let content = """
        WEBVTT

        intro
        00:00:01.000 --> 00:00:03.000
        Welcome

        main
        00:00:04.000 --> 00:00:06.000
        Main content
        """

        let cues = SubtitleParser.parseVTT(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "Welcome")
        #expect(cues[1].text == "Main content")
    }

    @Test func stripsHTMLTagsFromVTTText() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:03.000
        <b>Bold</b> and <i>italic</i>
        """

        let cues = SubtitleParser.parseVTT(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Bold and italic")
    }

    @Test func parsesShortTimestampFormat() {
        let content = """
        WEBVTT

        01:23.456 --> 02:34.567
        Short format
        """

        let cues = SubtitleParser.parseVTT(content)
        #expect(cues.count == 1)
        let expectedStart = 1.0 * 60 + 23.456
        let expectedEnd = 2.0 * 60 + 34.567
        #expect(abs(cues[0].startTime - expectedStart) < 0.001)
        #expect(abs(cues[0].endTime - expectedEnd) < 0.001)
    }

    @Test func returnsEmptyArrayForEmptyVTT() {
        let cues = SubtitleParser.parseVTT("WEBVTT\n\n")
        #expect(cues.isEmpty)
    }

    @Test func handlesCRLFNewlines() {
        let content = "WEBVTT\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nFirst cue\r\n\r\n00:00:02.500 --> 00:00:04.000\r\nSecond cue\r\n"

        let cues = SubtitleParser.parseVTT(content)
        #expect(cues.count == 2)
        #expect(cues[0].text == "First cue")
        #expect(abs(cues[1].endTime - 4.0) < 0.001)
    }

    @Test func parsesMultiLineVTTText() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:03.000
        Line one
        Line two
        """

        let cues = SubtitleParser.parseVTT(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Line one\nLine two")
    }
}

// MARK: - ASS/SSA Parsing Tests

@Suite("SubtitleParser - ASS/SSA")
struct SubtitleParserASSTests {

    @Test func parsesBasicASSDialogueLine() {
        let content = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,Hello from ASS
        """

        let cues = SubtitleParser.parseASS(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello from ASS")
        #expect(abs(cues[0].startTime - 1.0) < 0.001)
        #expect(abs(cues[0].endTime - 3.5) < 0.001)
    }

    @Test func stripsASSStyleTags() {
        let content = """
        [Events]
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\b1}Bold{\\b0} text {\\i1}italic{\\i0}
        """

        let cues = SubtitleParser.parseASS(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Bold text italic")
    }

    @Test func replacesNewlineEscapesInASS() {
        let content = """
        [Events]
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Line one\\NLine two\\nLine three
        """

        let cues = SubtitleParser.parseASS(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Line one\nLine two\nLine three")
    }

    @Test func handlesTextWithCommas() {
        let content = """
        [Events]
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Hello, world, how are you?
        """

        let cues = SubtitleParser.parseASS(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Hello, world, how are you?")
    }

    @Test func parsesMultipleDialogueLines() {
        let content = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:05.00,0:00:07.00,Default,,0,0,0,,Second cue
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,First cue
        """

        let cues = SubtitleParser.parseASS(content)
        #expect(cues.count == 2)
        // ASS parser sorts by start time
        #expect(cues[0].text == "First cue")
        #expect(cues[1].text == "Second cue")
    }

    @Test func skipsNonDialogueLines() {
        let content = """
        [Script Info]
        Title: Test
        [V4+ Styles]
        Style: Default,Arial,20,&H00FFFFFF
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Comment: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,This is a comment
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Actual dialogue
        """

        let cues = SubtitleParser.parseASS(content)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Actual dialogue")
    }

    @Test func returnsEmptyArrayForNoDialogue() {
        let content = """
        [Script Info]
        Title: Empty
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """

        let cues = SubtitleParser.parseASS(content)
        #expect(cues.isEmpty)
    }

    @Test func handlesASSTimestampFormat() {
        // ASS uses H:MM:SS.CS (centiseconds)
        let content = """
        Dialogue: 0,1:30:45.67,2:15:10.12,Default,,0,0,0,,Late in the movie
        """

        let cues = SubtitleParser.parseASS(content)
        #expect(cues.count == 1)
        let expectedStart = 1.0 * 3600 + 30.0 * 60 + 45.67
        let expectedEnd = 2.0 * 3600 + 15.0 * 60 + 10.12
        #expect(abs(cues[0].startTime - expectedStart) < 0.01)
        #expect(abs(cues[0].endTime - expectedEnd) < 0.01)
    }
}

// MARK: - Format Dispatch Tests

@Suite("SubtitleParser - Format Dispatch")
struct SubtitleParserFormatDispatchTests {

    @Test func dispatchesToSRTParser() {
        let content = """
        1
        00:00:01,000 --> 00:00:02,000
        SRT content
        """

        let cues = SubtitleParser.parse(content: content, format: .srt)
        #expect(cues.count == 1)
        #expect(cues[0].text == "SRT content")
    }

    @Test func dispatchesToVTTParser() {
        let content = """
        WEBVTT

        00:00:01.000 --> 00:00:02.000
        VTT content
        """

        let cues = SubtitleParser.parse(content: content, format: .vtt)
        #expect(cues.count == 1)
        #expect(cues[0].text == "VTT content")
    }

    @Test func dispatchesToASSParser() {
        let content = """
        Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,ASS content
        """

        let cues = SubtitleParser.parse(content: content, format: .ass)
        #expect(cues.count == 1)
        #expect(cues[0].text == "ASS content")
    }

    @Test func dispatchesToASSParserForSSA() {
        let content = """
        Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,SSA content
        """

        let cues = SubtitleParser.parse(content: content, format: .ssa)
        #expect(cues.count == 1)
        #expect(cues[0].text == "SSA content")
    }

    @Test func unknownFormatFallsBackToSRT() {
        let content = """
        1
        00:00:01,000 --> 00:00:02,000
        Fallback SRT
        """

        let cues = SubtitleParser.parse(content: content, format: .unknown)
        #expect(cues.count == 1)
        #expect(cues[0].text == "Fallback SRT")
    }
}

// MARK: - Active Cue Tests

@Suite("SubtitleParser - Active Cue")
struct SubtitleParserActiveCueTests {

    private let testCues = [
        SubtitleParser.SubtitleCue(id: 1, startTime: 1.0, endTime: 3.0, text: "First"),
        SubtitleParser.SubtitleCue(id: 2, startTime: 5.0, endTime: 8.0, text: "Second"),
        SubtitleParser.SubtitleCue(id: 3, startTime: 10.0, endTime: 12.0, text: "Third"),
    ]

    @Test func findsActiveCueAtExactStartTime() {
        let cue = SubtitleParser.activeCue(at: 1.0, in: testCues)
        #expect(cue?.text == "First")
    }

    @Test func findsActiveCueAtExactEndTime() {
        let cue = SubtitleParser.activeCue(at: 3.0, in: testCues)
        #expect(cue?.text == "First")
    }

    @Test func findsActiveCueMidway() {
        let cue = SubtitleParser.activeCue(at: 6.5, in: testCues)
        #expect(cue?.text == "Second")
    }

    @Test func returnsNilBetweenCues() {
        let cue = SubtitleParser.activeCue(at: 4.0, in: testCues)
        #expect(cue == nil)
    }

    @Test func returnsNilBeforeAllCues() {
        let cue = SubtitleParser.activeCue(at: 0.0, in: testCues)
        #expect(cue == nil)
    }

    @Test func returnsNilAfterAllCues() {
        let cue = SubtitleParser.activeCue(at: 15.0, in: testCues)
        #expect(cue == nil)
    }

    @Test func returnsNilForEmptyCueArray() {
        let cue = SubtitleParser.activeCue(at: 1.0, in: [])
        #expect(cue == nil)
    }

    @Test func zeroDurationCueActiveOnlyAtExactTime() {
        let cues = [
            SubtitleParser.SubtitleCue(id: 1, startTime: 5.0, endTime: 5.0, text: "Marker"),
        ]
        // Exactly at the timestamp — should match
        let atExact = SubtitleParser.activeCue(at: 5.0, in: cues)
        #expect(atExact?.text == "Marker")

        // Just before — should not match
        let justBefore = SubtitleParser.activeCue(at: 4.999, in: cues)
        #expect(justBefore == nil)

        // Just after — should not match
        let justAfter = SubtitleParser.activeCue(at: 5.001, in: cues)
        #expect(justAfter == nil)
    }
}
