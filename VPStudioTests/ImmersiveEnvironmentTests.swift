import Foundation
import Testing
@testable import VPStudio

// MARK: - EnvironmentType Enum Tests (HDRI Overhaul)

@Suite("EnvironmentType — HDRI Skybox Overhaul")
struct HDRIEnvironmentTypeTests {

    // MARK: - Case Count & CaseIterable

    @Test func allCasesContainsTwoEnvironments() {
        #expect(EnvironmentType.allCases.count == 2)
    }

    @Test func allCasesContainsExpectedTypes() {
        let allRawValues = EnvironmentType.allCases.map(\.rawValue)
        #expect(allRawValues.contains("HDRI Skybox"))
        #expect(allRawValues.contains("Custom Environment"))
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

    @Test func initFromInvalidRawValueReturnsNil() {
        #expect(EnvironmentType(rawValue: "Nonexistent") == nil)
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
