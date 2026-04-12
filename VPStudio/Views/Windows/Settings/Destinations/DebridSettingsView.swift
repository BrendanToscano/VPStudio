import SwiftUI
import UniformTypeIdentifiers

// MARK: - Debrid Settings

struct DebridSettingsView: View {
    static let sharedStreamingServiceTypes: [DebridServiceType] = DebridServiceType.allCases.filter { type in
        type != .easyNews
    }

    @Environment(AppState.self) private var appState
    @State private var configs: [DebridConfig] = []
    @State private var showingAddSheet = false
    @State private var newServiceType: DebridServiceType = .realDebrid
    @State private var newApiKey = ""
    @State private var surfaceError: AppError?
    @State private var testingConfigID: String?
    @State private var updatingConfigID: String?
    @State private var connectivityStatusByConfigID: [String: ConnectivityStatus] = [:]
    @State private var pendingDeletion: PendingDeletion?

    private enum ConnectivityStatus {
        case success(String)
        case failure(AppError)
    }

    private struct PendingDeletion: Identifiable {
        let id: String
        let serviceName: String
    }

    private var trimmedNewApiKey: String {
        newApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveNewService: Bool {
        !trimmedNewApiKey.isEmpty
    }

    private var supportedConfigs: [DebridConfig] {
        configs.filter(\.supportsSharedMagnetResolveFlow)
    }

    private var unsupportedConfigs: [DebridConfig] {
        configs.filter { !$0.supportsSharedMagnetResolveFlow }
    }

    var body: some View {
        List {
            if let surfaceError {
                Section {
                    SettingsErrorBanner(error: surfaceError)
                }
            }

            Section {
                if supportedConfigs.isEmpty {
                    Text("No streaming providers connected yet")
                        .foregroundStyle(.secondary)
                    Text("Connect a provider (like Real-Debrid) so VPStudio can resolve playable streams.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(supportedConfigs, id: \.id) { config in
                        debridRow(config)
                    }
                }
            } header: {
                Text("Configured Services")
            }

            if !unsupportedConfigs.isEmpty {
                Section {
                    Text(EasyNewsService.sharedStreamingExclusionReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(unsupportedConfigs, id: \.id) { config in
                        unsupportedDebridRow(config)
                    }
                } header: {
                    Text("Unsupported in Shared Streaming")
                }
            }

            Section {
                Button("Add Debrid Service", systemImage: "plus") {
                    surfaceError = nil
                    if let firstSupported = Self.sharedStreamingServiceTypes.first {
                        newServiceType = firstSupported
                    }
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
                        ForEach(Self.sharedStreamingServiceTypes) { service in
                            Text(service.displayName).tag(service)
                        }
                    }

                    HStack {
                        SecureField("API Key", text: $newApiKey)
                        PasteFieldButton { newApiKey = $0 }
                            .accessibilityLabel("Paste debrid API key from clipboard")
                            .accessibilityHint("Pastes the debrid API key into the add service form.")
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
        .confirmationDialog(
            "Delete Debrid Service?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { deletion in
            Button("Delete", role: .destructive) {
                guard let config = configs.first(where: { $0.id == deletion.id }) else { return }
                Task { await delete(config) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { deletion in
            Text("Delete \(deletion.serviceName)? This removes the provider and stored API key.")
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
                .accessibilityLabel("\(config.serviceType.displayName) active")
                .accessibilityHint("Turns this provider on or off.")
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
                    pendingDeletion = PendingDeletion(id: config.id, serviceName: config.serviceType.displayName)
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

    @ViewBuilder
    private func unsupportedDebridRow(_ config: DebridConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(config.serviceType.displayName)
                .font(.headline)

            Text("Saved for validation only. This provider is not used by shared streaming in the current runtime.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(testingConfigID == config.id ? "Testing..." : "Validate Token") {
                    Task { await validateConnection(for: config) }
                }
                .buttonStyle(.bordered)
                .disabled(testingConfigID == config.id || updatingConfigID == config.id)

                Button(role: .destructive) {
                    pendingDeletion = PendingDeletion(id: config.id, serviceName: config.serviceType.displayName)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(updatingConfigID == config.id)

                Spacer()
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
                try await appState.secretStore.deleteSecret(for: secretKey)
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
                try await appState.secretStore.deleteSecret(for: secretKey)
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
