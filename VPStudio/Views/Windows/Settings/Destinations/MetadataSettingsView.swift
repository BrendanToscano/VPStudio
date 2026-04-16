import SwiftUI
import UniformTypeIdentifiers

// MARK: - Metadata Settings

struct MetadataSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var tmdbApiKey = ""
    @State private var initialTMDBApiKey = ""
    @State private var isSaved = false
    @State private var isTestingApiKey = false
    @State private var surfaceError: AppError?
    @State private var notice: SettingsInlineNotice?

    var body: some View {
        Form {
            Section {
                HStack {
                    SecureField("TMDB API Key", text: $tmdbApiKey)
                    PasteFieldButton { tmdbApiKey = $0 }
                }
                Text("Get a free key at themoviedb.org")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save") {
                    Task { await saveTMDBAPIKey() }
                }
                .disabled(!hasUnsavedChanges)

                Button(isTestingApiKey ? "Testing..." : "Test API Key") {
                    Task { await testTMDBAPIKey() }
                }
                .disabled(isTestingApiKey || normalizedTMDBApiKey == nil)

                if isSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if let notice {
                    SettingsNoticeBanner(notice: notice)
                }

                if let surfaceError {
                    SettingsErrorBanner(error: surfaceError)
                }
            }
        }
        .navigationTitle("Movie & TV Metadata (TMDB)")
        .task {
            await loadTMDBAPIKey()
        }
        .onChange(of: tmdbApiKey) { _, _ in
            isSaved = false
            notice = nil
            surfaceError = nil
        }
    }

    private var normalizedTMDBApiKey: String? {
        SettingsInputValidation.normalizedSecret(tmdbApiKey)
    }

    private var hasUnsavedChanges: Bool {
        SettingsInputValidation.hasUnsavedSecretChange(current: tmdbApiKey, initial: initialTMDBApiKey)
    }

    private func saveTMDBAPIKey() async {
        do {
            let normalized = normalizedTMDBApiKey
            try await appState.settingsManager.setString(key: SettingsKeys.tmdbApiKey, value: normalized)
            tmdbApiKey = normalized ?? ""
            initialTMDBApiKey = tmdbApiKey
            isSaved = true
            surfaceError = nil
            notice = .success("TMDB API key saved.")
            NotificationCenter.default.post(name: .tmdbApiKeyDidChange, object: nil)
        } catch {
            isSaved = false
            notice = nil
            surfaceError = AppError(error)
        }
    }

    private func testTMDBAPIKey() async {
        guard let apiKey = normalizedTMDBApiKey else {
            notice = .warning("Enter an API key before testing.")
            surfaceError = nil
            return
        }

        isTestingApiKey = true
        defer { isTestingApiKey = false }

        do {
            let service = appState.createMetadataService(apiKey: apiKey)
            _ = try await service.getTrending(type: .movie, timeWindow: .week, page: 1)
            notice = .success("TMDB API key is valid.")
            surfaceError = nil
        } catch {
            notice = nil
            surfaceError = AppError(error, fallback: .unknown("TMDB validation failed."))
        }
    }

    private func loadTMDBAPIKey() async {
        do {
            tmdbApiKey = (try await appState.settingsManager.getString(key: SettingsKeys.tmdbApiKey)) ?? ""
            initialTMDBApiKey = tmdbApiKey
            isSaved = !tmdbApiKey.isEmpty
            surfaceError = nil
        } catch {
            tmdbApiKey = ""
            initialTMDBApiKey = ""
            isSaved = false
            surfaceError = AppError(error)
        }
    }
}
