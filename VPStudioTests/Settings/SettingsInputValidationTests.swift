import Testing
@testable import VPStudio

@Suite("Settings Input Validation")
struct SettingsInputValidationTests {
    @Test func normalizedSecretTrimsAndNils() {
        #expect(SettingsInputValidation.normalizedSecret("  key  ") == "key")
        #expect(SettingsInputValidation.normalizedSecret("\n\t  \n") == nil)
    }

    @Test func normalizedTextTrimsWhitespaceAndNewlines() {
        #expect(SettingsInputValidation.normalizedText("  value\n") == "value")
        #expect(SettingsInputValidation.normalizedText("\n\t") == "")
    }

    @Test func traktCredentialValidationRequiresBothFields() {
        #expect(SettingsInputValidation.hasTraktCredentials(clientId: "client", clientSecret: "secret"))
        #expect(!SettingsInputValidation.hasTraktCredentials(clientId: " ", clientSecret: "secret"))
        #expect(!SettingsInputValidation.hasTraktCredentials(clientId: "client", clientSecret: " "))
    }

    @Test func traktAuthCodeValidationRejectsWhitespace() {
        #expect(SettingsInputValidation.hasTraktAuthCode("code-123"))
        #expect(!SettingsInputValidation.hasTraktAuthCode("   "))
    }

    @Test func simklCredentialValidationRequiresClientAndToken() {
        #expect(SettingsInputValidation.hasSimklCredentials(clientId: "cid", accessToken: "token"))
        #expect(!SettingsInputValidation.hasSimklCredentials(clientId: "", accessToken: "token"))
        #expect(!SettingsInputValidation.hasSimklCredentials(clientId: "cid", accessToken: " "))
    }

    @Test func unsavedSecretChangeNormalizesBeforeComparing() {
        #expect(!SettingsInputValidation.hasUnsavedSecretChange(current: " token ", initial: "token"))
        #expect(SettingsInputValidation.hasUnsavedSecretChange(current: "new-token", initial: "token"))
        #expect(SettingsInputValidation.hasUnsavedSecretChange(current: " ", initial: "token"))
        #expect(!SettingsInputValidation.hasUnsavedSecretChange(current: " ", initial: "\n"))
    }
}
