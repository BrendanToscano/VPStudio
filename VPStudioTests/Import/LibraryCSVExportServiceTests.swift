import Foundation
import Testing
@testable import VPStudio

// MARK: - CSV Escape Tests

@Suite("LibraryCSVExportService - escapeCSV")
struct CSVExportEscapeTests {

    @Test func plainTextPassesThrough() {
        #expect(LibraryCSVExportService.escapeCSV("Hello World") == "Hello World")
    }

    @Test func commaTriggersQuoting() {
        #expect(LibraryCSVExportService.escapeCSV("Foo, Bar") == "\"Foo, Bar\"")
    }

    @Test func doubleQuoteEscaped() {
        #expect(LibraryCSVExportService.escapeCSV("Say \"hello\"") == "\"Say \"\"hello\"\"\"")
    }

    @Test func newlineTriggersQuoting() {
        #expect(LibraryCSVExportService.escapeCSV("Line1\nLine2") == "\"Line1\nLine2\"")
    }

    @Test func emptyStringPassesThrough() {
        #expect(LibraryCSVExportService.escapeCSV("") == "")
    }

    @Test func carriageReturnTriggersQuoting() {
        #expect(LibraryCSVExportService.escapeCSV("A\rB") == "\"A\rB\"")
    }

    @Test func formulaPrefixIsNeutralized() {
        #expect(LibraryCSVExportService.escapeCSV("=SUM(A1:A2)") == "'=SUM(A1:A2)")
        #expect(LibraryCSVExportService.escapeCSV("+cmd") == "'+cmd")
        #expect(LibraryCSVExportService.escapeCSV("@lookup") == "'@lookup")
    }

    @Test func formulaPrefixIsNeutralizedBeforeQuoting() {
        #expect(LibraryCSVExportService.escapeCSV("=SUM(A1,A2)") == "\"'=SUM(A1,A2)\"")
    }

    @Test func formulaNeutralizationHonorsLeadingSpacesAndExistingApostrophe() {
        #expect(LibraryCSVExportService.escapeCSV("  -cmd") == "'  -cmd")
        #expect(LibraryCSVExportService.escapeCSV("\tcmd") == "'\tcmd")
        #expect(LibraryCSVExportService.escapeCSV("'=SUM(A1:A2)") == "'=SUM(A1:A2)")
    }
}

// MARK: - Export Summary Tests

@Suite("LibraryCSVExportSummary")
struct CSVExportSummaryTests {

    @Test func defaultsToZero() {
        let summary = LibraryCSVExportSummary()
        #expect(summary.filesWritten == 0)
        #expect(summary.totalItemsExported == 0)
        #expect(summary.folderNames.isEmpty)
    }

    @Test func equatableConformance() {
        var a = LibraryCSVExportSummary()
        a.filesWritten = 2
        a.totalItemsExported = 10
        a.folderNames = ["Watchlist", "Favorites"]

        var b = LibraryCSVExportSummary()
        b.filesWritten = 2
        b.totalItemsExported = 10
        b.folderNames = ["Watchlist", "Favorites"]

        #expect(a == b)
    }

    @Test func sendableConformance() async {
        var summary = LibraryCSVExportSummary()
        summary.filesWritten = 3
        let result = await Task.detached { summary }.value
        #expect(result.filesWritten == 3)
    }
}

// MARK: - Export Integration Tests

private func makeTempDatabase() async throws -> DatabaseManager {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbPath = tempDir.appendingPathComponent("export-test.sqlite").path
    let database = try DatabaseManager(path: dbPath)
    try await database.migrate()
    return database
}

@Suite("LibraryCSVExportService - Integration", .serialized)
struct CSVExportIntegrationTests {

    @Test func exportEmptyLibraryProducesNoFiles() async throws {
        let db = try await makeTempDatabase()
        let service = LibraryCSVExportService(database: db)

        let (dirURL, summary) = try await service.exportAll()
        #expect(summary.filesWritten == 0)
        #expect(summary.totalItemsExported == 0)

        // Cleanup
        try? FileManager.default.removeItem(at: dirURL)
    }

    @Test func exportWatchlistProducesCSV() async throws {
        let db = try await makeTempDatabase()

        // Seed a media item and watchlist entry
        let item = MediaItem(
            id: "tt1234567", type: .movie, title: "Test Movie",
            year: 2024, genres: ["Action", "Sci-Fi"],
            imdbRating: 7.5, runtime: 120
        )
        try await db.saveMediaItem(item)
        let entry = UserLibraryEntry(
            id: "tt1234567-watchlist", mediaId: "tt1234567",
            folderId: LibraryFolder.systemFolderID(for: .watchlist),
            listType: .watchlist, addedAt: Date()
        )
        try await db.addToLibrary(entry)

        let service = LibraryCSVExportService(database: db)
        let (dirURL, summary) = try await service.exportAll()

        #expect(summary.filesWritten >= 1)
        #expect(summary.totalItemsExported >= 1)

        // Check that a CSV file exists
        let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
        let csvFiles = files.filter { $0.pathExtension == "csv" }
        #expect(!csvFiles.isEmpty)

        // Read the CSV and verify headers and content
        let csvContent = try String(contentsOf: csvFiles[0], encoding: .utf8)
        #expect(csvContent.contains("Const"))
        #expect(csvContent.contains("Title"))
        #expect(csvContent.contains("tt1234567"))
        #expect(csvContent.contains("Test Movie"))

        try? FileManager.default.removeItem(at: dirURL)
    }

    @Test func exportIncludesUserRatings() async throws {
        let db = try await makeTempDatabase()

        let item = MediaItem(
            id: "tt9999999", type: .movie, title: "Rated Movie",
            year: 2023, genres: ["Drama"], imdbRating: 8.2
        )
        try await db.saveMediaItem(item)
        let entry = UserLibraryEntry(
            id: "tt9999999-watchlist", mediaId: "tt9999999",
            folderId: LibraryFolder.systemFolderID(for: .watchlist),
            listType: .watchlist, addedAt: Date()
        )
        try await db.addToLibrary(entry)

        let rating = TasteEvent(
            mediaId: "tt9999999", eventType: .rated,
            feedbackScale: .oneToTen, feedbackValue: 9.0
        )
        try await db.saveTasteEvent(rating)

        let service = LibraryCSVExportService(database: db)
        let (dirURL, summary) = try await service.exportAll()

        #expect(summary.totalItemsExported >= 1)

        let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
        let csvFiles = files.filter { $0.pathExtension == "csv" }
        let csvContent = try String(contentsOf: csvFiles[0], encoding: .utf8)
        // Should use ratings headers since ratings exist
        #expect(csvContent.contains("Your Rating"))
        #expect(csvContent.contains("9"))

        try? FileManager.default.removeItem(at: dirURL)
    }

    @Test func exportCustomFolderCreatesNamedFile() async throws {
        let db = try await makeTempDatabase()

        let folder = try await db.createLibraryFolder(name: "Horror Picks", listType: .watchlist)

        let item = MediaItem(
            id: "tt5555555", type: .movie, title: "Scary Movie",
            year: 2022, genres: ["Horror"]
        )
        try await db.saveMediaItem(item)
        let entry = UserLibraryEntry(
            id: "tt5555555-watchlist", mediaId: "tt5555555",
            folderId: folder.id, listType: .watchlist, addedAt: Date()
        )
        try await db.addToLibrary(entry)

        let service = LibraryCSVExportService(database: db)
        let (dirURL, summary) = try await service.exportAll()

        #expect(summary.folderNames.contains("Horror Picks"))

        let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
        let horrorFile = files.first(where: { $0.lastPathComponent == "Watchlist - Horror Picks.csv" })
        #expect(horrorFile != nil)

        if let horrorFile {
            let content = try String(contentsOf: horrorFile, encoding: .utf8)
            #expect(content.contains("tt5555555"))
            #expect(content.contains("Scary Movie"))
        }

        try? FileManager.default.removeItem(at: dirURL)
    }

    @Test func exportAllWritesHistoryCSVWhenCompletedHistoryExists() async throws {
        let db = try await makeTempDatabase()

        try await db.saveMediaItem(
            MediaItem(
                id: "tt0300001",
                type: .movie,
                title: "History Movie",
                year: 2021,
                genres: ["Mystery"],
                imdbRating: 6.8,
                runtime: 101
            )
        )
        try await db.saveWatchHistory(
            WatchHistory(
                id: "history-completed",
                mediaId: "tt0300001",
                title: "Fallback History Title",
                progress: 101,
                duration: 101,
                watchedAt: Date(timeIntervalSince1970: 1_700_172_800),
                isCompleted: true
            )
        )

        let service = LibraryCSVExportService(database: db)
        let (dirURL, summary) = try await service.exportAll()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        #expect(summary.filesWritten == 1)
        #expect(summary.totalItemsExported == 1)
        #expect(summary.folderNames == ["History"])

        let historyFile = dirURL.appendingPathComponent("History.csv")
        let content = try String(contentsOf: historyFile, encoding: .utf8)
        #expect(content.contains("tt0300001"))
        #expect(content.contains("History Movie"))
        #expect(content.contains("movie"))
    }

    @Test func exportAllDisambiguatesSanitizedFolderNameCollisions() async throws {
        let db = try await makeTempDatabase()

        let slashFolder = try await db.createLibraryFolder(name: "A/B", listType: .watchlist)
        let backslashFolder = try await db.createLibraryFolder(name: "A\\B", listType: .watchlist)

        let first = MediaItem(id: "tt0300010", type: .movie, title: "Slash", year: 2022, genres: [])
        let second = MediaItem(id: "tt0300011", type: .movie, title: "Backslash", year: 2022, genres: [])
        try await db.saveMediaItem(first)
        try await db.saveMediaItem(second)
        try await db.addToLibrary(
            UserLibraryEntry(
                id: "tt0300010-watchlist",
                mediaId: first.id,
                folderId: slashFolder.id,
                listType: .watchlist,
                addedAt: Date()
            )
        )
        try await db.addToLibrary(
            UserLibraryEntry(
                id: "tt0300011-watchlist",
                mediaId: second.id,
                folderId: backslashFolder.id,
                listType: .watchlist,
                addedAt: Date()
            )
        )

        let service = LibraryCSVExportService(database: db)
        let (dirURL, _) = try await service.exportAll()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
        let fileNames = Set(files.map(\.lastPathComponent))

        #expect(fileNames.contains("Watchlist - A-B.csv"))
        #expect(fileNames.contains("Watchlist - A-B (1).csv"))
    }

    @Test func exportSingleFolder() async throws {
        let db = try await makeTempDatabase()

        let item = MediaItem(
            id: "tt7777777", type: .series, title: "Test Show",
            year: 2025, genres: ["Comedy"]
        )
        try await db.saveMediaItem(item)
        let entry = UserLibraryEntry(
            id: "tt7777777-watchlist", mediaId: "tt7777777",
            folderId: LibraryFolder.systemFolderID(for: .watchlist),
            listType: .watchlist, addedAt: Date()
        )
        try await db.addToLibrary(entry)

        let service = LibraryCSVExportService(database: db)
        let (csv, count) = try await service.exportFolder(listType: .watchlist, folderId: nil)

        #expect(count >= 1)
        #expect(csv.contains("tt7777777"))
        #expect(csv.contains("Test Show"))
        #expect(csv.contains("tvSeries"))
    }

    @Test func exportFolderConvertsNonDefaultRatingScalesForIMDb() async throws {
        let db = try await makeTempDatabase()

        let highPercent = MediaItem(id: "tt0300100", type: .movie, title: "Percent Rating", year: 2024, genres: [])
        let disliked = MediaItem(id: "tt0300101", type: .movie, title: "Disliked Rating", year: 2024, genres: [])
        let liked = MediaItem(id: "tt0300102", type: .movie, title: "Liked Rating", year: 2024, genres: [])
        for item in [highPercent, disliked, liked] {
            try await db.saveMediaItem(item)
            try await db.addToLibrary(
                UserLibraryEntry(
                    id: "\(item.id)-watchlist",
                    mediaId: item.id,
                    folderId: LibraryFolder.systemFolderID(for: .watchlist),
                    listType: .watchlist,
                    addedAt: Date()
                )
            )
        }

        try await db.saveTasteEvent(
            TasteEvent(
                mediaId: highPercent.id,
                eventType: .rated,
                feedbackScale: .oneToHundred,
                feedbackValue: 100
            )
        )
        try await db.saveTasteEvent(
            TasteEvent(
                mediaId: disliked.id,
                eventType: .rated,
                feedbackScale: .likeDislike,
                feedbackValue: 0
            )
        )
        try await db.saveTasteEvent(
            TasteEvent(
                mediaId: liked.id,
                eventType: .rated,
                feedbackScale: .likeDislike,
                feedbackValue: 1
            )
        )

        let service = LibraryCSVExportService(database: db)
        let (csv, count) = try await service.exportFolder(listType: .watchlist, folderId: nil)

        #expect(count == 3)
        #expect(csv.contains("tt0300100,10,"))
        #expect(csv.contains("tt0300101,3,"))
        #expect(csv.contains("tt0300102,8,"))
    }

    @Test func exportIMDbURLFormat() async throws {
        let db = try await makeTempDatabase()

        let item = MediaItem(
            id: "tt0111161", type: .movie, title: "The Shawshank Redemption",
            year: 1994, genres: ["Drama"]
        )
        try await db.saveMediaItem(item)
        let entry = UserLibraryEntry(
            id: "tt0111161-watchlist", mediaId: "tt0111161",
            folderId: LibraryFolder.systemFolderID(for: .watchlist),
            listType: .watchlist, addedAt: Date()
        )
        try await db.addToLibrary(entry)

        let service = LibraryCSVExportService(database: db)
        let (csv, _) = try await service.exportFolder(listType: .watchlist, folderId: nil)
        #expect(csv.contains("https://www.imdb.com/title/tt0111161/"))
    }

    @Test func exportUsesWindowsLineEndings() async throws {
        let db = try await makeTempDatabase()

        let item = MediaItem(id: "tt0000001", type: .movie, title: "A", year: 2020, genres: [])
        try await db.saveMediaItem(item)
        try await db.addToLibrary(UserLibraryEntry(
            id: "tt0000001-watchlist", mediaId: "tt0000001",
            folderId: LibraryFolder.systemFolderID(for: .watchlist),
            listType: .watchlist, addedAt: Date()
        ))

        let service = LibraryCSVExportService(database: db)
        let (csv, _) = try await service.exportFolder(listType: .watchlist, folderId: nil)
        #expect(csv.contains("\r\n"))
    }

    @Test func historyExportOnlyIncludesCompletedEntries() async throws {
        let db = try await makeTempDatabase()

        try await db.saveWatchHistory(
            WatchHistory(
                id: "resume-entry",
                mediaId: "tt0100001",
                title: "Incomplete Movie",
                progress: 1200,
                duration: 7200,
                watchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                isCompleted: false
            )
        )
        try await db.saveWatchHistory(
            WatchHistory(
                id: "completed-entry",
                mediaId: "tt0100002",
                title: "Completed Movie",
                progress: 7200,
                duration: 7200,
                watchedAt: Date(timeIntervalSince1970: 1_700_086_400),
                isCompleted: true
            )
        )

        let service = LibraryCSVExportService(database: db)
        let (csv, count) = try await service.exportFolder(listType: .history, folderId: nil)

        #expect(count == 1)
        #expect(csv.contains("Completed Movie"))
        #expect(!csv.contains("Incomplete Movie"))
    }

    @Test func exportAllDisambiguatesCollidingFolderNames() async throws {
        let db = try await makeTempDatabase()

        let customFolder = try await db.createLibraryFolder(name: "Favorites", listType: .watchlist)

        let watchlistItem = MediaItem(id: "tt0200001", type: .movie, title: "Custom Folder Item", year: 2024, genres: [])
        let favoritesItem = MediaItem(id: "tt0200002", type: .movie, title: "System Favorites Item", year: 2024, genres: [])
        try await db.saveMediaItem(watchlistItem)
        try await db.saveMediaItem(favoritesItem)

        try await db.addToLibrary(
            UserLibraryEntry(
                id: "tt0200001-watchlist-custom",
                mediaId: "tt0200001",
                folderId: customFolder.id,
                listType: .watchlist,
                addedAt: Date()
            )
        )
        try await db.addToLibrary(
            UserLibraryEntry(
                id: "tt0200002-favorites-system",
                mediaId: "tt0200002",
                folderId: LibraryFolder.systemFolderID(for: .favorites),
                listType: .favorites,
                addedAt: Date()
            )
        )

        let service = LibraryCSVExportService(database: db)
        let (dirURL, _) = try await service.exportAll()
        defer { try? FileManager.default.removeItem(at: dirURL) }

        let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
        let fileNames = Set(files.map(\.lastPathComponent))

        #expect(fileNames.contains("Favorites.csv"))
        #expect(fileNames.contains("Watchlist - Favorites.csv"))
    }

    @Test func importedHistoryDateRoundTripsWithoutDayShift() async throws {
        let db = try await makeTempDatabase()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-import-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let csv = """
        Const,Date Rated,Title,Title Type
        tt0111161,2025-02-14,The Shawshank Redemption,movie
        """
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)

        let importService = LibraryCSVImportService(database: db)
        let summary = try await importService.importCSV(
            from: fileURL,
            options: .init(destination: .history, importRatings: false, promoteLikedRatingsToFavorites: false)
        )
        #expect(summary.historyImported == 1)

        let exportService = LibraryCSVExportService(database: db)
        let (historyCSV, count) = try await exportService.exportFolder(listType: .history, folderId: nil)

        #expect(count == 1)
        #expect(historyCSV.contains("2025-02-14"))
    }
}
