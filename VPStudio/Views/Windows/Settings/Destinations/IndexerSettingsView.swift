import SwiftUI
import UniformTypeIdentifiers

// MARK: - Indexer Settings

struct IndexerSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var configs: [IndexerConfig] = []
    @State private var isShowingEditor = false
    @State private var draft = IndexerDraft.new()
    @State private var saveErrorMessage: String?
    @State private var testMessage: String?
    @State private var testingConfigID: String?

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
            .alert("Indexer Error", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "Unknown error")
            }
            .alert("Connection Test", isPresented: testMessagePresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(testMessage ?? "")
            }
    }

    private var indexerList: some View {
        List {
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

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented { saveErrorMessage = nil }
            }
        )
    }

    private var testMessagePresented: Binding<Bool> {
        Binding(
            get: { testMessage != nil },
            set: { isPresented in
                if !isPresented { testMessage = nil }
            }
        )
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

                Button {
                    Task { await move(configID: config.id, direction: .down) }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(configs.last?.id == config.id)

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
                    Task { await delete(configID: config.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)

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
            configs = fetched.sorted { $0.priority < $1.priority }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func saveDraft() async {
        guard draft.validationError == nil else {
            saveErrorMessage = draft.validationError
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
            configs = try await appState.database.fetchAllIndexerConfigs()
            isShowingEditor = false
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func setActive(_ active: Bool, for id: String) async {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        var updated = configs
        updated[index].isActive = active
        do {
            try await saveConfigs(updated)
            configs = try await appState.database.fetchAllIndexerConfigs()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func delete(configID: String) async {
        do {
            try await appState.database.deleteIndexerConfig(id: configID)
            await appState.reloadIndexers()
            configs = try await appState.database.fetchAllIndexerConfigs()
        } catch {
            saveErrorMessage = error.localizedDescription
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
            configs = reordered
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func testConnection(for config: IndexerConfig) async {
        testingConfigID = config.id
        defer { testingConfigID = nil }

        do {
            try await IndexerConnectivityTester.testConnection(for: config)
            testMessage = "\(config.name): connection succeeded."
        } catch {
            testMessage = "\(config.name): \(error.localizedDescription)"
        }
    }

    private func saveConfigs(_ input: [IndexerConfig]) async throws {
        let normalized = reindexed(input)
        try await appState.database.saveIndexerConfigs(normalized)
        await appState.reloadIndexers()
    }

    nonisolated static func normalizePrioritiesPreservingOrder(_ input: [IndexerConfig]) -> [IndexerConfig] {
        IndexerDefaultRanking.normalizePriorities(input)
    }

    private func addBuiltIn(_ definition: IndexerDefaultRanking.Definition) async {
        var updated = configs
        updated.append(definition.makeConfig(priority: updated.count, isActive: false))
        do {
            try await saveConfigs(updated)
            configs = try await appState.database.fetchAllIndexerConfigs()
                .sorted { $0.priority < $1.priority }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func reindexed(_ input: [IndexerConfig]) -> [IndexerConfig] {
        Self.normalizePrioritiesPreservingOrder(input)
    }

    private struct IndexerDraft {
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
                apiKeyTransport: .query
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
                  (scheme == "http" || scheme == "https"),
                  components.host?.isEmpty == false else {
                return "Enter a valid HTTP/HTTPS base URL."
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
            case .prowlarr:
                return .header
            default:
                return .query
            }
        }
    }
}
