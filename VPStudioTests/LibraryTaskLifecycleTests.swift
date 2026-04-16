import Foundation
import Testing
@testable import VPStudio

@Suite("Library Task Lifecycle")
struct LibraryTaskLifecycleTests {
    @Test
    func libraryViewCancelsLoadTaskOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Library/LibraryView.swift")
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("loadTask?.cancel()"))
        #expect(source.contains("loadTask = nil"))
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
