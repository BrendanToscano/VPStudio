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
}
