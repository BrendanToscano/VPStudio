import Foundation
import Testing
@testable import VPStudio

@Suite("Settings Destructive Confirmation")
struct SettingsDestructiveConfirmationTests {
    @Test
    func debridSettingsConfirmBeforeDeletingService() throws {
        let source = try normalizedContents(of: "VPStudio/Views/Windows/Settings/Destinations/DebridSettingsView.swift")
        #expect(source.contains(".confirmationDialog("))
        #expect(source.contains("DeleteDebridService?"))
        #expect(source.contains("Button(\"Delete\",role:.destructive)"))
        #expect(source.contains("awaitdelete(config)"))
        #expect(source.contains("ThisremovestheproviderandstoredAPIkey."))
    }

    @Test
    func debridSettingsExcludeEasyNewsFromSharedStreamingAddFlow() throws {
        let source = try normalizedContents(of: "VPStudio/Views/Windows/Settings/Destinations/DebridSettingsView.swift")
        #expect(source.contains("sharedStreamingServiceTypes"))
        #expect(source.contains("type!=.easyNews"))
        #expect(source.contains("UnsupportedinSharedStreaming"))
    }

    @Test
    func indexerSettingsConfirmBeforeDeletingIndexer() throws {
        let source = try normalizedContents(of: "VPStudio/Views/Windows/Settings/Destinations/IndexerSettingsView.swift")
        #expect(source.contains(".confirmationDialog("))
        #expect(source.contains("DeleteIndexer"))
        #expect(source.contains("Button(\"Delete\",role:.destructive)"))
        #expect(source.contains("awaitdelete(configID:deletion.id)"))
    }

    @Test
    func environmentSettingsConfirmBeforeDeletingImportedAsset() throws {
        let source = try normalizedContents(of: "VPStudio/Views/Windows/Settings/Destinations/EnvironmentSettingsView.swift")
        #expect(source.contains(".confirmationDialog("))
        #expect(source.contains("DeleteImportedEnvironment"))
        #expect(source.contains("Button(\"Delete\",role:.destructive)"))
        #expect(source.contains("removestheimportedenvironmentfromdisk"))
    }

    @Test
    func aiSettingsConfirmBeforeResettingUsageStatistics() throws {
        let source = try normalizedContents(of: "VPStudio/Views/Windows/Settings/Destinations/AISettingsView.swift")
        #expect(source.contains(".confirmationDialog("))
        #expect(source.contains("ResetAIUsageStatistics"))
        #expect(source.contains("Button(\"ResetStatistics\",role:.destructive)"))
        #expect(source.contains("costhistoryforallAIproviders"))
    }

    private func contents(of relativePath: String) throws -> String {
        let absolutePath = repoRootURL().appendingPathComponent(relativePath).path
        return try String(contentsOfFile: absolutePath, encoding: .utf8)
    }

    private func normalizedContents(of relativePath: String) throws -> String {
        let source = try contents(of: relativePath)
        return source.components(separatedBy: .whitespacesAndNewlines).joined()
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
