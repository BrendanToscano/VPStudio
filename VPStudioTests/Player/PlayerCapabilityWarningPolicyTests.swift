import CoreFoundation
import Testing
@testable import VPStudio

@Suite("Player Capability Warning Policy")
struct PlayerCapabilityWarningPolicyTests {
    @Test
    func emptyWarningsYieldNoInlineMessage() {
        #expect(PlayerCapabilityWarningPolicy.inlineMessage(for: []) == nil)
        #expect(PlayerCapabilityWarningPolicy.overflowCount(for: []) == 0)
    }

    @Test
    func firstWarningIsUsedAsInlineMessage() {
        let warnings = ["4K source detected", "HDR source detected"]
        #expect(PlayerCapabilityWarningPolicy.inlineMessage(for: warnings) == "4K source detected")
    }

    @Test
    func overflowCountTracksAdditionalWarnings() {
        let warnings = ["4K", "HDR", "Dolby Atmos"]
        #expect(PlayerCapabilityWarningPolicy.overflowCount(for: warnings) == 2)
    }

    @Test
    func inlineMessageTruncatesLongWarnings() {
        let longWarning = String(repeating: "a", count: 120)
        let message = PlayerCapabilityWarningPolicy.inlineMessage(for: [longWarning])

        #expect(message != nil)
        #expect(message?.count == PlayerCapabilityWarningPolicy.maxInlineCharacters)
        #expect(message?.hasSuffix("…") == true)
    }
}
