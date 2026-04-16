import Foundation
import Testing
@testable import VPStudio

@Suite("Error Surface Contracts")
struct ErrorSurfaceContractTests {
    @Test
    func libraryViewSeparatesTypedActionErrorsFromStatusCopy() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Library/LibraryView.swift")

        #expect(source.contains("@State private var actionError: AppError?"))
        #expect(source.contains("LibraryFeedbackPresentationPolicy.message"))
        #expect(source.contains("AppErrorInlineView(error:"))
        #expect(source.contains("LibraryActionFailurePolicy.appError"))
        #expect(source.contains("statusMessage = error.localizedDescription") == false)
    }

    @Test
    func downloadsViewUsesTypedRootErrorSurfaces() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Downloads/DownloadsView.swift")

        #expect(source.contains("DownloadsErrorSurfacePolicy.presentationMode"))
        #expect(source.contains("vm.rootError"))
        #expect(source.contains("AppErrorInlineView(error:"))
        #expect(source.contains("Downloads unavailable"))
        #expect(source.contains("Text(error)") == false)
        #expect(source.contains("if let error = vm.errorMessage") == false)
    }

    @Test
    func downloadsViewModelStoresTypedRootError() throws {
        let source = try contents(of: "VPStudio/ViewModels/Downloads/DownloadsViewModel.swift")

        #expect(source.contains("var rootError: AppError?"))
        #expect(source.contains("rootError = AppError(error)"))
        #expect(source.contains("rootError = nil"))
        #expect(source.contains("var errorMessage: String?"))
    }

    @Test
    func metadataSettingsUsesTypedInlineErrorFeedback() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/MetadataSettingsView.swift")

        #expect(source.contains("@State private var surfaceError: AppError?"))
        #expect(source.contains("@State private var notice: SettingsInlineNotice?"))
        #expect(source.contains("SettingsErrorBanner(error: surfaceError)"))
        #expect(source.contains("SettingsNoticeBanner(notice: notice)"))
        #expect(source.contains("saveErrorMessage") == false)
        #expect(source.contains("apiKeyTestStatus") == false)
    }

    @Test
    func debridSettingsReplaceAlertStringsWithTypedFeedback() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/DebridSettingsView.swift")

        #expect(source.contains("@State private var surfaceError: AppError?"))
        #expect(source.contains("SettingsErrorBanner(error: surfaceError)"))
        #expect(source.contains("AppErrorInlineView(error: error)"))
        #expect(source.contains("saveErrorMessage") == false)
        #expect(source.contains(".alert(") == false)
    }

    @Test
    func indexerSettingsUseTypedFeedbackInsteadOfStringAlerts() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/IndexerSettingsView.swift")

        #expect(source.contains("@State private var surfaceError: AppError?"))
        #expect(source.contains("@State private var notice: SettingsInlineNotice?"))
        #expect(source.contains("SettingsErrorBanner(error: surfaceError)"))
        #expect(source.contains("SettingsNoticeBanner(notice: notice)"))
        #expect(source.contains("saveErrorMessage") == false)
        #expect(source.contains("testMessage") == false)
        #expect(source.contains(".alert(") == false)
        #expect(source.contains("try? await appState.database.setSetting") == false)
    }

    @Test
    func subtitleSettingsStopUsingSilentTryWrites() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/SubtitleSettingsView.swift")

        #expect(source.contains("@State private var surfaceError: AppError?"))
        #expect(source.contains("SettingsErrorBanner(error: surfaceError)"))
        #expect(source.contains("persistStringSetting(key:"))
        #expect(source.contains("persistBoolSetting(key:"))
        #expect(source.contains("Task { try? await appState.settingsManager.set") == false)
    }

    @Test
    func debridSettingsDoNotSilentlySwallowSecretCleanupFailures() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Settings/Destinations/DebridSettingsView.swift")

        #expect(source.contains("try? await appState.secretStore.deleteSecret") == false)
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
