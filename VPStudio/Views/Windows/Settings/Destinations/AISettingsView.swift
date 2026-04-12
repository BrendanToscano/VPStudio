import SwiftUI

// MARK: - AI Settings

struct AISettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var geminiKey = ""
    @State private var openRouterKey = ""
    @State private var ollamaURL = "http://localhost:11434"
    @State private var selectedProvider: AIProviderKind = .anthropic
    @State private var preferredProvider: AIProviderKind = .anthropic
    @State private var suppressedProviderSelection: AIProviderKind?
    @State private var anthropicModelID: String = AIModelCatalog.defaultModel(for: .anthropic)?.id ?? ""
    @State private var openAIModelID: String = AIModelCatalog.defaultModel(for: .openAI)?.id ?? ""
    @State private var geminiModelID: String = AIModelCatalog.defaultModel(for: .gemini)?.id ?? ""
    @State private var openRouterModelID: String = AIModelCatalog.defaultModel(for: .openRouter)?.id ?? ""
    @State private var ollamaModelID: String = AIModelCatalog.defaultModel(for: .ollama)?.id ?? ""
    @State private var feedbackScaleMode: FeedbackScaleMode = .likeDislike
    @State private var likedTitles: [String] = []
    @State private var dislikedTitles: [String] = []
    @State private var recentRatings: [String] = []
    @State private var anthropicSaveTask: Task<Void, Never>?
    @State private var openAISaveTask: Task<Void, Never>?
    @State private var geminiSaveTask: Task<Void, Never>?
    @State private var openRouterSaveTask: Task<Void, Never>?
    @State private var feedbackReloadTask: Task<Void, Never>? 
    @State private var sessionUsage: AIUsageSummary = .empty
    @State private var lifetimeUsage: AIUsageSummary = .empty
    @State private var discoverAIEnabled = false
    @State private var aiAutoGenerate = true
    @State private var isShowingResetStatisticsConfirmation = false
    @State private var surfaceError: AppError?

    // Local on-device models
    @State private var localModelEnabled = false
    @State private var localModelID: String = AIModelCatalog.defaultModel(for: .local)?.id ?? ""
    @State private var localModels: [LocalModelDescriptor] = []

    // Live-fetched model lists (fall back to static catalog)
    @State private var anthropicModels: [AIModelDefinition] = AIModelCatalog.models(for: .anthropic)
    @State private var openAIModels: [AIModelDefinition] = AIModelCatalog.models(for: .openAI)
    @State private var geminiModels: [AIModelDefinition] = AIModelCatalog.models(for: .gemini)
    @State private var openRouterModels: [AIModelDefinition] = AIModelCatalog.models(for: .openRouter)
    @State private var ollamaModels: [AIModelDefinition] = AIModelCatalog.models(for: .ollama)
    @State private var isFetchingModels = false

    /// Approximate app launch time — used to partition session vs lifetime usage.
    private static let appLaunchDate = Date()

    private var configuredCloudProviders: [AIProviderKind] {
        var providers: [AIProviderKind] = []
        if !anthropicKey.trimmedForAISettings.isEmpty { providers.append(.anthropic) }
        if !openAIKey.trimmedForAISettings.isEmpty { providers.append(.openAI) }
        if !geminiKey.trimmedForAISettings.isEmpty { providers.append(.gemini) }
        if !openRouterKey.trimmedForAISettings.isEmpty { providers.append(.openRouter) }
        return providers
    }

    private var hasConfiguredCloudProvider: Bool {
        !configuredCloudProviders.isEmpty
    }

    private var hasUsableLocalProvider: Bool {
        guard localModelEnabled else { return false }
        let downloadedModels = localModels.filter { $0.status == .downloaded }
        return AppState.resolvedLocalModelID(
            preferredModelID: localModelID,
            downloadedModels: downloadedModels
        ) != nil
    }

    private var availableDefaultProviders: [AIProviderKind] {
        AIAssistantManager.availableDefaultProviders(
            configuredCloudProviders: configuredCloudProviders,
            hasOllamaEndpoint: hasUsableOllamaEndpoint,
            hasUsableLocalProvider: hasUsableLocalProvider
        )
    }

    private var resolvedSelectedProvider: AIProviderKind? {
        AIAssistantManager.resolvedDefaultProvider(
            preferredProvider: preferredProvider,
            availableProviders: availableDefaultProviders
        )
    }

    private var showsProviderFallbackMessage: Bool {
        guard let resolvedSelectedProvider else { return false }
        return preferredProvider != resolvedSelectedProvider
    }

    private var ollamaEndpointWarningMessage: String? {
        AIOllamaEndpointPolicy.warningMessage(for: ollamaURL)
    }

    private var hasUsableOllamaEndpoint: Bool {
        let trimmed = ollamaURL.trimmedForAISettings
        return !trimmed.isEmpty && ollamaEndpointWarningMessage == nil
    }

    var body: some View {
        formWithKeyHandlers
            .navigationTitle("AI Assistant")
            .confirmationDialog(
                "Reset AI Usage Statistics?",
                isPresented: $isShowingResetStatisticsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Statistics", role: .destructive) {
                    Task { await resetUsageStats() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears request counts and cost history for all AI providers. This cannot be undone.")
            }
        .task {
            anthropicKey = (try? await appState.settingsManager.getString(key: SettingsKeys.anthropicApiKey)) ?? ""
            openAIKey = (try? await appState.settingsManager.getString(key: SettingsKeys.openAIApiKey)) ?? ""
            geminiKey = (try? await appState.settingsManager.getString(key: SettingsKeys.geminiApiKey)) ?? ""
            openRouterKey = (try? await appState.settingsManager.getString(key: SettingsKeys.openRouterApiKey)) ?? ""
            ollamaURL = (try? await appState.settingsManager.getString(key: SettingsKeys.ollamaEndpoint)) ?? "http://localhost:11434"

            let storedAnthropicModel = try? await appState.settingsManager.getString(key: SettingsKeys.anthropicModelPreset)
            anthropicModelID = storedAnthropicModel ?? AIModelCatalog.defaultModel(for: .anthropic)?.id ?? "claude-sonnet-4-6"

            let storedOpenAIModel = try? await appState.settingsManager.getString(key: SettingsKeys.openAIModelPreset)
            openAIModelID = storedOpenAIModel ?? AIModelCatalog.defaultModel(for: .openAI)?.id ?? "gpt-5.4"

            let storedGeminiModel = try? await appState.settingsManager.getString(key: SettingsKeys.geminiModelPreset)
            geminiModelID = storedGeminiModel ?? AIModelCatalog.defaultModel(for: .gemini)?.id ?? "gemini-2.5-flash"

            let storedOpenRouterModel = try? await appState.settingsManager.getString(key: SettingsKeys.openRouterModelPreset)
            openRouterModelID = storedOpenRouterModel ?? AIModelCatalog.defaultModel(for: .openRouter)?.id ?? ""

            let storedOllamaModel = try? await appState.settingsManager.getString(key: SettingsKeys.ollamaModelPreset)
            ollamaModelID = storedOllamaModel ?? AIModelCatalog.defaultModel(for: .ollama)?.id ?? "llama3.1"

            if let providerRaw = try? await appState.settingsManager.getString(key: SettingsKeys.defaultAIProvider),
               let provider = AIProviderKind(rawValue: providerRaw) {
                preferredProvider = provider
            }
            selectedProvider = preferredProvider
            discoverAIEnabled = (try? await appState.settingsManager.getBool(key: SettingsKeys.discoverAIRecommendationsEnabled)) ?? false
            aiAutoGenerate = (try? await appState.settingsManager.getBool(key: SettingsKeys.aiAutoGenerate, default: true)) ?? true
            localModelEnabled = (try? await appState.settingsManager.getBool(key: SettingsKeys.localModelEnabled)) ?? false
            let storedLocalModel = try? await appState.settingsManager.getString(key: SettingsKeys.localModelPreset)
            localModelID = storedLocalModel ?? AIModelCatalog.defaultModel(for: .local)?.id ?? ""
            await reloadLocalModels(syncProvider: true)
            reconcileSelectedProvider()
            await loadFeedbackState()
            await loadUsageStats()
            await refreshModels()
        }
        .onChange(of: anthropicKey) { _, newValue in
            reconcileSelectedProvider()
            scheduleCloudKeySave(task: &anthropicSaveTask, key: SettingsKeys.anthropicApiKey, value: newValue, provider: .anthropic)
        }
        .onChange(of: openAIKey) { _, newValue in
            reconcileSelectedProvider()
            scheduleCloudKeySave(task: &openAISaveTask, key: SettingsKeys.openAIApiKey, value: newValue, provider: .openAI)
        }
        .onChange(of: geminiKey) { _, newValue in
            reconcileSelectedProvider()
            scheduleCloudKeySave(task: &geminiSaveTask, key: SettingsKeys.geminiApiKey, value: newValue, provider: .gemini)
        }
        .onChange(of: openRouterKey) { _, newValue in
            reconcileSelectedProvider()
            scheduleCloudKeySave(task: &openRouterSaveTask, key: SettingsKeys.openRouterApiKey, value: newValue, provider: .openRouter)
        }
        .onChange(of: localModelEnabled) { _, newValue in
            reconcileSelectedProvider()
            Task {
                await persistBoolSetting(key: SettingsKeys.localModelEnabled, value: newValue) {
                    await reloadLocalModels(syncProvider: false)
                    await refreshAIProviders()
                }
            }
        }
        .onChange(of: localModelID) { _, newValue in
            reconcileSelectedProvider()
            Task {
                await persistStringSetting(key: SettingsKeys.localModelPreset, value: newValue) {
                    await refreshAIProviders()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .localModelsDidChange)) { _ in
            Task {
                await reloadLocalModels(syncProvider: true)
                await MainActor.run { reconcileSelectedProvider() }
            }
        }
        .onDisappear {
            flushPendingCloudKeySaves()
            feedbackReloadTask?.cancel()
            feedbackReloadTask = nil
        }
    }

    private var formWithKeyHandlers: some View {
        formContent
        .onChange(of: ollamaURL) { _, newValue in
            reconcileSelectedProvider()
            Task {
                await persistOllamaEndpoint(newValue)
            }
        }
        .onChange(of: anthropicModelID) { _, newValue in
            Task {
                await persistStringSetting(key: SettingsKeys.anthropicModelPreset, value: newValue) {
                    await refreshAIProviders()
                }
            }
        }
        .onChange(of: openAIModelID) { _, newValue in
            Task {
                await persistStringSetting(key: SettingsKeys.openAIModelPreset, value: newValue) {
                    await refreshAIProviders()
                }
            }
        }
        .onChange(of: geminiModelID) { _, newValue in
            Task {
                await persistStringSetting(key: SettingsKeys.geminiModelPreset, value: newValue) {
                    await refreshAIProviders()
                }
            }
        }
        .onChange(of: openRouterModelID) { _, newValue in
            Task {
                await persistStringSetting(key: SettingsKeys.openRouterModelPreset, value: newValue) {
                    await refreshAIProviders()
                }
            }
        }
        .onChange(of: ollamaModelID) { _, newValue in
            Task {
                await persistStringSetting(key: SettingsKeys.ollamaModelPreset, value: newValue) {
                    await refreshAIProviders()
                }
            }
        }
        .onChange(of: selectedProvider) { _, newValue in
            if suppressedProviderSelection == newValue {
                suppressedProviderSelection = nil
                return
            }
            preferredProvider = newValue
            Task {
                await persistStringSetting(key: SettingsKeys.defaultAIProvider, value: newValue.rawValue) {
                    await refreshAIProviders()
                }
            }
        }
        .onChange(of: discoverAIEnabled) { _, newValue in
            Task {
                await persistBoolSetting(key: SettingsKeys.discoverAIRecommendationsEnabled, value: newValue)
            }
        }
        .onChange(of: aiAutoGenerate) { _, newValue in
            Task {
                await persistBoolSetting(key: SettingsKeys.aiAutoGenerate, value: newValue)
            }
        }
        .onChange(of: feedbackScaleMode) { _, newValue in
            Task {
                await persistStringSetting(
                    key: SettingsKeys.feedbackScaleMode,
                    value: newValue.canonicalMode.rawValue
                ) {
                    NotificationCenter.default.post(name: .tasteProfileDidChange, object: nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tasteProfileDidChange)) { _ in
            feedbackReloadTask?.cancel()
            feedbackReloadTask = Task { await loadFeedbackState() }
        }
    }

    @MainActor
    private func flushPendingCloudKeySaves() {
        anthropicSaveTask?.cancel()
        anthropicSaveTask = nil
        openAISaveTask?.cancel()
        openAISaveTask = nil
        geminiSaveTask?.cancel()
        geminiSaveTask = nil
        openRouterSaveTask?.cancel()
        openRouterSaveTask = nil

        Task { await persistCloudKey(key: SettingsKeys.anthropicApiKey, value: anthropicKey, provider: .anthropic) }
        Task { await persistCloudKey(key: SettingsKeys.openAIApiKey, value: openAIKey, provider: .openAI) }
        Task { await persistCloudKey(key: SettingsKeys.geminiApiKey, value: geminiKey, provider: .gemini) }
        Task { await persistCloudKey(key: SettingsKeys.openRouterApiKey, value: openRouterKey, provider: .openRouter) }
    }

    @MainActor
    private func scheduleCloudKeySave(
        task: inout Task<Void, Never>?,
        key: String,
        value: String,
        provider: AIProviderKind
    ) {
        task?.cancel()
        task = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await persistCloudKey(key: key, value: value, provider: provider)
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    surfaceError = AppError(error)
                }
            }
        }
    }

    @MainActor
    private func persistCloudKey(key: String, value: String, provider: AIProviderKind) async {
        do {
            try await appState.settingsManager.setString(key: key, value: value)
            await refreshAIProviders()
            await refreshModels(for: provider)
            surfaceError = nil
        } catch {
            surfaceError = AppError(error)
        }
    }

    @MainActor
    private func persistOllamaEndpoint(_ newValue: String) async {
        let trimmedValue = newValue.trimmedForAISettings
        if trimmedValue.isEmpty {
            await persistStringSetting(
                key: SettingsKeys.ollamaEndpoint,
                value: trimmedValue
            ) {
                await refreshAIProviders()
                await refreshOllamaModels()
            }
            return
        }

        guard let warningMessage = AIOllamaEndpointPolicy.warningMessage(for: trimmedValue) else {
            await persistStringSetting(
                key: SettingsKeys.ollamaEndpoint,
                value: trimmedValue
            ) {
                await refreshAIProviders()
                await refreshOllamaModels()
            }
            return
        }

        if warningMessage.contains("Plain HTTP is only allowed") {
            surfaceError = .unknown(warningMessage)
        }
    }

    @MainActor
    private func persistStringSetting(
        key: String,
        value: String,
        postSave: (() async -> Void)? = nil
    ) async {
        do {
            try await appState.settingsManager.setString(key: key, value: value)
            surfaceError = nil
            if let postSave {
                await postSave()
            }
        } catch {
            surfaceError = AppError(error)
        }
    }

    @MainActor
    private func persistBoolSetting(
        key: String,
        value: Bool,
        postSave: (() async -> Void)? = nil
    ) async {
        do {
            try await appState.settingsManager.setBool(key: key, value: value)
            surfaceError = nil
            if let postSave {
                await postSave()
            }
        } catch {
            surfaceError = AppError(error)
        }
    }

    @MainActor
    private func refreshAIProviders() async {
        await appState.configureAIProviders()
        reconcileSelectedProvider()
    }

    @MainActor
    private func refreshModels(for provider: AIProviderKind) async {
        switch provider {
        case .anthropic:
            await refreshAnthropicModels()
        case .openAI:
            await refreshOpenAIModels()
        case .gemini:
            await refreshGeminiModels()
        case .openRouter:
            await refreshOpenRouterModels()
        case .ollama:
            await refreshOllamaModels()
        case .local:
            break
        }
    }

    // MARK: - Usage & Costs Section

    @ViewBuilder
    private var usageCostsSection: some View {
        Section("Usage & Costs") {
            LabeledContent("Session Cost") {
                Text(formattedCost(sessionUsage.totalCostUSD))
                    .monospacedDigit()
            }
            LabeledContent("Lifetime Cost") {
                Text(formattedCost(lifetimeUsage.totalCostUSD))
                    .monospacedDigit()
            }
            LabeledContent("Total Requests") {
                Text("\(lifetimeUsage.requestCount)")
                    .monospacedDigit()
            }

            if !lifetimeUsage.byProvider.isEmpty {
                ForEach(AIProviderKind.allCases) { provider in
                    if let usage = lifetimeUsage.byProvider[provider] {
                        HStack {
                            Text(provider.displayName)
                                .foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formattedCost(usage.costUSD))
                                    .monospacedDigit()
                                Text("\(usage.requestCount) requests · \(formattedTokens(usage.inputTokens + usage.outputTokens)) tokens")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Button("Reset Statistics", role: .destructive) {
                isShowingResetStatisticsConfirmation = true
            }
        }
    }

    private var formContent: some View {
        Form {
            providerSections
            localAndUsageSections
            feedbackSections
            if let surfaceError {
                Section {
                    SettingsErrorBanner(error: surfaceError)
                }
            }
        }
    }

    // MARK: - Form Sections
    @ViewBuilder
    private var providerSections: some View {
        defaultProviderSection
        anthropicSection
        openAISection
        geminiSection
        openRouterSection
        ollamaSection
    }

    @ViewBuilder
    private var localAndUsageSections: some View {
        localModelsSection
        usageCostsSection
        discoverIntegrationSection
    }

    @ViewBuilder
    private var feedbackSections: some View {
        personalizationFeedbackSection
        likedTitlesSection
        dislikedTitlesSection
        recentRatingsSection
    }

    private var defaultProviderSection: some View {
        Section("Default Provider") {
            if availableDefaultProviders.isEmpty {
                Text("Configure a provider below to choose the default used for AI actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(availableDefaultProviders, id: \.self) { provider in
                        Text(providerSelectionLabel(for: provider)).tag(provider)
                    }
                }

                if showsProviderFallbackMessage, let resolvedSelectedProvider {
                    Text(
                        "\(providerSelectionLabel(for: preferredProvider)) is unavailable right now. Requests will use \(providerSelectionLabel(for: resolvedSelectedProvider))."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var anthropicSection: some View {
        Section("Anthropic") {
            HStack {
                SecureField("API Key", text: $anthropicKey)
                PasteFieldButton { anthropicKey = $0 }
                    .accessibilityLabel("Paste Anthropic API key from clipboard")
                    .accessibilityHint("Pastes the Anthropic API key into the field.")
            }
            Picker("Model", selection: $anthropicModelID) {
                ForEach(anthropicModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }
    }

    @ViewBuilder
    private var openAISection: some View {
        Section("OpenAI") {
            HStack {
                SecureField("API Key", text: $openAIKey)
                PasteFieldButton { openAIKey = $0 }
                    .accessibilityLabel("Paste OpenAI API key from clipboard")
                    .accessibilityHint("Pastes the OpenAI API key into the field.")
            }
            Picker("Model", selection: $openAIModelID) {
                ForEach(openAIModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }
    }

    @ViewBuilder
    private var geminiSection: some View {
        Section("Gemini") {
            HStack {
                SecureField("API Key", text: $geminiKey)
                PasteFieldButton { geminiKey = $0 }
                    .accessibilityLabel("Paste Gemini API key from clipboard")
                    .accessibilityHint("Pastes the Gemini API key into the field.")
            }
            Picker("Model", selection: $geminiModelID) {
                ForEach(geminiModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }
    }

    @ViewBuilder
    private var openRouterSection: some View {
        Section("OpenRouter") {
            HStack {
                SecureField("API Key", text: $openRouterKey)
                PasteFieldButton { openRouterKey = $0 }
                    .accessibilityLabel("Paste OpenRouter API key from clipboard")
                    .accessibilityHint("Pastes the OpenRouter API key into the field.")
            }
            Picker("Model", selection: $openRouterModelID) {
                ForEach(openRouterModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            Text("Model options refresh from OpenRouter after the API key is saved. If the live fetch fails, VPStudio falls back to the bundled curated list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var ollamaSection: some View {
        Section("Ollama") {
            TextField("Server URL", text: $ollamaURL)
            if let ollamaEndpointWarningMessage {
                Text(ollamaEndpointWarningMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Plain HTTP is only allowed for localhost and loopback Ollama servers. Remote Ollama endpoints must use HTTPS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Model", selection: $ollamaModelID) {
                ForEach(ollamaModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .disabled(!hasUsableOllamaEndpoint)
        }
    }

    // MARK: - On-Device Models

    @ViewBuilder
    private var localModelsSection: some View {
        Section("On-Device Models (MLX)") {
            Toggle("Enable Local Inference", isOn: $localModelEnabled)
            Text("Run AI models directly on your device. Free and private — no API key needed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if localModelEnabled {
                let downloaded = localModels.filter { $0.status == .downloaded }
                if !downloaded.isEmpty {
                    Picker("Active Model", selection: $localModelID) {
                        ForEach(downloaded, id: \.id) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                } else {
                    Text("Download at least one model before choosing On-Device as your active provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(localModels, id: \.id) { model in
                    localModelRow(model)
                }
            }
        }
    }

    @ViewBuilder
    private func localModelRow(_ model: LocalModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cpu")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(.headline)
                    Text("\(model.parameterCount) params \u{00B7} \(model.quantization) \u{00B7} \(model.diskSizeMB)MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Context: \(model.effectivePromptCap / 1000)K prompt \u{00B7} RAM: \(model.minMemoryMB)MB min")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                localModelAction(model)
            }

            if model.status == .downloaded {
                Button(role: .destructive) {
                    Task { await appState.localDownloadService.deleteModel(id: model.id) }
                } label: {
                    Label("Delete Model", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if model.status == .downloading {
                Button("Cancel") {
                    Task { await appState.localDownloadService.cancelDownload(id: model.id) }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func localModelAction(_ model: LocalModelDescriptor) -> some View {
        switch model.status {
        case .downloaded:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .downloading:
            VStack(spacing: 4) {
                ProgressView(value: model.downloadProgress)
                    .frame(width: 80)
                Text("\(Int(model.downloadProgress * 100))%")
                    .font(.caption2)
                    .monospacedDigit()
            }
        case .available:
            Button {
                Task { await appState.localDownloadService.downloadModel(id: model.id) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
        case .failed, .corrupted:
            Button {
                Task { await appState.localDownloadService.downloadModel(id: model.id) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        case .paused:
            Button {
                Task { await appState.localDownloadService.downloadModel(id: model.id) }
            } label: {
                Label("Resume", systemImage: "play.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    @MainActor
    private func reloadLocalModels(syncProvider: Bool) async {
        let models = (try? await appState.localCatalogStore.availableModels()) ?? []
        localModels = models

        let downloadedModels = models.filter { $0.status == .downloaded }
        let resolvedLocalModelID = AppState.resolvedLocalModelID(
            preferredModelID: localModelID,
            downloadedModels: downloadedModels
        )

        if let resolvedLocalModelID, resolvedLocalModelID != localModelID {
            localModelID = resolvedLocalModelID
            await persistStringSetting(
                key: SettingsKeys.localModelPreset,
                value: resolvedLocalModelID
            )
        }

        if syncProvider {
            await appState.configureAIProviders()
        }
    }

    private func reconcileSelectedProvider() {
        let nextSelection = resolvedSelectedProvider ?? preferredProvider
        guard nextSelection != selectedProvider else { return }
        suppressedProviderSelection = nextSelection
        selectedProvider = nextSelection
    }

    private func providerSelectionLabel(for provider: AIProviderKind) -> String {
        switch provider {
        case .anthropic:
            return "Anthropic Claude"
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        case .openRouter:
            return "OpenRouter"
        case .ollama:
            return "Ollama (Local)"
        case .local:
            return "On-Device (MLX)"
        }
    }

    @ViewBuilder
    private var discoverIntegrationSection: some View {
        Section("Discover Integration") {
            Toggle("Show AI Curated Row", isOn: $discoverAIEnabled)
            Text("Personalized \u{201C}Curated For You\u{201D} row on the Discover page using your taste profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Auto-generate recommendations", isOn: $aiAutoGenerate)
                .disabled(!discoverAIEnabled)
            Text("When off, shows cached recommendations. Press \u{201C}Regenerate\u{201D} on the Discover page to fetch new ones.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var personalizationFeedbackSection: some View {
        Section("Personalization Feedback") {
            Picker("Rating Scale", selection: $feedbackScaleMode) {
                ForEach(FeedbackScaleMode.selectableCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text("This scale is used when you rate titles and is sent to AI context.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var likedTitlesSection: some View {
        Section("Liked Titles") {
            if likedTitles.isEmpty {
                Text("No liked titles yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(likedTitles, id: \.self) { title in
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private var dislikedTitlesSection: some View {
        Section("Disliked Titles") {
            if dislikedTitles.isEmpty {
                Text("No disliked titles yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dislikedTitles, id: \.self) { title in
                    Text(title)
                }
            }
        }
    }

    @ViewBuilder
    private var recentRatingsSection: some View {
        Section("Recent Ratings") {
            if recentRatings.isEmpty {
                Text("No ratings yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentRatings, id: \.self) { line in
                    Text(line)
                }
            }
        }
    }

    // MARK: - Cost Formatting

    private func formattedCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    private func formattedTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    // MARK: - Model Fetching

    @MainActor
    private func refreshModels() async {
        isFetchingModels = true
        defer { isFetchingModels = false }
        async let anthropic: Void = refreshAnthropicModels()
        async let openAI: Void = refreshOpenAIModels()
        async let gemini: Void = refreshGeminiModels()
        async let openRouter: Void = refreshOpenRouterModels()
        async let ollama: Void = refreshOllamaModels()
        _ = await (anthropic, openAI, gemini, openRouter, ollama)
    }

    @MainActor
    private func refreshAnthropicModels() async {
        let fetched = await AIModelFetcher.fetchAnthropicModels(apiKey: anthropicKey)
        if !fetched.isEmpty {
            anthropicModels = fetched
            ensureSelectionValid(modelID: &anthropicModelID, in: anthropicModels)
        }
    }

    @MainActor
    private func refreshOpenAIModels() async {
        let fetched = await AIModelFetcher.fetchOpenAIModels(apiKey: openAIKey)
        if !fetched.isEmpty {
            openAIModels = fetched
            ensureSelectionValid(modelID: &openAIModelID, in: openAIModels)
        }
    }

    @MainActor
    private func refreshGeminiModels() async {
        let fetched = await AIModelFetcher.fetchGeminiModels(apiKey: geminiKey)
        if !fetched.isEmpty {
            geminiModels = fetched
            ensureSelectionValid(modelID: &geminiModelID, in: geminiModels)
        }
    }

    @MainActor
    private func refreshOpenRouterModels() async {
        let fetched = await AIModelFetcher.fetchOpenRouterModels(apiKey: openRouterKey)
        if !fetched.isEmpty {
            openRouterModels = fetched
            ensureSelectionValid(modelID: &openRouterModelID, in: openRouterModels)
        }
    }

    @MainActor
    private func refreshOllamaModels() async {
        guard hasUsableOllamaEndpoint else { return }

        let fetched = await AIModelFetcher.fetchOllamaModels(baseURL: ollamaURL)
        if !fetched.isEmpty {
            ollamaModels = fetched
            ensureSelectionValid(modelID: &ollamaModelID, in: ollamaModels)
        }
    }

    /// Ensures the current selection exists in the model list to avoid invalid Picker tags.
    private func ensureSelectionValid(modelID: inout String, in models: [AIModelDefinition]) {
        if !models.contains(where: { $0.id == modelID }) {
            modelID = models.first(where: \.isDefault)?.id ?? models.first?.id ?? modelID
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadUsageStats() async {
        sessionUsage = (try? await appState.database.fetchAIUsageSummary(since: Self.appLaunchDate)) ?? .empty
        lifetimeUsage = (try? await appState.database.fetchAIUsageSummary()) ?? .empty
    }

    @MainActor
    private func resetUsageStats() async {
        do {
            try await appState.database.deleteAllAIUsageRecords()
            surfaceError = nil
            await loadUsageStats()
        } catch {
            surfaceError = AppError(error)
        }
    }

    @MainActor
    private func loadFeedbackState() async {
        feedbackScaleMode = ((try? await appState.settingsManager.getFeedbackScaleMode()) ?? .likeDislike).canonicalMode

        let events = (try? await appState.database.fetchTasteEvents(eventType: .rated, limit: 400)) ?? []
        let mediaIDs = Set(events.compactMap(\.mediaId))
        var titleByMediaID: [String: String] = [:]
        for mediaID in mediaIDs {
            if let title = try? await appState.database.fetchMediaItem(id: mediaID)?.title,
               !title.isEmpty {
                titleByMediaID[mediaID] = title
            }
        }

        var nextLiked: [String] = []
        var nextDisliked: [String] = []
        var nextRecentRatings: [String] = []

        var likedSeen = Set<String>()
        var dislikedSeen = Set<String>()
        var recentSeen = Set<String>()

        for event in events {
            guard let rawValue = event.feedbackValue else { continue }
            let scale = (event.feedbackScale ?? feedbackScaleMode).canonicalMode
            let title = resolvedFeedbackTitle(for: event, titleByMediaID: titleByMediaID)
            guard !title.isEmpty else { continue }

            switch scale.sentiment(for: rawValue) {
            case .liked:
                let key = title.lowercased()
                if likedSeen.insert(key).inserted {
                    nextLiked.append(title)
                }
            case .disliked:
                let key = title.lowercased()
                if dislikedSeen.insert(key).inserted {
                    nextDisliked.append(title)
                }
            case .neutral:
                break
            }

            let ratingLine = "\(title) (\(scale.format(rawValue)))"
            let ratingKey = ratingLine.lowercased()
            if nextRecentRatings.count < 20, recentSeen.insert(ratingKey).inserted {
                nextRecentRatings.append(ratingLine)
            }
        }

        likedTitles = nextLiked
        dislikedTitles = nextDisliked
        recentRatings = nextRecentRatings
    }

    private func resolvedFeedbackTitle(for event: TasteEvent, titleByMediaID: [String: String]) -> String {
        if let metadataTitle = event.metadata["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !metadataTitle.isEmpty {
            return metadataTitle
        }
        if let mediaID = event.mediaId,
           let mediaTitle = titleByMediaID[mediaID],
           !mediaTitle.isEmpty {
            return mediaTitle
        }
        return event.mediaId ?? "Unknown title"
    }
}

private extension String {
    var trimmedForAISettings: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
