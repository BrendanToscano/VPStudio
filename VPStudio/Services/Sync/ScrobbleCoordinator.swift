import Foundation

/// Coordinates scrobbling with external services (Trakt, Simkl) during playback.
///
/// Call `startPlayback`, `pausePlayback`, `resumePlayback`, and `stopPlayback`
/// from PlayerView at the appropriate lifecycle moments. The coordinator reads
/// the user's sync preferences and only scrobbles when enabled.
actor ScrobbleCoordinator {
    private let settingsManager: SettingsManager
    private let secretStore: any SecretStore

    private var traktService: TraktSyncService?
    private var activeMediaId: String?
    private var activeMediaType: MediaType?
    private var isScrobbling = false

    init(settingsManager: SettingsManager, secretStore: any SecretStore) {
        self.settingsManager = settingsManager
        self.secretStore = secretStore
    }

    /// Call when playback begins for a media item.
    func startPlayback(mediaId: String, mediaType: MediaType, progress: Double) async {
        activeMediaId = mediaId
        activeMediaType = mediaType

        guard await isTraktScrobbleEnabled() else { return }
        guard let service = await traktServiceIfAvailable() else { return }

        do {
            try await service.startScrobble(imdbId: mediaId, type: mediaType, progress: progress)
            isScrobbling = true
        } catch {
            // Scrobble failures are non-fatal — don't interrupt playback.
        }
    }

    /// Call when playback is paused.
    func pausePlayback(progress: Double) async {
        guard isScrobbling, let mediaId = activeMediaId, let mediaType = activeMediaType else { return }
        guard let service = traktService else { return }

        do {
            try await service.pauseScrobble(imdbId: mediaId, type: mediaType, progress: progress)
        } catch {
            // Non-fatal
        }
    }

    /// Call when playback resumes from pause.
    func resumePlayback(progress: Double) async {
        guard isScrobbling, let mediaId = activeMediaId, let mediaType = activeMediaType else { return }
        guard let service = traktService else { return }

        do {
            try await service.startScrobble(imdbId: mediaId, type: mediaType, progress: progress)
        } catch {
            // Non-fatal
        }
    }

    /// Call when playback ends (user closes player or video finishes).
    func stopPlayback(progress: Double) async {
        guard isScrobbling, let mediaId = activeMediaId, let mediaType = activeMediaType else { return }
        guard let service = traktService else { return }

        do {
            try await service.stopScrobble(imdbId: mediaId, type: mediaType, progress: progress)
        } catch {
            // Non-fatal
        }

        // Also add to history if enabled and progress is meaningful (>80%)
        if progress > 80, await isTraktHistoryEnabled() {
            try? await service.addToHistory(imdbId: mediaId, type: mediaType)
        }

        isScrobbling = false
        activeMediaId = nil
        activeMediaType = nil
    }

    // MARK: - Private

    private func isTraktScrobbleEnabled() async -> Bool {
        (try? await settingsManager.getBool(key: SettingsKeys.traktAutoScrobble, default: false)) ?? false
    }

    private func isTraktHistoryEnabled() async -> Bool {
        (try? await settingsManager.getBool(key: SettingsKeys.traktSyncHistory, default: true)) ?? true
    }

    private func traktServiceIfAvailable() async -> TraktSyncService? {
        if let service = traktService { return service }

        let userClientId = try? await settingsManager.getString(key: SettingsKeys.traktClientId)
        let userClientSecret = try? await settingsManager.getString(key: SettingsKeys.traktClientSecret)
        guard let creds = TraktDefaults.resolvedCredentials(
            userClientId: userClientId,
            userClientSecret: userClientSecret
        ) else { return nil }
        let clientId = creds.clientId
        let clientSecret = creds.clientSecret

        let service = TraktSyncService(
            clientId: clientId,
            clientSecret: clientSecret,
            onTokensRefreshed: { [settingsManager] access, refresh in
                try? await settingsManager.setString(key: SettingsKeys.traktAccessToken, value: access)
                if let refresh {
                    try? await settingsManager.setString(key: SettingsKeys.traktRefreshToken, value: refresh)
                }
            }
        )

        if let accessToken = try? await settingsManager.getString(key: SettingsKeys.traktAccessToken),
           !accessToken.isEmpty {
            let refreshToken = try? await settingsManager.getString(key: SettingsKeys.traktRefreshToken)
            await service.setTokens(access: accessToken, refresh: refreshToken)
        } else {
            return nil
        }

        traktService = service
        return service
    }
}
