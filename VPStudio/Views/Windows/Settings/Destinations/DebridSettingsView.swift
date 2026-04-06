import SwiftUI
import UniformTypeIdentifiers

// MARK: - Debrid Settings

struct DebridSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var configs: [DebridConfig] = []
    @State private var showingAddSheet = false
    @State private var newServiceType: DebridServiceType = .realDebrid
    @State private var newApiKey = ""
    @State private var surfaceError: AppError?
    @State private var testingConfigID: String?
    @State private var updatingConfigID: String?
    @State private var connectivityStatusByConfigID: [String: ConnectivityStatus] = [:]

    private enum ConnectivityStatus {
        case success(String)
        case failure(AppError)
    }

    private var trimmedNewApiKey: String {
        newApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveNewService: Bool {
        !trimmedNewApiKey.isEmpty
    }

    var body: some View {
        List {
            if let surfaceError {
                Section {
                    SettingsErrorBanner(error: surfaceError)
                }
            }

            Section {
                if configs.isEmpty {
                    Text("No streaming providers connected yet")
                        .foregroundStyle(.secondary)
                    Text("Connect a provider (like Real-Debrid) so VPStudio can resolve playable streams.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(configs, id: \.id) { config in
                        debridRow(config)
                    }
                }
            } header: {
                Text("Configured Services")
            }

            Section {
                Button("Add Debrid Service", systemImage: "plus") {
                    surfaceError = nil
                    showingAddSheet = true
                }
            }
        }
        .navigationTitle("Streaming Providers")
        .task {
            await loadConfigs()
        }
        .refreshable {
            await loadConfigs()
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: { surfaceError = nil }) {
            NavigationStack {
                Form {
                    Picker("Service", selection: $newServiceType) {
                        ForEach(DebridServiceType.allCases) { service in
                            Text(service.displayName).tag(service)
                        }
                    }

                    HStack {
                        SecureField("API Key", text: $newApiKey)
                        PasteFieldButton { newApiKey = $0 }
                    }

                    Section {
                        Button("Save") {
                            Task { await saveDebridConfig() }
                        }
                        .disabled(!canSaveNewService)
                    }
                }
                .navigationTitle("Add Service")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddSheet = false }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func debridRow(_ config: DebridConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(config.serviceType.displayName)
                        .font(.headline)
                    Text(config.isActive ? "Active" : "Inactive")
                        .font(.caption)
                        .foregroundStyle(config.isActive ? .green : .secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { config.isActive },
                    set: { newValue in
                        Task { await setActive(newValue, for: config.id) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(updatingConfigID == config.id)
            }

            HStack(spacing: 8) {
                Button(testingConfigID == config.id ? "Testing..." : "Validate Token") {
                    Task { await validateConnection(for: config) }
                }
                .buttonStyle(.bordered)
                .disabled(testingConfigID == config.id || updatingConfigID == config.id)

                Button(role: .destructive) {
                    Task { await delete(config) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(updatingConfigID == config.id)

                Spacer()

                Text("#\(config.priority + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let status = connectivityStatusByConfigID[config.id] {
                switch status {
                case .success(let message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failure(let error):
                    AppErrorInlineView(error: error)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func loadConfigs() async {
        do {
            let fetched = try await appState.database.fetchAllDebridConfigs()
            configs = fetched
            let validIDs = Set(fetched.map(\.id))
            connectivityStatusByConfigID = connectivityStatusByConfigID.filter { validIDs.contains($0.key) }
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
        }
    }

    private func saveDebridConfig() async {
        let normalizedApiKey = trimmedNewApiKey
        guard !normalizedApiKey.isEmpty else { return }

        let configId = UUID().uuidString
        let secretKey = SecretKey.debridToken(service: newServiceType, configId: configId)
        let encodedRef = SecretReference.encode(key: secretKey)
        do {
            try await appState.secretStore.setSecret(normalizedApiKey, for: secretKey)

            let config = DebridConfig(
                id: configId,
                serviceType: newServiceType,
                apiTokenRef: encodedRef,
                isActive: true,
                priority: configs.count,
                createdAt: Date(),
                updatedAt: Date()
            )
            do {
                try await appState.database.saveDebridConfig(config)
            } catch {
                try? await appState.secretStore.deleteSecret(for: secretKey)
                throw error
            }

            try await appState.debridManager.initialize()
            await loadConfigs()
            newApiKey = ""
            showingAddSheet = false
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
        }
    }

    private func setActive(_ active: Bool, for configID: String) async {
        guard let index = configs.firstIndex(where: { $0.id == configID }) else { return }
        updatingConfigID = configID
        defer { updatingConfigID = nil }

        var updated = configs
        updated[index].isActive = active

        do {
            try await saveConfigs(updated)
            try await appState.debridManager.initialize()
            connectivityStatusByConfigID[configID] = nil
            await loadConfigs()
        } catch {
            surfaceError = AppError(error)
        }
    }

    private func delete(_ config: DebridConfig) async {
        updatingConfigID = config.id
        defer { updatingConfigID = nil }

        do {
            try await appState.database.deleteDebridConfig(id: config.id)
            if let secretKey = SecretReference.decode(config.apiTokenRef) {
                try? await appState.secretStore.deleteSecret(for: secretKey)
            }

            let remaining = try await appState.database.fetchAllDebridConfigs()
            try await saveConfigs(remaining)
            try await appState.debridManager.initialize()
            connectivityStatusByConfigID[config.id] = nil
            await loadConfigs()
        } catch {
            surfaceError = AppError(error)
        }
    }

    private func validateConnection(for config: DebridConfig) async {
        testingConfigID = config.id
        defer { testingConfigID = nil }

        do {
            guard let token = try await resolveToken(for: config) else {
                connectivityStatusByConfigID[config.id] = .failure(.unknown("No API token found for this configuration."))
                return
            }

            let service = makeDebridService(type: config.serviceType, token: token)
            let isValid = try await service.validateToken()
            if isValid {
                connectivityStatusByConfigID[config.id] = .success("\(config.serviceType.displayName) token is valid.")
            } else {
                connectivityStatusByConfigID[config.id] = .failure(.unknown("\(config.serviceType.displayName) token was rejected."))
            }
        } catch {
            connectivityStatusByConfigID[config.id] = .failure(AppError(error))
        }
    }

    private func saveConfigs(_ input: [DebridConfig]) async throws {
        let now = Date()
        let normalized = input
            .sorted { lhs, rhs in lhs.priority < rhs.priority }
            .enumerated()
            .map { offset, config in
                var copy = config
                copy.priority = offset
                copy.updatedAt = now
                return copy
            }

        for config in normalized {
            try await appState.database.saveDebridConfig(config)
        }
    }

    private func resolveToken(for config: DebridConfig) async throws -> String? {
        if let secretKey = SecretReference.decode(config.apiTokenRef) {
            return try await appState.secretStore.getSecret(for: secretKey)
        }

        let token = config.apiTokenRef.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private func makeDebridService(type: DebridServiceType, token: String) -> any DebridServiceProtocol {
        switch type {
        case .realDebrid:
            return RealDebridService(apiToken: token)
        case .allDebrid:
            return AllDebridService(apiToken: token)
        case .premiumize:
            return PremiumizeService(apiToken: token)
        case .torBox:
            return TorBoxService(apiToken: token)
        case .debridLink:
            return DebridLinkService(apiToken: token)
        case .offcloud:
            return OffcloudService(apiToken: token)
        case .easyNews:
            return EasyNewsService(apiToken: token)
        }
    }
}
