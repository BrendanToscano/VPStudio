#if os(visionOS)
import SwiftUI
import RealityKit
import ImageIO
import os

private let logger = Logger(subsystem: "com.vpstudio", category: "HDRISkybox")

// MARK: - Screen Size Presets

/// Cinema screen size/distance presets. Cycle with `.immersiveControlCycleScreenSize`.
enum ScreenSizePreset: String, CaseIterable, Sendable {
    case personal = "Personal"
    case cinema   = "Cinema"
    case imax     = "IMAX"

    var width: Float {
        switch self {
        case .personal: 6
        case .cinema:   10
        case .imax:     16
        }
    }

    var height: Float {
        switch self {
        case .personal: 3.375
        case .cinema:   5.625
        case .imax:     9
        }
    }

    var distance: Float {
        switch self {
        case .personal: 10
        case .cinema:   20
        case .imax:     35
        }
    }

    var next: ScreenSizePreset {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return self }
        return all[(idx + 1) % all.count]
    }
}

// MARK: - View

struct HDRISkyboxEnvironment: View {
    @Environment(AppState.self) private var appState
    @Environment(VPPlayerEngine.self) private var engine

    @State private var headTracker = HeadTracker()
    @State private var isShowingImmersiveControls = false
    @State private var cinemaScreen: ModelEntity?
    @State private var controlsAnchor: Entity?
    @State private var didAnchorScreenToHead = false
    @State private var screenSizePreset: ScreenSizePreset = .cinema
    @State private var loadingState: LoadingState = .loading
    @State private var autoDismissTask: Task<Void, Never>?

    /// Tracks the identity of the current video source so we only rebuild the
    /// `VideoMaterial` when the source actually changes — avoids GPU churn on
    /// every RealityView update cycle (P1-IM-005).
    @State private var lastMaterialSourceID: ObjectIdentifier?

    private enum LoadingState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        RealityView { content, attachments in
            // MARK: Placeholder sphere (dark gradient while HDRI loads)
            let placeholderMesh = MeshResource.generateSphere(radius: 999)
            var placeholderMat = UnlitMaterial()
            placeholderMat.color = .init(tint: .init(red: 0.02, green: 0.02, blue: 0.04, alpha: 1))
            let placeholder = ModelEntity(mesh: placeholderMesh, materials: [placeholderMat])
            placeholder.scale *= SIMD3<Float>(x: -1, y: 1, z: 1)
            placeholder.name = "hdri-placeholder"
            content.add(placeholder)

            // MARK: Cinema screen (default position, repositioned by head tracker)
            let preset = screenSizePreset
            let screenMesh = MeshResource.generatePlane(width: preset.width, height: preset.height)
            let screenMat = SimpleMaterial(color: .black, isMetallic: false)
            let screen = ModelEntity(mesh: screenMesh, materials: [screenMat])
            screen.name = "cinema-screen"
            screen.position = SIMD3<Float>(0, 1.6, -preset.distance)
            content.add(screen)
            cinemaScreen = screen

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

            // MARK: Loading indicator attachment
            if let loadingPanel = attachments.entity(for: "loadingIndicator") {
                loadingPanel.position = SIMD3<Float>(0, 1.6, -4)
                content.add(loadingPanel)
            }

            // MARK: Async HDRI load
            guard let asset = appState.selectedEnvironmentAsset else {
                loadingState = .failed("No environment selected")
                return
            }

            guard let url = await appState.environmentCatalogManager.resolvedAssetURL(for: asset) else {
                loadingState = .failed("Environment file missing: \(asset.name)")
                return
            }

            // Validate file exists before attempting to load HDRI
            guard FileManager.default.fileExists(atPath: url.path) else {
                loadingState = .failed("HDRI file not found: \(url.lastPathComponent)")
                return
            }

            guard let cgImage = await Task.detached(priority: .userInitiated, operation: {
                Self.loadHDRImage(from: url)
            }).value else {
                loadingState = .failed("Could not decode HDRI image")
                return
            }

            let yawRadians = (asset.hdriYawOffset ?? 0) * (.pi / 180.0)

            do {
                // MARK: Sky sphere
                let skyMesh = MeshResource.generateSphere(radius: 1000)
                let texture = try await TextureResource(
                    image: cgImage,
                    options: .init(semantic: .hdrColor)
                )

                var skyMaterial = UnlitMaterial()
                skyMaterial.color = .init(texture: .init(texture))

                let skyEntity = ModelEntity(mesh: skyMesh, materials: [skyMaterial])
                skyEntity.scale *= SIMD3<Float>(x: -1, y: 1, z: 1)
                if yawRadians != 0 {
                    skyEntity.orientation = simd_quatf(angle: yawRadians, axis: [0, 1, 0])
                }
                skyEntity.name = "hdri-sky"
                content.add(skyEntity)

                // Remove placeholder
                placeholder.removeFromParent()

                // Remove loading indicator
                if let loadingPanel = attachments.entity(for: "loadingIndicator") {
                    loadingPanel.removeFromParent()
                }

                // MARK: IBL
                let environmentResource = try await EnvironmentResource(equirectangular: cgImage)
                let iblEntity = Entity()
                iblEntity.name = "hdri-ibl"
                if yawRadians != 0 {
                    iblEntity.orientation = simd_quatf(angle: yawRadians, axis: [0, 1, 0])
                }
                iblEntity.components.set(ImageBasedLightComponent(
                    source: .single(environmentResource),
                    intensityExponent: 1.0
                ))
                content.add(iblEntity)

                // MARK: Ground plane
                let groundMaterial = SimpleMaterial(
                    color: .init(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.3),
                    roughness: 0.9,
                    isMetallic: false
                )
                let ground = ModelEntity(
                    mesh: .generatePlane(width: 20, depth: 20),
                    materials: [groundMaterial]
                )
                ground.name = "hdri-ground"
                ground.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
                content.add(ground)

                // MARK: Ambient floor rim
                let rimMesh = MeshResource.generatePlane(width: 22, depth: 22)
                var rimMat = UnlitMaterial()
                rimMat.color = .init(tint: .init(red: 0.15, green: 0.12, blue: 0.08, alpha: 0.06))
                let rimEntity = ModelEntity(mesh: rimMesh, materials: [rimMat])
                rimEntity.name = "hdri-floor-rim"
                rimEntity.position.y = 0.001
                content.add(rimEntity)

                loadingState = .loaded

            } catch {
                loadingState = .failed(error.localizedDescription)
            }

        } update: { content, attachments in
            // MARK: Cinema screen material (cached — only rebuild when source changes)
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

            // MARK: Head-pose screen anchoring (one-shot)
            // Uses entity.look(at:from:relativeTo:forward:) from HUD gist research
            // to properly orient the screen toward the viewer. Head Y position is
            // used instead of hardcoded 1.6m (P2-055).
            if !didAnchorScreenToHead,
               let screen = cinemaScreen,
               let initial = headTracker.initialHeadTransform {
                let col3 = initial.columns.3
                let headPos = SIMD3<Float>(col3.x, col3.y, col3.z)
                let col2 = initial.columns.2
                let forward = normalize(SIMD3<Float>(-col2.x, 0, -col2.z))
                let dist = screenSizePreset.distance
                let screenPos = headPos + forward * dist
                let finalScreenPos = SIMD3<Float>(screenPos.x, headPos.y, screenPos.z)
                screen.look(at: headPos, from: finalScreenPos, relativeTo: nil, forward: .positiveZ)
                didAnchorScreenToHead = true
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
                    let forward = normalize(SIMD3<Float>(-col2.x, 0, -col2.z))
                    let target = headPos + forward * ImmersiveControlsPolicy.controlsForwardOffset
                    let smoothing = ImmersiveControlsPolicy.controlsAnchorSmoothing
                    anchor.position = simd_mix(
                        anchor.position, target,
                        SIMD3<Float>(repeating: smoothing)
                    )
                } else {
                    // Simulator / no ARKit — park controls at a sensible default.
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
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlCycleScreenSize)) { _ in
            cycleScreenSize()
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlTogglePlayPause)) { _ in
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekBack)) { _ in
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekForward)) { _ in
            scheduleAutoDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekToPercent)) { _ in
            scheduleAutoDismiss()
        }
        .onAppear {
            appState.immersiveSpaceDidAppear(.hdriSkybox)
            headTracker.start()
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
            appState.immersiveSpaceDidDisappear()
            headTracker.stop()

            // Explicit cleanup to break any lingering RealityKit references.
            cinemaScreen = nil
            controlsAnchor = nil
            lastMaterialSourceID = nil
            didAnchorScreenToHead = false
        }
    }

    // MARK: - Screen Size Cycling

    private func cycleScreenSize() {
        let newPreset = screenSizePreset.next
        screenSizePreset = newPreset

        guard let screen = cinemaScreen else { return }

        // Regenerate mesh for new dimensions.
        screen.model?.mesh = MeshResource.generatePlane(width: newPreset.width, height: newPreset.height)

        // Calculate target position using head Y instead of hardcoded 1.6m (P2-055).
        let headPos: SIMD3<Float>
        let targetPos: SIMD3<Float>
        if didAnchorScreenToHead, let initial = headTracker.initialHeadTransform {
            let col3 = initial.columns.3
            headPos = SIMD3<Float>(col3.x, col3.y, col3.z)
            let col2 = initial.columns.2
            let forward = normalize(SIMD3<Float>(-col2.x, 0, -col2.z))
            let newPos = headPos + forward * newPreset.distance
            targetPos = SIMD3<Float>(newPos.x, headPos.y, newPos.z)
        } else {
            let eyeY = ImmersiveControlsPolicy.fallbackEyeHeight
            headPos = SIMD3<Float>(0, eyeY, 0)
            targetPos = SIMD3<Float>(0, eyeY, -newPreset.distance)
        }

        // Compute target transform with proper facing via look(at:).
        let temp = Entity()
        temp.look(at: headPos, from: targetPos, relativeTo: nil, forward: .positiveZ)
        screen.move(to: temp.transform, relativeTo: nil, duration: 0.4)
    }

    // MARK: - Auto-Dismiss

    /// Schedules auto-hide of controls after the policy-defined interval.
    /// Any user interaction resets the timer.
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

    // MARK: - HDRI Image Loading

    nonisolated private static func loadHDRImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            logger.error("Could not create image source for \(url.lastPathComponent, privacy: .public)")
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true,
        ]

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            logger.error("Could not decode image at \(url.lastPathComponent, privacy: .public)")
            return nil
        }

        return image
    }
}
#endif
