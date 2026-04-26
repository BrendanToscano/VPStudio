import Testing
@testable import VPStudio

struct RuntimeMemoryDiagnosticsTests {
    @Test
    func eventRawValuesMatchStableLogNames() {
        let expected: [(RuntimeDiagnosticsEvent, String)] = [
            (.appBootstrapCompleted, "app_bootstrap_completed"),
            (.tabSelectionChanged, "tab_selection_changed"),
            (.libraryLoadStarted, "library_load_started"),
            (.libraryLoadFinished, "library_load_finished"),
            (.playerPrepareStarted, "player_prepare_started"),
            (.playerPrepareSucceeded, "player_prepare_succeeded"),
            (.playerPrepareFailed, "player_prepare_failed"),
            (.playerCloseRequested, "player_close_requested"),
            (.playerDidDisappear, "player_did_disappear"),
        ]

        for (event, rawValue) in expected {
            #expect(event.rawValue == rawValue)
        }
    }

    @Test
    func normalizedContextReturnsEmptyForNilAndBlankValues() {
        #expect(RuntimeDiagnosticsPolicy.normalizedContext(nil) == "")
        #expect(RuntimeDiagnosticsPolicy.normalizedContext(" \n\t ") == "")
    }

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

    @Test
    func residentMegabytesConvertsBytesUsingBinaryMegabytes() {
        let snapshot = RuntimeMemorySnapshot(residentBytes: 1_572_864)
        #expect(snapshot.residentMegabytes == 1.5)
    }

    @Test
    func captureDisabledDoesNotRequireSnapshot() {
        RuntimeMemoryDiagnostics.capture(
            event: .appBootstrapCompleted,
            enabled: false,
            context: "disabled"
        )
    }

    @Test
    func captureEnabledLogsWithEmptyContext() {
        RuntimeMemoryDiagnostics.capture(
            event: .libraryLoadStarted,
            enabled: true,
            context: nil
        )
    }

    @Test
    func captureEnabledLogsWithNormalizedContext() {
        RuntimeMemoryDiagnostics.capture(
            event: .playerPrepareFailed,
            enabled: true,
            context: "  avplayer:network-timeout  "
        )
    }

    @Test
    func currentSnapshotIsAvailableOnDarwin() {
        #if canImport(Darwin)
        let snapshot = RuntimeMemoryDiagnostics.currentSnapshot()
        #expect(snapshot?.residentBytes ?? 0 > 0)
        #else
        #expect(RuntimeMemoryDiagnostics.currentSnapshot() == nil)
        #endif
    }
}
