import Foundation
import Testing
@testable import VPStudio

@Suite("CSV Import Sheet Policies")
struct CSVImportSheetPolicyTests {
    @Test func aggregateSummaryAddsAllImportedCounters() {
        let summaries = [
            makeSummary(
                format: .imdbWatchlist,
                rowsRead: 3,
                rowsImported: 2,
                rowsSkipped: 1,
                created: 2,
                updated: 0,
                watchlist: 2,
                favorites: 0,
                history: 0,
                ratings: 1
            ),
            makeSummary(
                format: .imdbRatings,
                rowsRead: 4,
                rowsImported: 3,
                rowsSkipped: 1,
                created: 1,
                updated: 2,
                watchlist: 0,
                favorites: 2,
                history: 1,
                ratings: 3
            ),
        ]

        let aggregate = LibraryCSVImportSheet.aggregatedSummary(summaries)

        #expect(aggregate.detectedFormat == .generic)
        #expect(aggregate.rowsRead == 7)
        #expect(aggregate.rowsImported == 5)
        #expect(aggregate.rowsSkipped == 2)
        #expect(aggregate.mediaItemsCreated == 3)
        #expect(aggregate.mediaItemsUpdated == 2)
        #expect(aggregate.watchlistImported == 2)
        #expect(aggregate.favoritesImported == 2)
        #expect(aggregate.historyImported == 1)
        #expect(aggregate.ratingsImported == 4)
        #expect(aggregate.targetFolderID == nil)
        #expect(aggregate.targetFolderName == nil)
    }

    @Test func libraryChangeAndNoticePoliciesDistinguishRatingsOnlyImports() {
        let ratingsOnly = makeSummary(rowsRead: 2, rowsImported: 2, ratings: 2)
        let existingOnly = makeSummary(rowsRead: 2, rowsImported: 0, rowsSkipped: 2)
        let withLibraryChange = makeSummary(rowsRead: 1, rowsImported: 1, favorites: 1)

        #expect(LibraryCSVImportSheet.hasLibraryChanges(in: ratingsOnly) == false)
        #expect(LibraryCSVImportSheet.hasLibraryChanges(in: existingOnly) == false)
        #expect(LibraryCSVImportSheet.hasLibraryChanges(in: withLibraryChange))
        #expect(
            LibraryCSVImportSheet.noLibraryChangesNotice(anyRatingsImported: true)
                == "Import finished, but no new library items were added. Ratings were imported."
        )
        #expect(
            LibraryCSVImportSheet.noLibraryChangesNotice(anyRatingsImported: false)
                == "Import finished, but no new library items were added. The imported titles may already exist."
        )
    }

    @Test func summaryLogLineUsesStableDiagnosticFormat() {
        let summary = makeSummary(
            rowsRead: 9,
            rowsImported: 7,
            rowsSkipped: 2,
            watchlist: 3,
            favorites: 2,
            history: 1,
            ratings: 4
        )

        #expect(LibraryCSVImportSheet.summaryLogLine(summary) == "rows=7/9 skipped=2 W=3 F=2 H=1 R=4")
    }

    @Test func debugFileStatsDescribesReadableAndMissingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("ratings.csv")
        try "Const,Title,Your Rating\n tt001,Movie,8\n".write(to: url, atomically: true, encoding: .utf8)

        let stats = LibraryCSVImportSheet.debugFileStats(at: url)
        #expect(stats.contains("bytes="))
        #expect(stats.contains("lines=2"))
        #expect(stats.contains("header=\"Const,Title,Your Rating\""))

        let missingStats = LibraryCSVImportSheet.debugFileStats(at: root.appendingPathComponent("missing.csv"))
        #expect(missingStats.hasPrefix("read=failed path="))
    }

    private func makeSummary(
        format: LibraryCSVDetectedFormat = .generic,
        rowsRead: Int = 0,
        rowsImported: Int = 0,
        rowsSkipped: Int = 0,
        created: Int = 0,
        updated: Int = 0,
        watchlist: Int = 0,
        favorites: Int = 0,
        history: Int = 0,
        ratings: Int = 0
    ) -> LibraryCSVImportSummary {
        LibraryCSVImportSummary(
            detectedFormat: format,
            rowsRead: rowsRead,
            rowsImported: rowsImported,
            rowsSkipped: rowsSkipped,
            mediaItemsCreated: created,
            mediaItemsUpdated: updated,
            watchlistImported: watchlist,
            favoritesImported: favorites,
            historyImported: history,
            ratingsImported: ratings
        )
    }
}

@Suite("IMDb CSV Import Sheet Policies")
struct IMDbCSVImportSheetPolicyTests {
    @Test func importButtonTitleReflectsSelectionPreviewAndInFlightState() {
        #expect(IMDbCSVImportPolicy.importButtonTitle(
            hasSelectedFile: false,
            previewDetected: false,
            importInFlight: false
        ) == "Preview CSV Before Importing")
        #expect(IMDbCSVImportPolicy.importButtonTitle(
            hasSelectedFile: false,
            previewDetected: true,
            importInFlight: false
        ) == "Change CSV File")
        #expect(IMDbCSVImportPolicy.importButtonTitle(
            hasSelectedFile: true,
            previewDetected: true,
            importInFlight: false
        ) == "Import Selected CSV")
        #expect(IMDbCSVImportPolicy.importButtonTitle(
            hasSelectedFile: true,
            previewDetected: false,
            importInFlight: true
        ) == "Importing...")
    }

    @Test func targetFolderPolicyRejectsDisabledBlankAndWhitespaceNames() {
        #expect(IMDbCSVImportPolicy.targetFolderName(importToFolder: false, folderName: "IMDb") == nil)
        #expect(IMDbCSVImportPolicy.targetFolderName(importToFolder: true, folderName: "") == nil)
        #expect(IMDbCSVImportPolicy.targetFolderName(importToFolder: true, folderName: "   \n") == nil)
        #expect(IMDbCSVImportPolicy.targetFolderName(importToFolder: true, folderName: "  IMDb Ratings  ") == "IMDb Ratings")
    }

    @Test func normalizedHeadersStripPunctuationCaseAndSpacing() {
        let headers = ["Your Rating", "IMDb ID", "Date-Added", "Original_Title"]

        #expect(IMDbCSVImportPolicy.normalizedHeaders(from: headers) == [
            "yourrating",
            "imdbid",
            "dateadded",
            "originaltitle",
        ])
    }

    @Test func previewRowsSkipBlankLinesAndRespectLimit() {
        let lines: ArraySlice<String> = [
            "",
            " tt001, \"Movie, The\" ",
            "   ",
            "tt002,Show",
            "tt003,Third",
            "tt004,Fourth",
        ][...]

        let rows = IMDbCSVImportPolicy.previewRows(from: lines, limit: 2)

        #expect(rows == [
            ["tt001", "Movie, The"],
            ["tt002", "Show"],
        ])
    }

    @Test func parseCSVLineHandlesQuotedCommasAndWhitespace() {
        let parsed = IMDbCSVImportSheet.parseCSVLine(" tt001, \"Movie, The\", 2024, \"8\" ")

        #expect(parsed == ["tt001", "Movie, The", "2024", "8"])
    }

    @Test func parseCSVLineHandlesEscapedQuotesInsideQuotedFields() {
        let parsed = IMDbCSVImportSheet.parseCSVLine(#"tt001,"Movie ""The One""",2024"#)

        #expect(parsed == ["tt001", "Movie \"The One\"", "2024"])
    }

    @Test func parseCSVLineKeepsEmptyColumns() {
        let parsed = IMDbCSVImportSheet.parseCSVLine("Title,,Year,")

        #expect(parsed == ["Title", "", "Year", ""])
    }

    @Test func detectColumnMappingsRecognizesIMDbAndGenericHeaders() {
        let headers = [
            "const",
            "primarytitle",
            "startyear",
            "titletype",
            "yourrating",
            "imdbrating",
            "favorite",
            "dateadded",
            "unknowncolumn",
        ]

        let mappings = IMDbCSVImportSheet.detectColumnMappings(from: headers)

        #expect(mappings["const"] == "imdbID")
        #expect(mappings["primarytitle"] == "title")
        #expect(mappings["startyear"] == "year")
        #expect(mappings["titletype"] == "mediaType")
        #expect(mappings["yourrating"] == "userRating")
        #expect(mappings["imdbrating"] == "imdbRating")
        #expect(mappings["favorite"] == "liked")
        #expect(mappings["dateadded"] == "date")
        #expect(mappings["unknowncolumn"] == nil)
    }

    @Test func mappingChoiceCasesRemainStableForPreviewPicker() {
        #expect(CSVHeaderPreviewSheet.MappingChoice.allCases == [.detected, .ai, .ignore])
        #expect(CSVHeaderPreviewSheet.MappingChoice.detected.rawValue == "Auto")
        #expect(CSVHeaderPreviewSheet.MappingChoice.ai.rawValue == "AI")
        #expect(CSVHeaderPreviewSheet.MappingChoice.ignore.rawValue == "Ignore")
    }
}

@Suite("CSV Export Sheet Policies")
struct CSVExportSheetPolicyTests {
    @Test func csvFileURLsReturnsOnlyCSVFilesSortedByFilename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let second = root.appendingPathComponent("watchlist.csv")
        let first = root.appendingPathComponent("favorites.CSV")
        let ignored = root.appendingPathComponent("notes.txt")
        try "b".write(to: second, atomically: true, encoding: .utf8)
        try "a".write(to: first, atomically: true, encoding: .utf8)
        try "ignore".write(to: ignored, atomically: true, encoding: .utf8)

        let urls = LibraryCSVExportSheet.csvFileURLs(in: root)

        #expect(urls.map(\.lastPathComponent) == ["favorites.CSV", "watchlist.csv"])
    }

    @Test func csvFileURLsReturnsEmptyForUnreadableDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        #expect(LibraryCSVExportSheet.csvFileURLs(in: missing).isEmpty)
    }
}
