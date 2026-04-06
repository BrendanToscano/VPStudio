import Foundation

enum TMDBOriginalLanguagePolicy {
    /// Returns true when TMDB `with_original_language` should be sent.
    ///
    /// Policy:
    /// - Do not send for default `en-US` only.
    /// - Do not send when multiple languages are selected (TMDB supports one value).
    /// - Do not send for Hindi / related Indian locales to avoid excluding English-titled content.
    /// - Otherwise, send ISO 639-1 code derived from the selected locale.
    static func shouldSendOriginalLanguage(for languageFilters: Set<String>) -> Bool {
        guard languageFilters.count == 1, let localeCode = languageFilters.first else {
            return false
        }

        guard localeCode != "en-US" else {
            return false
        }

        return !isHindiOrRelatedIndianLocale(localeCode)
    }

    static func originalLanguageCode(for languageFilters: Set<String>) -> String? {
        guard shouldSendOriginalLanguage(for: languageFilters),
              let localeCode = languageFilters.first
        else {
            return nil
        }

        return DiscoverFilters.iso639LanguageCode(from: localeCode)
    }

    private static let indianLocaleLanguageCodes: Set<String> = [
        "as", // Assamese
        "bn", // Bengali
        "gu", // Gujarati
        "hi", // Hindi
        "kn", // Kannada
        "ml", // Malayalam
        "mr", // Marathi
        "or", // Odia
        "pa", // Punjabi
        "ta", // Tamil
        "te", // Telugu
        "ur"  // Urdu
    ]

    private static func isHindiOrRelatedIndianLocale(_ localeCode: String) -> Bool {
        let normalized = localeCode.replacingOccurrences(of: "_", with: "-")
        let components = normalized.split(separator: "-").map { String($0).lowercased() }
        guard let languageCode = components.first, !languageCode.isEmpty else {
            return false
        }

        if languageCode == "hi" {
            return true
        }

        // Treat related Indian-language filters as exceptions even when region
        // is omitted, so users still see English-titled catalog entries.
        if components.count == 1, indianLocaleLanguageCodes.contains(languageCode) {
            return true
        }

        let regionCode = components.last?.uppercased()
        return regionCode == "IN" && indianLocaleLanguageCodes.contains(languageCode)
    }
}
