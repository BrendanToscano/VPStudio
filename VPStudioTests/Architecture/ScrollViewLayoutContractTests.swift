import Foundation
import Testing
@testable import VPStudio

/// Regression tests for the infinite scroll bug caused by GeometryReader
/// inside nested ScrollViews. GeometryReader triggers layout measurement
/// cycles that cause the scroll position to jump endlessly.
///
/// Root cause: GeometryReader in episode progress bars inside horizontal
/// ScrollViews nested in a vertical ScrollView caused infinite re-layout.
/// Fix: replaced with scaleEffect-based progress bars.
@Suite("ScrollView Layout Contract")
struct ScrollViewLayoutContractTests {

    // MARK: - GeometryReader Ban in Detail ScrollViews

    /// GeometryReader inside ScrollView content causes layout thrashing.
    /// Progress bars must use scaleEffect or fixed frames instead.
    @Test("Detail views must not use GeometryReader inside ScrollView content")
    func noGeometryReaderInDetailScrollViews() {
        let detailDir = repoRootURL()
            .appendingPathComponent("VPStudio/Views/Windows/Detail")

        let swiftFiles = findSwiftFiles(in: detailDir)
        #expect(!swiftFiles.isEmpty, "Should find Swift files in Detail directory")

        for file in swiftFiles {
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let lines = content.components(separatedBy: .newlines)

            // Track if we're inside a ScrollView scope (simplified heuristic)
            var scrollViewDepth = 0
            for (lineNumber, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.contains("ScrollView") && !trimmed.hasPrefix("//") {
                    scrollViewDepth += 1
                }

                if scrollViewDepth > 0 && !trimmed.hasPrefix("//") && trimmed.contains("GeometryReader") {
                    Issue.record("""
                        \(file.lastPathComponent):\(lineNumber + 1) — \
                        GeometryReader found inside ScrollView scope. \
                        This causes infinite layout thrashing. \
                        Use scaleEffect or fixed frames instead.
                        """)
                }
            }
        }
    }

    /// EpisodeCardView progress bars must not use GeometryReader.
    @Test("EpisodeCardView progress bars use scaleEffect, not GeometryReader")
    func episodeCardProgressBarsUseScaleEffect() {
        let file = repoRootURL()
            .appendingPathComponent("VPStudio/Views/Windows/Detail/EpisodeCardView.swift")
        let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""

        #expect(!content.isEmpty, "EpisodeCardView.swift should exist and be readable")
        #expect(
            !hasCodeUsage(of: "GeometryReader", in: content),
            "EpisodeCardView must not use GeometryReader — causes scroll layout thrashing"
        )
    }

    /// SeriesDetailLayout episode cards must not use GeometryReader for progress.
    @Test("SeriesDetailLayout episodeCard uses scaleEffect, not GeometryReader")
    func seriesDetailLayoutProgressUsesScaleEffect() {
        let file = repoRootURL()
            .appendingPathComponent("VPStudio/Views/Windows/Detail/SeriesDetailLayout.swift")
        let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""

        #expect(!content.isEmpty, "SeriesDetailLayout.swift should exist and be readable")
        #expect(
            !hasCodeUsage(of: "GeometryReader", in: content),
            "SeriesDetailLayout must not use GeometryReader — causes scroll layout thrashing"
        )
    }

    // MARK: - Helpers

    private func repoRootURL() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return url
    }

    /// Returns true if `symbol` appears in actual code (not comments).
    private func hasCodeUsage(of symbol: String, in source: String) -> Bool {
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if trimmed.contains(symbol) { return true }
        }
        return false
    }

    private func findSwiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                files.append(fileURL)
            }
        }
        return files
    }
}
