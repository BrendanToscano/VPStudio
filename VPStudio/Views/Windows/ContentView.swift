import SwiftUI

enum NavigationChromePolicy {
    static func usesSidebar(for layout: NavigationLayout) -> Bool {
        layout == .leftSidebar
    }

    static func usesBottomTabBar(for layout: NavigationLayout) -> Bool {
        layout == .bottomTabBar
    }
}

enum BottomTabAction: Equatable {
    case select(SidebarTab)
    case openEnvironmentPicker
}

enum BottomTabRoutingPolicy {
    static func action(for tab: SidebarTab, opensEnvironmentPicker: Bool) -> BottomTabAction {
        if tab == .environments, opensEnvironmentPicker {
            return .openEnvironmentPicker
        }
        return .select(tab)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("onboarding.soft_setup_dismissed") private var softSetupPromptDismissed = false

    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    @State private var discoverViewModel = DiscoverViewModel()
    @State private var isShowingQuickStartPrompt = false

    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isShowingEnvironmentPicker = false
    #endif

    var body: some View {
        @Bindable var state = appState

        ZStack {
            NavigationStack {
                contentView(for: state.selectedTab)
            }
            .id(state.navigationResetID)
            .transition(
                .opacity.combined(
                    with: .scale(TabTransitionPolicy.scaleEffect)
                )
            )
            .animation(
                .spring(
                    response: TabTransitionPolicy.springResponse,
                    dampingFraction: TabTransitionPolicy.springDamping
                ),
                value: state.selectedTab
            )

            // Launch screen overlay — fades out once bootstrap completes
            if appState.isBootstrapping {
                LaunchScreen()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.6), value: appState.isBootstrapping)
        .safeAreaInset(edge: .top) {
            if !appState.networkMonitor.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption.weight(.semibold))
                    Text("You're offline — downloaded content is still available")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.orange.gradient)
            }
        }
        .background(Color.black.opacity(0.6))
        .onAppear {
            appState.terminateActivePlayerSession()
            NotificationCenter.default.post(name: .mainWindowDidActivate, object: nil)
            #if os(macOS) || os(visionOS)
            dismissWindow(id: "player")
            #endif
        }
        .sheet(isPresented: $state.isShowingSetup) {
            SetupWizardView()
        }
        .overlay(alignment: .top) {
            if isShowingQuickStartPrompt {
                QuickStartPromptView(
                    onRunSetup: {
                        softSetupPromptDismissed = true
                        isShowingQuickStartPrompt = false
                        appState.isShowingSetup = true
                    },
                    onSkip: {
                        softSetupPromptDismissed = true
                        isShowingQuickStartPrompt = false
                    }
                )
                .padding(.top, 16)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(90)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isShowingQuickStartPrompt)
        .task {
            await appState.bootstrap()
            // Restore persisted tab selection after bootstrap (settings DB is now ready)
            if let savedTab = try? await appState.settingsManager.getString(key: SettingsKeys.lastSelectedTab) {
                // Backward compat: accept legacy "Search" raw value after rename to "Explore"
                let tab = SidebarTab(rawValue: savedTab)
                    ?? (savedTab == "Search" ? .search : nil)
                if let tab {
                    appState.selectedTab = tab
                }
            }
            // Restore persisted navigation layout
            if let savedLayout = try? await appState.settingsManager.getString(key: SettingsKeys.navigationLayout),
               let layout = NavigationLayout(rawValue: savedLayout) {
                appState.navigationLayout = layout
            }
            RuntimeMemoryDiagnostics.capture(
                event: .appBootstrapCompleted,
                enabled: appState.runtimeDiagnosticsEnabled
            )
            if appState.setupRecommendationNeeded, !softSetupPromptDismissed {
                isShowingQuickStartPrompt = true
            }
        }
        .onChange(of: state.isShowingSetup) { _, isShowingSetup in
            if isShowingSetup {
                softSetupPromptDismissed = true
                isShowingQuickStartPrompt = false
            }
        }
        #if os(visionOS)
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            if appState.navigationLayout == .bottomTabBar {
                VPBottomTabBar(
                    selectedTab: $state.selectedTab,
                    opensEnvironmentPicker: true,
                    onOpenEnvironmentPicker: { isShowingEnvironmentPicker = true },
                    onTabSelection: { tab in handleTabSelection(tab, state: state) }
                )
                .environment(appState)
            }
        }
        .ornament(attachmentAnchor: .scene(.leading), contentAlignment: .trailing) {
            if appState.navigationLayout == .leftSidebar {
                VPSidebarView(
                    selectedTab: $state.selectedTab,
                    opensEnvironmentPicker: true,
                    onOpenEnvironmentPicker: { isShowingEnvironmentPicker = true },
                    onTabSelection: { tab in handleTabSelection(tab, state: state) }
                )
                .environment(appState)
            }
        }
        .sheet(isPresented: $isShowingEnvironmentPicker) {
            EnvironmentPickerSheet(
                onSelect: { asset in
                    Task { await openEnvironment(asset) }
                },
                onDismiss: {
                    Task { await dismissEnvironmentIfNeeded(reason: .userInitiated) }
                }
            )
            .environment(appState)
        }
        #else
        .safeAreaInset(edge: .bottom) {
            if appState.navigationLayout == .bottomTabBar {
                VPBottomTabBar(
                    selectedTab: $state.selectedTab,
                    opensEnvironmentPicker: false,
                    onOpenEnvironmentPicker: {},
                    onTabSelection: { tab in handleTabSelection(tab, state: state) }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
        }
        .safeAreaInset(edge: .leading) {
            if appState.navigationLayout == .leftSidebar {
                VPSidebarView(
                    selectedTab: $state.selectedTab,
                    opensEnvironmentPicker: false,
                    onOpenEnvironmentPicker: {},
                    onTabSelection: { tab in handleTabSelection(tab, state: state) }
                )
                .padding(.vertical, 12)
                .padding(.leading, 10)
            }
        }
        #endif
    }

    private func handleTabSelection(_ tab: SidebarTab, state: AppState) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            state.selectedTab = tab
            state.navigationResetID = UUID()
        }
        Task { try? await appState.settingsManager.setValue(tab.rawValue, forKey: SettingsKeys.lastSelectedTab) }
        RuntimeMemoryDiagnostics.capture(
            event: .tabSelectionChanged,
            enabled: appState.runtimeDiagnosticsEnabled,
            context: tab.rawValue
        )
    }

    @ViewBuilder
    private func contentView(for tab: SidebarTab) -> some View {
        switch tab {
        case .discover:
            DiscoverView(viewModel: discoverViewModel)
        case .search:
            SearchView()
        case .library:
            LibraryView()
        case .downloads:
            DownloadsView()
        case .environments:
            EnvironmentsTabView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - visionOS Environment Logic

    #if os(visionOS)
    private func openEnvironment(_ asset: EnvironmentAsset) async {
        if asset.id == appState.selectedEnvironmentAsset?.id, appState.isImmersiveSpaceOpen {
            await dismissEnvironmentIfNeeded(reason: .userInitiated)
            return
        }

        await dismissEnvironmentIfNeeded(reason: .switchingEnvironment)
        await appState.activateEnvironmentAsset(asset)

        guard appState.beginImmersiveTransition() else { return }
        let spaceID = await appState.environmentCatalogManager.immersiveSpaceID(for: asset)
        let result = await openImmersiveSpace(id: spaceID)
        switch result {
        case .opened:
            break
        case .error, .userCancelled:
            appState.cancelImmersiveTransition()
        @unknown default:
            appState.cancelImmersiveTransition()
        }
    }

    private func dismissEnvironmentIfNeeded(reason: ImmersiveDismissReason) async {
        guard appState.isImmersiveSpaceOpen else { return }
        guard appState.beginImmersiveTransition() else { return }
        appState.stageImmersiveDismiss(reason: reason)
        await dismissImmersiveSpace()
    }
    #endif
}

private struct QuickStartPromptView: View {
    let onRunSetup: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.vpRed)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick Start")
                        .font(.headline)
                    Text("Explore now with no setup, or run setup for full streaming features.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onSkip) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Dismiss quick start")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button(action: onSkip) {
                    Label("Explore Now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onRunSetup) {
                    Label("Run Setup", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.12))
        }
        .frame(maxWidth: 760)
    }

}

// MARK: - Bottom Tab Bar

struct VPBottomTabBar: View {
    @Binding var selectedTab: SidebarTab
    let opensEnvironmentPicker: Bool
    let onOpenEnvironmentPicker: () -> Void
    let onTabSelection: (SidebarTab) -> Void

    /// Counts driving badge visibility — wired by parent or defaults to 0.
    var activeDownloadCount: Int = 0
    var settingsWarningCount: Int = 0

    #if os(macOS)
    @State private var hoveredTab: SidebarTab?
    #endif

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SidebarTab.mainTabs, id: \.self) { tab in
                tabButton(tab: tab, isSelected: selectedTab == tab) {
                    switch BottomTabRoutingPolicy.action(
                        for: tab,
                        opensEnvironmentPicker: opensEnvironmentPicker
                    ) {
                    case .openEnvironmentPicker:
                        onOpenEnvironmentPicker()
                    case .select(let selected):
                        onTabSelection(selected)
                    }
                }
            }

            // Thin separator between main tabs and settings
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 1, height: 28)
                .padding(.horizontal, 2)

            tabButton(tab: .settings, isSelected: selectedTab == .settings) {
                onTabSelection(.settings)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
    }

    private func tabButton(tab: SidebarTab, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 16, weight: isSelected ? .semibold : .medium))

                    // Badge dot
                    if TabBadgePolicy.shouldShowBadge(
                        for: tab,
                        activeDownloadCount: activeDownloadCount,
                        settingsWarningCount: settingsWarningCount
                    ) {
                        Circle()
                            .fill(TabBadgePolicy.badgeColor(for: tab))
                            .frame(width: 7, height: 7)
                            .offset(x: 4, y: -2)
                    }
                }

                Text(tab.rawValue)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            .frame(width: 64, height: 48)
            .background {
                #if os(macOS)
                if isSelected {
                    Capsule()
                        .fill(LinearGradient.vpAccent.opacity(0.8))
                        .shadow(color: .vpRed.opacity(0.4), radius: 8, y: 2)
                } else if hoveredTab == tab {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                }
                #else
                if isSelected {
                    Capsule()
                        .fill(LinearGradient.vpAccent.opacity(0.8))
                        .shadow(color: .vpRed.opacity(0.4), radius: 8, y: 2)
                }
                #endif
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TabBarAccessibilityPolicy.accessibilityLabel(for: tab, isSelected: isSelected))
        .accessibilityHint(TabBarAccessibilityPolicy.accessibilityHint(for: tab))
        #if os(visionOS)
        .hoverEffect(.highlight)
        #else
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredTab = isHovered ? tab : nil
            }
        }
        #endif
        .animation(
            .spring(
                response: TabTransitionPolicy.springResponse,
                dampingFraction: TabTransitionPolicy.springDamping
            ),
            value: selectedTab
        )
    }
}

// MARK: - Environments Tab

#if os(visionOS)
struct EnvironmentsTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var environments: [EnvironmentAsset] = []
    @State private var isLoading = true
    @State private var environmentLoadTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose an immersive environment to enhance your viewing experience.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if isLoading {
                    LoadingOverlay(
                        title: "Loading Environments",
                        message: "Fetching available environments\u{2026}"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if environments.isEmpty {
                    emptyState
                } else {
                    let columns = [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)]
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(environments) { asset in
                            EnvironmentPreviewCard(
                                asset: asset,
                                isActive: asset.id == appState.selectedEnvironmentAsset?.id,
                                isImmersiveOpen: appState.isImmersiveSpaceOpen,
                                onSelect: { Task { await selectEnvironment(asset) } }
                            )
                        }
                    }

                    if appState.isImmersiveSpaceOpen {
                        Button(role: .destructive) {
                            Task { await exitEnvironment() }
                        } label: {
                            Label("Exit Environment", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Environments")
        .task { await coalescedLoadEnvironments() }
        .onReceive(NotificationCenter.default.publisher(for: .environmentsDidChange)) { [weak self] _ in
            self?.scheduleEnvironmentLoad()
        }
        .onDisappear {
            environmentLoadTask?.cancel()
            environmentLoadTask = nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mountain.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Environments")
                .font(.title3.weight(.semibold))
            Text("Download environments from Settings to use them here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @MainActor
    private func scheduleEnvironmentLoad() {
        environmentLoadTask?.cancel()
        environmentLoadTask = Task { await loadEnvironments() }
    }

    @MainActor
    private func coalescedLoadEnvironments() async {
        scheduleEnvironmentLoad()
        await environmentLoadTask?.value
    }

    @MainActor
    private func loadEnvironments() async {
        isLoading = true
        let latestEnvironments = (try? await appState.environmentCatalogManager.fetchAssets()) ?? []
        guard !Task.isCancelled else { return }
        environments = latestEnvironments
        isLoading = false
    }

    private func selectEnvironment(_ asset: EnvironmentAsset) async {
        if asset.id == appState.selectedEnvironmentAsset?.id, appState.isImmersiveSpaceOpen {
            await exitEnvironment()
            return
        }
        if appState.isImmersiveSpaceOpen {
            guard appState.beginImmersiveTransition() else { return }
            appState.stageImmersiveDismiss(reason: .switchingEnvironment)
            await dismissImmersiveSpace()
        }
        await appState.activateEnvironmentAsset(asset)
        guard appState.beginImmersiveTransition() else { return }
        let spaceID = await appState.environmentCatalogManager.immersiveSpaceID(for: asset)
        let result = await openImmersiveSpace(id: spaceID)
        switch result {
        case .opened: break
        case .error, .userCancelled: appState.cancelImmersiveTransition()
        @unknown default: appState.cancelImmersiveTransition()
        }
    }

    private func exitEnvironment() async {
        guard appState.isImmersiveSpaceOpen else { return }
        guard appState.beginImmersiveTransition() else { return }
        appState.stageImmersiveDismiss(reason: .userInitiated)
        await dismissImmersiveSpace()
    }
}
#else
struct EnvironmentsTabView: View {
    var body: some View {
        Text("Environments are available on Vision Pro.")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
