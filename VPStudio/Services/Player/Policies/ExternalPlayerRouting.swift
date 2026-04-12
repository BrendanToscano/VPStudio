import Foundation

enum ExternalPlayerApp: String, CaseIterable, Identifiable, Sendable {
    case builtIn = "built_in"
    case infuse
    case skybox
    case moonPlayer = "moonplayer"
    case vlc
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .builtIn:
            return "Built-In Player"
        case .infuse:
            return "Infuse"
        case .skybox:
            return "Skybox"
        case .moonPlayer:
            return "MoonPlayer"
        case .vlc:
            return "VLC"
        case .custom:
            return "Custom URL Scheme"
        }
    }

    var summary: String {
        switch self {
        case .builtIn:
            return "Use VPStudio's built-in playback engine."
        case .infuse:
            return "Launch streams using Infuse URL callbacks."
        case .skybox:
            return "Launch streams using Skybox URL callbacks."
        case .moonPlayer:
            return "Launch streams using MoonPlayer URL callbacks."
        case .vlc:
            return "Launch streams using VLC URL callbacks."
        case .custom:
            return "Use your own URL template. Include the {url} placeholder."
        }
    }

    fileprivate var launchTemplate: String? {
        switch self {
        case .builtIn:
            return nil
        case .infuse:
            return "infuse://x-callback-url/play?url={url}"
        case .skybox:
            return "skybox://open?url={url}"
        case .moonPlayer:
            return "moonplayer://open?url={url}"
        case .vlc:
            return "vlc-x-callback://x-callback-url/stream?url={url}"
        case .custom:
            return nil
        }
    }

    nonisolated static func fromStoredValue(_ rawValue: String?) -> ExternalPlayerApp {
        guard let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty else {
            return .builtIn
        }

        return ExternalPlayerApp(rawValue: normalized) ?? .builtIn
    }
}

struct ExternalPlayerPreference: Sendable, Equatable {
    var app: ExternalPlayerApp
    var customURLTemplate: String?

    init(app: ExternalPlayerApp = .builtIn, customURLTemplate: String? = nil) {
        self.app = app
        self.customURLTemplate = ExternalPlayerRouting.normalizedCustomTemplate(customURLTemplate)
    }

    init(storedApp: String?, customURLTemplate: String?) {
        self.init(
            app: ExternalPlayerApp.fromStoredValue(storedApp),
            customURLTemplate: customURLTemplate
        )
    }

    var usesExternalPlayer: Bool {
        app != .builtIn
    }
}

enum ExternalPlayerTemplateValidation: Equatable {
    case empty
    case valid
    case invalid(String)
}

enum ExternalPlayerRouting {
    nonisolated static let encodedURLPlaceholder = "{url}"
    nonisolated static let rawURLPlaceholder = "{raw_url}"

    nonisolated static func launchURL(for streamURL: URL, app: ExternalPlayerApp, customURLTemplate: String? = nil) -> URL? {
        launchURL(
            for: streamURL,
            preference: ExternalPlayerPreference(app: app, customURLTemplate: customURLTemplate)
        )
    }

    nonisolated static func launchURL(for streamURL: URL, preference: ExternalPlayerPreference) -> URL? {
        guard preference.usesExternalPlayer else { return nil }

        let template: String?
        switch preference.app {
        case .custom:
            template = preference.customURLTemplate
        default:
            template = preference.app.launchTemplate
        }

        guard let normalizedTemplate = normalizedCustomTemplate(template) else { return nil }
        guard case .valid = validationResult(forCustomTemplate: normalizedTemplate) else {
            return nil
        }

        let encodedStreamURL = encodeAsOpaqueComponent(streamURL.absoluteString)
        let hasPlaceholder = normalizedTemplate.contains(encodedURLPlaceholder)

        if hasPlaceholder {
            let resolved = normalizedTemplate
                .replacingOccurrences(of: encodedURLPlaceholder, with: encodedStreamURL)
            return URL(string: resolved)
        }

        if normalizedTemplate.hasSuffix("=") {
            return URL(string: normalizedTemplate + encodedStreamURL)
        }

        guard var components = URLComponents(string: normalizedTemplate),
              components.scheme?.isEmpty == false else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "url", value: streamURL.absoluteString))
        components.queryItems = queryItems
        return components.url
    }

    nonisolated static func normalizedCustomTemplate(_ template: String?) -> String? {
        guard let template else { return nil }
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: rawURLPlaceholder, with: encodedURLPlaceholder)
    }

    nonisolated static func validationResult(forCustomTemplate template: String?) -> ExternalPlayerTemplateValidation {
        guard let normalizedTemplate = normalizedCustomTemplate(template) else {
            return .empty
        }

        let invalidPlaceholders = placeholderTokens(in: normalizedTemplate).filter {
            $0 != encodedURLPlaceholder
        }
        if !invalidPlaceholders.isEmpty {
            let placeholders = invalidPlaceholders.joined(separator: ", ")
            return .invalid("Unsupported placeholder \(placeholders). Use {url}.")
        }

        let scheme = URLComponents(string: normalizedTemplate)?.scheme ?? URL(string: normalizedTemplate)?.scheme
        guard let scheme, !scheme.isEmpty else {
            return .invalid("Template must start with a URL scheme such as player://")
        }

        return .valid
    }

    nonisolated private static func placeholderTokens(in template: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\{[^}]+\}"#) else {
            return []
        }
        let range = NSRange(template.startIndex..<template.endIndex, in: template)
        return regex.matches(in: template, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: template) else { return nil }
            return String(template[swiftRange])
        }
    }

    nonisolated private static func encodeAsOpaqueComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum ExternalPlayerSettings {
    static func loadPreference(from settingsManager: SettingsManager) async -> ExternalPlayerPreference {
        let appValue = try? await settingsManager.getString(key: SettingsKeys.externalPlayerApp)
        let templateValue = try? await settingsManager.getString(key: SettingsKeys.externalPlayerURLTemplate)
        return ExternalPlayerPreference(storedApp: appValue, customURLTemplate: templateValue)
    }
}
