import SwiftUI

// MARK: - Simkl Settings

struct SimklSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var hasSavedAuthorization = false
    @State private var isShowingDisconnectConfirmation = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Cleanup Only in This Build", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                    Text("Simkl sync and scrobbling are unavailable in this build. This screen is read-only and only lets you review or clear any saved authorization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if hasSavedAuthorization {
                Section("Saved Authorization") {
                    Label("Saved credentials are present", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Button("Disconnect", role: .destructive) {
                        isShowingDisconnectConfirmation = true
                    }
                    .accessibilityHint("Removes any saved Simkl authorization from this device.")
                }
            }
        }
        .navigationTitle("Simkl")
        .alert("Disconnect Simkl?", isPresented: $isShowingDisconnectConfirmation) {
            Button("Disconnect", role: .destructive) {
                disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes any saved Simkl authorization from this device. Simkl remains cleanup-only in this build.")
        }
        .task {
            await loadSavedAuthorizationState()
        }
    }

    @MainActor
    private func loadSavedAuthorizationState() async {
        do {
            let clientId = (try await appState.settingsManager.getString(key: SettingsKeys.simklClientId)) ?? ""
            let accessToken = (try await appState.settingsManager.getString(key: SettingsKeys.simklAccessToken)) ?? ""
            hasSavedAuthorization = SettingsInputValidation.hasSimklCredentials(
                clientId: clientId,
                accessToken: accessToken
            )
            statusMessage = hasSavedAuthorization
                ? "Saved authorization exists, but Simkl remains cleanup-only in this build."
                : "No Simkl authorization is saved."
            errorMessage = nil
        } catch {
            hasSavedAuthorization = false
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        Task {
            do {
                try await appState.settingsManager.setString(key: SettingsKeys.simklClientId, value: nil)
                try await appState.settingsManager.setString(key: SettingsKeys.simklAccessToken, value: nil)
                try await appState.settingsManager.setString(key: SettingsKeys.simklRefreshToken, value: nil)
                NotificationCenter.default.post(name: .settingsDidChange, object: nil)
                await loadSavedAuthorizationState()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
