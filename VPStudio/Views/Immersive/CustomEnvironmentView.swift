#if os(visionOS)
import os
import Foundation
import SwiftUI
import RealityKit

private let logger = Logger(subsystem: "com.vpstudio.app", category: "CustomEnvironment")

struct CustomEnvironmentView: View {
    @Environment(AppState.self) private var appState
    @Environment(VPPlayerEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var headTracker = HeadTracker()
    @State private var isShowingImmersiveControls = false
    @State private var cinemaScreen: ModelEntity?
    @State private var controlsAnchor: Entity?
    @State private var lastMaterialSourceID: ObjectIdentifier?
    @State private var subtitleEntity: Entity?
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var loadingState: LoadingState = .loading
    @State private var subtitleFontSize: Double = 24

    private enum LoadingState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        RealityView { content, attachments in
            loadingState = .loading

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

            if let loadingPanel = attachments.entity(for: "loadingIndicator") {
                loadingPanel.position = SIMD3<Float>(0, 1.6, -4)
                content.add(loadingPanel)
                if case .loaded = loadingState {
                    loadingPanel.removeFromParent()
                }
            }

            guard let selected = appState.selectedEnvironmentAsset else {
                logger.warning("No selectedEnvironmentAsset — space opened prematurely?")
                let fallbackScreen = makeFallbackScreen()
                content.add(fallbackScreen)
                cinemaScreen = fallbackScreen
                loadingState = .failed("No environment selected. Showing a fallback screen.")
                return
            }

            guard let url = await appState.environmentCatalogManager.resolvedAssetURL(for: selected) else {
                logger.warning("resolvedAssetURL returned nil for asset — file missing?")
                let fallbackScreen = makeFallbackScreen()
                content.add(fallbackScreen)
                cinemaScreen = fallbackScreen
                loadingState = .failed("The selected environment file is missing. Showing a fallback screen.")
                return
            }

            do {
                let entity = try await Entity(contentsOf: url)
                content.add(entity)
                if let screen = findScreenEntity(in: entity) {
                    cinemaScreen = screen
                    loadingState = .loaded
                } else {
                    let fallbackScreen = makeFallbackScreen()
                    content.add(fallbackScreen)
                    cinemaScreen = fallbackScreen
                    logger.warning("No screen mesh found in custom environment '\(selected.name, privacy: .public)'")
                    loadingState = .failed("No screen surface was found in this environment. Showing a fallback screen.")
                }
            } catch {
                logger.error("Entity(contentsOf:) failed — \(error.localizedDescription, privacy: .public)")
                let fallbackScreen = makeFallbackScreen()
                content.add(fallbackScreen)
                cinemaScreen = fallbackScreen
                loadingState = .failed("The environment failed to load. Showing a fallback screen.")
            }

            // MARK: Subtitle attachment
            if let subtitlePanel = attachments.entity(for: "immersiveSubtitle") {
                // Position below the screen if found, otherwise a sensible default.
                if let screen = cinemaScreen {
                    let bounds = screen.visualBounds(relativeTo: nil)
                    subtitlePanel.position = SIMD3<Float>(
                        screen.position.x,
                        screen.position.y + bounds.min.y - 0.15,
                        screen.position.z
                    )
                    subtitlePanel.orientation = screen.orientation
                } else {
                    subtitlePanel.position = SIMD3<Float>(0, 0.6, -4)
                }
                content.add(subtitlePanel)
                subtitleEntity = subtitlePanel
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

            // MARK: Subtitle position tracking
            if let subEnt = attachments.entity(for: "immersiveSubtitle"),
               let screen = cinemaScreen {
                let bounds = screen.visualBounds(relativeTo: nil)
                subEnt.position = SIMD3<Float>(
                    screen.position.x,
                    screen.position.y + bounds.min.y - 0.15,
                    screen.position.z
                )
                subEnt.orientation = screen.orientation
                subtitleEntity = subEnt
            }

            // MARK: Controls anchor tracking
            if let anchor = controlsAnchor {
                if headTracker.isTracking {
                    let m = headTracker.headTransform
                    let col3 = m.columns.3
                    let headPos = SIMD3<Float>(
                        col3.x,
                        col3.y + ImmersiveControlsPolicy.controlsVerticalOffset,
                        col3.z
                    )
                    let col2 = m.columns.2
                    let forward = safeHorizontalForward(from: col2)
                    let target = headPos + forward * ImmersiveControlsPolicy.controlsForwardOffset
                    anchor.position = ImmersiveControlsPolicy.smoothedPosition(
                        current: anchor.position,
                        target: target
                    )
                } else {
                    anchor.position = ImmersiveControlsPolicy.fallbackControlsPosition
                }
            }

        } attachments: {
            Attachment(id: "playerControls") {
                if isShowingImmersiveControls {
                    ImmersivePlayerControlsView(showsScreenSizeControl: false)
                        .frame(width: 520)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }

            Attachment(id: "immersiveSubtitle") {
                if let subtitleText = engine.currentSubtitleText, !subtitleText.isEmpty {
                    ImmersiveSubtitleRenderer(
                        text: subtitleText,
                        fontSize: subtitleFontSize,
                        maxWidth: ScreenSizePreset.cinema.subtitleMaxWidth
                    )
                    .transition(.opacity)
                    .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.15), value: subtitleText)
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
            performOptionalAnimation(.easeInOut(duration: 0.25)) {
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
            appState.immersiveSpaceDidAppear(.customEnvironment)
            headTracker.start()
            Task { await loadSubtitleAppearance() }
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
            appState.immersiveSpaceDidDisappear()
            headTracker.stop()

            // Break lingering RealityKit references.
            cinemaScreen = nil
            controlsAnchor = nil
            subtitleEntity = nil
            lastMaterialSourceID = nil
        }
    }

    /// Schedules auto-hide of controls after 10 seconds (OpenImmersive pattern).
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        guard isShowingImmersiveControls else { return }
        autoDismissTask = Task {
            try? await Task.sleep(for: ImmersiveControlsPolicy.autoDismissInterval)
            guard !Task.isCancelled else { return }
            performOptionalAnimation(.easeInOut(duration: 0.25)) {
                isShowingImmersiveControls = false
            }
            headTracker.isIdle = true
        }
    }

    private func performOptionalAnimation(_ animation: Animation, updates: () -> Void) {
        if accessibilityReduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    @MainActor
    private func loadSubtitleAppearance() async {
        let storedSize = (try? await appState.settingsManager.getString(key: SettingsKeys.subtitleFontSize))
            .flatMap(Double.init)
        subtitleFontSize = storedSize.map { max(16, min(48, $0)) } ?? ScreenSizePreset.cinema.subtitleFontSize
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

    private func safeHorizontalForward(from column: SIMD4<Float>) -> SIMD3<Float> {
        let candidate = SIMD3<Float>(-column.x, 0, -column.z)
        let lengthSquared = candidate.x * candidate.x + candidate.y * candidate.y + candidate.z * candidate.z
        guard lengthSquared > .leastNonzeroMagnitude else {
            return SIMD3<Float>(0, 0, -1)
        }
        return candidate / sqrt(lengthSquared)
    }

    private func makeFallbackScreen() -> ModelEntity {
        let mesh = MeshResource.generatePlane(
            width: ScreenSizePreset.personal.width,
            height: ScreenSizePreset.personal.height
        )
        let material = SimpleMaterial(color: .black, isMetallic: false)
        let screen = ModelEntity(mesh: mesh, materials: [material])
        screen.name = "custom-fallback-screen"
        screen.position = SIMD3<Float>(0, ImmersiveControlsPolicy.fallbackEyeHeight, -4)
        return screen
    }

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
            Text("Environment Warning")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
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
        }
        .padding(24)
        .frame(maxWidth: 320)
        .glassBackgroundEffect()
    }
}
#endif
