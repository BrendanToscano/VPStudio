import Foundation
import Testing
@testable import VPStudio

@Suite("Settings Debounced Task Lifecycle")
struct SettingsDebouncedTaskLifecycleTests {
    @Test
    func aiSettingsCancelsDebouncedSaveTasksOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/AISettingsView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("anthropicSaveTask?.cancel()"))
        #expect(source.contains("openAISaveTask?.cancel()"))
        #expect(source.contains("feedbackReloadTask?.cancel()"))
    }

    @Test
    func aiSettingsCoalescesTasteProfileReloadNotifications() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/AISettingsView.swift")
        #expect(source.contains("@State private var feedbackReloadTask: Task<Void, Never>?"))
        #expect(source.contains(".onReceive(NotificationCenter.default.publisher(for: .tasteProfileDidChange))"))
        #expect(source.contains("feedbackReloadTask?.cancel()"))
        #expect(source.contains("feedbackReloadTask = Task { await loadFeedbackState() }"))
    }

    @Test
    func traktSettingsCancelsDebouncedSaveTasksOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/TraktSettingsView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("clientIdSaveTask?.cancel()"))
        #expect(source.contains("clientSecretSaveTask?.cancel()"))
    }

    @Test
    func simklSettingsCancelsDebouncedSaveTaskOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/SimklSettingsView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("simklClientIdSaveTask?.cancel()"))
    }

    @Test
    func subtitleSettingsCancelsDebouncedSaveTaskOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/SubtitleSettingsView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("openSubsSaveTask?.cancel()"))
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
