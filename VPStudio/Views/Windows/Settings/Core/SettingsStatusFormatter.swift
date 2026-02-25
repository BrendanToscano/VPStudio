import Foundation

enum SettingsStatusKind: Equatable, Sendable {
    case positive
    case warning
    case neutral
}

struct SettingsDestinationStatus: Equatable, Sendable {
    let message: String
    let kind: SettingsStatusKind
}

struct SettingsStatusSnapshot: Equatable, Sendable {
    var activeDebridCount = 0
    var activeIndexerCount = 0
    var hasTMDBKey = false
    var hasOpenSubtitlesKey = false
    var environmentAssetCount = 0
    var aiProvider: AIProviderKind = .anthropic
    var hasOpenAIKey = false
    var hasAnthropicKey = false
    var hasOllamaEndpoint = true
    var hasTraktCredentials = false
    var hasSimklCredentials = false
}

enum SettingsStatusFormatter {
    static func status(
        for destination: SettingsDestination,
        snapshot: SettingsStatusSnapshot
    ) -> SettingsDestinationStatus {
        switch destination {
        case .debrid:
            if snapshot.activeDebridCount > 0 {
                let suffix = snapshot.activeDebridCount == 1 ? "service" : "services"
                return SettingsDestinationStatus(
                    message: "\(snapshot.activeDebridCount) active \(suffix)",
                    kind: .positive
                )
            }
            return SettingsDestinationStatus(message: "Not configured", kind: .warning)

        case .indexers:
            if snapshot.activeIndexerCount > 0 {
                let suffix = snapshot.activeIndexerCount == 1 ? "indexer" : "indexers"
                return SettingsDestinationStatus(
                    message: "\(snapshot.activeIndexerCount) active \(suffix)",
                    kind: .positive
                )
            }
            return SettingsDestinationStatus(message: "No active indexers", kind: .warning)

        case .metadata:
            if snapshot.hasTMDBKey {
                return SettingsDestinationStatus(message: "API key configured", kind: .positive)
            }
            return SettingsDestinationStatus(message: "API key required", kind: .warning)

        case .player:
            return SettingsDestinationStatus(message: "Playback preferences", kind: .neutral)

        case .subtitles:
            if snapshot.hasOpenSubtitlesKey {
                return SettingsDestinationStatus(message: "OpenSubtitles enabled", kind: .positive)
            }
            return SettingsDestinationStatus(message: "Local subtitles only", kind: .neutral)

        case .environments:
            if snapshot.environmentAssetCount > 0 {
                let suffix = snapshot.environmentAssetCount == 1 ? "asset" : "assets"
                return SettingsDestinationStatus(
                    message: "\(snapshot.environmentAssetCount) \(suffix)",
                    kind: .positive
                )
            }
            return SettingsDestinationStatus(message: "No environments added", kind: .warning)

        case .ai:
            let provider = snapshot.aiProvider.displayName
            let isConfigured: Bool
            switch snapshot.aiProvider {
            case .openAI:
                isConfigured = snapshot.hasOpenAIKey
            case .anthropic:
                isConfigured = snapshot.hasAnthropicKey
            case .ollama:
                isConfigured = snapshot.hasOllamaEndpoint
            }
            if isConfigured {
                return SettingsDestinationStatus(message: "\(provider) configured", kind: .positive)
            }
            return SettingsDestinationStatus(message: "\(provider) needs credentials", kind: .warning)

        case .trakt:
            if snapshot.hasTraktCredentials {
                return SettingsDestinationStatus(message: "Connected", kind: .positive)
            }
            return SettingsDestinationStatus(message: "Not connected", kind: .warning)

        case .simkl:
            if snapshot.hasSimklCredentials {
                return SettingsDestinationStatus(message: "Connected", kind: .positive)
            }
            return SettingsDestinationStatus(message: "Not connected", kind: .warning)
        }
    }
}
