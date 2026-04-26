import Foundation
import Testing
@testable import VPStudio

@Suite("Environment Loader Task Lifecycle")
struct EnvironmentLoaderTaskLifecycleTests {
    @Test
    func environmentsTabViewCoalescesNotificationDrivenLoadsAndCancelsOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/ContentView.swift")
        #expect(source.contains("@State private var environmentLoadTask: Task<Void, Never>?"))
        #expect(source.contains(".task { await coalescedLoadEnvironments() }"))
        #expect(source.contains(".onReceive(NotificationCenter.default.publisher(for: .environmentsDidChange))"))
        #expect(source.contains("environmentLoadTask?.cancel()"))
        #expect(source.contains("environmentLoadTask = Task { await loadEnvironments() }"))
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("environmentLoadTask = nil"))
    }

    @Test
    func environmentPickerSheetCoalescesNotificationDrivenLoadsAndCancelsOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Discover/EnvironmentPreviewRow.swift")
        #expect(source.contains("@State private var environmentLoadTask: Task<Void, Never>?"))
        #expect(source.contains(".task { await coalescedLoadEnvironments() }"))
        #expect(source.contains(".onReceive(NotificationCenter.default.publisher(for: .environmentsDidChange))"))
        #expect(source.contains("environmentLoadTask?.cancel()"))
        #expect(source.contains("environmentLoadTask = Task { await loadEnvironments() }"))
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("environmentLoadTask = nil"))
    }

    @Test
    func environmentSettingsViewCoalescesNotificationDrivenLoadsAndCancelsOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/EnvironmentSettingsView.swift")
        #expect(source.contains("@State private var assetLoadTask: Task<Void, Never>?"))
        #expect(source.contains("await coalescedLoadAssets()"))
        #expect(source.contains(".onReceive(NotificationCenter.default.publisher(for: .environmentsDidChange))"))
        #expect(source.contains("assetLoadTask?.cancel()"))
        #expect(source.contains("assetLoadTask = Task { await loadAssets() }"))
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("assetLoadTask = nil"))
    }

    @Test
    func builtInCinemaEnvironmentIsVisibleInSharedPickerEvenWithoutImportedAssets() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Discover/EnvironmentPreviewRow.swift")

        #expect(source.contains("var onSelectCinema: (() -> Void)? = nil"))
        #expect(source.contains("CinemaEnvironmentPreviewCard("))
        #expect(source.contains("Text(\"Cinema Environment\")"))
        #expect(source.contains("Text(\"No imported environments\")"))
        #expect(source.contains("Text(\"No Environments\")") == false)
    }

    @Test
    func playerEnvironmentPickerPassesCinemaOpenAction() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        #expect(source.contains("onSelectCinema: {"))
        #expect(source.contains("openCinemaEnvironmentAfterMenuDismissal()"))
    }

    @Test
    func mainEnvironmentSurfacesExposeBuiltInCinemaEnvironment() throws {
        let contentSource = try contents(of: "VPStudio/Views/Windows/ContentView.swift")
        let settingsSource = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/EnvironmentSettingsView.swift")

        #expect(contentSource.contains("CinemaEnvironmentPreviewCard("))
        #expect(contentSource.contains("selectCinemaEnvironment()"))
        #expect(contentSource.contains("openImmersiveSpace(id: EnvironmentType.cinemaEnvironment.immersiveSpaceId)"))
        #expect(settingsSource.contains("builtInCinemaRow"))
        #expect(settingsSource.contains("Text(\"Cinema Environment\")"))
        #expect(settingsSource.contains("Text(\"Built-In\")"))
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
