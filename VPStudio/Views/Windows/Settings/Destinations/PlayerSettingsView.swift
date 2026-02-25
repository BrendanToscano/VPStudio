import SwiftUI

// MARK: - Player Settings

struct PlayerSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var preferredQuality: VideoQuality = .hd1080p
    @State private var autoPlay = true
    @State private var hardwareDecoding = true
    @State private var playerEngineStrategy: PlayerEngineStrategy = .compatibility
    @State private var externalPlayerApp: ExternalPlayerApp = .builtIn
    @State private var externalPlayerTemplate = ""
    @State private var preferCached = true
    @State private var preferAtmos = true
    @State private var hdrPreference: HDRPreference = .auto
    @State private var runtimeDiagnosticsEnabled = false
    @State private var navigationLayout: NavigationLayout = .bottomTabBar

    var body: some View {
        Form {
            navigationSection
            qualitySection
            playbackSection
            engineSection
            playerAppSection
            highFidelitySection
            diagnosticsSection
        }
        .navigationTitle("Playback")
        .task {
            await loadSettings()
        }
        .onChange(of: preferredQuality) { _, newValue in
            savePreferredQuality(newValue)
        }
        .onChange(of: autoPlay) { _, newValue in
            saveAutoPlay(newValue)
        }
        .onChange(of: hardwareDecoding) { _, newValue in
            saveHardwareDecoding(newValue)
        }
        .onChange(of: playerEngineStrategy) { _, newValue in
            savePlayerEngineStrategy(newValue)
        }
        .onChange(of: externalPlayerApp) { _, newValue in
            saveExternalPlayerApp(newValue)
        }
        .onChange(of: externalPlayerTemplate) { _, newValue in
            saveExternalPlayerTemplate(newValue)
        }
        .onChange(of: preferCached) { _, newValue in
            savePreferCached(newValue)
        }
        .onChange(of: preferAtmos) { _, newValue in
            savePreferAtmos(newValue)
        }
        .onChange(of: hdrPreference) { _, newValue in
            saveHDRPreference(newValue)
        }
        .onChange(of: runtimeDiagnosticsEnabled) { _, newValue in
            saveRuntimeDiagnosticsEnabled(newValue)
        }
        .onChange(of: navigationLayout) { _, newValue in
            saveNavigationLayout(newValue)
        }
    }

    private var navigationSection: some View {
        Section("Navigation") {
            Picker("Layout", selection: $navigationLayout) {
                ForEach(NavigationLayout.allCases, id: \.self) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }

            Text("Choose between a bottom tab bar or a left sidebar for navigation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var qualitySection: some View {
        Section("Quality") {
            Picker("Preferred Quality", selection: $preferredQuality) {
                Text("4K").tag(VideoQuality.uhd4k)
                Text("1080p").tag(VideoQuality.hd1080p)
                Text("720p").tag(VideoQuality.hd720p)
            }

            Toggle("Prefer Cached Streams", isOn: $preferCached)
        }
    }

    private var playbackSection: some View {
        Section("Playback") {
            Toggle("Auto-Play", isOn: $autoPlay)
            Toggle("Hardware Decoding", isOn: $hardwareDecoding)
        }
    }

    private var engineSection: some View {
        Section("Engine") {
            Picker("Player Engine Mode", selection: $playerEngineStrategy) {
                ForEach(PlayerEngineStrategy.allCases) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }

            Text(playerEngineStrategy.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var playerAppSection: some View {
        Section("Player App") {
            Picker("Open Streams With", selection: $externalPlayerApp) {
                ForEach(ExternalPlayerApp.allCases) { app in
                    Text(app.displayName).tag(app)
                }
            }

            if externalPlayerApp == .custom {
                TextField(
                    "Custom URL Template",
                    text: $externalPlayerTemplate,
                    prompt: Text("player://open?url={url}")
                )
            }

            Text(externalPlayerApp.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Custom templates should include {url}. Example: vlc-x-callback://x-callback-url/stream?url={url}")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var highFidelitySection: some View {
        Section("High-Fidelity AV") {
            Toggle("Prefer Atmos / Spatial Audio", isOn: $preferAtmos)

            Picker("Preferred HDR", selection: $hdrPreference) {
                ForEach(HDRPreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }

            Text("Playback automatically falls back when stream profile exceeds runtime capabilities.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            Toggle("Enable Runtime Diagnostics", isOn: $runtimeDiagnosticsEnabled)
            Text("When enabled, the app logs resident-memory snapshots around tab switches, library reloads, and player lifecycle transitions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadSettings() async {
        preferredQuality = (try? await appState.settingsManager.getPreferredQuality()) ?? .hd1080p
        autoPlay = (try? await appState.settingsManager.getBool(key: SettingsKeys.autoPlayNext, default: true)) ?? true
        hardwareDecoding = (try? await appState.settingsManager.getBool(key: SettingsKeys.hardwareDecoding, default: true)) ?? true
        let strategyRaw = (try? await appState.settingsManager.getString(key: SettingsKeys.playerEngineStrategy)) ?? ""
        playerEngineStrategy = PlayerEngineStrategy(rawValue: strategyRaw) ?? .compatibility
        let externalPreference = await ExternalPlayerSettings.loadPreference(from: appState.settingsManager)
        externalPlayerApp = externalPreference.app
        externalPlayerTemplate = externalPreference.customURLTemplate ?? ""
        preferCached = (try? await appState.settingsManager.getBool(key: SettingsKeys.preferCachedStreams, default: true)) ?? true
        preferAtmos = (try? await appState.settingsManager.getBool(key: SettingsKeys.preferAtmosAudio, default: true)) ?? true
        if let storedHDR = (try? await appState.settingsManager.getString(key: SettingsKeys.preferredHDRFormat)),
           let parsed = HDRPreference(rawValue: storedHDR) {
            hdrPreference = parsed
        } else {
            hdrPreference = .auto
        }
        runtimeDiagnosticsEnabled = (try? await appState.settingsManager.getBool(
            key: SettingsKeys.runtimeDiagnosticsEnabled,
            default: false
        )) ?? appState.runtimeDiagnosticsEnabled
        appState.runtimeDiagnosticsEnabled = runtimeDiagnosticsEnabled
        if let storedLayout = try? await appState.settingsManager.getString(key: SettingsKeys.navigationLayout),
           let parsed = NavigationLayout(rawValue: storedLayout) {
            navigationLayout = parsed
        } else {
            navigationLayout = appState.navigationLayout
        }
    }

    private func savePreferredQuality(_ value: VideoQuality) {
        Task { try? await appState.settingsManager.setString(key: SettingsKeys.preferredQuality, value: value.rawValue) }
    }

    private func saveAutoPlay(_ value: Bool) {
        Task { try? await appState.settingsManager.setBool(key: SettingsKeys.autoPlayNext, value: value) }
    }

    private func saveHardwareDecoding(_ value: Bool) {
        Task { try? await appState.settingsManager.setBool(key: SettingsKeys.hardwareDecoding, value: value) }
    }

    private func savePlayerEngineStrategy(_ value: PlayerEngineStrategy) {
        Task { try? await appState.settingsManager.setString(key: SettingsKeys.playerEngineStrategy, value: value.rawValue) }
    }

    private func saveExternalPlayerApp(_ value: ExternalPlayerApp) {
        Task { try? await appState.settingsManager.setString(key: SettingsKeys.externalPlayerApp, value: value.rawValue) }
    }

    private func saveExternalPlayerTemplate(_ value: String) {
        Task {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            try? await appState.settingsManager.setString(
                key: SettingsKeys.externalPlayerURLTemplate,
                value: trimmed.isEmpty ? nil : trimmed
            )
        }
    }

    private func savePreferCached(_ value: Bool) {
        Task { try? await appState.settingsManager.setBool(key: SettingsKeys.preferCachedStreams, value: value) }
    }

    private func savePreferAtmos(_ value: Bool) {
        Task { try? await appState.settingsManager.setBool(key: SettingsKeys.preferAtmosAudio, value: value) }
    }

    private func saveHDRPreference(_ value: HDRPreference) {
        Task { try? await appState.settingsManager.setString(key: SettingsKeys.preferredHDRFormat, value: value.rawValue) }
    }

    private func saveRuntimeDiagnosticsEnabled(_ value: Bool) {
        appState.runtimeDiagnosticsEnabled = value
        Task { try? await appState.settingsManager.setBool(key: SettingsKeys.runtimeDiagnosticsEnabled, value: value) }
    }

    private func saveNavigationLayout(_ value: NavigationLayout) {
        appState.navigationLayout = value
        Task { try? await appState.settingsManager.setString(key: SettingsKeys.navigationLayout, value: value.rawValue) }
    }
}
