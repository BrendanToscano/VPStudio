import Foundation

enum SettingsCategory: String, CaseIterable, Sendable, Equatable, Identifiable {
    case services
    case playback
    case intelligence
    case sync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .services: return "Services"
        case .playback: return "Playback"
        case .intelligence: return "Intelligence"
        case .sync: return "Sync"
        }
    }
}

enum SettingsDestination: String, CaseIterable, Sendable, Identifiable {
    case debrid
    case indexers
    case metadata
    case player
    case subtitles
    case environments
    case ai
    case trakt
    case simkl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .debrid: return "Streaming Providers (Debrid)"
        case .indexers: return "Search Providers"
        case .metadata: return "Movie & TV Metadata (TMDB)"
        case .player: return "Playback"
        case .subtitles: return "Subtitles"
        case .environments: return "Environments"
        case .ai: return "AI Recommendations"
        case .trakt: return "Trakt"
        case .simkl: return "Simkl"
        }
    }

    var icon: String {
        switch self {
        case .debrid: return "cloud"
        case .indexers: return "magnifyingglass.circle"
        case .metadata: return "film"
        case .player: return "play.circle"
        case .subtitles: return "captions.bubble"
        case .environments: return "mountain.2"
        case .ai: return "brain"
        case .trakt: return "arrow.triangle.2.circlepath"
        case .simkl: return "arrow.triangle.2.circlepath.circle"
        }
    }

    var summary: String {
        switch self {
        case .debrid:
            return "Connect and prioritize debrid providers so streams can resolve reliably."
        case .indexers:
            return "Add search providers so VPStudio can find sources quickly."
        case .metadata:
            return "Add your TMDB key for posters, details, and Discover results."
        case .player:
            return "Tune stream preferences and playback behavior."
        case .subtitles:
            return "Set subtitle language, auto-search, and typography."
        case .environments:
            return "Import and control immersive environment assets."
        case .ai:
            return "Connect an AI provider for personalized recommendations and rating help."
        case .trakt:
            return "Connect Trakt to sync watch history, ratings, and watchlist."
        case .simkl:
            return "Connect Simkl to sync watch history and list progress."
        }
    }

    var category: SettingsCategory {
        switch self {
        case .debrid, .indexers, .metadata:
            return .services
        case .player, .subtitles, .environments:
            return .playback
        case .ai:
            return .intelligence
        case .trakt, .simkl:
            return .sync
        }
    }

    /// Whether this destination represents a service that requires explicit user
    /// configuration (API key, credentials, provider setup) to function.
    /// Destinations that work out-of-the-box with sensible defaults are not essential.
    var isEssential: Bool {
        switch self {
        case .debrid, .indexers, .metadata, .ai, .trakt, .simkl:
            return true
        case .player, .subtitles, .environments:
            return false
        }
    }

    var searchTokens: [String] {
        switch self {
        case .debrid:
            return ["realdebrid", "all debrid", "premiumize", "offcloud", "torbox", "token", "provider"]
        case .indexers:
            return ["torznab", "jackett", "prowlarr", "zilean", "stremio", "search"]
        case .metadata:
            return ["tmdb", "movie database", "api key"]
        case .player:
            return ["playback", "quality", "stream", "hdr", "audio", "hardware"]
        case .subtitles:
            return ["opensubtitles", "caption", "language", "font"]
        case .environments:
            return ["immersive", "skybox", "hdri", "usdz", "reality"]
        case .ai:
            return ["openai", "anthropic", "ollama", "llm", "assistant", "ratings", "imdb", "csv", "import"]
        case .trakt:
            return ["watch history", "watchlist", "oauth", "scrobble"]
        case .simkl:
            return ["simkl", "oauth", "watchlist", "history"]
        }
    }

    func matches(_ normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }

        let terms = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        let haystack = ([title, summary] + searchTokens).joined(separator: " ").lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}

struct SettingsDestinationGroup: Equatable, Sendable, Identifiable {
    var id: SettingsCategory { category }
    let category: SettingsCategory
    let destinations: [SettingsDestination]
}

enum SettingsNavigationCatalog {
    static let orderedDestinations: [SettingsDestination] = [
        .debrid,
        .indexers,
        .metadata,
        .player,
        .subtitles,
        .environments,
        .ai,
        .trakt,
        .simkl,
    ]

    /// Destinations that require explicit user setup to function.
    /// Used as the denominator for configuration health scoring.
    static var essentialDestinations: [SettingsDestination] {
        orderedDestinations.filter(\.isEssential)
    }

    static func destination(from rawValue: String?) -> SettingsDestination? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        return SettingsDestination(rawValue: rawValue)
    }

    static func groups(matching query: String) -> [SettingsDestinationGroup] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return SettingsCategory.allCases.compactMap { category in
            let filtered = orderedDestinations.filter { destination in
                destination.category == category && destination.matches(normalizedQuery)
            }

            guard !filtered.isEmpty else { return nil }
            return SettingsDestinationGroup(category: category, destinations: filtered)
        }
    }
}
