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
