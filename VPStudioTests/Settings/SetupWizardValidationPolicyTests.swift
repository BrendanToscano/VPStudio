import Testing
@testable import VPStudio

@Suite("SetupWizardValidationPolicy")
struct SetupWizardValidationPolicyTests {
    @Test
    func tmdbKeyIsRequiredToContinueFromMetadataStep() {
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
}
