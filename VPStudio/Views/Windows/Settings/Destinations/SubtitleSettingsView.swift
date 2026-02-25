import SwiftUI
import UniformTypeIdentifiers

// MARK: - Subtitle Settings

struct SubtitleSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var openSubsApiKey = ""
    @State private var preferredLanguage = "en"
    @State private var autoSearch = true
    @State private var fontSize: Double = 24
    @State private var openSubsSaveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("OpenSubtitles") {
                HStack {
                    SecureField("API Key", text: $openSubsApiKey)
                    PasteFieldButton { openSubsApiKey = $0 }
                }
                Text("Get a key at opensubtitles.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preferences") {
                TextField("Preferred Language", text: $preferredLanguage)
                Toggle("Auto-Search Subtitles", isOn: $autoSearch)
            }

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
        .navigationTitle("Subtitles")
        .task {
            openSubsApiKey = (try? await appState.settingsManager.getString(key: SettingsKeys.openSubtitlesApiKey)) ?? ""
            preferredLanguage = (try? await appState.settingsManager.getString(key: SettingsKeys.subtitleLanguage)) ?? "en"
            autoSearch = (try? await appState.settingsManager.getBool(key: SettingsKeys.subtitleAutoSearch, default: true)) ?? true
            if let storedSize = (try? await appState.settingsManager.getString(key: SettingsKeys.subtitleFontSize)),
               let parsed = Double(storedSize) {
                fontSize = max(16, min(48, parsed))
            }
        }
        .onChange(of: openSubsApiKey) { _, newValue in
            openSubsSaveTask?.cancel()
            openSubsSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                try? await appState.settingsManager.setString(key: SettingsKeys.openSubtitlesApiKey, value: newValue)
            }
        }
        .onDisappear {
            openSubsSaveTask?.cancel()
            openSubsSaveTask = nil
        }
        .onChange(of: preferredLanguage) { _, newValue in
            Task { try? await appState.settingsManager.setString(key: SettingsKeys.subtitleLanguage, value: newValue) }
        }
        .onChange(of: autoSearch) { _, newValue in
            Task { try? await appState.settingsManager.setBool(key: SettingsKeys.subtitleAutoSearch, value: newValue) }
        }
        .onChange(of: fontSize) { _, newValue in
            Task {
                try? await appState.settingsManager.setString(
                    key: SettingsKeys.subtitleFontSize,
                    value: String(Int(newValue))
                )
            }
        }
    }
}
