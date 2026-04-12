import Foundation
import Testing
@testable import VPStudio

@Suite("Settings Debounced Task Lifecycle")
struct SettingsDebouncedTaskLifecycleTests {
    @Test
    func aiSettingsCancelsDebouncedSaveTasksOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/AISettingsView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("flushPendingCloudKeySaves()"))
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
        #expect(source.contains("flushPendingClientCredentialSaves()"))
        #expect(source.contains("clientIdSaveTask?.cancel()"))
        #expect(source.contains("clientSecretSaveTask?.cancel()"))
    }

    @Test
    func traktSettingsSurfacesPersistenceErrors() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/TraktSettingsView.swift")
        #expect(source.contains("persistBool"))
        #expect(source.contains("persistString"))
        #expect(source.contains("errorMessage = error.localizedDescription"))
    }

    @Test
    func simklSettingsExposeReadOnlyCleanupSurface() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/SimklSettingsView.swift")
        #expect(source.contains("Cleanup Only in This Build"))
        #expect(source.contains("read-only"))
        #expect(source.contains("Saved Authorization"))
        #expect(source.contains("Disconnect"))
        #expect(source.contains("isShowingDisconnectConfirmation"))
        #expect(source.contains(".alert(\"Disconnect Simkl?\", isPresented: $isShowingDisconnectConfirmation)"))
    }

    @Test
    func simklSettingsNoLongerOfferInteractiveAuthorizationFlow() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/SimklSettingsView.swift")
        #expect(source.contains("authorizationState") == false)
        #expect(source.contains("openAuthorizationPage") == false)
        #expect(source.contains("completeAuthorization") == false)
        #expect(source.contains("simklClientIdSaveTask") == false)
        #expect(source.contains("simklClientSecretSaveTask") == false)
    }

    @Test
    func subtitleSettingsFlushesOpenSubtitlesKeyOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/SubtitleSettingsView.swift")
        #expect(source.contains(".onDisappear { flushOpenSubtitlesKey() }"))
        #expect(source.contains("openSubsSaveTask?.cancel()"))
        #expect(source.contains("private func flushOpenSubtitlesKey()"))
        #expect(source.contains("persistStringSetting(key: SettingsKeys.openSubtitlesApiKey, value: openSubsApiKey)"))
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
