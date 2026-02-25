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
        self.customURLTemplate = Self.normalizedTemplate(customURLTemplate)
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

    nonisolated private static func normalizedTemplate(_ template: String?) -> String? {
        guard let template else { return nil }
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
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

        guard let normalizedTemplate = normalizedTemplate(template) else { return nil }

        let encodedStreamURL = encodeForQueryValue(streamURL.absoluteString)
        let hasPlaceholder = normalizedTemplate.contains(encodedURLPlaceholder)
            || normalizedTemplate.contains(rawURLPlaceholder)

        let resolved = normalizedTemplate
            .replacingOccurrences(of: encodedURLPlaceholder, with: encodedStreamURL)
            .replacingOccurrences(of: rawURLPlaceholder, with: streamURL.absoluteString)

        return URL(string: hasPlaceholder ? resolved : resolved + encodedStreamURL)
    }

    nonisolated private static func normalizedTemplate(_ template: String?) -> String? {
        guard let template else { return nil }
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func encodeForQueryValue(_ value: String) -> String {
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
