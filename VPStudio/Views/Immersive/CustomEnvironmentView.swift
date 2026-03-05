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
    @State private var sceneRoot: Entity?
    @State private var cinemaScreen: ModelEntity?
    @State private var controlsAnchor: Entity?
    @State private var lastMaterialSourceID: ObjectIdentifier?
    @State private var autoDismissTask: Task<Void, Never>?

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.name = "custom-root"
            content.add(root)
            sceneRoot = root

            guard let selected = appState.selectedEnvironmentAsset else {
                logger.warning("No selectedEnvironmentAsset — space opened prematurely?")
                return
            }

            guard let url = await appState.environmentCatalogManager.resolvedAssetURL(for: selected) else {
                logger.warning("resolvedAssetURL returned nil for asset — file missing?")
                return
            }

            do {
                let entity = try await Entity(contentsOf: url)
                root.addChild(entity)
                cinemaScreen = findScreenEntity(in: entity)
            } catch {
                logger.error("Entity(contentsOf:) failed — \(error.localizedDescription, privacy: .public)")
            }

            // MARK: TapCatcher
            let tapShape = ShapeResource.generateBox(size: [200, 200, 0.5])
            let tapCatcher = Entity()
            tapCatcher.name = "tap-catcher"
            tapCatcher.components.set(CollisionComponent(shapes: [tapShape], mode: .trigger, filter: .default))
            tapCatcher.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            tapCatcher.position = SIMD3<Float>(0, 0, -5)
            root.addChild(tapCatcher)

            // MARK: Controls anchor
            let anchor = Entity()
            anchor.name = "controls-anchor"
            root.addChild(anchor)
            controlsAnchor = anchor

            if let controlsPanel = attachments.entity(for: "playerControls") {
                controlsPanel.position = SIMD3<Float>(
                    0,
                    ImmersiveControlsPolicy.controlsVerticalOffset,
                    -ImmersiveControlsPolicy.controlsForwardOffset
                )
                anchor.addChild(controlsPanel)
            }

        } update: { _, attachments in
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
            if let anchor = controlsAnchor {
                if let controlsPanel = attachments.entity(for: "playerControls"),
                   controlsPanel.parent !== anchor {
                    controlsPanel.position = SIMD3<Float>(
                        0,
                        ImmersiveControlsPolicy.controlsVerticalOffset,
                        -ImmersiveControlsPolicy.controlsForwardOffset
                    )
                    anchor.addChild(controlsPanel)
                }

                if headTracker.isTracking {
                    let m = headTracker.headTransform
                    let col3 = m.columns.3
                    let headPos = SIMD3<Float>(
                        col3.x,
                        col3.y + ImmersiveControlsPolicy.controlsVerticalOffset,
                        col3.z
                    )
                    let col2 = m.columns.2
                    let planarForward = SIMD3<Float>(-col2.x, 0, -col2.z)
                    let forward = simd_length_squared(planarForward) > 0.0001
                        ? normalize(planarForward)
                        : SIMD3<Float>(0, 0, -1)
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
                    ImmersivePlayerControlsView()
                        .frame(width: 520)
                        .transition(.opacity.combined(with: .scale(0.92)))
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
            resetStateForReentry()
            appState.immersiveSpaceDidAppear(.customEnvironment)
            headTracker.stop()
            headTracker.isIdle = true
            headTracker.start()
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
            appState.immersiveSpaceDidDisappear()
            headTracker.stop()
            headTracker.isIdle = true

            // Break lingering RealityKit references.
            sceneRoot?.removeFromParent()
            sceneRoot = nil
            cinemaScreen = nil
            controlsAnchor = nil
            lastMaterialSourceID = nil
            isShowingImmersiveControls = false
        }
    }

    private func resetStateForReentry() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        isShowingImmersiveControls = false
        lastMaterialSourceID = nil
        sceneRoot?.removeFromParent()
        sceneRoot = nil
        cinemaScreen = nil
        controlsAnchor = nil
    }

    /// Schedules auto-hide of controls after the shared immersive policy interval.
    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        guard isShowingImmersiveControls else { return }
        autoDismissTask = Task {
            try? await Task.sleep(for: ImmersiveControlsPolicy.autoDismissInterval)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isShowingImmersiveControls = false
            }
            headTracker.isIdle = true
        }
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
