import SwiftUI
import UniformTypeIdentifiers

// MARK: - Simkl Settings

struct SimklSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var isConnected = false
    @State private var clientId = ""
    @State private var accessToken = ""
    @State private var statusMessage: String?
    @State private var simklClientIdSaveTask: Task<Void, Never>?

    var body: some View {
        Form {
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
                        isConnected = false
                        statusMessage = nil
                        Task {
                            try? await appState.settingsManager.setString(key: SettingsKeys.simklAccessToken, value: nil)
                        }
                    }
                } else {
                    TextField("Client ID", text: $clientId)
                    HStack {
                        SecureField("Access Token", text: $accessToken)
                        PasteFieldButton { accessToken = $0 }
                    }
                    Button("Open Authorization Page") {
                        openAuthorizationPage()
                    }
                    .disabled(SettingsInputValidation.normalizedText(clientId).isEmpty)
                    Button("Save Credentials") {
                        Task {
                            let trimmedClientID = SettingsInputValidation.normalizedText(clientId)
                            let trimmedAccessToken = SettingsInputValidation.normalizedText(accessToken)
                            guard !trimmedClientID.isEmpty, !trimmedAccessToken.isEmpty else { return }
                            try? await appState.settingsManager.setString(key: SettingsKeys.simklClientId, value: trimmedClientID)
                            try? await appState.settingsManager.setString(key: SettingsKeys.simklAccessToken, value: trimmedAccessToken)
                            isConnected = true
                            statusMessage = "Connected with saved token."
                        }
                    }
                    .disabled(!SettingsInputValidation.hasSimklCredentials(clientId: clientId, accessToken: accessToken))
                }
            }
        }
        .navigationTitle("Simkl")
        .task {
            clientId = (try? await appState.settingsManager.getString(key: SettingsKeys.simklClientId)) ?? ""
            if let token = try? await appState.settingsManager.getString(key: SettingsKeys.simklAccessToken),
               !token.isEmpty {
                accessToken = token
                isConnected = true
                statusMessage = "Connected with stored token."
            } else {
                accessToken = ""
                isConnected = false
                statusMessage = nil
            }
        }
        .onChange(of: clientId) { _, newValue in
            simklClientIdSaveTask?.cancel()
            simklClientIdSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                try? await appState.settingsManager.setString(key: SettingsKeys.simklClientId, value: newValue)
            }
        }
        .onDisappear {
            simklClientIdSaveTask?.cancel()
            simklClientIdSaveTask = nil
        }
    }

    private func openAuthorizationPage() {
        let trimmedClientID = SettingsInputValidation.normalizedText(clientId)
        guard !trimmedClientID.isEmpty else { return }
        let service = SimklSyncService(clientId: trimmedClientID)
        Task {
            guard let url = await service.getAuthorizationURL() else { return }
            await MainActor.run {
                openURL(url)
            }
        }
    }
}
