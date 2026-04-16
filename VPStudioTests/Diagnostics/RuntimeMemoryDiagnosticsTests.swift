import Testing
@testable import VPStudio

struct RuntimeMemoryDiagnosticsTests {
    @Test
    func normalizedContextTrimsWhitespace() {
        let normalized = RuntimeDiagnosticsPolicy.normalizedContext("   player close   ")
        #expect(normalized == "player close")
    }

    @Test
    func normalizedContextTruncatesLongValues() {
        let long = String(repeating: "a", count: RuntimeDiagnosticsPolicy.maxContextLength + 20)
        let normalized = RuntimeDiagnosticsPolicy.normalizedContext(long)

        #expect(normalized.hasSuffix("..."))
        #expect(normalized.count == RuntimeDiagnosticsPolicy.maxContextLength + 3)
    }

    @Test
    func formattedMessageIncludesEventMemoryAndContext() {
        let snapshot = RuntimeMemorySnapshot(residentBytes: 52 * 1_048_576)
        let message = RuntimeMemoryDiagnostics.formattedMessage(
            event: .playerPrepareSucceeded,
            snapshot: snapshot,
            context: "avplayer:test.mkv"
        )

        #expect(message.contains("[player_prepare_succeeded]"))
        #expect(message.contains("rss=52.00MB"))
        #expect(message.contains("context=avplayer:test.mkv"))
    }

    @Test
    func formattedMessageOmitsContextWhenEmpty() {
        let snapshot = RuntimeMemorySnapshot(residentBytes: 10 * 1_048_576)
        let message = RuntimeMemoryDiagnostics.formattedMessage(
            event: .tabSelectionChanged,
            snapshot: snapshot,
            context: ""
        )

        #expect(message == "[tab_selection_changed] rss=10.00MB")
    }
}
