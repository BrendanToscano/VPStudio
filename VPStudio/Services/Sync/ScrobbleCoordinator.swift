import Foundation

/// Coordinates scrobbling with external services (Trakt, Simkl) during playback.
///
/// Call `startPlayback`, `pausePlayback`, `resumePlayback`, and `stopPlayback`
/// from PlayerView at the appropriate lifecycle moments. The coordinator reads
/// the user's sync preferences and only scrobbles when enabled.
actor ScrobbleCoordinator {
    private struct TraktRuntimeConfiguration: Equatable, Sendable {
        let clientId: String
        let clientSecret: String
        let accessToken: String
        let refreshToken: String?
    }

    private let settingsManager: SettingsManager
    private let secretStore: any SecretStore
    private let session: URLSession?

    private var traktService: TraktSyncService?
    private var traktConfiguration: TraktRuntimeConfiguration?
    private var activeMediaId: String?
    private var activeMediaType: MediaType?
    private var activeEpisodeId: String?
    private var isScrobbling = false
    private(set) var lastErrorMessage: String?

    init(
        settingsManager: SettingsManager,
        secretStore: any SecretStore,
        session: URLSession? = nil
    ) {
        self.settingsManager = settingsManager
        self.secretStore = secretStore
        self.session = session
    }

    /// Call when playback begins for a media item.
    func startPlayback(
        mediaId: String,
        mediaType: MediaType,
        progress: Double,
        episodeId: String? = nil
    ) async {
        activeMediaId = mediaId
        activeMediaType = mediaType
        activeEpisodeId = episodeId
        lastErrorMessage = nil

        guard await isTraktScrobbleEnabled() else { return }
        guard let service = await traktServiceIfAvailable() else { return }
        let normalizedProgress = normalizedScrobbleProgress(progress)

        do {
            try await service.startScrobble(imdbId: mediaId, type: mediaType, progress: normalizedProgress)
            isScrobbling = true
        } catch {
            recordError(error, operation: "Trakt start scrobble failed")
        }
    }

    /// Call when playback is paused.
    func pausePlayback(progress: Double) async {
        guard isScrobbling, let mediaId = activeMediaId, let mediaType = activeMediaType else { return }
        guard let service = await traktServiceIfAvailable() else { return }
        let normalizedProgress = normalizedScrobbleProgress(progress)

        do {
            try await service.pauseScrobble(imdbId: mediaId, type: mediaType, progress: normalizedProgress)
        } catch {
            recordError(error, operation: "Trakt pause scrobble failed")
        }
    }

    /// Call when playback resumes from pause.
    func resumePlayback(progress: Double) async {
        guard isScrobbling, let mediaId = activeMediaId, let mediaType = activeMediaType else { return }
        guard let service = await traktServiceIfAvailable() else { return }
        let normalizedProgress = normalizedScrobbleProgress(progress)

        do {
            try await service.startScrobble(imdbId: mediaId, type: mediaType, progress: normalizedProgress)
        } catch {
            recordError(error, operation: "Trakt resume scrobble failed")
        }
    }

    /// Call when playback ends (user closes player or video finishes).
    func stopPlayback(progress: Double) async {
        guard let mediaId = activeMediaId, let mediaType = activeMediaType else { return }
        let normalizedProgress = normalizedScrobbleProgress(progress)
        let service = await traktServiceIfAvailable()

        if isScrobbling, let service {
            do {
                try await service.stopScrobble(imdbId: mediaId, type: mediaType, progress: normalizedProgress)
            } catch {
                recordError(error, operation: "Trakt stop scrobble failed")
            }
        }

        // Also add to history if enabled and progress is meaningful (>80%)
        if normalizedProgress > 80, await isTraktHistoryEnabled(), let service {
            do {
                try await service.addToHistory(
                    imdbId: mediaId,
                    type: mediaType,
                    episodeId: activeEpisodeId
                )
            } catch {
                recordError(error, operation: "Trakt history sync failed")
            }
        }

        isScrobbling = false
        activeMediaId = nil
        activeMediaType = nil
        activeEpisodeId = nil
    }

    func invalidateTraktSession() {
        traktService = nil
        traktConfiguration = nil
        isScrobbling = false
        activeMediaId = nil
        activeMediaType = nil
        activeEpisodeId = nil
        lastErrorMessage = nil
    }

    // MARK: - Private

    private func isTraktScrobbleEnabled() async -> Bool {
        (try? await settingsManager.getBool(key: SettingsKeys.traktAutoScrobble, default: false)) ?? false
    }

    private func isTraktHistoryEnabled() async -> Bool {
        (try? await settingsManager.getBool(key: SettingsKeys.traktSyncHistory, default: true)) ?? true
    }

    private func normalizedScrobbleProgress(_ progress: Double) -> Double {
        let clamped = max(progress, 0)
        if clamped <= 1 {
            return clamped * 100
        }
        return min(clamped, 100)
    }

    private func traktServiceIfAvailable() async -> TraktSyncService? {
        guard let configuration = await currentTraktConfiguration() else {
            invalidateTraktSession()
            return nil
        }

        if let service = traktService,
           traktConfiguration?.clientId == configuration.clientId,
           traktConfiguration?.clientSecret == configuration.clientSecret {
            await service.setTokens(access: configuration.accessToken, refresh: configuration.refreshToken)
            traktConfiguration = configuration
            return service
        }

        let service = TraktSyncService(
            clientId: configuration.clientId,
            clientSecret: configuration.clientSecret,
            session: session,
            onTokensRefreshed: { [weak self] access, refresh in
                guard let self else { return }
                await self.persistRefreshedTraktTokens(access: access, refresh: refresh)
            }
        )

        await service.setTokens(access: configuration.accessToken, refresh: configuration.refreshToken)
        traktService = service
        traktConfiguration = configuration
        return service
    }

    private func currentTraktConfiguration() async -> TraktRuntimeConfiguration? {
        let userClientId = try? await settingsManager.getString(key: SettingsKeys.traktClientId)
        let userClientSecret = try? await settingsManager.getString(key: SettingsKeys.traktClientSecret)
        guard let credentials = TraktDefaults.resolvedCredentials(
            userClientId: userClientId,
            userClientSecret: userClientSecret
        ) else { return nil }

        guard let storedAccessToken = try? await settingsManager.getString(key: SettingsKeys.traktAccessToken) else {
            return nil
        }
        let accessToken = storedAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else { return nil }

        let refreshToken = (try? await settingsManager.getString(key: SettingsKeys.traktRefreshToken))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRefreshToken = refreshToken?.isEmpty == false ? refreshToken : nil

        return TraktRuntimeConfiguration(
            clientId: credentials.clientId,
            clientSecret: credentials.clientSecret,
            accessToken: accessToken,
            refreshToken: resolvedRefreshToken
        )
    }

    private func persistRefreshedTraktTokens(access: String, refresh: String?) async {
        do {
            try await settingsManager.setString(key: SettingsKeys.traktAccessToken, value: access)
            try await settingsManager.setString(key: SettingsKeys.traktRefreshToken, value: refresh)
        } catch {
            recordError(error, operation: "Trakt token refresh persistence failed")
        }
    }

    private func recordError(_ error: Error, operation: String) {
        lastErrorMessage = "\(operation): \(error.localizedDescription)"
    }
}
