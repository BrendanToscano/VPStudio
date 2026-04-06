import SwiftUI

// MARK: - Subtitle Settings

struct SubtitleSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var openSubsApiKey = ""
    @State private var preferredSubtitleLanguage = "en"
    @State private var preferredAudioLanguage = "en"
    @State private var autoSearch = true
    @State private var fontSize: Double = 24
    @State private var openSubsSaveTask: Task<Void, Never>?
    @State private var surfaceError: AppError?

    var body: some View {
        Form {
            openSubtitlesSection
            languagePreferencesSection
            subtitleBehaviorSection
            appearanceSection

            if let surfaceError {
                Section {
                    SettingsErrorBanner(error: surfaceError)
                }
            }
        }
        .navigationTitle("Subtitles")
        .task { await loadSettings() }
        .onChange(of: openSubsApiKey) { _, newValue in scheduleAPISave(newValue) }
        .onDisappear { openSubsSaveTask?.cancel(); openSubsSaveTask = nil }
        .onChange(of: preferredSubtitleLanguage) { _, newValue in
            Task { await persistStringSetting(key: SettingsKeys.subtitleLanguage, value: newValue) }
        }
        .onChange(of: preferredAudioLanguage) { _, newValue in
            Task { await persistStringSetting(key: SettingsKeys.audioLanguage, value: newValue) }
        }
        .onChange(of: autoSearch) { _, newValue in
            Task { await persistBoolSetting(key: SettingsKeys.subtitleAutoSearch, value: newValue) }
        }
        .onChange(of: fontSize) { _, newValue in
            Task { await persistStringSetting(key: SettingsKeys.subtitleFontSize, value: String(Int(newValue))) }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var openSubtitlesSection: some View {
        Section("OpenSubtitles") {
            HStack {
                SecureField("API Key", text: $openSubsApiKey)
                PasteFieldButton { openSubsApiKey = $0 }
            }
            Text("Get a key at opensubtitles.com")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var languagePreferencesSection: some View {
        Section("Language Preferences") {
            TextField("Preferred Subtitle Language", text: $preferredSubtitleLanguage)
                .disableAutomaticTextEntryAdjustments()
            TextField("Preferred Audio Language", text: $preferredAudioLanguage)
                .disableAutomaticTextEntryAdjustments()
            Text("Language codes such as \"en\", \"es\", \"fr\", \"ja\", \"ko\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var subtitleBehaviorSection: some View {
        Section("Subtitle Behavior") {
            Toggle("Auto-Search Subtitles", isOn: $autoSearch)
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Appearance") {
            HStack {
                Text("Font Size")
                Spacer()
                Text("\(Int(fontSize))pt")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $fontSize, in: 16...48, step: 2)
        }
    }

    // MARK: - Helpers

    private func loadSettings() async {
        var firstError: AppError?

        do {
            openSubsApiKey = (try await appState.settingsManager.getString(key: SettingsKeys.openSubtitlesApiKey)) ?? ""
        } catch {
            firstError = firstError ?? AppError(error)
            openSubsApiKey = ""
        }

        do {
            preferredSubtitleLanguage = (try await appState.settingsManager.getString(key: SettingsKeys.subtitleLanguage)) ?? "en"
        } catch {
            firstError = firstError ?? AppError(error)
            preferredSubtitleLanguage = "en"
        }

        do {
            preferredAudioLanguage = (try await appState.settingsManager.getString(key: SettingsKeys.audioLanguage)) ?? "en"
        } catch {
            firstError = firstError ?? AppError(error)
            preferredAudioLanguage = "en"
        }

        do {
            autoSearch = try await appState.settingsManager.getBool(key: SettingsKeys.subtitleAutoSearch, default: true)
        } catch {
            firstError = firstError ?? AppError(error)
            autoSearch = true
        }

        do {
            if let storedSize = try await appState.settingsManager.getString(key: SettingsKeys.subtitleFontSize),
               let parsed = Double(storedSize) {
                fontSize = max(16, min(48, parsed))
            }
        } catch {
            firstError = firstError ?? AppError(error)
        }

        surfaceError = firstError
    }

    private func scheduleAPISave(_ value: String) {
        openSubsSaveTask?.cancel()
        openSubsSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await persistStringSetting(key: SettingsKeys.openSubtitlesApiKey, value: value)
        }
    }

    private func persistStringSetting(key: String, value: String) async {
        do {
            try await appState.settingsManager.setString(key: key, value: value)
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
        }
    }

    private func persistBoolSetting(key: String, value: Bool) async {
        do {
            try await appState.settingsManager.setBool(key: key, value: value)
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
        }
    }
}
