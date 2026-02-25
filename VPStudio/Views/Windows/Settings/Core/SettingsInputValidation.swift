import Foundation

enum SettingsInputValidation {
    static func normalizedSecret(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasTraktCredentials(clientId: String, clientSecret: String) -> Bool {
        !normalizedText(clientId).isEmpty && !normalizedText(clientSecret).isEmpty
    }

    static func hasTraktAuthCode(_ code: String) -> Bool {
        !normalizedText(code).isEmpty
    }

    static func hasSimklCredentials(clientId: String, accessToken: String) -> Bool {
        !normalizedText(clientId).isEmpty && !normalizedText(accessToken).isEmpty
    }

    static func hasUnsavedSecretChange(current: String, initial: String) -> Bool {
        normalizedSecret(current) != normalizedSecret(initial)
    }
}
