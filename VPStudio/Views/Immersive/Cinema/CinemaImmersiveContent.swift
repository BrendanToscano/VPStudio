#if os(visionOS)
import SwiftUI
import RealityKit
import simd
import AVFoundation

private final class CinemaSceneEntities {
    var screenBackplateEntity: ModelEntity?
    var screenEntity: ModelEntity?
    var screenFrameEntities: [ModelEntity] = []
    var backdropEntity: ModelEntity?
    var floorEntity: ModelEntity?
    var rearWallEntity: ModelEntity?
    var leftWallEntity: ModelEntity?
    var rightWallEntity: ModelEntity?
    var ceilingEntity: ModelEntity?
    var seatEntities: [ModelEntity] = []
    var aisleLightEntities: [ModelEntity] = []
    var directionalLight: Entity?
    var pointLight: Entity?
    var rootEntity: Entity?

    var lastScreenSize: CGSize = .zero
    var lastEnvironmentDarkness: Double = -1
    var lastAmbientLighting: Double = -1
    var lastMaterialSourceID: ObjectIdentifier?
}

enum CinemaImmersivePlacementPolicy {
    static let fallbackEyeHeight: Float = 1.55
    static let backdropRadius: Float = 26
    static let floorWidth: Float = 18
    static let floorDepth: Float = 18
    static let wallWidth: Float = 18
    static let wallHeight: Float = 7
    static let ceilingHeight: Float = 4.4
    static let sideWallDepth: Float = 18
    static let sideWallThickness: Float = 0.04
    static let floorYOffset: Float = -1.45
    static let rearWallZOffset: Float = -8.5
    static let sideWallXOffset: Float = 9
    static let frameThickness: Float = 0.08
    static let frameDepth: Float = 0.06
    static let screenBackplatePadding: Float = 0.18
    static let screenForwardOffset: Float = 0.012
    static let seatingRows = 4
    static let seatsPerRow = 7

    static func safeHorizontalForward(from column: SIMD4<Float>) -> SIMD3<Float> {
        let candidate = SIMD3<Float>(-column.x, 0, -column.z)
        let lengthSquared = candidate.x * candidate.x + candidate.y * candidate.y + candidate.z * candidate.z
        guard lengthSquared > .leastNonzeroMagnitude else {
            return SIMD3<Float>(0, 0, -1)
        }
        return candidate / sqrt(lengthSquared)
    }

    @MainActor
    static func screenPosition(
        settings: CinemaSettings,
        headTransform: simd_float4x4?
    ) -> (position: SIMD3<Float>, lookAt: SIMD3<Float>) {
        if let headTransform {
            let translation = headTransform.columns.3
            let head = SIMD3<Float>(translation.x, translation.y, translation.z)
            let forward = safeHorizontalForward(from: headTransform.columns.2)
            let right = normalizeOrFallback(simd_cross(forward, SIMD3<Float>(0, 1, 0)), fallback: SIMD3<Float>(1, 0, 0))
            let distance = max(Float(settings.screenDistance - settings.seatOffset.z), 0.75)
            let position = head
                + forward * distance
                + right * Float(settings.seatOffset.x)
                + SIMD3<Float>(0, Float(settings.screenHeight + settings.seatOffset.y), 0)
            return (position, head)
        }

        let eye = SIMD3<Float>(0, fallbackEyeHeight, 0)
        let position = SIMD3<Float>(
            Float(settings.seatOffset.x),
            fallbackEyeHeight + Float(settings.screenHeight + settings.seatOffset.y),
            -max(Float(settings.screenDistance - settings.seatOffset.z), 0.75)
        )
        return (position, eye)
    }

    static func shouldShowBackdrop(immersionStyleRaw: String, environmentDarkness: Double) -> Bool {
        guard environmentDarkness > 0.05 else { return false }
        return CinemaImmersionStyle(rawValue: immersionStyleRaw) != nil
    }

    static func backdropOpacity(for environmentDarkness: Double) -> Float {
        Float(min(max(environmentDarkness, 0.18), 1.0))
    }

    private static func normalizeOrFallback(_ value: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(value)
        guard lengthSquared > .leastNonzeroMagnitude else { return fallback }
        return value / sqrt(lengthSquared)
    }
}

public struct CinemaImmersiveContent: View {
    @Environment(AppState.self) private var appState
    @Environment(VPPlayerEngine.self) private var engine
    @Bindable public var settings: CinemaSettings

    @State private var scene = CinemaSceneEntities()
    @State private var headTracker = HeadTracker()
    @State private var didAnchorScreenToHead = false

    public init(settings: CinemaSettings) {
        self.settings = settings
    }

    public var body: some View {
        RealityView { content in
            let anchor = AnchorEntity(world: matrix_identity_float4x4)

            // ---- Screen ----
            let screenSize = settings.screenSize
            let planeWidth = Float(screenSize.width)
            let planeHeight = Float(screenSize.height)

            let backplateMesh = MeshResource.generateBox(
                width: planeWidth + CinemaImmersivePlacementPolicy.screenBackplatePadding,
                height: planeHeight + CinemaImmersivePlacementPolicy.screenBackplatePadding,
                depth: 0.04
            )
            let screenBackplateEntity = ModelEntity(
                mesh: backplateMesh,
                materials: [Self.makeShellMaterial(red: 0.008, green: 0.009, blue: 0.012, alpha: 1.0)]
            )
            screenBackplateEntity.name = "cinemaScreenBackplate"
            scene.screenBackplateEntity = screenBackplateEntity

            let screenMesh = MeshResource.generatePlane(
                width: planeWidth,
                height: planeHeight,
                cornerRadius: 0.02
            )
            let screenEntity = ModelEntity(mesh: screenMesh, materials: [makeScreenMaterial()])
            screenEntity.name = "cinemaScreen"
            scene.screenEntity = screenEntity
            scene.lastScreenSize = screenSize
            scene.lastMaterialSourceID = currentMaterialSourceID()

            scene.screenFrameEntities = Self.makeScreenFrameEntities(
                width: planeWidth,
                height: planeHeight
            )

            // ---- Visible cinema shell ----
            let backdropMesh = MeshResource.generateSphere(radius: CinemaImmersivePlacementPolicy.backdropRadius)
            var backdropMaterial = UnlitMaterial()
            backdropMaterial.color.tint = UIColor(red: 0.018, green: 0.020, blue: 0.032, alpha: 1)
            let backdropEntity = ModelEntity(mesh: backdropMesh, materials: [backdropMaterial])
            backdropEntity.components[OpacityComponent.self] = OpacityComponent(opacity: 0.0)
            backdropEntity.name = "cinemaBackdrop"
            backdropEntity.scale = SIMD3<Float>(-1, 1, 1)
            scene.backdropEntity = backdropEntity

            let floorEntity = ModelEntity(
                mesh: .generatePlane(
                    width: CinemaImmersivePlacementPolicy.floorWidth,
                    depth: CinemaImmersivePlacementPolicy.floorDepth
                ),
                materials: [Self.makeShellMaterial(red: 0.090, green: 0.085, blue: 0.095, alpha: 1.0)]
            )
            floorEntity.name = "cinemaFloor"
            scene.floorEntity = floorEntity

            let rearWallEntity = ModelEntity(
                mesh: .generatePlane(
                    width: CinemaImmersivePlacementPolicy.wallWidth,
                    height: CinemaImmersivePlacementPolicy.wallHeight
                ),
                materials: [Self.makeShellMaterial(red: 0.085, green: 0.030, blue: 0.040, alpha: 1.0)]
            )
            rearWallEntity.name = "cinemaRearWall"
            scene.rearWallEntity = rearWallEntity

            let sideWallMesh = MeshResource.generateBox(
                width: CinemaImmersivePlacementPolicy.sideWallThickness,
                height: CinemaImmersivePlacementPolicy.wallHeight,
                depth: CinemaImmersivePlacementPolicy.sideWallDepth
            )
            let leftWallEntity = ModelEntity(
                mesh: sideWallMesh,
                materials: [Self.makeShellMaterial(red: 0.060, green: 0.026, blue: 0.036, alpha: 1.0)]
            )
            leftWallEntity.name = "cinemaLeftWall"
            scene.leftWallEntity = leftWallEntity

            let rightWallEntity = ModelEntity(
                mesh: sideWallMesh,
                materials: [Self.makeShellMaterial(red: 0.060, green: 0.026, blue: 0.036, alpha: 1.0)]
            )
            rightWallEntity.name = "cinemaRightWall"
            scene.rightWallEntity = rightWallEntity

            let ceilingEntity = ModelEntity(
                mesh: .generateBox(
                    width: CinemaImmersivePlacementPolicy.floorWidth,
                    height: 0.04,
                    depth: CinemaImmersivePlacementPolicy.floorDepth
                ),
                materials: [Self.makeShellMaterial(red: 0.035, green: 0.034, blue: 0.045, alpha: 1.0)]
            )
            ceilingEntity.name = "cinemaCeiling"
            scene.ceilingEntity = ceilingEntity

            scene.seatEntities = Self.makeSeatEntities()
            scene.aisleLightEntities = Self.makeAisleLightEntities()

            scene.lastEnvironmentDarkness = settings.environmentDarkness

            // ---- Directional light ----
            let dirLight = Entity()
            dirLight.name = "directionalLight"
            dirLight.components[DirectionalLightComponent.self] = DirectionalLightComponent(
                color: .white,
                intensity: Float(settings.ambientLighting)
            )
            dirLight.orientation = simd_quatf(
                angle: Float.pi / 4,
                axis: SIMD3<Float>(1, -1, 0)
            )
            scene.directionalLight = dirLight
            scene.lastAmbientLighting = settings.ambientLighting

            // ---- Point light ----
            let pointLight = Entity()
            pointLight.name = "pointLight"
            pointLight.components[PointLightComponent.self] = PointLightComponent(
                color: .white,
                intensity: Float(settings.ambientLighting),
                attenuationRadius: 10.0
            )
            scene.pointLight = pointLight

            // ---- Root with IBL suppression ----
            let root = Entity()
            root.name = "root"
            root.components[EnvironmentLightingConfigurationComponent.self] = EnvironmentLightingConfigurationComponent(
                environmentLightingWeight: 0.0
            )
            root.addChild(backdropEntity)
            root.addChild(floorEntity)
            root.addChild(rearWallEntity)
            root.addChild(leftWallEntity)
            root.addChild(rightWallEntity)
            root.addChild(ceilingEntity)
            root.addChild(screenBackplateEntity)
            root.addChild(screenEntity)
            for frameEntity in scene.screenFrameEntities {
                root.addChild(frameEntity)
            }
            for seatEntity in scene.seatEntities {
                root.addChild(seatEntity)
            }
            for aisleLightEntity in scene.aisleLightEntities {
                root.addChild(aisleLightEntity)
            }
            root.addChild(dirLight)
            root.addChild(pointLight)
            scene.rootEntity = root

            anchor.addChild(root)
            content.add(anchor)

            // Initial transform / material updates
            updateScreenTransform()
            updateSphere()
            updateLights()

        } update: { _ in
            guard scene.rootEntity != nil else { return }
            updateScreenMaterialIfNeeded()

            // Rebuild mesh only when aspect ratio (screenSize) changes
            let currentScreenSize = settings.screenSize
            if currentScreenSize != scene.lastScreenSize {
                let newMesh = MeshResource.generatePlane(
                    width: Float(currentScreenSize.width),
                    height: Float(currentScreenSize.height),
                    cornerRadius: 0.02
                )
                if var model = scene.screenEntity?.model {
                    model.mesh = newMesh
                    scene.screenEntity?.model = model
                }
                if var model = scene.screenBackplateEntity?.model {
                    model.mesh = MeshResource.generateBox(
                        width: Float(currentScreenSize.width) + CinemaImmersivePlacementPolicy.screenBackplatePadding,
                        height: Float(currentScreenSize.height) + CinemaImmersivePlacementPolicy.screenBackplatePadding,
                        depth: 0.04
                    )
                    scene.screenBackplateEntity?.model = model
                }
                rebuildScreenFrame(width: Float(currentScreenSize.width), height: Float(currentScreenSize.height))
                scene.lastScreenSize = currentScreenSize
            }

            updateScreenTransform()
            updateSphere()
            updateLights()
        }
        .preferredSurroundingsEffect(
            settings.useSurroundingsEffect && settings.environmentDarkness >= 0.5 ? .systemDark : nil
        )
        .onAppear {
            appState.immersiveSpaceDidAppear(.cinemaEnvironment)
            appState.spatialAudioManager.enterImmersiveMode()
            headTracker.start()
        }
        .onDisappear {
            appState.immersiveSpaceDidDisappear()
            appState.spatialAudioManager.exitImmersiveMode()
            headTracker.stop()
            didAnchorScreenToHead = false
        }
    }

    // MARK: - Update helpers

    private func updateScreenTransform() {
        guard let screen = scene.screenEntity else { return }
        let headTransform = headTracker.initialHeadTransform
        let placement = CinemaImmersivePlacementPolicy.screenPosition(
            settings: settings,
            headTransform: headTransform
        )

        screen.look(at: placement.lookAt, from: placement.position, relativeTo: nil, forward: .positiveZ)
        if settings.screenTilt != 0 {
            screen.orientation *= simd_quatf(
                angle: Float(settings.screenTilt * Double.pi / 180),
                axis: SIMD3<Float>(1, 0, 0)
            )
        }
        let forward = normalizeOrFallback(
            vector3(screen.transform.matrix.columns.2),
            fallback: SIMD3<Float>(0, 0, 1)
        )
        scene.screenBackplateEntity?.orientation = screen.orientation
        scene.screenBackplateEntity?.position = placement.position - forward * 0.035
        screen.position = placement.position + forward * CinemaImmersivePlacementPolicy.screenForwardOffset
        for frameEntity in scene.screenFrameEntities {
            frameEntity.orientation = screen.orientation
        }
        positionScreenFrameEntities(
            center: placement.position,
            forward: forward,
            right: normalizeOrFallback(vector3(screen.transform.matrix.columns.0), fallback: SIMD3<Float>(1, 0, 0)),
            up: normalizeOrFallback(vector3(screen.transform.matrix.columns.1), fallback: SIMD3<Float>(0, 1, 0))
        )
        didAnchorScreenToHead = headTransform != nil
    }

    private func updateSphere() {
        let shouldShow = CinemaImmersivePlacementPolicy.shouldShowBackdrop(
            immersionStyleRaw: settings.immersionStyleRaw,
            environmentDarkness: settings.environmentDarkness
        )

        if let backdrop = scene.backdropEntity {
            backdrop.isEnabled = shouldShow
            if shouldShow {
                backdrop.components[OpacityComponent.self] = OpacityComponent(
                    opacity: CinemaImmersivePlacementPolicy.backdropOpacity(for: settings.environmentDarkness)
                )
            }
        }
        scene.lastEnvironmentDarkness = settings.environmentDarkness

        let center = scene.screenEntity?.position ?? SIMD3<Float>(0, CinemaImmersivePlacementPolicy.fallbackEyeHeight, -Float(settings.screenDistance))
        scene.backdropEntity?.position = SIMD3<Float>(
            Float(settings.seatOffset.x),
            CinemaImmersivePlacementPolicy.fallbackEyeHeight + Float(settings.seatOffset.y),
            Float(settings.seatOffset.z)
        )
        scene.floorEntity?.position = SIMD3<Float>(
            Float(settings.seatOffset.x),
            CinemaImmersivePlacementPolicy.floorYOffset + Float(settings.seatOffset.y),
            Float(settings.seatOffset.z)
        )
        scene.rearWallEntity?.position = SIMD3<Float>(
            center.x,
            CinemaImmersivePlacementPolicy.fallbackEyeHeight + Float(settings.seatOffset.y),
            center.z + CinemaImmersivePlacementPolicy.rearWallZOffset
        )
        scene.leftWallEntity?.position = SIMD3<Float>(
            center.x - CinemaImmersivePlacementPolicy.sideWallXOffset,
            CinemaImmersivePlacementPolicy.fallbackEyeHeight + Float(settings.seatOffset.y),
            center.z
        )
        scene.rightWallEntity?.position = SIMD3<Float>(
            center.x + CinemaImmersivePlacementPolicy.sideWallXOffset,
            CinemaImmersivePlacementPolicy.fallbackEyeHeight + Float(settings.seatOffset.y),
            center.z
        )
        scene.ceilingEntity?.position = SIMD3<Float>(
            Float(settings.seatOffset.x),
            CinemaImmersivePlacementPolicy.ceilingHeight + Float(settings.seatOffset.y),
            Float(settings.seatOffset.z)
        )
        positionSeatsAndAisleLights()
    }

    private func updateLights() {
        guard let dirLight = scene.directionalLight,
              let pointLight = scene.pointLight else { return }

        let intensity = Float(settings.ambientLighting)

        if settings.ambientLighting != scene.lastAmbientLighting {
            dirLight.components[DirectionalLightComponent.self] = DirectionalLightComponent(
                color: .white,
                intensity: intensity
            )
            pointLight.components[PointLightComponent.self] = PointLightComponent(
                color: .white,
                intensity: intensity,
                attenuationRadius: 10.0
            )
            scene.lastAmbientLighting = settings.ambientLighting
        }

        let pointPosition = SIMD3<Float>(
            Float(settings.seatOffset.x),
            Float(settings.seatOffset.y + 2.0),
            Float(settings.seatOffset.z)
        )
        pointLight.position = pointPosition
    }

    private func currentMaterialSourceID() -> ObjectIdentifier? {
        if let renderer = appState.activeVideoRenderer {
            return ObjectIdentifier(renderer)
        }
        guard let player = appState.activeAVPlayer else {
            return ObjectIdentifier(scene)
        }
        return ObjectIdentifier(player)
    }

    private func makeScreenMaterial() -> RealityKit.Material {
        if let renderer = appState.activeVideoRenderer {
            return VideoMaterial(videoRenderer: renderer)
        }
        if let player = appState.activeAVPlayer {
            return VideoMaterial(avPlayer: player)
        }

        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.78, green: 0.80, blue: 0.86, alpha: 1.0))
        return material
    }

    private static func makeShellMaterial(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> RealityKit.Material {
        var material = UnlitMaterial()
        material.color.tint = UIColor(red: red, green: green, blue: blue, alpha: alpha)
        return material
    }

    private static func makeScreenFrameEntities(width: Float, height: Float) -> [ModelEntity] {
        let horizontalMesh = MeshResource.generateBox(
            width: width + CinemaImmersivePlacementPolicy.frameThickness * 2,
            height: CinemaImmersivePlacementPolicy.frameThickness,
            depth: CinemaImmersivePlacementPolicy.frameDepth
        )
        let verticalMesh = MeshResource.generateBox(
            width: CinemaImmersivePlacementPolicy.frameThickness,
            height: height + CinemaImmersivePlacementPolicy.frameThickness * 2,
            depth: CinemaImmersivePlacementPolicy.frameDepth
        )
        let material = makeShellMaterial(red: 0.82, green: 0.73, blue: 0.50, alpha: 1.0)
        let top = ModelEntity(mesh: horizontalMesh, materials: [material])
        top.name = "cinemaScreenFrameTop"
        let bottom = ModelEntity(mesh: horizontalMesh, materials: [material])
        bottom.name = "cinemaScreenFrameBottom"
        let left = ModelEntity(mesh: verticalMesh, materials: [material])
        left.name = "cinemaScreenFrameLeft"
        let right = ModelEntity(mesh: verticalMesh, materials: [material])
        right.name = "cinemaScreenFrameRight"
        return [top, bottom, left, right]
    }

    private static func makeSeatEntities() -> [ModelEntity] {
        let mesh = MeshResource.generateBox(width: 0.72, height: 0.42, depth: 0.54)
        let material = makeShellMaterial(red: 0.23, green: 0.035, blue: 0.055, alpha: 1.0)
        return (0..<CinemaImmersivePlacementPolicy.seatingRows).flatMap { row in
            (0..<CinemaImmersivePlacementPolicy.seatsPerRow).map { column in
                let seat = ModelEntity(mesh: mesh, materials: [material])
                seat.name = "cinemaSeat_\(row)_\(column)"
                return seat
            }
        }
    }

    private static func makeAisleLightEntities() -> [ModelEntity] {
        let mesh = MeshResource.generateBox(width: 0.18, height: 0.018, depth: 0.18)
        let material = makeShellMaterial(red: 1.0, green: 0.72, blue: 0.30, alpha: 1.0)
        return (0..<10).flatMap { index in
            [-1, 1].map { side in
                let light = ModelEntity(mesh: mesh, materials: [material])
                light.name = "cinemaAisleLight_\(side)_\(index)"
                return light
            }
        }
    }

    private func rebuildScreenFrame(width: Float, height: Float) {
        let parent = scene.rootEntity
        scene.screenFrameEntities.forEach { $0.removeFromParent() }
        scene.screenFrameEntities = Self.makeScreenFrameEntities(width: width, height: height)
        scene.screenFrameEntities.forEach { parent?.addChild($0) }
    }

    private func positionScreenFrameEntities(
        center: SIMD3<Float>,
        forward: SIMD3<Float>,
        right: SIMD3<Float>,
        up: SIMD3<Float>
    ) {
        guard scene.screenFrameEntities.count == 4 else { return }
        let width = Float(settings.screenSize.width)
        let height = Float(settings.screenSize.height)
        let frameOffset = CinemaImmersivePlacementPolicy.frameThickness / 2
        let front = center + forward * 0.03
        scene.screenFrameEntities[0].position = front + up * (height / 2 + frameOffset)
        scene.screenFrameEntities[1].position = front - up * (height / 2 + frameOffset)
        scene.screenFrameEntities[2].position = front - right * (width / 2 + frameOffset)
        scene.screenFrameEntities[3].position = front + right * (width / 2 + frameOffset)
    }

    private func positionSeatsAndAisleLights() {
        let rowSpacing: Float = 1.0
        let seatSpacing: Float = 0.86
        let startZ = Float(settings.seatOffset.z) + 1.0
        let centerX = Float(settings.seatOffset.x)
        var index = 0
        for row in 0..<CinemaImmersivePlacementPolicy.seatingRows {
            for column in 0..<CinemaImmersivePlacementPolicy.seatsPerRow {
                guard index < scene.seatEntities.count else { return }
                let seat = scene.seatEntities[index]
                let x = centerX + (Float(column) - Float(CinemaImmersivePlacementPolicy.seatsPerRow - 1) / 2) * seatSpacing
                let y = -0.78 + Float(settings.seatOffset.y) + Float(row) * 0.08
                let z = startZ + Float(row) * rowSpacing
                seat.position = SIMD3<Float>(x, y, z)
                index += 1
            }
        }

        for (index, light) in scene.aisleLightEntities.enumerated() {
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let step = Float(index / 2)
            light.position = SIMD3<Float>(
                centerX + side * 3.7,
                CinemaImmersivePlacementPolicy.floorYOffset + Float(settings.seatOffset.y) + 0.025,
                Float(settings.seatOffset.z) - 3.4 + step * 0.72
            )
        }
    }

    private func normalizeOrFallback(_ value: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(value)
        guard lengthSquared > .leastNonzeroMagnitude else { return fallback }
        return value / sqrt(lengthSquared)
    }

    private func vector3(_ column: SIMD4<Float>) -> SIMD3<Float> {
        SIMD3<Float>(column.x, column.y, column.z)
    }

    private func updateScreenMaterialIfNeeded() {
        let sourceID = currentMaterialSourceID()
        guard sourceID != scene.lastMaterialSourceID else { return }
        scene.screenEntity?.model?.materials = [makeScreenMaterial()]
        scene.lastMaterialSourceID = sourceID
    }
}
#endif
