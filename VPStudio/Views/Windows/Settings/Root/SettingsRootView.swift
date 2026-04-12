import SwiftUI

enum SettingsNavigationInteractionPolicy {
    static func persistedDestinationRawValue(for destination: SettingsDestination) -> String {
        destination.rawValue
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var didLoadInitialSearch = false
    @State private var isRefreshingStatuses = false
    @State private var destinationStatuses: [SettingsDestination: SettingsDestinationStatus] = [:]
    @State private var isShowingResetSheet = false
    @State private var didTriggerQAAutoReset = false

    @AppStorage("settings.last_destination") private var lastDestinationRawValue = ""
    @AppStorage("settings.search_query") private var persistedSearchQuery = ""
    @AppStorage(VPMenuBackgroundIntensityPolicy.appStorageKey)
    private var menuBackgroundIntensityRaw = VPMenuBackgroundIntensityPolicy.defaultValue

    private var filteredGroups: [SettingsDestinationGroup] {
        SettingsNavigationCatalog.groups(matching: query)
    }

    private var menuBackgroundIntensity: Binding<Double> {
        Binding(
            get: { SettingsAppearancePolicy.normalizedMenuBackgroundIntensity(menuBackgroundIntensityRaw) },
            set: { menuBackgroundIntensityRaw = SettingsAppearancePolicy.normalizedMenuBackgroundIntensity($0) }
        )
    }

    private var recentDestination: SettingsDestination? {
        SettingsNavigationCatalog.destination(from: lastDestinationRawValue)
    }

    private var indicatorStatuses: [SettingsRowIndicatorPolicy.StatusKind] {
        destinationStatuses.values.map { SettingsRowIndicatorPolicy.statusKind(from: $0.kind) }
    }

    private var warningCount: Int {
        SettingsHealthPolicy.warningCount(statuses: indicatorStatuses)
    }

    private var configuredCount: Int {
        SettingsHealthPolicy.essentialConfiguredCount(statuses: destinationStatuses)
    }

    private var totalCount: Int {
        SettingsHealthPolicy.essentialTotal
    }

    private var healthProgress: Double {
        SettingsHealthPolicy.configurationProgress(configured: configuredCount, total: totalCount)
    }

    private var healthTint: Color {
        if healthProgress >= 0.75 { return .green }
        if healthProgress >= 0.45 { return .orange }
        return .yellow
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Configuration Health")
                                .font(.subheadline.weight(.semibold))
                            Text(SettingsHealthPolicy.progressLabel(configured: configuredCount, total: totalCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if SettingsHealthPolicy.shouldShowWarningBadge(warningCount: warningCount) {
                            GlassTag(
                                text: "\(warningCount) warning\(warningCount == 1 ? "" : "s")",
                                tintColor: .orange,
                                symbol: "exclamationmark.triangle"
                            )
                        }
                    }

                    GlassProgressBar(progress: healthProgress, tint: healthTint)
                }
                .padding(.vertical, 4)
            }

            if let recentDestination, recentDestination.matches(normalizedQuery) {
                Section("Continue") {
                    destinationLink(for: recentDestination, isRecent: true)
                }
            }

            if SettingsSearchPolicy.shouldShowEmptyState(
                resultCount: filteredGroups.flatMap(\.destinations).count,
                query: query
            ) {
                Section {
                    ContentUnavailableView(
                        "No Matching Settings",
                        systemImage: "magnifyingglass",
                        description: Text(SettingsSearchPolicy.resultsSummary(count: 0, query: query))
                    )
                    .padding(.vertical, 20)
                }
            } else {
                ForEach(filteredGroups) { group in
                    Section {
                        ForEach(group.destinations) { destination in
                            destinationLink(for: destination, isRecent: false)
                        }
                    } header: {
                        SettingsSectionHeader(
                            category: group.category,
                            configuredCount: configuredCountForCategory(group.category),
                            totalCount: group.destinations.count
                        )
                    }
                }
            }

            Section("Appearance") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Menu Background Intensity", systemImage: "circle.lefthalf.filled")
                        Spacer()
                        Text(SettingsAppearancePolicy.menuBackgroundIntensityLabel(for: menuBackgroundIntensity.wrappedValue))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: menuBackgroundIntensity, in: VPMenuBackgroundIntensityPolicy.range)
                        .accessibilityLabel("Menu background intensity")
                        .accessibilityValue(SettingsAppearancePolicy.menuBackgroundIntensityLabel(for: menuBackgroundIntensity.wrappedValue))
                        .accessibilityHint("Adjusts the strength of the cinematic menu background.")
                }
                .padding(.vertical, 4)
            }

            Section("Quick Actions") {
                Button {
                    appState.isShowingSetup = true
                } label: {
                    Label("Run Setup Wizard", systemImage: "wand.and.stars")
                }

                Button {
                    Task { await refreshStatuses() }
                } label: {
                    if isRefreshingStatuses {
                        Label("Refreshing…", systemImage: "arrow.clockwise")
                    } else {
                        Label("Refresh Configuration Status", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingStatuses)
            }

            Section("About") {
                infoRow(title: "Version", value: appVersion)
                infoRow(title: "Build", value: appBuild)
            }

            Section {
                Button(role: .destructive) {
                    isShowingResetSheet = true
                } label: {
                    Label("Reset All Data", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Permanently erases all settings, credentials, downloads, and local data.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            VPMenuBackground()
                .ignoresSafeArea()
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $isShowingResetSheet) {
            ResetDataView()
        }
        .navigationDestination(for: SettingsDestination.self) { destination in
            destinationView(for: destination)
                .onAppear {
                    lastDestinationRawValue = SettingsNavigationInteractionPolicy.persistedDestinationRawValue(
                        for: destination
                    )
                }
        }
        .searchable(text: $query, prompt: "Search settings, providers, AI, downloads")
        .task {
            if !didLoadInitialSearch {
                query = persistedSearchQuery
                didLoadInitialSearch = true
            }
            await refreshStatuses()
            if QARuntimeOptions.autoOpenResetSheet, !didTriggerQAAutoReset {
                didTriggerQAAutoReset = true
                isShowingResetSheet = true
            }
        }
        .refreshable {
            await refreshStatuses()
        }
        .onChange(of: query) { _, newValue in
            persistedSearchQuery = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .tmdbApiKeyDidChange)) { _ in
            Task { await refreshStatuses() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .indexersDidChange)) { _ in
            Task { await refreshStatuses() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .environmentsDidChange)) { _ in
            Task { await refreshStatuses() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .localModelsDidChange)) { _ in
            Task { await refreshStatuses() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSubtitlesDidChange)) { _ in
            Task { await refreshStatuses() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidResetAllData)) { _ in
            query = ""
            persistedSearchQuery = ""
            lastDestinationRawValue = ""
            didLoadInitialSearch = false
            isShowingResetSheet = false
        }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    @ViewBuilder
    private func destinationView(for destination: SettingsDestination) -> some View {
        switch destination {
        case .debrid:
            DebridSettingsView()
        case .indexers:
            IndexerSettingsView()
        case .metadata:
            MetadataSettingsView()
        case .ai:
            AISettingsView()
        case .trakt:
            TraktSettingsView()
        case .simkl:
            SimklSettingsView()
        case .imdbImport:
            IMDbImportSettingsView()
        case .player:
            PlayerSettingsView()
        case .subtitles:
            SubtitleSettingsView()
        case .environments:
            EnvironmentSettingsView()
        case .library:
            LibraryView()
        case .downloads:
            DownloadsView()
        case .resetData:
            ResetDataView()
        case .testMode:
            TestModeView()
        }
    }

    private func destinationLink(for destination: SettingsDestination, isRecent: Bool) -> some View {
        NavigationLink(value: destination) {
            SettingsDestinationRow(
                destination: destination,
                status: destinationStatuses[destination],
                isRecent: isRecent
            )
        }
        .buttonStyle(.plain)
    }

    private func configuredCountForCategory(_ category: SettingsCategory) -> Int {
        SettingsNavigationCatalog.orderedDestinations
            .filter { $0.category == category }
            .filter { destination in
                destinationStatuses[destination]?.kind == .positive
            }
            .count
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func refreshStatuses() async {
        isRefreshingStatuses = true
        let snapshot = await captureStatusSnapshot()
        var nextStatuses: [SettingsDestination: SettingsDestinationStatus] = [:]
        for destination in SettingsNavigationCatalog.orderedDestinations {
            nextStatuses[destination] = SettingsStatusFormatter.status(for: destination, snapshot: snapshot)
        }
        destinationStatuses = nextStatuses
        isRefreshingStatuses = false
    }

    private func captureStatusSnapshot() async -> SettingsStatusSnapshot {
        var snapshot = SettingsStatusSnapshot()

        if let configs = try? await appState.database.fetchAllDebridConfigs() {
            snapshot.activeDebridCount = configs.filter(\.isActive).count
        }

        if let configs = try? await appState.database.fetchAllIndexerConfigs() {
            snapshot.activeIndexerCount = configs.filter(\.isActive).count
        }

        snapshot.hasTMDBKey = await hasNonEmptyString(for: SettingsKeys.tmdbApiKey)
        snapshot.hasOpenSubtitlesKey = await hasNonEmptyString(for: SettingsKeys.openSubtitlesApiKey)

        if let assets = try? await appState.environmentCatalogManager.fetchAssets() {
            snapshot.environmentAssetCount = assets.count
        }

        let providerRaw = (try? await appState.settingsManager.getString(key: SettingsKeys.defaultAIProvider))
            ?? AIProviderKind.anthropic.rawValue
        snapshot.aiProvider = AIProviderKind(rawValue: providerRaw) ?? .anthropic

        snapshot.hasOpenAIKey = await hasNonEmptyString(for: SettingsKeys.openAIApiKey)
        snapshot.hasAnthropicKey = await hasNonEmptyString(for: SettingsKeys.anthropicApiKey)
        snapshot.hasGeminiKey = await hasNonEmptyString(for: SettingsKeys.geminiApiKey)
        snapshot.hasOllamaEndpoint = await hasNonEmptyString(
            for: SettingsKeys.ollamaEndpoint,
            fallback: "http://localhost:11434"
        )
        snapshot.hasOpenRouterKey = await hasNonEmptyString(for: SettingsKeys.openRouterApiKey)
        let userTraktClient = try? await appState.settingsManager.getString(key: SettingsKeys.traktClientId)
        let userTraktSecret = try? await appState.settingsManager.getString(key: SettingsKeys.traktClientSecret)
        snapshot.hasTraktCredentials = TraktDefaults.resolvedCredentials(
            userClientId: userTraktClient,
            userClientSecret: userTraktSecret
        ) != nil
        let hasTraktAccessToken = await hasNonEmptyString(for: SettingsKeys.traktAccessToken)
        snapshot.hasTraktConnection = snapshot.hasTraktCredentials && hasTraktAccessToken

        let hasSimklClient = await hasNonEmptyString(for: SettingsKeys.simklClientId)
        let hasSimklToken = await hasNonEmptyString(for: SettingsKeys.simklAccessToken)
        snapshot.hasSimklCredentials = hasSimklClient && hasSimklToken

        return snapshot
    }

    private func hasNonEmptyString(for key: String, fallback: String? = nil) async -> Bool {
        let value = (try? await appState.settingsManager.getString(key: key)) ?? fallback
        return !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
