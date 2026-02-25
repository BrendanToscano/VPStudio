import SwiftUI
import UniformTypeIdentifiers

// MARK: - Metadata Settings

struct MetadataSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var tmdbApiKey = ""
    @State private var initialTMDBApiKey = ""
    @State private var isSaved = false
    @State private var isTestingApiKey = false
    @State private var saveErrorMessage: String?
    @State private var apiKeyTestStatus: APIKeyTestStatus?

    private struct APIKeyTestStatus {
        let message: String
        let isSuccess: Bool

        var symbolName: String {
            isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        }

        var tint: Color {
            isSuccess ? .green : .red
        }

        static func success(_ message: String) -> Self {
            Self(message: message, isSuccess: true)
        }

        static func failure(_ message: String) -> Self {
            Self(message: message, isSuccess: false)
        }
    }

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

                if let status = apiKeyTestStatus {
                    Label(status.message, systemImage: status.symbolName)
                        .font(.caption)
                        .foregroundStyle(status.tint)
                }
            }
        }
        .navigationTitle("TMDB API")
        .task {
            tmdbApiKey = (try? await appState.settingsManager.getString(key: SettingsKeys.tmdbApiKey)) ?? ""
            initialTMDBApiKey = tmdbApiKey
            isSaved = !tmdbApiKey.isEmpty
        }
        .onChange(of: tmdbApiKey) { _, _ in
            isSaved = false
            apiKeyTestStatus = nil
        }
        .alert(
            "Could Not Save TMDB Key",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { saveErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
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
            saveErrorMessage = nil
            NotificationCenter.default.post(name: .tmdbApiKeyDidChange, object: nil)
        } catch {
            isSaved = false
            saveErrorMessage = error.localizedDescription
        }
    }

    private func testTMDBAPIKey() async {
        guard let apiKey = normalizedTMDBApiKey else {
            apiKeyTestStatus = .failure("Enter an API key before testing.")
            return
        }

        isTestingApiKey = true
        defer { isTestingApiKey = false }

        do {
            let service = appState.createMetadataService(apiKey: apiKey)
            _ = try await service.getTrending(type: .movie, timeWindow: .week, page: 1)
            apiKeyTestStatus = .success("TMDB API key is valid.")
        } catch {
            apiKeyTestStatus = .failure("TMDB validation failed: \(error.localizedDescription)")
        }
    }
}

