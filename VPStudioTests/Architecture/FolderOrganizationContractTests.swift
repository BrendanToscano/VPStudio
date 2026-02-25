import Foundation
import Testing
@testable import VPStudio

@Suite("Folder Organization Contract")
struct FolderOrganizationContractTests {
    @Test
    func playerServiceStructureUsesDomainSubfolders() {
        assertExists("VPStudio/Services/Player/Engines/PlayerEngine.swift")
        assertExists("VPStudio/Services/Player/Engines/AVPlayerEngine.swift")
        assertExists("VPStudio/Services/Player/Engines/KSPlayerEngine.swift")
        assertExists("VPStudio/Services/Player/Policies/PlayerSessionRouting.swift")
        assertExists("VPStudio/Services/Player/Policies/ExternalPlayerRouting.swift")
        assertExists("VPStudio/Services/Player/Immersive/APMPInjector.swift")
        assertExists("VPStudio/Services/Player/State/VPPlayerEngine.swift")

        assertMissing("VPStudio/Services/Player/PlayerEngine.swift")
        assertMissing("VPStudio/Services/Player/AVPlayerEngine.swift")
        assertMissing("VPStudio/Services/Player/KSPlayerEngine.swift")
    }

    @Test
    func viewModelsAreGroupedByFeatureDomain() {
        assertExists("VPStudio/ViewModels/Detail/DetailViewModel.swift")
        assertExists("VPStudio/ViewModels/Detail/DetailFeatureState.swift")
        assertExists("VPStudio/ViewModels/Discover/DiscoverViewModel.swift")
        assertExists("VPStudio/ViewModels/Search/SearchViewModel.swift")
        assertExists("VPStudio/ViewModels/Downloads/DownloadsViewModel.swift")

        assertMissing("VPStudio/ViewModels/DetailViewModel.swift")
        assertMissing("VPStudio/ViewModels/DiscoverViewModel.swift")
        assertMissing("VPStudio/ViewModels/SearchViewModel.swift")
    }

    @Test
    func settingsViewsAreSplitByRole() {
        assertExists("VPStudio/Views/Windows/Settings/Root/SettingsRootView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Onboarding/SetupWizardView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Core/SettingsInputValidation.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/DebridSettingsView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/IndexerSettingsView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/MetadataSettingsView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/PlayerSettingsView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/SubtitleSettingsView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/EnvironmentSettingsView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/AISettingsView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/TraktSettingsView.swift")
        assertExists("VPStudio/Views/Windows/Settings/Destinations/SimklSettingsView.swift")

        assertMissing("VPStudio/Views/Windows/Settings/SettingsRootView.swift")
        assertMissing("VPStudio/Views/Windows/Settings/SettingsView.swift")
        assertMissing("VPStudio/Views/Windows/Settings/SetupWizardView.swift")
        assertMissing("VPStudio/Views/Windows/Settings/Destinations/SettingsView.swift")
    }

    @Test
    func testSuiteUsesDomainSubfolders() {
        assertExists("VPStudioTests/Player/PlayerEngineTests.swift")
        assertExists("VPStudioTests/Settings/SettingsStatusFormatterTests.swift")
        assertExists("VPStudioTests/ViewModels/DetailViewModelStateMachineTests.swift")
        assertExists("VPStudioTests/Architecture/SchemaPruningTests.swift")

        assertMissing("VPStudioTests/PlayerEngineTests.swift")
        assertMissing("VPStudioTests/SettingsStatusFormatterTests.swift")
    }

    private func assertExists(_ relativePath: String) {
        let absolutePath = repoRootURL().appendingPathComponent(relativePath).path
        #expect(FileManager.default.fileExists(atPath: absolutePath), "\(relativePath) should exist")
    }

    private func assertMissing(_ relativePath: String) {
        let absolutePath = repoRootURL().appendingPathComponent(relativePath).path
        #expect(FileManager.default.fileExists(atPath: absolutePath) == false, "\(relativePath) should not exist")
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
