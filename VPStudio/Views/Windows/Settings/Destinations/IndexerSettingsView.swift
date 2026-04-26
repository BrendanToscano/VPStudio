import SwiftUI
import UniformTypeIdentifiers

// MARK: - Indexer Settings

struct IndexerSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var configs: [IndexerConfig] = []
    @State private var isShowingEditor = false
    @State private var draft = IndexerDraft.new()
    @State private var surfaceError: AppError?
    @State private var notice: SettingsInlineNotice?
    @State private var testingConfigID: String?
    @State private var pendingDeletion: PendingDeletion?

    private struct PendingDeletion: Identifiable {
        let id: String
        let name: String
    }

    var body: some View {
        indexerList
            .navigationTitle("Indexers")
            .task {
                await loadConfigs()
            }
            .refreshable {
                await loadConfigs()
            }
            .sheet(isPresented: $isShowingEditor) {
                editorSheet
            }
            .confirmationDialog(
                "Delete Indexer?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { deletion in
                Button("Delete", role: .destructive) {
                    Task { await delete(configID: deletion.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { deletion in
                Text("Delete \(deletion.name)? This removes the indexer and stored API key.")
            }
    }

    private var indexerList: some View {
        List {
            if let notice {
                Section {
                    SettingsNoticeBanner(notice: notice)
                }
            }

            if let surfaceError {
                Section {
                    SettingsErrorBanner(error: surfaceError)
                }
            }

            Section("Configured Indexers") {
                if configs.isEmpty {
                    Text("No indexers configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(configs) { config in
                        indexerRow(config)
                    }
                }
            }
            addCustomSection
            reAddBuiltInsSection
        }
    }



    private var addCustomSection: some View {
        Section {
            Button("Add Custom Indexer", systemImage: "plus") {
                draft = .new()
                isShowingEditor = true
            }
        }
    }

    @ViewBuilder
    private var reAddBuiltInsSection: some View {
        let missing = IndexerDefaultRanking.deletedBuiltIns(from: configs)
        if !missing.isEmpty {
            Section("Re-add Built-in Indexer") {
                ForEach(missing, id: \.id) { definition in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(definition.name)
                                .font(.headline)
                            Text(definition.type.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add") {
                            Task { await addBuiltIn(definition) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var editorSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draft.name)

                Picker("Type", selection: $draft.indexerType) {
                    Text("Jackett").tag(IndexerConfig.IndexerType.jackett)
                    Text("Prowlarr").tag(IndexerConfig.IndexerType.prowlarr)
                    Text("Torznab").tag(IndexerConfig.IndexerType.torznab)
                    Text("Zilean").tag(IndexerConfig.IndexerType.zilean)
                    Text("Stremio Addon").tag(IndexerConfig.IndexerType.stremio)
                }
                .onChange(of: draft.indexerType) { _, newType in
                    draft.applyDefaults(for: newType)
                }

                TextField("Base URL", text: $draft.baseURL)

                if draft.showsAPIKeyField {
                    HStack {
                        SecureField("API Key", text: $draft.apiKey)
                        PasteFieldButton { draft.apiKey = $0 }
                    }
                }

                if draft.showsAPIKeyTransportField {
                    Picker("API Key Transport", selection: $draft.apiKeyTransport) {
                        Text("Query Param").tag(IndexerConfig.APIKeyTransport.query)
                        Text("Header").tag(IndexerConfig.APIKeyTransport.header)
                    }
                }

                if draft.showsEndpointPathField {
                    TextField("Endpoint Path", text: $draft.endpointPath)
                }

                if draft.showsCategoryField {
                    TextField("Category Filter (optional)", text: $draft.categoryFilter)
                }

                Toggle("Enabled", isOn: $draft.isActive)

                if let validationError = draft.validationError {
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(draft.editingID == nil ? "Add Indexer" : "Edit Indexer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveDraft() }
                    }
                    .disabled(draft.validationError != nil)
                }
            }
        }
    }

    @ViewBuilder
    private func indexerRow(_ config: IndexerConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(config.name)
                        .font(.headline)
                    Text(config.indexerType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let baseURL = config.baseURL, !baseURL.isEmpty {
                        Text(baseURL)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if !config.endpointPath.isEmpty {
                        Text(config.endpointPath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { config.isActive },
                    set: { newValue in
                        Task { await setActive(newValue, for: config.id) }
                    }
                ))
                .accessibilityLabel("\(config.name) enabled")
                .accessibilityValue(config.isActive ? "On" : "Off")
                .accessibilityHint("Turns this indexer on or off.")
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await move(configID: config.id, direction: .up) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(configs.first?.id == config.id)
                .accessibilityLabel("Move indexer up")
                .accessibilityHint("Raises this indexer's priority in the list.")

                Button {
                    Task { await move(configID: config.id, direction: .down) }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(configs.last?.id == config.id)
                .accessibilityLabel("Move indexer down")
                .accessibilityHint("Lowers this indexer's priority in the list.")

                Button("Edit") {
                    draft = .from(config)
                    isShowingEditor = true
                }
                .buttonStyle(.bordered)

                Button(testingConfigID == config.id ? "Testing..." : "Test Connection") {
                    Task { await testConnection(for: config) }
                }
                .buttonStyle(.bordered)
                .disabled(testingConfigID == config.id)

                Button(role: .destructive) {
                    pendingDeletion = PendingDeletion(id: config.id, name: config.name)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Delete indexer")
                .accessibilityHint("Removes this indexer from the list.")

                Spacer()

                Text("#\(config.priority + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadConfigs() async {
        do {
            let fetched = try await appState.database.fetchAllIndexerConfigs()
            let hydrated = try await hydrateConfigsForDisplay(fetched)
            configs = hydrated.sorted { $0.priority < $1.priority }
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
        }
    }

    private func saveDraft() async {
        guard draft.validationError == nil else {
            notice = .warning(draft.validationError ?? "Indexer validation failed.")
            surfaceError = nil
            return
        }

        var updated = configs
        let normalizedURL = draft.normalizedURL
        let normalizedAPIKey = draft.normalizedAPIKey

        if let editID = draft.editingID,
           let index = updated.firstIndex(where: { $0.id == editID }) {
            updated[index].name = draft.name
            updated[index].indexerType = draft.indexerType
            updated[index].baseURL = normalizedURL
            updated[index].apiKey = normalizedAPIKey
            updated[index].isActive = draft.isActive
            updated[index].providerSubtype = draft.providerSubtype
            updated[index].endpointPath = draft.normalizedEndpointPath
            updated[index].categoryFilter = draft.normalizedCategoryFilter
            updated[index].apiKeyTransport = draft.apiKeyTransport
        } else {
            updated.append(
                IndexerConfig(
                    id: UUID().uuidString,
                    name: draft.name,
                    indexerType: draft.indexerType,
                    baseURL: normalizedURL,
                    apiKey: normalizedAPIKey,
                    isActive: draft.isActive,
                    priority: updated.count,
                    providerSubtype: draft.providerSubtype,
                    endpointPath: draft.normalizedEndpointPath,
                    categoryFilter: draft.normalizedCategoryFilter,
                    apiKeyTransport: draft.apiKeyTransport
                )
            )
        }

        do {
            try await saveConfigs(updated)
            let fetched = try await appState.database.fetchAllIndexerConfigs()
            configs = try await hydrateConfigsForDisplay(fetched)
            try await appState.indexerManager.initialize()
            notice = .success("Indexer settings saved.")
            surfaceError = nil
            isShowingEditor = false
        } catch {
            surfaceError = AppError(error)
            notice = nil
        }
    }

    private func setActive(_ active: Bool, for id: String) async {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        var updated = configs
        updated[index].isActive = active
        do {
            try await saveConfigs(updated)
            let fetched = try await appState.database.fetchAllIndexerConfigs()
            configs = try await hydrateConfigsForDisplay(fetched)
            try await appState.indexerManager.initialize()
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
        }
    }

    private func delete(configID: String) async {
        do {
            try await appState.database.setSetting(key: IndexerManager.bootstrapSettingKey, value: "true")
            if let config = configs.first(where: { $0.id == configID }) {
                try await config.deleteStoredSecret(using: appState.secretStore)
            }
            try await appState.database.deleteIndexerConfig(id: configID)
            let fetched = try await appState.database.fetchAllIndexerConfigs()
            configs = try await hydrateConfigsForDisplay(fetched)
            try await appState.indexerManager.initialize()
            notice = .success("Indexer removed.")
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
            notice = nil
        }
    }

    private enum MoveDirection {
        case up
        case down
    }

    private func move(configID: String, direction: MoveDirection) async {
        guard let sourceIndex = configs.firstIndex(where: { $0.id == configID }) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = sourceIndex - 1
        case .down:
            targetIndex = sourceIndex + 1
        }
        guard configs.indices.contains(targetIndex) else { return }

        var reordered = configs
        let moving = reordered.remove(at: sourceIndex)
        reordered.insert(moving, at: targetIndex)
        reordered = reindexed(reordered)

        do {
            try await saveConfigs(reordered)
            let fetched = try await appState.database.fetchAllIndexerConfigs()
            configs = try await hydrateConfigsForDisplay(fetched)
            try await appState.indexerManager.initialize()
            notice = .success("Indexer order updated.")
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
            notice = nil
        }
    }

    private func testConnection(for config: IndexerConfig) async {
        testingConfigID = config.id
        defer { testingConfigID = nil }

        do {
            try await IndexerConnectivityTester.testConnection(for: config)
            notice = .success("\(config.name): connection succeeded.")
            surfaceError = nil
        } catch {
            notice = nil
            surfaceError = AppError(error)
        }
    }

    private func saveConfigs(_ input: [IndexerConfig]) async throws {
        let normalized = reindexed(input)
        let persisted = try await persistIndexerConfigs(normalized)
        try await appState.database.saveIndexerConfigs(persisted)
    }

    nonisolated static func normalizePrioritiesPreservingOrder(_ input: [IndexerConfig]) -> [IndexerConfig] {
        IndexerDefaultRanking.normalizePriorities(input)
    }

    private func addBuiltIn(_ definition: IndexerDefaultRanking.Definition) async {
        var updated = configs
        updated.append(definition.makeConfig(priority: updated.count, isActive: false))
        do {
            try await saveConfigs(updated)
            let fetched = try await appState.database.fetchAllIndexerConfigs()
            configs = try await hydrateConfigsForDisplay(fetched)
                .sorted { $0.priority < $1.priority }
            try await appState.indexerManager.initialize()
            notice = .success("Built-in indexer added.")
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
            notice = nil
        }
    }

    private func reindexed(_ input: [IndexerConfig]) -> [IndexerConfig] {
        Self.normalizePrioritiesPreservingOrder(input)
    }

    private func hydrateConfigsForDisplay(_ fetched: [IndexerConfig]) async throws -> [IndexerConfig] {
        let persisted = try await persistIndexerConfigs(fetched)
        if persisted != fetched {
            try await appState.database.saveIndexerConfigs(persisted)
        }

        var display: [IndexerConfig] = []
        display.reserveCapacity(persisted.count)
        for config in persisted {
            display.append(try await config.resolvedCopy(using: appState.secretStore))
        }
        return display
    }

    private func persistIndexerConfigs(_ input: [IndexerConfig]) async throws -> [IndexerConfig] {
        var persisted: [IndexerConfig] = []
        persisted.reserveCapacity(input.count)
        for config in input {
            persisted.append(try await config.persistedCopy(using: appState.secretStore).config)
        }
        return persisted
    }

    struct IndexerDraft {
        var editingID: String?
        var name: String
        var indexerType: IndexerConfig.IndexerType
        var baseURL: String
        var apiKey: String
        var isActive: Bool
        var endpointPath: String
        var categoryFilter: String
        var apiKeyTransport: IndexerConfig.APIKeyTransport

        static func new() -> Self {
            Self(
                editingID: nil,
                name: "",
                indexerType: .jackett,
                baseURL: "",
                apiKey: "",
                isActive: true,
                endpointPath: "/api/v2.0/indexers/all/results/torznab/api",
                categoryFilter: "",
                apiKeyTransport: .header
            )
        }

        static func from(_ config: IndexerConfig) -> Self {
            Self(
                editingID: config.id,
                name: config.name,
                indexerType: config.indexerType,
                baseURL: config.baseURL ?? "",
                apiKey: config.apiKey ?? "",
                isActive: config.isActive,
                endpointPath: config.endpointPath,
                categoryFilter: config.categoryFilter ?? "",
                apiKeyTransport: config.apiKeyTransport
            )
        }

        mutating func applyDefaults(for type: IndexerConfig.IndexerType) {
            endpointPath = defaultEndpointPath(for: type)
            apiKeyTransport = defaultTransport(for: type)
            if !showsCategoryField {
                categoryFilter = ""
            }
        }

        var showsAPIKeyField: Bool {
            switch indexerType {
            case .jackett, .prowlarr, .torznab:
                return true
            default:
                return false
            }
        }

        var showsAPIKeyTransportField: Bool {
            switch indexerType {
            case .jackett, .prowlarr, .torznab:
                return true
            default:
                return false
            }
        }

        var showsEndpointPathField: Bool {
            !indexerType.isBuiltIn
        }

        var showsCategoryField: Bool {
            switch indexerType {
            case .jackett, .torznab:
                return true
            default:
                return false
            }
        }

        var providerSubtype: IndexerConfig.ProviderSubtype {
            switch indexerType {
            case .jackett:
                return .jackett
            case .prowlarr:
                return .prowlarr
            case .stremio:
                return .stremioAddon
            case .apiBay, .yts, .eztv:
                return .builtIn
            case .torznab, .zilean:
                return .customTorznab
            }
        }

        var normalizedURL: String? {
            let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        var normalizedAPIKey: String? {
            let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        var normalizedEndpointPath: String {
            let value = endpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                return defaultEndpointPath(for: indexerType)
            }
            return value.hasPrefix("/") ? value : "/\(value)"
        }

        var normalizedCategoryFilter: String? {
            let value = categoryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        var validationError: String? {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                return "Indexer name is required."
            }

            guard let urlString = normalizedURL else {
                return "Base URL is required."
            }
            guard let components = URLComponents(string: urlString),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "https",
                  components.host?.isEmpty == false else {
                return "Enter a valid HTTPS base URL."
            }

            if showsAPIKeyField, (normalizedAPIKey?.isEmpty ?? true) {
                return "API key is required for \(indexerType.displayName)."
            }

            if indexerType == .stremio {
                if normalizedEndpointPath.lowercased().contains("manifest") == false {
                    return "Stremio endpoint should usually point to /manifest.json."
                }
            }

            return nil
        }

        private func defaultEndpointPath(for type: IndexerConfig.IndexerType) -> String {
            switch type {
            case .jackett:
                return "/api/v2.0/indexers/all/results/torznab/api"
            case .prowlarr:
                return "/api/v1/search"
            case .torznab, .zilean:
                return "/api"
            case .stremio:
                return "/manifest.json"
            case .apiBay, .yts, .eztv:
                return ""
            }
        }

        private func defaultTransport(for type: IndexerConfig.IndexerType) -> IndexerConfig.APIKeyTransport {
            switch type {
            case .jackett, .prowlarr, .torznab:
                return .header
            default:
                return .query
            }
        }
    }
}
