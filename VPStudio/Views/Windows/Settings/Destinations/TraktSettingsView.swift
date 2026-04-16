import SwiftUI
import UniformTypeIdentifiers

// MARK: - Trakt Settings

struct TraktSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var isConnected = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var autoScrobble = true
    @State private var syncWatchlist = true
    @State private var syncHistory = true
    @State private var syncRatings = true
    @State private var syncFolders = false
    @State private var isSyncing = false
    @State private var lastSyncDate: String?
    @State private var syncResultMessage: String?

    // Device code flow
    @State private var isAuthenticating = false
    @State private var deviceUserCode: String?
    @State private var deviceVerificationURL: String?
    @State private var pollTask: Task<Void, Never>?

    // Advanced (manual credentials)
    @State private var showAdvanced = false
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var clientIdSaveTask: Task<Void, Never>?
    @State private var clientSecretSaveTask: Task<Void, Never>?
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            connectionSection
            if isConnected {
                syncSection
            }
            syncOptionsSection
            advancedSection
        }
        .navigationTitle("Trakt")
        .task {
            await reloadPersistedState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidChange)) { _ in
            Task { await reloadPersistedState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidResetAllData)) { _ in
            Task { await reloadPersistedState() }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
            flushPendingClientCredentialSaves()
        }
        .onChange(of: autoScrobble) { _, newValue in
            Task { await persistBool(newValue, key: SettingsKeys.traktAutoScrobble) }
        }
        .onChange(of: syncWatchlist) { _, newValue in
            Task { await persistBool(newValue, key: SettingsKeys.traktSyncWatchlist) }
        }
        .onChange(of: syncHistory) { _, newValue in
            Task { await persistBool(newValue, key: SettingsKeys.traktSyncHistory) }
        }
        .onChange(of: syncRatings) { _, newValue in
            Task { await persistBool(newValue, key: SettingsKeys.traktSyncRatings) }
        }
        .onChange(of: syncFolders) { _, newValue in
            Task { await persistBool(newValue, key: SettingsKeys.traktSyncFolders) }
        }
        .alert(
            "Trakt Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Disconnect Trakt?",
            isPresented: $confirmDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops Trakt sync and scrobbling for this app until you sign in again.")
        }
    }

    // MARK: - Connection

    @ViewBuilder
    private var connectionSection: some View {
        Section {
            if isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Disconnect", role: .destructive) {
                    confirmDisconnect = true
                }
            } else if isAuthenticating, let code = deviceUserCode, let urlString = deviceVerificationURL {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Waiting for authorization\u{2026}", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))

                    Text("Go to the link below and enter this code:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Text(code)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)

                        Button {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = code
                            #elseif canImport(AppKit)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Copy Trakt device code")
                        .accessibilityHint("Copies the authorization code to the clipboard.")
                    }

                    Button {
                        if let url = URL(string: urlString) {
                            openURL(url)
                        }
                    } label: {
                        Label(urlString, systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)

                    ProgressView()
                        .controlSize(.small)
                }

                Button("Cancel", role: .cancel) {
                    cancelDeviceFlow()
                }
            } else {
                Button {
                    Task { await startDeviceCodeFlow() }
                } label: {
                    Label("Login with Trakt", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!hasCredentials)

                if !hasCredentials, !TraktDefaults.hasBundledCredentials {
                    Text("Enter your Trakt Client ID and Secret in the Advanced section below to enable login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section("Sync") {
            Button {
                Task { await performSync() }
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing\u{2026}")
                    } else {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .disabled(isSyncing)

            if let lastSyncDate {
                HStack {
                    Text("Last synced")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedSyncDate(lastSyncDate))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if let syncResultMessage {
                Text(syncResultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syncOptionsSection: some View {
        Section("Sync Options") {
            Toggle("Auto-Scrobble", isOn: $autoScrobble)
            Toggle("Sync Watchlist", isOn: $syncWatchlist)
            Toggle("Sync Watch History", isOn: $syncHistory)
            Toggle("Sync Ratings", isOn: $syncRatings)
            Toggle("Sync Folders as Trakt Lists", isOn: $syncFolders)
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedSection: some View {
        Section {
            DisclosureGroup("Trakt API Credentials", isExpanded: $showAdvanced) {
                HStack {
                    TextField("Client ID", text: $clientId)
                    PasteFieldButton { clientId = $0 }
                        .accessibilityLabel("Paste Trakt client ID from clipboard")
                        .accessibilityHint("Pastes the Trakt client ID into the field.")
                }
                HStack {
                    SecureField("Client Secret", text: $clientSecret)
                    PasteFieldButton { clientSecret = $0 }
                        .accessibilityLabel("Paste Trakt client secret from clipboard")
                        .accessibilityHint("Pastes the Trakt client secret into the field.")
                }

                Text(TraktDefaults.hasBundledCredentials
                    ? "Optional: override the built-in Trakt API credentials with your own."
                    : "Register an app at trakt.tv/oauth/applications to get these. Use `urn:ietf:wg:oauth:2.0:oob` as the redirect URI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: clientId) { _, newValue in
            clientIdSaveTask?.cancel()
            clientIdSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await persistString(newValue, key: SettingsKeys.traktClientId)
            }
        }
        .onChange(of: clientSecret) { _, newValue in
            clientSecretSaveTask?.cancel()
            clientSecretSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await persistString(newValue, key: SettingsKeys.traktClientSecret)
            }
        }
    }

    // MARK: - Device Code Flow

    /// Effective credentials: user-entered override or bundled defaults.
    private var resolvedCredentials: (clientId: String, clientSecret: String)? {
        TraktDefaults.resolvedCredentials(
            userClientId: clientId,
            userClientSecret: clientSecret
        )
    }

    private var hasCredentials: Bool {
        resolvedCredentials != nil
    }

    @MainActor
    private func startDeviceCodeFlow() async {
        guard let creds = resolvedCredentials else { return }

        let service = TraktSyncService(clientId: creds.clientId, clientSecret: creds.clientSecret)

        do {
            let deviceCode = try await service.requestDeviceCode()
            errorMessage = nil
            isAuthenticating = true
            deviceUserCode = deviceCode.userCode
            deviceVerificationURL = deviceCode.verificationUrl

            // Open the verification URL automatically
            if let url = URL(string: deviceCode.verificationUrl) {
                openURL(url)
            }

            // Start polling
            pollTask?.cancel()
            pollTask = Task {
                await pollForAuthorization(
                    service: service,
                    deviceCode: deviceCode.deviceCode,
                    interval: deviceCode.interval,
                    expiresIn: deviceCode.expiresIn
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func pollForAuthorization(
        service: TraktSyncService,
        deviceCode: String,
        interval: Int,
        expiresIn: Int
    ) async {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var pollInterval = max(interval, 1)

        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(pollInterval))
            guard !Task.isCancelled else { return }

            do {
                let result = try await service.pollDeviceToken(deviceCode: deviceCode)
                switch result {
                case .pending:
                    continue
                case .slowDown:
                    pollInterval += 1
                    continue
                case .success(let access, let refresh):
                    do {
                        try await appState.settingsManager.setString(key: SettingsKeys.traktAccessToken, value: access)
                        try await appState.settingsManager.setString(key: SettingsKeys.traktRefreshToken, value: refresh)
                        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
                        errorMessage = nil
                        isConnected = true
                        isAuthenticating = false
                        deviceUserCode = nil
                        deviceVerificationURL = nil
                        statusMessage = "Connected to Trakt."
                        return
                    } catch {
                        isAuthenticating = false
                        deviceUserCode = nil
                        deviceVerificationURL = nil
                        errorMessage = error.localizedDescription
                        return
                    }
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    deviceUserCode = nil
                    deviceVerificationURL = nil
                    errorMessage = error.localizedDescription
                }
                return
            }
        }

        if !Task.isCancelled {
            isAuthenticating = false
            deviceUserCode = nil
            deviceVerificationURL = nil
            errorMessage = "Authorization timed out. Please try again."
        }
    }

    private func cancelDeviceFlow() {
        pollTask?.cancel()
        pollTask = nil
        isAuthenticating = false
        deviceUserCode = nil
        deviceVerificationURL = nil
    }

    private func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        Task {
            do {
                try await appState.disconnectTrakt()
                await MainActor.run {
                    isConnected = false
                    isAuthenticating = false
                    deviceUserCode = nil
                    deviceVerificationURL = nil
                    statusMessage = nil
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func reloadPersistedState() async {
        clientId = (try? await appState.settingsManager.getString(key: SettingsKeys.traktClientId)) ?? ""
        clientSecret = (try? await appState.settingsManager.getString(key: SettingsKeys.traktClientSecret)) ?? ""

        if let token = try? await appState.settingsManager.getString(key: SettingsKeys.traktAccessToken),
           !token.isEmpty {
            isConnected = true
            statusMessage = "Connected to Trakt."
        } else {
            isConnected = false
            statusMessage = nil
            isAuthenticating = false
            deviceUserCode = nil
            deviceVerificationURL = nil
        }

        autoScrobble = (try? await appState.settingsManager.getBool(key: SettingsKeys.traktAutoScrobble, default: true)) ?? true
        syncWatchlist = (try? await appState.settingsManager.getBool(key: SettingsKeys.traktSyncWatchlist, default: true)) ?? true
        syncHistory = (try? await appState.settingsManager.getBool(key: SettingsKeys.traktSyncHistory, default: true)) ?? true
        syncRatings = (try? await appState.settingsManager.getBool(key: SettingsKeys.traktSyncRatings, default: true)) ?? true
        syncFolders = (try? await appState.settingsManager.getBool(key: SettingsKeys.traktSyncFolders, default: false)) ?? false
        lastSyncDate = try? await appState.settingsManager.getString(key: SettingsKeys.traktLastSyncDate)
    }

    private func flushPendingClientCredentialSaves() {
        clientIdSaveTask?.cancel()
        clientIdSaveTask = nil
        clientSecretSaveTask?.cancel()
        clientSecretSaveTask = nil

        let pendingClientId = clientId
        let pendingClientSecret = clientSecret
        Task {
            await persistString(pendingClientId, key: SettingsKeys.traktClientId)
            await persistString(pendingClientSecret, key: SettingsKeys.traktClientSecret)
        }
    }

    // MARK: - Sync

    @MainActor
    private func performSync() async {
        isSyncing = true
        syncResultMessage = nil
        defer { isSyncing = false }

        guard let result = await appState.performTraktSyncAndRefreshLocalState() else {
            syncResultMessage = "Cannot sync: Trakt credentials are missing."
            return
        }

        syncResultMessage = result.summary
        lastSyncDate = try? await appState.settingsManager.getString(key: SettingsKeys.traktLastSyncDate)
    }

    private func formattedSyncDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    private func persistBool(_ value: Bool, key: String) async {
        do {
            await MainActor.run {
                errorMessage = nil
            }
            try await appState.settingsManager.setBool(key: key, value: value)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func persistString(_ value: String?, key: String) async {
        do {
            await MainActor.run {
                errorMessage = nil
            }
            try await appState.settingsManager.setString(key: key, value: value)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}
