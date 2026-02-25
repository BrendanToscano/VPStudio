import Foundation
import Testing
@testable import VPStudio

@Suite("Player Settings Diagnostics Toggle")
struct PlayerSettingsDiagnosticsToggleTests {
    @Test
    func playerSettingsExposesRuntimeDiagnosticsToggle() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/PlayerSettingsView.swift")

        #expect(source.contains("Enable Runtime Diagnostics"))
        #expect(source.contains("SettingsKeys.runtimeDiagnosticsEnabled"))
        #expect(source.contains("saveRuntimeDiagnosticsEnabled(newValue)"))
        #expect(source.contains("appState.runtimeDiagnosticsEnabled = value"))
    }

    @Test
    func settingsKeysExposeRuntimeDiagnosticsFlag() {
        #expect(SettingsKeys.runtimeDiagnosticsEnabled == "runtime_diagnostics_enabled")
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
