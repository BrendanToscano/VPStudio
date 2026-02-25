import Foundation

actor SettingsManager {
    private let database: DatabaseManager
    private let secretStore: any SecretStore
    private let secretKeys: Set<String> = [
        SettingsKeys.tmdbApiKey,
        SettingsKeys.openSubtitlesApiKey,
        SettingsKeys.openAIApiKey,
        SettingsKeys.anthropicApiKey,
        SettingsKeys.traktClientId,
        SettingsKeys.traktClientSecret,
        SettingsKeys.traktAccessToken,
        SettingsKeys.traktRefreshToken,
        SettingsKeys.simklAccessToken,
    ]

    private var migratingKeys: Set<String> = []

    init(database: DatabaseManager, secretStore: any SecretStore) {
        self.database = database
        self.secretStore = secretStore
    }

    func getValue(forKey key: String) async throws -> String? {
        guard let stored = try await database.getSetting(key: key) else { return nil }
        guard secretKeys.contains(key) else { return stored }

        if let secretKey = SecretReference.decode(stored) {
            return try await secretStore.getSecret(for: secretKey)
        }

        // Guard against actor-reentrant migration race: if another suspended
        // call is already migrating this key, return the plaintext value
        // (still valid until migration completes).
        guard !migratingKeys.contains(key) else { return stored }
        migratingKeys.insert(key)
        defer { migratingKeys.remove(key) }

        let migratedKey = SecretKey.setting(key)
        try await secretStore.setSecret(stored, for: migratedKey)
        do {
            try await database.setSetting(key: key, value: SecretReference.encode(key: migratedKey))
        } catch {
            // Roll back keychain entry — plaintext value remains in DB, migration will retry next read.
            try? await secretStore.deleteSecret(for: migratedKey)
            return stored
        }
        return stored
    }

    func setValue(_ value: String?, forKey key: String) async throws {
        guard secretKeys.contains(key) else {
            try await database.setSetting(key: key, value: value)
            return
        }

        let secretKey = SecretKey.setting(key)
        if let normalizedValue = normalizedSecretValue(value) {
            try await secretStore.setSecret(normalizedValue, for: secretKey)
            do {
                try await database.setSetting(key: key, value: SecretReference.encode(key: secretKey))
            } catch {
                // Roll back keychain entry to avoid orphaned secrets.
                try? await secretStore.deleteSecret(for: secretKey)
                throw error
            }
        } else {
            try await database.setSetting(key: key, value: nil)
            try? await secretStore.deleteSecret(for: secretKey)
        }
    }

    private func normalizedSecretValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Convenience aliases
    func getString(key: String) async throws -> String? {
        try await getValue(forKey: key)
    }

    func setString(key: String, value: String?) async throws {
        try await setValue(value, forKey: key)
    }

    func getTMDBApiKey() async throws -> String? {
        try await getValue(forKey: SettingsKeys.tmdbApiKey)
    }

    func getPreferredQuality() async throws -> VideoQuality {
        guard let raw = try await getValue(forKey: SettingsKeys.preferredQuality),
              let quality = VideoQuality(rawValue: raw) else { return .hd1080p }
        return quality
    }

    func getFeedbackScaleMode() async throws -> FeedbackScaleMode {
        let raw = try await getValue(forKey: SettingsKeys.feedbackScaleMode)
        return FeedbackScaleMode.fromStoredValue(raw)
    }

    func getBool(key: String, default defaultValue: Bool = false) async throws -> Bool {
        guard let raw = try await getValue(forKey: key) else { return defaultValue }
        return raw == "1" || raw.lowercased() == "true"
    }

    func setBool(key: String, value: Bool) async throws {
        try await setValue(value ? "1" : "0", forKey: key)
    }
}

enum SettingsKeys {
    nonisolated static let tmdbApiKey = "tmdb_api_key"
    nonisolated static let preferredQuality = "preferred_quality"
    nonisolated static let subtitleLanguage = "subtitle_language"
    nonisolated static let subtitleFontSize = "subtitle_font_size"
    nonisolated static let subtitleAutoSearch = "subtitle_auto_search"
    nonisolated static let openSubtitlesApiKey = "opensubtitles_api_key"
    nonisolated static let autoPlayNext = "auto_play_next"
    nonisolated static let hardwareDecoding = "hardware_decoding"
    nonisolated static let playerEngineStrategy = "player_engine_strategy"
    nonisolated static let externalPlayerApp = "external_player_app"
    nonisolated static let externalPlayerURLTemplate = "external_player_url_template"
    nonisolated static let preferCachedStreams = "prefer_cached_streams"
    nonisolated static let preferAtmosAudio = "prefer_atmos_audio"
    nonisolated static let preferredHDRFormat = "preferred_hdr_format"
    nonisolated static let defaultDebridService = "default_debrid_service"

    nonisolated static let openAIApiKey = "openai_api_key"
    nonisolated static let anthropicApiKey = "anthropic_api_key"
    nonisolated static let openAIModelPreset = "openai_model_preset"
    nonisolated static let anthropicModelPreset = "anthropic_model_preset"
    nonisolated static let ollamaEndpoint = "ollama_endpoint"
    nonisolated static let ollamaModelPreset = "ollama_model_preset"
    nonisolated static let defaultAIProvider = "default_ai_provider"
    nonisolated static let aiCompareMode = "ai_compare_mode"

    nonisolated static let traktClientId = "trakt_client_id"
    nonisolated static let traktClientSecret = "trakt_client_secret"
    nonisolated static let traktAccessToken = "trakt_access_token"
    nonisolated static let traktRefreshToken = "trakt_refresh_token"
    nonisolated static let traktAutoScrobble = "trakt_auto_scrobble"
    nonisolated static let traktSyncWatchlist = "trakt_sync_watchlist"
    nonisolated static let traktSyncHistory = "trakt_sync_history"
    nonisolated static let traktSyncRatings = "trakt_sync_ratings"
    nonisolated static let traktLastSyncDate = "trakt_last_sync_date"
    nonisolated static let traktSyncFolders = "trakt_sync_folders"
    nonisolated static let simklClientId = "simkl_client_id"
    nonisolated static let simklAccessToken = "simkl_access_token"

    nonisolated static let lastSelectedTab = "last_selected_tab"
    nonisolated static let personalizationEnabled = "personalization_enabled"
    nonisolated static let preferredEnvironment = "preferred_environment"
    nonisolated static let autoOpenEnvironment = "auto_open_environment"
    nonisolated static let feedbackScaleMode = "feedback_scale_mode"
    nonisolated static let runtimeDiagnosticsEnabled = "runtime_diagnostics_enabled"
    nonisolated static let recentSearches = "recent_searches"
    nonisolated static let navigationLayout = "navigation_layout"
    nonisolated static let discoverAIRecommendationsEnabled = "discover_ai_recommendations_enabled"
    nonisolated static let aiAutoGenerate = "ai_auto_generate"
    nonisolated static let aiCachedRecommendations = "ai_cached_recommendations"

    nonisolated static let playerDimPassthrough = "player_dim_passthrough"
}
