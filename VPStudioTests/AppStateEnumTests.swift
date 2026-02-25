import Testing
@testable import VPStudio

// MARK: - SidebarTab extended coverage (icons by name, count)
// The basic icon/id/rawValue tests are in ModelTests.swift SidebarTabTests.

@Suite("SidebarTab - Icon Values")
struct SidebarTabIconValueTests {

    @Test func allCasesCountIsSix() {
        #expect(SidebarTab.allCases.count == 6)
    }

    @Test func discoverIconIsSafari() {
        #expect(SidebarTab.discover.icon == "safari")
    }

    @Test func searchIconIsSparkle() {
        #expect(SidebarTab.search.icon == "sparkle.magnifyingglass")
    }

    @Test func libraryIconIsBooksVertical() {
        #expect(SidebarTab.library.icon == "books.vertical")
    }

    @Test func environmentsIconIsMountain() {
        #expect(SidebarTab.environments.icon == "mountain.2")
    }

    @Test func downloadsIconIsArrowDownCircle() {
        #expect(SidebarTab.downloads.icon == "arrow.down.circle")
    }

    @Test func settingsIconIsGearshape() {
        #expect(SidebarTab.settings.icon == "gearshape")
    }
}

// MARK: - EnvironmentType extended coverage (specific string values)
// The basic icon/description/uniqueness tests are in ModelTests.swift EnvironmentTypeTests.

@Suite("EnvironmentType - Specific Values")
struct EnvironmentTypeSpecificValueTests {

    @Test func allCasesCountIsTwo() {
        #expect(EnvironmentType.allCases.count == 2)
    }

    @Test func hdriSkyboxIconIsPano() {
        #expect(EnvironmentType.hdriSkybox.icon == "pano")
    }

    @Test func customEnvironmentIconIsCubeTransparent() {
        #expect(EnvironmentType.customEnvironment.icon == "cube.transparent")
    }

    @Test func hdriSkyboxImmersiveSpaceIdIsHdriSkybox() {
        #expect(EnvironmentType.hdriSkybox.immersiveSpaceId == "hdriSkybox")
    }

    @Test func customEnvironmentImmersiveSpaceIdIsCustomEnvironment() {
        #expect(EnvironmentType.customEnvironment.immersiveSpaceId == "customEnvironment")
    }

    @Test func hdriSkyboxDescriptionContainsHdri() {
        #expect(EnvironmentType.hdriSkybox.description.contains("HDRI"))
    }

    @Test func customEnvironmentDescriptionContains3D() {
        #expect(EnvironmentType.customEnvironment.description.contains("3D"))
    }
}

// MARK: - ImmersiveDismissReason

@Suite("ImmersiveDismissReason")
struct ImmersiveDismissReasonTests {

    @Test func equatableSameCases() {
        #expect(ImmersiveDismissReason.userInitiated == .userInitiated)
        #expect(ImmersiveDismissReason.switchingEnvironment == .switchingEnvironment)
        #expect(ImmersiveDismissReason.suspension == .suspension)
        #expect(ImmersiveDismissReason.memoryPressure == .memoryPressure)
        #expect(ImmersiveDismissReason.playerClosed == .playerClosed)
    }

    @Test func equatableDifferentCases() {
        #expect(ImmersiveDismissReason.userInitiated != .suspension)
        #expect(ImmersiveDismissReason.memoryPressure != .playerClosed)
        #expect(ImmersiveDismissReason.switchingEnvironment != .userInitiated)
    }
}
