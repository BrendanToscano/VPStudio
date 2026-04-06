import Foundation

enum SettingsCategory: String, CaseIterable, Sendable, Equatable, Identifiable {
    case connect
    case watch
    case discover
    case library
    case about

    var id: String { rawValue }

    /// Display title shown as the section header in the Settings list.
    var title: String {
        switch self {
        case .connect:
            return "Connect"
        case .watch:
            return "Watch"
        case .discover:
            return "Discover"
        case .library:
            return "Library"
        case .about:
            return "About"
        }
    }

    /// Subtitle shown below the title in the section header to explain the category.
    var subtitle: String {
        switch self {
        case .connect:
            return "Accounts, providers, and API keys"
        case .watch:
            return "Playback, quality, and subtitles"
        case .discover:
            return "Environments and browsing"
        case .library:
            return "Downloads and local content"
        case .about:
            return "App info, health, and data"
        }
    }
}

enum SettingsDestination: String, CaseIterable, Sendable, Identifiable {
    case debrid
    case indexers
    case metadata
    case ai
    case trakt
    case simkl
    case imdbImport
    case player
    case subtitles
    case environments
    case library
    case downloads
    case resetData
    case testMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .debrid:
            return "Streaming Providers (Debrid)"
        case .indexers:
            return "Search Providers"
        case .metadata:
            return "Movie & TV Metadata (TMDB)"
        case .ai:
            return "AI Recommendations"
        case .trakt:
            return "Trakt"
        case .simkl:
            return "Simkl"
        case .imdbImport:
            return "IMDb Import"
        case .player:
            return "Playback"
        case .subtitles:
            return "Subtitles"
        case .environments:
            return "Environments"
        case .library:
            return "Library"
        case .downloads:
            return "Downloads"
        case .resetData:
            return "Reset All Data"
        case .testMode:
            return "Test Mode"
        }
    }

    var icon: String {
        switch self {
        case .debrid:
            return "cloud"
        case .indexers:
            return "magnifyingglass.circle"
        case .metadata:
            return "film"
        case .ai:
            return "brain"
        case .trakt:
            return "arrow.triangle.2.circlepath"
        case .simkl:
            return "arrow.triangle.2.circlepath.circle"
        case .imdbImport:
            return "film.stack"
        case .player:
            return "play.circle"
        case .subtitles:
            return "captions.bubble"
        case .environments:
            return "mountain.2"
        case .library:
            return "books.vertical"
        case .downloads:
            return "arrow.down.circle"
        case .resetData:
            return "trash"
        case .testMode:
            return "flame"
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
        case .ai:
            return "Connect an AI provider for personalized recommendations and rating help."
        case .trakt:
            return "Connect Trakt to sync watch history, ratings, and watchlist."
        case .simkl:
            return "Connect Simkl to sync watch history and list progress."
        case .imdbImport:
            return "Import your IMDb watchlist, ratings, and watch history from CSV exports."
        case .player:
            return "Tune stream preferences and playback behavior."
        case .subtitles:
            return "Set subtitle language, auto-search, and typography."
        case .environments:
            return "Import and control immersive environment assets."
        case .library:
            return "Browse your locally saved and imported content."
        case .downloads:
            return "View and manage your downloaded episodes and movies."
        case .resetData:
            return "Permanently erase all settings, credentials, and local data."
        case .testMode:
            return "Visual QA: preview all screens with mock data, no credentials required."
        }
    }

    var category: SettingsCategory {
        switch self {
        case .debrid, .indexers, .metadata, .ai, .trakt, .simkl, .imdbImport:
            return .connect
        case .player, .subtitles:
            return .watch
        case .environments:
            return .discover
        case .library, .downloads:
            return .library
        case .resetData:
            return .about
        case .testMode:
            return .about
        }
    }

    /// Whether this destination represents a service that requires explicit user
    /// configuration (API key, credentials, provider setup) to function.
    /// Destinations that work out-of-the-box with sensible defaults are not essential.
    var isEssential: Bool {
        switch self {
        case .debrid, .indexers, .metadata, .ai, .trakt, .simkl:
            return true
        case .player, .subtitles, .environments, .library, .downloads, .resetData, .imdbImport, .testMode:
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
        case .ai:
            return ["openai", "anthropic", "ollama", "llm", "assistant", "ratings", "imdb", "csv", "import", "local", "on-device", "mlx", "download model", "qwen", "phi", "llama"]
        case .trakt:
            return ["watch history", "watchlist", "oauth", "scrobble"]
        case .simkl:
            return ["simkl", "oauth", "watchlist", "history"]
        case .imdbImport:
            return ["imdb", "import", "csv", "watchlist", "ratings", "watch history", "export"]
        case .player:
            return ["playback", "quality", "stream", "hdr", "audio", "hardware"]
        case .subtitles:
            return ["opensubtitles", "caption", "language", "font"]
        case .environments:
            return ["immersive", "skybox", "hdri", "usdz", "reality"]
        case .library:
            return ["saved", "imported", "collection", "local"]
        case .downloads:
            return ["offline", "saved episodes", "downloaded movies"]
        case .resetData:
            return ["erase", "delete all", "factory reset", "wipe"]
        case .testMode:
            return ["test", "qa", "preview", "visual", "mock", "debug"]
        }
    }

    func matches(_ normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }

        let terms = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        let haystack = ([title, summary] + searchTokens)
            .joined(separator: " ")
            .lowercased()

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
        .ai,
        .trakt,
        .simkl,
        .imdbImport,
        .player,
        .subtitles,
        .environments,
        .library,
        .downloads,
        .resetData,
        .testMode,
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
