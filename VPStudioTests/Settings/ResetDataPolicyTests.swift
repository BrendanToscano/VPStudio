import Testing
@testable import VPStudio

@Suite("Reset Data Policy")
struct ResetDataPolicyTests {
    @Test func confirmationPhraseAllowsOnlyTrimmedResetText() {
        #expect(ResetDataPolicy.requiredConfirmationPhrase == "RESET")
        #expect(ResetDataPolicy.normalizedConfirmationText("  RESET\n") == "RESET")
        #expect(ResetDataPolicy.canExecuteReset(confirmationText: "RESET"))
        #expect(ResetDataPolicy.canExecuteReset(confirmationText: " reset "))
        #expect(!ResetDataPolicy.canExecuteReset(confirmationText: "RESET EVERYTHING"))
        #expect(!ResetDataPolicy.canExecuteReset(confirmationText: ""))
        #expect(!ResetDataPolicy.canExecuteReset(confirmationText: " \n\t "))
    }

    @Test func resettingStateAlwaysDisablesDestructiveAction() {
        #expect(!ResetDataPolicy.canExecuteReset(confirmationText: "RESET", isResetting: true))
        #expect(ResetDataPolicy.canExecuteReset(confirmationText: "RESET", isResetting: false))
    }

    @Test func deletionItemsCoverEveryResetCategoryShownToUsers() {
        #expect(ResetDataPolicy.deletionItems == [
            ResetDataPolicy.DeletionItem(icon: "key.fill", title: "API Keys & Credentials"),
            ResetDataPolicy.DeletionItem(icon: "clock.fill", title: "Watch History & Library"),
            ResetDataPolicy.DeletionItem(icon: "arrow.down.circle.fill", title: "Downloads"),
            ResetDataPolicy.DeletionItem(icon: "mountain.2.fill", title: "Environment Assets"),
            ResetDataPolicy.DeletionItem(icon: "gearshape.fill", title: "All Settings"),
        ])
    }

    @Test func visibleResetControlLabelsStayStableForUITestsAndAccessibility() {
        #expect(ResetDataPolicy.resetButtonTitle == "Reset Everything")
        #expect(ResetDataPolicy.progressAccessibilityLabel == "Reset in progress")
    }
}
