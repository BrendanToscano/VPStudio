import Testing
@testable import VPStudio

@Suite("SetupWizardValidationPolicy")
struct SetupWizardValidationPolicyTests {
    @Test
    func tmdbKeyIsRequiredToContinueFromMetadataStep() {
        #expect(SetupWizardValidationPolicy.trimmedValue("  abc\n") == "abc")
        #expect(SetupWizardValidationPolicy.canContinueFromMetadataStep(tmdbApiKey: "   ") == false)
        #expect(SetupWizardValidationPolicy.canContinueFromMetadataStep(tmdbApiKey: "\n\t") == false)
        #expect(SetupWizardValidationPolicy.canContinueFromMetadataStep(tmdbApiKey: "abcd") == true)
        #expect(SetupWizardValidationPolicy.requiredTMDBMessage == "TMDB API key is required to continue.")
    }

    @Test
    func setupWizardAIOffersCurrentCloudProviders() {
        let offeredProviders = Set(AIProviderOption.allCases)
        #expect(offeredProviders.contains(.none))
        #expect(offeredProviders.contains(.openAI))
        #expect(offeredProviders.contains(.anthropic))
        #expect(offeredProviders.contains(.gemini))
        #expect(offeredProviders.contains(.openRouter))
    }

    @Test
    func debridStepSkipsWhenNoTokenWasEntered() {
        #expect(SetupWizardValidationPolicy.continueButtonTitle(currentStep: 1, debridApiKey: "   ") == "Skip for Now")
        #expect(SetupWizardValidationPolicy.continueButtonIcon(currentStep: 1, debridApiKey: "\n\t") == "forward")

        #expect(SetupWizardValidationPolicy.continueButtonTitle(currentStep: 1, debridApiKey: "token") == "Continue")
        #expect(SetupWizardValidationPolicy.continueButtonIcon(currentStep: 1, debridApiKey: "token") == "arrow.right")
        #expect(SetupWizardValidationPolicy.continueButtonTitle(currentStep: 2, debridApiKey: "") == "Continue")
    }

    @Test
    func aiProviderSettingsKeysMatchSettingsStorage() {
        #expect(SetupWizardValidationPolicy.settingsKey(for: .none) == nil)
        #expect(SetupWizardValidationPolicy.settingsKey(for: .openAI) == SettingsKeys.openAIApiKey)
        #expect(SetupWizardValidationPolicy.settingsKey(for: .anthropic) == SettingsKeys.anthropicApiKey)
        #expect(SetupWizardValidationPolicy.settingsKey(for: .gemini) == SettingsKeys.geminiApiKey)
        #expect(SetupWizardValidationPolicy.settingsKey(for: .openRouter) == SettingsKeys.openRouterApiKey)

        #expect(!SetupWizardValidationPolicy.shouldSaveAIKey(provider: .openAI, apiKey: "   "))
        #expect(!SetupWizardValidationPolicy.shouldSaveAIKey(provider: .none, apiKey: "key"))
        #expect(SetupWizardValidationPolicy.shouldSaveAIKey(provider: .gemini, apiKey: " key "))
    }

    @Test
    func completionSummaryRowsReflectConfiguredOptionalSteps() {
        let rows = SetupWizardValidationPolicy.completionSummaryRows(
            selectedService: .realDebrid,
            debridApiKey: " token ",
            tmdbApiKey: " tmdb ",
            selectedAIProvider: .openRouter,
            selectedQuality: .uhd4k,
            selectedSubtitleLanguage: .english
        )

        #expect(rows == [
            SetupWizardValidationPolicy.SummaryRow(icon: "link", text: "Real-Debrid connected"),
            SetupWizardValidationPolicy.SummaryRow(icon: "film", text: "TMDB metadata configured"),
            SetupWizardValidationPolicy.SummaryRow(icon: "brain", text: "OpenRouter AI enabled"),
            SetupWizardValidationPolicy.SummaryRow(icon: "4k.tv", text: "Quality set to 4K"),
            SetupWizardValidationPolicy.SummaryRow(icon: "captions.bubble", text: "English subtitles"),
        ])
    }

    @Test
    func completionSummaryRowsOmitSkippedOptionalStepsButAlwaysIncludeQuality() {
        let rows = SetupWizardValidationPolicy.completionSummaryRows(
            selectedService: .premiumize,
            debridApiKey: "   ",
            tmdbApiKey: "",
            selectedAIProvider: .none,
            selectedQuality: .hd1080p,
            selectedSubtitleLanguage: .none
        )

        #expect(rows == [
            SetupWizardValidationPolicy.SummaryRow(icon: "4k.tv", text: "Quality set to 1080p"),
        ])
    }
}
