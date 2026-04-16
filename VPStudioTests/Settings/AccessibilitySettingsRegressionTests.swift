import Foundation
import Testing
@testable import VPStudio

@Suite("Accessibility and Settings Regressions")
struct AccessibilitySettingsRegressionTests {
    @Test
    func discoverAndSearchSourceIncludeAccessibilityGuardrails() throws {
        let discoverSource = try contents(of: "VPStudio/Views/Windows/Discover/DiscoverView.swift")
        let searchSource = try contents(of: "VPStudio/Views/Windows/Search/SearchView.swift")
        let recentSearchesSource = try contents(of: "VPStudio/Views/Windows/Search/RecentSearchesSection.swift")
        let indexerSource = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/IndexerSettingsView.swift")

        #expect(discoverSource.contains("@Environment(\\.accessibilityVoiceOverEnabled)"))
        #expect(discoverSource.contains(".task(id: accessibilityVoiceOverEnabled)"))
        #expect(discoverSource.contains("guard !accessibilityVoiceOverEnabled else { return }"))
        #expect(searchSource.contains("accessibilityLabel: \"Open Filters\""))
        #expect(searchSource.contains(".accessibilityLabel(\"Clear search text\")"))
        #expect(searchSource.contains(".accessibilityLabel(\"Open more search filters\")"))
        #expect(searchSource.contains(".accessibilityLabel(viewModel.isLoadingAI ? \"Curating recommendations\" : \"Curate search results\")"))
        #expect(recentSearchesSource.contains(".accessibilityLabel(\"Clear recent searches\")"))
        #expect(recentSearchesSource.contains(".accessibilityLabel(\"Remove \\(term) from recent searches\")"))
        #expect(indexerSource.contains(".accessibilityLabel(\"\\(config.name) enabled\")"))
        #expect(indexerSource.contains(".accessibilityHint(\"Turns this indexer on or off.\")"))
    }

    @Test
    func launchAndSettingsSourcesIncludeMotionAndControlGuardrails() throws {
        let asyncStateSource = try contents(of: "VPStudio/Views/Components/AsyncStateViews.swift")
        let launchSource = try contents(of: "VPStudio/Views/Windows/LaunchScreen.swift")
        let subtitleSource = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/SubtitleSettingsView.swift")
        let settingsRootSource = try contents(of: "VPStudio/Views/Windows/Settings/Root/SettingsRootView.swift")
        let testModeSource = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/TestModeView.swift")
        let setupWizardSource = try contents(of: "VPStudio/Views/Windows/Settings/Onboarding/SetupWizardView.swift")

        #expect(asyncStateSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(launchSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(setupWizardSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(subtitleSource.contains(".accessibilityLabel(\"Preferred subtitle languages\")"))
        #expect(subtitleSource.contains(".accessibilityLabel(\"Subtitle font size\")"))
        #expect(settingsRootSource.contains(".accessibilityLabel(\"Menu background intensity\")"))
        #expect(testModeSource.contains(".accessibilityLabel(\"Playback position\")"))
        #expect(!testModeSource.contains("Button(action: {})"))
    }

    @Test
    func playerAndImmersiveSourcesHonorSystemAccessibilityPreferences() throws {
        let playerSource = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        let customEnvironmentSource = try contents(of: "VPStudio/Views/Immersive/CustomEnvironmentView.swift")
        let hdriSource = try contents(of: "VPStudio/Views/Immersive/HDRISkyboxEnvironment.swift")
        let immersiveControlsSource = try contents(of: "VPStudio/Views/Immersive/ImmersivePlayerControlsView.swift")

        #expect(playerSource.contains("import MediaAccessibility"))
        #expect(playerSource.contains("MACaptionAppearanceGetDisplayType(.user)"))
        #expect(playerSource.contains("MACaptionAppearanceCopySelectedLanguages(.user)"))
        #expect(playerSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(customEnvironmentSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(customEnvironmentSource.contains("subtitleFontSize"))
        #expect(hdriSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(hdriSource.contains("subtitleFontSize"))
        #expect(immersiveControlsSource.contains("@Environment(\\.accessibilityReduceMotion)"))
    }

    @Test
    func setupWizardSourceRequiresTMDBAndSurfacesSaveFailures() throws {
        let setupWizardSource = try contents(of: "VPStudio/Views/Windows/Settings/Onboarding/SetupWizardView.swift")

        #expect(setupWizardSource.contains("SetupWizardValidationPolicy.requiredTMDBMessage"))
        #expect(setupWizardSource.contains("guard stepAfterAdvance > stepBeforeAdvance else { break }"))
        #expect(setupWizardSource.contains("saveError = error.localizedDescription"))
    }

    @Test
    func detailAndSimklSourcesExposeAccessibilityAndDestructiveActionGuardrails() throws {
        let seriesDetailSource = try contents(of: "VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift")
        let torrentsSource = try contents(of: "VPStudio/Views/Windows/Detail/DetailTorrentsSection.swift")
        let simklSource = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/SimklSettingsView.swift")

        #expect(seriesDetailSource.contains(".accessibilityLabel(\"Share title\")"))
        #expect(seriesDetailSource.contains(".accessibilityLabel(viewModel.isInWatchlist ? \"Remove from Watchlist\" : \"Add to Watchlist\")"))
        #expect(seriesDetailSource.contains(".accessibilityLabel(\"Cast\")"))
        #expect(seriesDetailSource.contains(".accessibilityLabel(viewModel.currentFeedbackValue != nil ? \"Edit rating\" : \"Rate title\")"))
        #expect(seriesDetailSource.contains(".accessibilityLabel(\"Analyze with AI\")"))
        #expect(torrentsSource.contains(".accessibilityLabel(\"Play \\(torrent.title)\")"))
        #expect(torrentsSource.contains(".accessibilityLabel(\"Download \\(torrent.title)\")"))
        #expect(torrentsSource.contains(".accessibilityLabel(\"Retry download for \\(torrent.title)\")"))
        #expect(simklSource.contains("@State private var isShowingDisconnectConfirmation = false"))
        #expect(simklSource.contains(".alert(\"Disconnect Simkl?\", isPresented: $isShowingDisconnectConfirmation)"))
    }

    private func contents(of relativePath: String) throws -> String {
        let absolutePath = repoRootURL().appendingPathComponent(relativePath).path
        return try String(contentsOfFile: absolutePath, encoding: .utf8)
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
