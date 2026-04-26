import Foundation
import Testing
@testable import VPStudio

@Suite("Settings Navigation Interaction Policy")
struct SettingsNavigationInteractionPolicyTests {
    @Test
    func persistedDestinationMatchesRawValue() {
        for destination in SettingsNavigationCatalog.orderedDestinations {
            let persisted = SettingsNavigationInteractionPolicy.persistedDestinationRawValue(for: destination)
            #expect(persisted == destination.rawValue)
        }
    }

    @Test
    func settingsRootUsesValueNavigationLinksForSingleClickActivation() throws {
        let source = try String(contentsOf: settingsRootURL(), encoding: .utf8)

        #expect(source.contains("NavigationLink(value: destination)"))
        #expect(source.contains(".navigationDestination(for: SettingsDestination.self)"))
        #expect(source.contains(".navigationDestination(item: $selectedDestination)") == false)
        #expect(source.contains("private func openDestination(") == false)
        #expect(source.contains("selectedDestination") == false)
    }

    private func settingsRootURL() -> URL {
        repoRootURL().appendingPathComponent("VPStudio/Views/Windows/Settings/Root/SettingsRootView.swift")
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
