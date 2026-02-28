#if os(visionOS)
import os
import SwiftUI
import RealityKit

private let logger = Logger(subsystem: "com.vpstudio.app", category: "CustomEnvironment")

struct CustomEnvironmentView: View {
    @Environment(AppState.self) private var appState
    @Environment(VPPlayerEngine.self) private var engine

    @State private var headTracker = HeadTracker()
    @State private var isShowingImmersiveControls = false
    @State private var cinemaScreen: ModelEntity?
    @State private var controlsAnchor: Entity?
    @State private var lastMaterialSourceID: ObjectIdentifier?
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var loadingState: LoadingState = .loading

    private enum LoadingState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        RealityView { content, attachments in
            // MARK: Placeholder (dark gradient while loading)
            let placeholderMesh = MeshResource.generateSphere(radius: 999)
            var placeholderMat = UnlitMaterial()
            placeholderMat.color = .init(tint: .init(red: 0.02, green: 0.02, blue: 0.04, alpha: 1))
            let placeholder = ModelEntity(mesh: placeholderMesh, materials: [placeholderMat])
            placeholder.scale *= SIMD3<Float>(x: -1, y: 1, z: 1)
            placeholder.name = "custom-env-placeholder"
            content.add(placeholder)

            guard let selected = appState.selectedEnvironmentAsset else {
                placeholder.removeFromParent()
                loadingState = .failed("No environment selected")
                return
            }

            guard let url = await appState.environmentCatalogManager.resolvedAssetURL(for: selected) else {
                placeholder.removeFromParent()
                loadingState = .failed("Environment file not found: \(selected.name)")
                return
            }

            // Validate file exists before attempting to load
            guard FileManager.default.fileExists(atPath: url.path) else {
                placeholder.removeFromParent()
                loadingState = .failed("Environment file is missing: \(url.lastPathComponent)")
                return
            }

            do {
                let entity = try await Entity(contentsOf: url)
                content.add(entity)
                cinemaScreen = findScreenEntity(in: entity)

                // Remove placeholder on success
                placeholder.removeFromParent()
                loadingState = .loaded
            } catch {
                placeholder.removeFromParent()
                loadingState = .failed("Could not load environment: \(error.localizedDescription)")
                logger.error("Entity(contentsOf:) failed — \(error.localizedDescription, privacy: .public)")
            }

            // MARK: TapCatcher
            let tapShape = ShapeResource.generateBox(size: [200, 200, 0.5])
            let tapCatcher = Entity()
            tapCatcher.name = "tap-catcher"
            tapCatcher.components.set(CollisionComponent(shapes: [tapShape], mode: .trigger, filter: .default))
            tapCatcher.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            tapCatcher.position = SIMD3<Float>(0, 0, -5)
            content.add(tapCatcher)

            // MARK: Controls anchor
            let anchor = Entity()
            anchor.name = "controls-anchor"
            content.add(anchor)
            controlsAnchor = anchor

            if let controlsPanel = attachments.entity(for: "playerControls") {
                controlsPanel.position = SIMD3<Float>(0, -0.15, -1.5)
                anchor.addChild(controlsPanel)
            }

        } update: { content, attachments in
            // MARK: Cinema screen material (cached)
            if let screen = cinemaScreen {
                let currentSourceID: ObjectIdentifier? = {
                    if let r = appState.activeVideoRenderer { return ObjectIdentifier(r) }
                    if let p = appState.activeAVPlayer { return ObjectIdentifier(p) }
                    return nil
                }()

                if currentSourceID != lastMaterialSourceID {
                    if let renderer = appState.activeVideoRenderer {
                        screen.model?.materials = [VideoMaterial(videoRenderer: renderer)]
                    } else if let player = appState.activeAVPlayer {
                        screen.model?.materials = [VideoMaterial(avPlayer: player)]
                    } else {
                        screen.model?.materials = [SimpleMaterial(color: .black, isMetallic: false)]
                    }
                    lastMaterialSourceID = currentSourceID
                }
            }

            // MARK: Controls anchor tracking
            if headTracker.isTracking, let anchor = controlsAnchor {
                let m = headTracker.headTransform
                let col3 = m.columns.3
                let headPos = SIMD3<Float>(col3.x, col3.y - 0.15, col3.z)
                let col2 = m.columns.2
                let forward = normalize(SIMD3<Float>(-col2.x, 0, -col2.z))
                let target = headPos + forward * 1.5
                anchor.position = simd_mix(anchor.position, target, SIMD3<Float>(repeating: 0.08))
            }

        } attachments: {
            Attachment(id: "playerControls") {
                if isShowingImmersiveControls {
                    ImmersivePlayerControlsView()
                        .frame(width: 520)
                        .transition(.opacity.combined(with: .scale(0.92)))
                }
            }

            Attachment(id: "loadingIndicator") {
                switch loadingState {
                case .loading:
                    loadingView
                case .failed(let message):
                    errorView(message: message)
                case .loaded:
                    EmptyView()
                }
            }
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { _ in
                    NotificationCenter.default.post(name: .immersiveTapCatcherDidFire, object: nil)
                }
        )
        .preferredSurroundingsEffect(.systemDark)
        .onReceive(NotificationCenter.default.publisher(for: .immersiveTapCatcherDidFire)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                isShowingImmersiveControls.toggle()
            }
            headTracker.isIdle = !isShowingImmersiveControls
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlTogglePlayPause)) { _ in
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekToPercent)) { _ in
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekBack)) { _ in
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekForward)) { _ in
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlCycleScreenSize)) { _ in
            // Custom USDZ environments have a fixed screen mesh — screen cycling is
            // a no-op, but we still reset the auto-dismiss timer for consistency.
            scheduleAutoDismiss()
        }
        .onAppear {
            loadingState = .loading
            appState.immersiveSpaceDidAppear(.customEnvironment)
            headTracker.start()
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
            appState.immersiveSpaceDidDisappear()
            headTracker.stop()

            // Break lingering RealityKit references.
            cinemaScreen = nil
            controlsAnchor = nil
            lastMaterialSourceID = nil
            loadingState = .loading
        }
    }

    /// Schedules auto-hide of controls after 10 seconds (OpenImmersive pattern).
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        guard isShowingImmersiveControls else { return }
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isShowingImmersiveControls = false
            }
            headTracker.isIdle = true
        }
    }

    // MARK: - Loading / Error Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Loading environment…")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(24)
        .glassBackgroundEffect()
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            Text("Failed to load environment")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button {
                NotificationCenter.default.post(name: .immersiveControlDismiss, object: nil)
            } label: {
                Text("Close")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 300)
        .glassBackgroundEffect()
    }

    /// Recursively scan the USDZ hierarchy to find the mesh intended to be the movie screen.
    private func findScreenEntity(in root: Entity) -> ModelEntity? {
        let keywords = ["screen", "display", "tv", "monitor", "cinema", "video"]
        let lowerName = root.name.lowercased()

        if let modelEntity = root as? ModelEntity,
           keywords.contains(where: { lowerName.containsStandaloneToken($0) }) {
            logger.info("Anchored video to USDZ mesh '\(root.name, privacy: .public)'")
            return modelEntity
        }

        for child in root.children {
            if let found = findScreenEntity(in: child) {
                return found
            }
        }
        return nil
    }
}
#endif
