#if os(visionOS)
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Sheet

/// Full-screen sheet that presents when the environment ornament button is tapped.
/// Shows environment cards in a grid so users can preview and manage them.
struct EnvironmentPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let onSelect: (EnvironmentAsset) -> Void
    let onDismiss: () -> Void

    @State private var environments: [EnvironmentAsset] = []
    @State private var isShowingFileImporter = false
    @State private var importError: String?
    @State private var environmentLoadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if environments.isEmpty {
                        emptyState
                    } else {
                        description
                        cardGrid
                        if appState.isImmersiveSpaceOpen {
                            exitButton
                        }
                    }

                    if let error = importError {
                        importErrorBanner(error)
                    }
                }
                .padding(28)
            }
            .navigationTitle("Environments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("Import HDRI", systemImage: "plus.circle")
                    }
                }
            }
        }
        .task { await coalescedLoadEnvironments() }
        .onReceive(NotificationCenter.default.publisher(for: .environmentsDidChange)) { _ in
            scheduleEnvironmentLoad()
        }
        .onDisappear {
            environmentLoadTask?.cancel()
            environmentLoadTask = nil
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: Self.hdriContentTypes,
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFileImport(result) }
        }
    }

    // MARK: - Content Types

    private static var hdriContentTypes: [UTType] {
        var types: [UTType] = []
        if let hdr = UTType(filenameExtension: "hdr") { types.append(hdr) }
        if let exr = UTType(filenameExtension: "exr") { types.append(exr) }
        if let usdz = UTType(filenameExtension: "usdz") { types.append(usdz) }
        if let reality = UTType(filenameExtension: "reality") { types.append(reality) }
        return types
    }

    // MARK: - Sub-views

    private var description: some View {
        Text("Choose an immersive environment to preview. Tap a card to open it in full space. The active environment opens automatically when you start playback.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var cardGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16),
        ]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(environments) { asset in
                EnvironmentPreviewCard(
                    asset: asset,
                    isActive: asset.id == appState.selectedEnvironmentAsset?.id,
                    isImmersiveOpen: appState.isImmersiveSpaceOpen,
                    onSelect: {
                        onSelect(asset)
                        dismiss()
                    },
                    onDelete: asset.sourceType == .imported ? {
                        Task { await deleteAsset(asset) }
                    } : nil
                )
            }
        }
    }

    private var exitButton: some View {
        Button(role: .destructive) {
            onDismiss()
            dismiss()
        } label: {
            Label("Exit Environment", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mountain.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Environments")
                .font(.title3.weight(.semibold))
            Text("Tap the + button to import HDRI (.hdr, .exr) or 3D scene (.usdz, .reality) files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func importErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") { importError = nil }
                .font(.caption)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

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
        let latestEnvironments = (try? await appState.environmentCatalogManager.fetchAssets()) ?? []
        guard !Task.isCancelled else { return }
        environments = latestEnvironments
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        importError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                _ = try await appState.environmentCatalogManager.importEnvironment(from: url)
                await coalescedLoadEnvironments()
            } catch {
                importError = error.localizedDescription
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func deleteAsset(_ asset: EnvironmentAsset) async {
        do {
            try await appState.environmentCatalogManager.deleteAsset(id: asset.id)
            await coalescedLoadEnvironments()
        } catch {
            importError = "Failed to delete: \(error.localizedDescription)"
        }
    }
}

// MARK: - Card

struct EnvironmentPreviewCard: View {
    let asset: EnvironmentAsset
    let isActive: Bool
    let isImmersiveOpen: Bool
    let onSelect: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var thumbnailImage: CGImage?
    @State private var thumbnailFailed = false
    @State private var isHovered = false
    @State private var thumbnailLoadTask: Task<Void, Never>?

    private let cardWidth: CGFloat = 230
    private let cardHeight: CGFloat = 136

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                previewBackground
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.45), location: 0.55),
                        .init(color: .black.opacity(0.82), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: assetTypeIcon)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(assetTypeLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text(asset.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(16)
            }
            .frame(width: cardWidth, height: cardHeight)
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [activeBorderTop, activeBorderBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 2 : 1
                )
        }
        .overlay(alignment: .topTrailing) {
            if isActive && isImmersiveOpen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .padding(10)
                    .transition(.scale(0.7).combined(with: .opacity))
            }
        }
        // Thumbnail load failure warning
        .overlay(alignment: .topLeading) {
            if thumbnailFailed && isHDRIAsset {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .padding(10)
            }
        }
        .shadow(color: .black.opacity(0.07), radius: 24)
        .shadow(
            color: isActive ? .blue.opacity(0.28) : .black.opacity(isHovered ? 0.28 : 0.13),
            radius: 8,
            y: 4
        )
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .hoverEffect(.lift)
        .task(id: asset.assetPath) {
            thumbnailLoadTask?.cancel()
            thumbnailLoadTask = Task { await loadThumbnail() }
            await thumbnailLoadTask?.value
        }
        .onDisappear {
            thumbnailLoadTask?.cancel()
            thumbnailLoadTask = nil
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Background

    @ViewBuilder
    private var previewBackground: some View {
        if let image = thumbnailImage {
            Image(image, scale: 1.0, label: Text(asset.name))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHovered)
        } else {
            placeholderGradient
        }
    }

    private var placeholderGradient: some View {
        let isHDRI = isHDRIAsset
        return LinearGradient(
            colors: isHDRI
                ? [Color(red: 0.04, green: 0.07, blue: 0.18), Color(red: 0.08, green: 0.18, blue: 0.38)]
                : [Color(red: 0.06, green: 0.05, blue: 0.12), Color(red: 0.14, green: 0.10, blue: 0.26)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: isHDRI ? "pano.fill" : "cube.transparent.fill")
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.12))
        }
    }

    // MARK: Helpers

    private var isHDRIAsset: Bool {
        let ext = URL(fileURLWithPath: asset.assetPath).pathExtension.lowercased()
        return ["hdr", "exr"].contains(ext)
    }

    private var assetTypeIcon: String { isHDRIAsset ? "pano" : "cube.transparent" }

    private var assetTypeLabel: String {
        asset.sourceType == .bundled ? "Built-in" : (isHDRIAsset ? "HDRI" : "3D Scene")
    }

    private var activeBorderTop: Color {
        isActive ? .blue.opacity(0.9) : .white.opacity(isHovered ? 0.4 : 0.18)
    }

    private var activeBorderBottom: Color {
        isActive ? .blue.opacity(0.4) : .white.opacity(isHovered ? 0.10 : 0.04)
    }

    // MARK: Thumbnail

    private func loadThumbnail() async {
        thumbnailImage = nil
        thumbnailFailed = false
        guard isHDRIAsset else { return }
        let url = URL(fileURLWithPath: asset.assetPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            thumbnailFailed = true
            return
        }

        let decodeTask = Task.detached(priority: .userInitiated) { () -> CGImage? in
            if Task.isCancelled {
                return nil
            }
            return Self.loadHDRThumbnail(from: url, maxDimension: 512)
        }

        let image = await withTaskCancellationHandler(
            operation: {
                await decodeTask.value
            },
            onCancel: {
                decodeTask.cancel()
            }
        )

        guard !Task.isCancelled else { return }

        if let image {
            thumbnailImage = image
        } else {
            thumbnailFailed = true
        }
    }

    nonisolated private static func loadHDRThumbnail(from url: URL, maxDimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // Verify source contains at least one image before attempting to load.
        guard CGImageSourceGetCount(source) > 0 else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
            return thumb
        }

        let fullOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true,
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, fullOptions as CFDictionary)
    }
}
#endif
