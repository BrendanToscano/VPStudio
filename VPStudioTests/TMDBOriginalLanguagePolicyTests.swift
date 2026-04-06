import Testing
@testable import VPStudio

struct TMDBOriginalLanguagePolicyTests {
    @Test
    func englishOnlyDoesNotSendOriginalLanguage() {
        #expect(TMDBOriginalLanguagePolicy.shouldSendOriginalLanguage(for: ["en-US"]) == false)
        #expect(TMDBOriginalLanguagePolicy.originalLanguageCode(for: ["en-US"]) == nil)
    }

    @Test
    func multipleSelectionsDoNotSendOriginalLanguage() {
        #expect(TMDBOriginalLanguagePolicy.shouldSendOriginalLanguage(for: ["en-US", "fr-FR"]) == false)
        #expect(TMDBOriginalLanguagePolicy.originalLanguageCode(for: ["en-US", "fr-FR"]) == nil)
    }

    @Test(arguments: ["hi-IN", "as-IN", "bn-IN", "ta-IN", "te-IN", "as", "bn"])
    func indianLanguageSelectionsDoNotSendOriginalLanguage(localeCode: String) {
        #expect(TMDBOriginalLanguagePolicy.shouldSendOriginalLanguage(for: [localeCode]) == false)
        #expect(TMDBOriginalLanguagePolicy.originalLanguageCode(for: [localeCode]) == nil)
    }

    @Test
    func otherSingleNonEnglishLocaleUsesIso639Code() {
        #expect(TMDBOriginalLanguagePolicy.shouldSendOriginalLanguage(for: ["fr-FR"]) == true)
        #expect(TMDBOriginalLanguagePolicy.originalLanguageCode(for: ["fr-FR"]) == "fr")
    }
}
