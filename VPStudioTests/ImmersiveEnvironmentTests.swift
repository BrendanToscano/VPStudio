import Foundation
import Testing
@testable import VPStudio

// MARK: - EnvironmentType Enum Tests (HDRI Overhaul)

@Suite("EnvironmentType — HDRI Skybox Overhaul")
struct HDRIEnvironmentTypeTests {

    // MARK: - Case Count & CaseIterable

    @Test func allCasesContainsThreeEnvironments() {
        #expect(EnvironmentType.allCases.count == 3)
    }

    @Test func allCasesContainsExpectedTypes() {
        let allRawValues = EnvironmentType.allCases.map(\.rawValue)
        #expect(allRawValues.contains("HDRI Skybox"))
        #expect(allRawValues.contains("Custom Environment"))
        #expect(allRawValues.contains("Cinema Environment"))
    }

    @Test func removedTypesNoLongerExist() {
        #expect(EnvironmentType(rawValue: "The Void") == nil)
        #expect(EnvironmentType(rawValue: "The Theater") == nil)
        #expect(EnvironmentType(rawValue: "Mountain Lodge") == nil)
        #expect(EnvironmentType(rawValue: "Rooftop") == nil)
        #expect(EnvironmentType(rawValue: "Deep Space") == nil)
        #expect(EnvironmentType(rawValue: "Underwater Abyss") == nil)
        #expect(EnvironmentType(rawValue: "Noir Alley") == nil)
        #expect(EnvironmentType(rawValue: "Zen Garden") == nil)
        #expect(EnvironmentType(rawValue: "Art Deco Lounge") == nil)
    }

    // MARK: - Raw Values

    @Test func hdriSkyboxRawValue() {
        #expect(EnvironmentType.hdriSkybox.rawValue == "HDRI Skybox")
    }

    @Test func customEnvironmentRawValue() {
        #expect(EnvironmentType.customEnvironment.rawValue == "Custom Environment")
    }

    @Test func cinemaEnvironmentRawValue() {
        #expect(EnvironmentType.cinemaEnvironment.rawValue == "Cinema Environment")
    }

    // MARK: - Identifiable

    @Test func allCasesHaveUniqueIDs() {
        let ids = EnvironmentType.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func idMatchesRawValue() {
        for env in EnvironmentType.allCases {
            #expect(env.id == env.rawValue)
        }
    }

    // MARK: - Icon

    @Test func hdriSkyboxIcon() {
        #expect(EnvironmentType.hdriSkybox.icon == "pano")
    }

    @Test func customEnvironmentIcon() {
        #expect(EnvironmentType.customEnvironment.icon == "cube.transparent")
    }

    @Test func cinemaEnvironmentIcon() {
        #expect(EnvironmentType.cinemaEnvironment.icon == "theatermasks")
    }

    @Test func allCasesHaveNonEmptyIcons() {
        for env in EnvironmentType.allCases {
            #expect(!env.icon.isEmpty)
        }
    }

    @Test func allCasesHaveUniqueIcons() {
        let icons = EnvironmentType.allCases.map(\.icon)
        #expect(Set(icons).count == icons.count)
    }

    // MARK: - Immersive Space ID

    @Test func hdriSkyboxImmersiveSpaceId() {
        #expect(EnvironmentType.hdriSkybox.immersiveSpaceId == "hdriSkybox")
    }

    @Test func customEnvironmentImmersiveSpaceId() {
        #expect(EnvironmentType.customEnvironment.immersiveSpaceId == "customEnvironment")
    }

    @Test func cinemaEnvironmentImmersiveSpaceId() {
        #expect(EnvironmentType.cinemaEnvironment.immersiveSpaceId == "cinemaEnvironment")
    }

    @Test func allCasesHaveUniqueImmersiveSpaceIds() {
        let ids = EnvironmentType.allCases.map(\.immersiveSpaceId)
        #expect(Set(ids).count == ids.count)
    }

    @Test func immersiveSpaceIdDoesNotContainSpaces() {
        for env in EnvironmentType.allCases {
            #expect(!env.immersiveSpaceId.contains(" "))
        }
    }

    @Test func immersiveSpaceIdIsLowerCamelCase() {
        for env in EnvironmentType.allCases {
            let id = env.immersiveSpaceId
            #expect(id.first?.isLowercase == true)
            #expect(id.allSatisfy { $0.isLetter || $0.isNumber })
        }
    }

    // MARK: - Description

    @Test func hdriSkyboxDescription() {
        #expect(EnvironmentType.hdriSkybox.description == "360-degree HDRI panoramic skybox")
    }

    @Test func customEnvironmentDescription() {
        #expect(EnvironmentType.customEnvironment.description == "User-imported 3D environment model")
    }

    @Test func cinemaEnvironmentDescription() {
        #expect(EnvironmentType.cinemaEnvironment.description == "Configurable cinema screen with persistent seating and lighting controls")
    }

    @Test func allCasesHaveNonEmptyDescriptions() {
        for env in EnvironmentType.allCases {
            #expect(!env.description.isEmpty)
        }
    }

    @Test func descriptionDoesNotEndWithPeriod() {
        for env in EnvironmentType.allCases {
            #expect(!env.description.hasSuffix("."))
        }
    }

    // MARK: - Init from raw value

    @Test func initFromRawValueHdriSkybox() {
        #expect(EnvironmentType(rawValue: "HDRI Skybox") == .hdriSkybox)
    }

    @Test func initFromRawValueCustomEnvironment() {
        #expect(EnvironmentType(rawValue: "Custom Environment") == .customEnvironment)
    }

    @Test func initFromRawValueCinemaEnvironment() {
        #expect(EnvironmentType(rawValue: "Cinema Environment") == .cinemaEnvironment)
    }

    @Test func initFromInvalidRawValueReturnsNil() {
        #expect(EnvironmentType(rawValue: "Nonexistent") == nil)
    }

    @Test func playerEnvironmentPillExposesBuiltInCinemaEnvironment() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        #expect(source.contains("openCinemaEnvironmentAfterMenuDismissal()"))
        #expect(source.contains("Label(\"Cinema Environment\", systemImage: \"theatermasks\")"))
        #expect(source.contains("Label(\"Cinema Settings\", systemImage: \"slider.horizontal.3\")"))
        #expect(source.contains("ForEach(environmentAssets, id: \\.id)"))
        #expect(source.contains("Label(\"Browse Environments\", systemImage: \"mountain.2\")"))
    }

    @Test func playerCinemaEnvironmentRequiresPlayableAVPlayer() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        #expect(source.contains("guard PlayerCinemaEnvironmentPolicy.canOpen(activeEngine: activeEngine, hasAVPlayer: avPlayer != nil),"))
        #expect(source.contains("playbackMessage = PlayerCinemaEnvironmentPolicy.unavailableMessage"))
        #expect(source.contains("openImmersiveSpace(id: EnvironmentType.cinemaEnvironment.immersiveSpaceId)"))
    }

    @Test func playerCinemaEnvironmentRefreshesAppStatePlayerBridgeBeforeOpening() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        #expect(source.contains("appState.activeAVPlayer = player"))
        #expect(source.range(of: "appState.activeAVPlayer = player")!.lowerBound < source.range(of: "openImmersiveSpace(id: EnvironmentType.cinemaEnvironment.immersiveSpaceId)")!.lowerBound)
    }

    @Test func playerCinemaEnvironmentSyncsDetectedAspectRatioIntoCinemaSettings() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        #expect(source.contains("@Environment(CinemaSettings.self) private var cinemaSettings"))
        #expect(source.contains("syncCinemaAspectRatio(newRatio)"))
        #expect(source.contains("cinemaSettings.videoAspectRatio = Double(ratio)"))
    }

    @Test func playerEnvironmentMenuDefersImmersiveActionsUntilMenuDismissal() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        #expect(source.contains("openCinemaEnvironmentAfterMenuDismissal()"))
        #expect(source.contains("openEnvironmentAfterMenuDismissal(_ asset: EnvironmentAsset)"))
        #expect(source.contains("showEnvironmentPickerAfterMenuDismissal()"))
        #expect(source.contains("dismissEnvironmentAfterMenuDismissal()"))
        #expect(source.contains("try? await Task.sleep(for: PlayerCinemaEnvironmentPolicy.menuDismissalDelay)"))
    }

    @Test func playerReusableEnvironmentMenusAlwaysExposeBuiltInCinemaEnvironment() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerEnvironmentMenu.swift")

        #expect(source.contains("let onSelectCinema: () -> Void"))
        #expect(source.contains("onSelectCinema()"))
        #expect(source.contains("Label(\"Cinema Environment\", systemImage: \"theatermasks\")"))
        #expect(source.contains("Label(\"Cinema Environment\", systemImage: \"checkmark\")"))
        #expect(source.contains("if !assets.isEmpty || appState.isImmersiveSpaceOpen") == false)
    }

    @Test func playerCinemaAvailabilityPolicyDrivesMenuDisabledStateAndOpenGuard() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        let policyCall = "PlayerCinemaEnvironmentPolicy.canOpen(\n                            activeEngine: activeEngine,\n                            hasAVPlayer: avPlayer != nil\n                        )"
        #expect(source.contains(policyCall))
        #expect(source.contains("guard PlayerCinemaEnvironmentPolicy.canOpen(activeEngine: activeEngine, hasAVPlayer: avPlayer != nil),"))
    }

    @Test func cinemaImmersiveSpaceIsRegisteredWithSettingsEnvironment() throws {
        let source = try contents(of: "VPStudio/App/VPStudioApp.swift")

        #expect(source.contains("@State private var cinemaSettings = CinemaSettings()"))
        #expect(source.contains("ImmersiveSpace(id: \"cinemaEnvironment\")"))
        #expect(source.contains("CinemaImmersiveContent(settings: cinemaSettings)"))
        #expect(source.contains(".environment(cinemaSettings)"))
    }

    @Test func cinemaImmersiveContentReportsLifecycleToAppState() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/Cinema/CinemaImmersiveContent.swift")

        #expect(source.contains("VideoMaterial(avPlayer: player)"))
        #expect(source.contains("appState.immersiveSpaceDidAppear(.cinemaEnvironment)"))
        #expect(source.contains("appState.immersiveSpaceDidDisappear()"))
        #expect(source.contains(".preferredSurroundingsEffect("))
    }

    @Test func cinemaImmersiveContentDoesNotOpenAsAHeadUnanchoredVoid() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/Cinema/CinemaImmersiveContent.swift")

        #expect(source.contains("@State private var headTracker = HeadTracker()"))
        #expect(source.contains("headTracker.start()"))
        #expect(source.contains("CinemaImmersivePlacementPolicy.screenPosition("))
        #expect(source.contains("screen.look(at: placement.lookAt, from: placement.position, relativeTo: nil, forward: .positiveZ)"))
        #expect(source.contains("MeshResource.generatePlane(\n                width: planeWidth,\n                height: planeHeight"))
        #expect(source.contains("AnchorEntity(world: matrix_identity_float4x4)"))
    }

    @Test func cinemaImmersiveContentBuildsVisibleTheaterShellForFullImmersion() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/Cinema/CinemaImmersiveContent.swift")

        #expect(source.contains("cinemaBackdrop"))
        #expect(source.contains("cinemaFloor"))
        #expect(source.contains("cinemaRearWall"))
        #expect(source.contains("cinemaLeftWall"))
        #expect(source.contains("cinemaRightWall"))
        #expect(source.contains("cinemaCeiling"))
        #expect(source.contains("cinemaSeat_"))
        #expect(source.contains("cinemaAisleLight_"))
        #expect(source.contains("cinemaScreenFrameTop"))
        #expect(source.contains("cinemaScreenBackplate"))
        #expect(source.contains("CinemaImmersivePlacementPolicy.shouldShowBackdrop("))
        #expect(source.contains("return CinemaImmersionStyle(rawValue: immersionStyleRaw) != nil"))
        #expect(source.contains("EnvironmentLightingConfigurationComponent("))
        #expect(source.contains("let isMixed = settings.immersionStyleRaw == CinemaImmersionStyle.mixed.rawValue") == false)
    }

    @Test func cinemaImmersiveContentUsesVisiblePlaceholderUntilVideoMaterialArrives() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/Cinema/CinemaImmersiveContent.swift")

        #expect(source.contains("return ObjectIdentifier(scene)"))
        #expect(source.contains("UIColor(red: 0.78, green: 0.80, blue: 0.86, alpha: 1.0)"))
        #expect(!source.contains("material.color = .init(tint: .black)"))
        #expect(source.contains("updateScreenMaterialIfNeeded()"))
    }

    @Test func cinemaImmersiveContentKeepsVisibleFrameAlignedWithTiltedScreen() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/Cinema/CinemaImmersiveContent.swift")
        let body = try section(
            from: "private func updateScreenTransform() {",
            to: "private func updateSphere() {",
            in: source
        )
        guard let tiltRange = body.range(of: "if settings.screenTilt != 0"),
              let frameRange = body.range(of: "for frameEntity in scene.screenFrameEntities") else {
            Issue.record("Expected tilted screen and frame alignment logic")
            return
        }

        #expect(tiltRange.lowerBound < frameRange.lowerBound)
        #expect(body.contains("scene.screenBackplateEntity?.orientation = screen.orientation"))
        #expect(body.contains("frameEntity.orientation = screen.orientation"))
    }

    @Test func cinemaImmersiveContentRecoversWhenPlayerArrivesAfterSpaceCreation() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/Cinema/CinemaImmersiveContent.swift")

        #expect(source.contains("scene.lastMaterialSourceID = currentMaterialSourceID()"))
        #expect(source.contains("updateScreenMaterialIfNeeded()"))
        #expect(source.contains("scene.screenEntity?.model?.materials = [makeScreenMaterial()]"))
        #expect(source.contains("cinemaScreenPlaceholder") == false)
    }

    @Test func cinemaImmersiveContentSupportsRendererBridgeLikeOtherImmersiveEnvironments() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/Cinema/CinemaImmersiveContent.swift")

        #expect(source.contains("if let renderer = appState.activeVideoRenderer"))
        #expect(source.contains("return ObjectIdentifier(renderer)"))
        #expect(source.contains("VideoMaterial(videoRenderer: renderer)"))
        #expect(source.range(of: "activeVideoRenderer")!.lowerBound < source.range(of: "activeAVPlayer")!.lowerBound)
    }

    private func contents(of relativePath: String) throws -> String {
        let absolutePath = repoRootURL().appendingPathComponent(relativePath).path
        return try String(contentsOfFile: absolutePath, encoding: .utf8)
    }

    private func section(from startToken: String, to endToken: String, in source: String) throws -> String {
        guard let startRange = source.range(of: startToken),
              let endRange = source.range(of: endToken, range: startRange.upperBound..<source.endIndex) else {
            throw NSError(
                domain: "HDRIEnvironmentTypeTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing section from \(startToken) to \(endToken)"]
            )
        }
        return String(source[startRange.upperBound..<endRange.lowerBound])
    }

    private func repoRootURL() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return url
    }
}

// MARK: - CuratedEnvironmentProvider Tests

@Suite("CuratedEnvironmentProvider")
struct CuratedEnvironmentProviderTests {

    @Test func allCasesContainsThreeProviders() {
        #expect(CuratedEnvironmentProvider.allCases.count == 3)
    }

    @Test func polyHavenCaseExists() {
        #expect(CuratedEnvironmentProvider.polyHaven.rawValue == "polyHaven")
    }

    @Test func polyHavenDisplayName() {
        #expect(CuratedEnvironmentProvider.polyHaven.displayName == "Poly Haven")
    }

    @Test func officialDisplayName() {
        #expect(CuratedEnvironmentProvider.official.displayName == "Official")
    }

    @Test func githubDisplayName() {
        #expect(CuratedEnvironmentProvider.github.displayName == "GitHub")
    }

    @Test func allProvidersHaveNonEmptyDisplayNames() {
        for provider in CuratedEnvironmentProvider.allCases {
            #expect(!provider.displayName.isEmpty)
        }
    }

    @Test func allProvidersHaveUniqueRawValues() {
        let rawValues = CuratedEnvironmentProvider.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func providerIsCodable() throws {
        let encoded = try JSONEncoder().encode(CuratedEnvironmentProvider.polyHaven)
        let decoded = try JSONDecoder().decode(CuratedEnvironmentProvider.self, from: encoded)
        #expect(decoded == .polyHaven)
    }
}

// MARK: - EnvironmentAsset hdriYawOffset Tests

@Suite("EnvironmentAsset — hdriYawOffset")
struct EnvironmentAssetYawOffsetTests {

    @Test func hdriYawOffsetDefaultsToNil() {
        let asset = EnvironmentAsset(
            id: "test",
            name: "Test",
            sourceType: .imported,
            assetPath: "/tmp/test.hdr"
        )
        #expect(asset.hdriYawOffset == nil)
    }

    @Test func hdriYawOffsetRoundTripsWithValue() {
        let asset = EnvironmentAsset(
            id: "test",
            name: "Test",
            sourceType: .imported,
            assetPath: "/tmp/test.hdr",
            hdriYawOffset: 45.0
        )
        #expect(asset.hdriYawOffset == 45.0)
    }

    @Test func hdriYawOffsetCanBeNegative() {
        let asset = EnvironmentAsset(
            id: "test",
            name: "Test",
            sourceType: .imported,
            assetPath: "/tmp/test.hdr",
            hdriYawOffset: -90.0
        )
        #expect(asset.hdriYawOffset == -90.0)
    }

    @Test func hdriYawOffsetCanBeZero() {
        let asset = EnvironmentAsset(
            id: "test",
            name: "Test",
            sourceType: .imported,
            assetPath: "/tmp/test.hdr",
            hdriYawOffset: 0.0
        )
        #expect(asset.hdriYawOffset == 0.0)
    }

    @Test func hdriYawOffsetAffectsEquality() {
        let a = EnvironmentAsset(
            id: "test",
            name: "Test",
            sourceType: .imported,
            assetPath: "/tmp/test.hdr",
            hdriYawOffset: 45.0
        )
        let b = EnvironmentAsset(
            id: "test",
            name: "Test",
            sourceType: .imported,
            assetPath: "/tmp/test.hdr",
            hdriYawOffset: 90.0
        )
        // Different yaw offsets mean different assets
        #expect(a != b)
    }
}

// MARK: - CuratedEnvironmentPreset Tests

@Suite("CuratedEnvironmentPreset")
struct CuratedEnvironmentPresetTests {

    @Test func presetIsEquatable() {
        let a = CuratedEnvironmentPreset(
            id: "test",
            name: "Test",
            description: "Desc",
            provider: .polyHaven,
            downloadURL: URL(string: "https://example.com/test.hdr")!,
            sourceAttributionURL: "https://example.com",
            licenseName: "CC0"
        )
        let b = a
        #expect(a == b)
    }

    @Test func presetIdIsIdentifiable() {
        let preset = CuratedEnvironmentPreset(
            id: "unique-id",
            name: "Test",
            description: "Desc",
            provider: .polyHaven,
            downloadURL: URL(string: "https://example.com/test.hdr")!,
            sourceAttributionURL: "https://example.com",
            licenseName: "CC0"
        )
        #expect(preset.id == "unique-id")
    }

    @Test func defaultHdriYawOffsetDefaultsToNil() {
        let preset = CuratedEnvironmentPreset(
            id: "test",
            name: "Test",
            description: "Desc",
            provider: .polyHaven,
            downloadURL: URL(string: "https://example.com/test.hdr")!,
            sourceAttributionURL: "https://example.com",
            licenseName: "CC0"
        )
        #expect(preset.defaultHdriYawOffset == nil)
    }

    @Test func defaultHdriYawOffsetRoundTripsWithValue() {
        let preset = CuratedEnvironmentPreset(
            id: "test",
            name: "Test",
            description: "Desc",
            provider: .polyHaven,
            downloadURL: URL(string: "https://example.com/test.hdr")!,
            sourceAttributionURL: "https://example.com",
            licenseName: "CC0",
            defaultHdriYawOffset: 120.0
        )
        #expect(preset.defaultHdriYawOffset == 120.0)
    }

    @Test func onlinePresetsAllUsePolyHavenProvider() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            #expect(preset.provider == .polyHaven)
        }
    }

    @Test func onlinePresetsAllHaveHdrExtension() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            let ext = preset.downloadURL.pathExtension.lowercased()
            #expect(ext == "hdr" || ext == "exr", "Expected .hdr or .exr, got .\(ext) for \(preset.name)")
        }
    }

    @Test func onlinePresetsAllHaveCC0License() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            #expect(preset.licenseName.contains("CC0"))
        }
    }

    @Test func onlinePresetsHaveUniqueIDs() {
        let presets = EnvironmentCatalogManager.onlinePresets
        let ids = presets.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func onlinePresetsHaveValidDownloadURLs() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            #expect(preset.downloadURL.scheme == "https")
            #expect(preset.downloadURL.host?.contains("polyhaven") == true)
        }
    }

    @Test func onlinePresetsHaveNonEmptyDescriptions() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            #expect(!preset.description.isEmpty)
        }
    }

    @Test func onlinePresetsHaveSourceAttributionURLs() {
        let presets = EnvironmentCatalogManager.onlinePresets
        for preset in presets {
            #expect(!preset.sourceAttributionURL.isEmpty)
            #expect(URL(string: preset.sourceAttributionURL) != nil)
        }
    }
}
