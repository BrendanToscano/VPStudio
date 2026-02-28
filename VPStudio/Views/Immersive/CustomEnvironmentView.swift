#if os(visionOS)
import os
import SwiftUI
import RealityKit
import AVFoundation

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

    /// Strong reference to the AVPlayer to prevent it from being deallocated
    /// when the PlayerView's weak reference is cleared.
    @State private var immersivePlayer: AVPlayer?

    /// Strong reference to the video renderer for immersive playback.
    @State private var immersiveVideoRenderer: AVSampleBufferVideoRenderer?

    var body: some View {
        RealityView { content, attachments in
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
                content.add(entity)
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
            // MARK: Sync player references from AppState (weak) to local (strong)
            if immersivePlayer === nil || immersivePlayer !== appState.activeAVPlayer {
                immersivePlayer = appState.activeAVPlayer
            }
            if immersiveVideoRenderer === nil || immersiveVideoRenderer !== appState.activeVideoRenderer {
                immersiveVideoRenderer = appState.activeVideoRenderer
            }

            // MARK: Cinema screen material (cached)
            if let screen = cinemaScreen {
                let currentSourceID: ObjectIdentifier? = {
                    if let r = immersiveVideoRenderer { return ObjectIdentifier(r) }
                    if let p = immersivePlayer { return ObjectIdentifier(p) }
                    return nil
                }()

                if currentSourceID != lastMaterialSourceID {
                    if let renderer = immersiveVideoRenderer {
                        screen.model?.materials = [VideoMaterial(videoRenderer: renderer)]
                    } else if let player = immersivePlayer {
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
            immersivePlayer = nil
            immersiveVideoRenderer = nil
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
