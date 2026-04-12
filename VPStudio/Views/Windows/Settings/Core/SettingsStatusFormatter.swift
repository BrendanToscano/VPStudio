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
    var hasGeminiKey = false
    var hasOllamaEndpoint = true
    var hasOpenRouterKey = false
    var isLocalAIEnabled = false
    var hasUsableLocalModel = false
    var hasTraktCredentials = false
    var hasTraktConnection = false
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

        case .ai:
            let availableProviders = availableAIProviders(for: snapshot)
            let resolvedProvider = AIAssistantManager.resolvedDefaultProvider(
                preferredProvider: snapshot.aiProvider,
                availableProviders: availableProviders
            )

            if let resolvedProvider {
                if resolvedProvider == snapshot.aiProvider {
                    return SettingsDestinationStatus(
                        message: "\(resolvedProvider.displayName) configured",
                        kind: .positive
                    )
                }

                return SettingsDestinationStatus(
                    message: "Using \(resolvedProvider.displayName)",
                    kind: .warning
                )
            }

            if snapshot.aiProvider == .local {
                let provider = snapshot.aiProvider.displayName
                let message = snapshot.isLocalAIEnabled
                    ? "\(provider) needs a downloaded model"
                    : "\(provider) is disabled"
                return SettingsDestinationStatus(message: message, kind: .warning)
            }

            return SettingsDestinationStatus(
                message: "\(snapshot.aiProvider.displayName) needs credentials",
                kind: .warning
            )

        case .trakt:
            if snapshot.hasTraktConnection {
                return SettingsDestinationStatus(message: "Connected", kind: .positive)
            }
            if snapshot.hasTraktCredentials {
                return SettingsDestinationStatus(message: "Ready to connect", kind: .neutral)
            }
            return SettingsDestinationStatus(message: "Not connected", kind: .warning)

        case .simkl:
            if snapshot.hasSimklCredentials {
                return SettingsDestinationStatus(message: "Unavailable in this build", kind: .neutral)
            }
            return SettingsDestinationStatus(message: "Unavailable in this build", kind: .neutral)

        case .imdbImport:
            return SettingsDestinationStatus(message: "CSV import via IMDb exports", kind: .neutral)

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

        case .library:
            return SettingsDestinationStatus(message: "Browse your library", kind: .neutral)

        case .downloads:
            return SettingsDestinationStatus(message: "Manage downloads", kind: .neutral)

        case .resetData:
            return SettingsDestinationStatus(message: "Erase all app data", kind: .neutral)

        case .testMode:
            return SettingsDestinationStatus(message: "9 screens to preview", kind: .neutral)
        }
    }

    private static func availableAIProviders(for snapshot: SettingsStatusSnapshot) -> [AIProviderKind] {
        var cloudProviders: [AIProviderKind] = []
        if snapshot.hasAnthropicKey { cloudProviders.append(.anthropic) }
        if snapshot.hasOpenAIKey { cloudProviders.append(.openAI) }
        if snapshot.hasGeminiKey { cloudProviders.append(.gemini) }
        if snapshot.hasOpenRouterKey { cloudProviders.append(.openRouter) }

        return AIAssistantManager.availableDefaultProviders(
            configuredCloudProviders: cloudProviders,
            hasOllamaEndpoint: snapshot.hasOllamaEndpoint,
            hasUsableLocalProvider: snapshot.isLocalAIEnabled && snapshot.hasUsableLocalModel
        )
    }
}
