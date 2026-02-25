import SwiftUI
import UniformTypeIdentifiers

// MARK: - Environment Settings

struct EnvironmentSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var assets: [EnvironmentAsset] = []
    @State private var isImporting = false
    @State private var environmentError: String?
    @State private var installingPresetIDs: Set<String> = []
    @State private var autoOpenEnvironment = true
    @State private var assetLoadTask: Task<Void, Never>?

    private let onlinePresets = EnvironmentCatalogManager.onlinePresets

    var body: some View {
        List {
            Section("Curated Environments") {
                let bundled = assets.filter { $0.sourceType == .bundled }
                if bundled.isEmpty {
                    Text("Import a .hdr, .exr, .usdz, or .reality asset to customize.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bundled) { asset in
                        environmentRow(asset)
                    }
                }
            }

            Section("Online Presets (Poly Haven HDRI)") {
                ForEach(onlinePresets) { preset in
                    onlinePresetRow(preset)
                }

                Text("Use one-click import for curated sources, then activate from Imported Environments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Imported Environments") {
                if assets.filter({ $0.sourceType == .imported }).isEmpty {
                    Text("No imported environments yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assets.filter { $0.sourceType == .imported }) { asset in
                        environmentRow(asset)
                    }
                }

                Button("Import Environment (.hdr / .exr / .usdz / .reality)", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
            }

            Section("Playback") {
                Toggle("Auto-open environment on playback", isOn: $autoOpenEnvironment)
                Text("When enabled, the active environment opens automatically when you start a video.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Active environment is applied when opening immersive playback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Environments")
        .task {
            await coalescedLoadAssets()
            autoOpenEnvironment = (try? await appState.settingsManager.getBool(
                key: SettingsKeys.autoOpenEnvironment, default: true
            )) ?? true
        }
        .refreshable {
            await coalescedLoadAssets()
        }
        .onChange(of: autoOpenEnvironment) { _, newValue in
            Task { try? await appState.settingsManager.setBool(key: SettingsKeys.autoOpenEnvironment, value: newValue) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .environmentsDidChange)) { _ in
            scheduleAssetLoad()
        }
        .onDisappear {
            assetLoadTask?.cancel()
            assetLoadTask = nil
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: supportedEnvironmentTypes,
            allowsMultipleSelection: false
        ) { result in
            Task {
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }
                    let hasSecurityScope = url.startAccessingSecurityScopedResource()
                    defer {
                        if hasSecurityScope {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    _ = try await appState.environmentCatalogManager.importEnvironment(from: url)
                    await coalescedLoadAssets()
                } catch {
                    environmentError = error.localizedDescription
                }
            }
        }
        .alert(
            "Environment Error",
            isPresented: Binding(
                get: { environmentError != nil },
                set: { isPresented in
                    if !isPresented { environmentError = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(environmentError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func onlinePresetRow(_ preset: CuratedEnvironmentPreset) -> some View {
        let isInstalled = assets.contains(where: {
            $0.sourceType == .imported
                && $0.name == preset.name
                && $0.sourceAttributionURL == preset.sourceAttributionURL
        })
        let isInstalling = installingPresetIDs.contains(preset.id)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: preset.provider == .polyHaven ? "pano" : preset.provider == .official ? "apple.logo" : "shippingbox")
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.headline)
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(preset.provider.displayName) • \(preset.licenseName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let sourceURL = URL(string: preset.sourceAttributionURL) {
                        Link("Source", destination: sourceURL)
                            .font(.caption2)
                    }
                }

                Spacer()

                if isInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await installPreset(preset) }
                    } label: {
                        if isInstalling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Add", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func environmentRow(_ asset: EnvironmentAsset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: asset.sourceType == .bundled ? "sparkles" : "square.and.arrow.down")
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.headline)
                    Text(asset.sourceType == .bundled ? "Built-In" : "Imported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if asset.sourceType == .imported {
                        Text(asset.assetPath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else if let license = asset.licenseName, !license.isEmpty {
                        Text(license)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let source = asset.sourceAttributionURL,
                       let sourceURL = URL(string: source) {
                        Link("Source", destination: sourceURL)
                            .font(.caption2)
                    }
                }

                Spacer()

                if asset.isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 8) {
                if !asset.isActive {
                    Button("Activate") {
                        Task {
                            await appState.activateEnvironmentAsset(asset)
                            await coalescedLoadAssets()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if asset.sourceType == .imported {
                    Button(role: .destructive) {
                        Task {
                            do {
                                try await appState.environmentCatalogManager.deleteAsset(id: asset.id)
                                await coalescedLoadAssets()
                            } catch {
                                environmentError = error.localizedDescription
                            }
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private var supportedEnvironmentTypes: [UTType] {
        let types = [
            UTType(filenameExtension: "usdz"),
            UTType(filenameExtension: "reality"),
            UTType(filenameExtension: "hdr"),
            UTType(filenameExtension: "exr"),
        ].compactMap { $0 }
        return types.isEmpty ? [.data] : types
    }

    @MainActor
    private func installPreset(_ preset: CuratedEnvironmentPreset) async {
        guard !installingPresetIDs.contains(preset.id) else { return }
        installingPresetIDs.insert(preset.id)
        defer { installingPresetIDs.remove(preset.id) }

        do {
            _ = try await appState.environmentCatalogManager.importCuratedPreset(preset)
            await coalescedLoadAssets()
        } catch {
            environmentError = error.localizedDescription
        }
    }

    @MainActor
    private func scheduleAssetLoad() {
        assetLoadTask?.cancel()
        assetLoadTask = Task { await loadAssets() }
    }

    @MainActor
    private func coalescedLoadAssets() async {
        scheduleAssetLoad()
        await assetLoadTask?.value
    }

    @MainActor
    private func loadAssets() async {
        do {
            let latestAssets = try await appState.environmentCatalogManager.fetchAssets()
            guard !Task.isCancelled else { return }
            assets = latestAssets
            environmentError = nil
        } catch {
            guard !Task.isCancelled else { return }
            environmentError = error.localizedDescription
        }
    }
}
