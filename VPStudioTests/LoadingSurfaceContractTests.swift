import Foundation
import Testing
@testable import VPStudio

@Suite("Loading Surface Policies")
struct LoadingSurfacePolicyTests {
    @Test
    func libraryLoadingPolicyTracksSelectionReloads() {
        #expect(LibraryLoadingSurfacePolicy.shouldShowLoadingSurface(isLoadingSelection: true))
        #expect(LibraryLoadingSurfacePolicy.shouldShowLoadingSurface(isLoadingSelection: false) == false)
        #expect(LibraryLoadingSurfacePolicy.title == "Loading Library")
        #expect(LibraryLoadingSurfacePolicy.message == "Fetching watchlist, favorites, and history.")
    }

    @Test
    func downloadsLoadingPolicyShowsRootLoaderBeforeViewModelExists() {
        #expect(
            DownloadsLoadingSurfacePolicy.shouldShowRootLoading(
                hasViewModel: false,
                isLoading: false,
                groupCount: 0
            )
        )
    }

    @Test
    func downloadsLoadingPolicyShowsRootLoaderDuringInitialEmptyLoad() {
        #expect(
            DownloadsLoadingSurfacePolicy.shouldShowRootLoading(
                hasViewModel: true,
                isLoading: true,
                groupCount: 0
            )
        )
    }

    @Test
    func downloadsLoadingPolicyKeepsContentWhenGroupsAlreadyExist() {
        #expect(
            DownloadsLoadingSurfacePolicy.shouldShowRootLoading(
                hasViewModel: true,
                isLoading: true,
                groupCount: 3
            ) == false
        )

        #expect(
            DownloadsLoadingSurfacePolicy.shouldShowRootLoading(
                hasViewModel: true,
                isLoading: false,
                groupCount: 0
            ) == false
        )
    }
}

@Suite("Loading Surface Contracts")
struct LoadingSurfaceContractTests {
    @Test
    func contentViewLaunchScreenIsBoundToBootstrapping() throws {
        let source = try contents(of: "VPStudio/Views/Windows/ContentView.swift")
        #expect(source.contains("if appState.isBootstrapping"))
        #expect(source.contains("LaunchScreen()"))
    }

    @Test
    func downloadsViewUsesSharedLoadingOverlayInsteadOfRawProgressView() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Downloads/DownloadsView.swift")
        #expect(source.contains("DownloadsLoadingSurfacePolicy.shouldShowRootLoading"))
        #expect(source.contains("LoadingOverlay("))
        #expect(source.contains("ProgressView(\"Loading Downloads...\")") == false)
    }

    @Test
    func libraryViewUsesDedicatedSelectionLoadingSurface() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Library/LibraryView.swift")
        #expect(source.contains("@State private var isLoadingSelection = true"))
        #expect(source.contains("@State private var selectionLoadToken = 0"))
        #expect(source.contains("LibraryLoadingSurfacePolicy.shouldShowLoadingSurface"))
        #expect(source.contains("LoadingOverlay("))
        #expect(source.contains("selectionLoadToken += 1"))
        #expect(source.contains("isLoadingSelection = true"))
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
