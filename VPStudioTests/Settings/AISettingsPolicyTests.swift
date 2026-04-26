import Testing
@testable import VPStudio

@Suite("AI Settings Policy")
struct AISettingsPolicyTests {
    @Test func providerSelectionLabelsMatchUserFacingDefaultProviderNames() {
        #expect(AISettingsPolicy.providerSelectionLabel(for: .anthropic) == "Anthropic Claude")
        #expect(AISettingsPolicy.providerSelectionLabel(for: .openAI) == "OpenAI")
        #expect(AISettingsPolicy.providerSelectionLabel(for: .gemini) == "Gemini")
        #expect(AISettingsPolicy.providerSelectionLabel(for: .openRouter) == "OpenRouter")
        #expect(AISettingsPolicy.providerSelectionLabel(for: .ollama) == "Ollama (Local)")
        #expect(AISettingsPolicy.providerSelectionLabel(for: .local) == "On-Device (MLX)")
    }

    @Test func usageFormattersKeepSmallCostsAndLargeTokenCountsReadable() {
        #expect(AISettingsPolicy.formattedCost(0) == "$0.0000")
        #expect(AISettingsPolicy.formattedCost(0.0099) == "$0.0099")
        #expect(AISettingsPolicy.formattedCost(0.01) == "$0.01")
        #expect(AISettingsPolicy.formattedCost(12.345) == "$12.35")

        #expect(AISettingsPolicy.formattedTokens(999) == "999")
        #expect(AISettingsPolicy.formattedTokens(1_000) == "1.0K")
        #expect(AISettingsPolicy.formattedTokens(12_340) == "12.3K")
        #expect(AISettingsPolicy.formattedTokens(1_000_000) == "1.0M")
        #expect(AISettingsPolicy.formattedTokens(1_250_000) == "1.2M")
    }

    @Test func modelSelectionPreservesValidIDAndFallsBackToDefaultThenFirst() {
        let first = model(id: "first", isDefault: false)
        let preferred = model(id: "preferred", isDefault: true)
        let last = model(id: "last", isDefault: false)

        #expect(AISettingsPolicy.validModelSelection(currentModelID: "last", models: [first, preferred, last]) == "last")
        #expect(AISettingsPolicy.validModelSelection(currentModelID: "missing", models: [first, preferred, last]) == "preferred")
        #expect(AISettingsPolicy.validModelSelection(currentModelID: "missing", models: [first, last]) == "first")
        #expect(AISettingsPolicy.validModelSelection(currentModelID: "missing", models: []) == "missing")
    }

    @Test func discoverProviderRequiredMessageStaysActionable() {
        #expect(AISettingsPolicy.discoverProviderRequiredMessage == "Configure an AI provider before enabling the Discover AI row.")
    }

    private func model(id: String, isDefault: Bool) -> AIModelDefinition {
        AIModelDefinition(
            id: id,
            displayName: id,
            provider: .openAI,
            inputCostPer1MTokens: 0,
            outputCostPer1MTokens: 0,
            maxContextTokens: 1,
            isDefault: isDefault
        )
    }
}
