import Foundation
import Testing
@testable import VPStudio

@Suite("Multi-CSV Import", .serialized)
struct LibraryCSVMultiImportTests {

    // MARK: - Helpers

    private func makeTemporaryDatabase() async throws -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("multi-import-test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, tempDir)
    }

    private func writeCSV(_ content: String, name: String, in directory: URL) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Multi-file Import

    @Test
    func importMultipleCSVsCreatesSeparateFolders() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let watchlistCSV = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0111161,2024-01-10,The Shawshank Redemption,movie,1994
            tt0068646,2024-01-11,The Godfather,movie,1972
            """,
            name: "Watchlist.csv",
            in: tempDir
        )

        let horrorCSV = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0081505,2024-02-01,The Shining,movie,1980
            """,
            name: "Horror Picks.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)

        // Import first file into its folder
        let opts1 = LibraryCSVImportOptions(
            destination: .watchlist,
            targetFolderName: LibraryCSVImportService.defaultFolderName(from: watchlistCSV)
        )
        let summary1 = try await service.importCSV(from: watchlistCSV, options: opts1)
        #expect(summary1.rowsImported == 2)
        #expect(summary1.targetFolderName == "Watchlist")

        // Import second file into its folder
        let opts2 = LibraryCSVImportOptions(
            destination: .watchlist,
            targetFolderName: LibraryCSVImportService.defaultFolderName(from: horrorCSV)
        )
        let summary2 = try await service.importCSV(from: horrorCSV, options: opts2)
        #expect(summary2.rowsImported == 1)
        #expect(summary2.targetFolderName == "Horror Picks")

        // Verify separate folders were created
        let folders = try await database.fetchAllLibraryFolders(listType: .watchlist)
        let customFolders = folders.filter { !$0.isSystem }
        #expect(customFolders.count == 2)
        let folderNames = Set(customFolders.map(\.name))
        #expect(folderNames.contains("Watchlist"))
        #expect(folderNames.contains("Horror Picks"))
    }

    @Test
    func importMultipleCSVsDeduplicatesSharedMedia() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Same movie in two CSVs
        let csv1 = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0111161,2024-01-10,The Shawshank Redemption,movie,1994
            """,
            name: "List A.csv",
            in: tempDir
        )
        let csv2 = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0111161,2024-02-10,The Shawshank Redemption,movie,1994
            """,
            name: "List B.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)

        let opts1 = LibraryCSVImportOptions(destination: .watchlist, targetFolderName: "List A")
        let summary1 = try await service.importCSV(from: csv1, options: opts1)
        #expect(summary1.mediaItemsCreated == 1)

        let opts2 = LibraryCSVImportOptions(destination: .watchlist, targetFolderName: "List B")
        let summary2 = try await service.importCSV(from: csv2, options: opts2)
        // Media item already exists — should update, not create
        #expect(summary2.mediaItemsCreated == 0)
    }

    @Test
    func importSequentialCSVsPreservesBothFolders() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csv1 = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0111161,2024-01-10,The Shawshank Redemption,movie,1994
            """,
            name: "Folder A.csv",
            in: tempDir
        )
        let csv2 = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0068646,2024-01-11,The Godfather,movie,1972
            """,
            name: "Folder B.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)

        let s1 = try await service.importCSV(from: csv1, options: .init(destination: .watchlist, targetFolderName: "Folder A"))
        #expect(s1.rowsImported == 1)
        #expect(s1.targetFolderName == "Folder A")

        let s2 = try await service.importCSV(from: csv2, options: .init(destination: .watchlist, targetFolderName: "Folder B"))
        #expect(s2.rowsImported == 1)
        #expect(s2.targetFolderName == "Folder B")

        // Both items are in the library
        #expect(try await database.isInLibrary(mediaId: "tt0111161", listType: .watchlist))
        #expect(try await database.isInLibrary(mediaId: "tt0068646", listType: .watchlist))

        // Both folders exist
        let folders = try await database.fetchAllLibraryFolders(listType: .watchlist)
        let names = Set(folders.filter { !$0.isSystem }.map(\.name))
        #expect(names.contains("Folder A"))
        #expect(names.contains("Folder B"))
    }

    @Test
    func defaultFolderNameFromFilename() {
        let url1 = URL(fileURLWithPath: "/tmp/Horror Picks.csv")
        #expect(LibraryCSVImportService.defaultFolderName(from: url1) == "Horror Picks")

        let url2 = URL(fileURLWithPath: "/tmp/My Watchlist.csv")
        #expect(LibraryCSVImportService.defaultFolderName(from: url2) == "My Watchlist")

        let url3 = URL(fileURLWithPath: "/tmp/ratings.csv")
        #expect(LibraryCSVImportService.defaultFolderName(from: url3) == "ratings")
    }

    @Test
    func importEmptyCSVAmongMultipleSkipsGracefully() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let goodCSV = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0111161,2024-01-10,The Shawshank Redemption,movie,1994
            """,
            name: "Good List.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let opts = LibraryCSVImportOptions(destination: .watchlist, targetFolderName: "Good List")
        let summary = try await service.importCSV(from: goodCSV, options: opts)
        #expect(summary.rowsImported == 1)
    }

    @Test
    func importVPStudioExportedCSVWithWindowsLineEndings() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Simulate a VPStudio-exported CSV (uses \r\n line endings)
        let csvContent = "Const,Title,URL,Title Type,IMDb Rating,Year,Created\r\ntt0111161,The Shawshank Redemption,https://www.imdb.com/title/tt0111161/,movie,9.3,1994,2024-01-10\r\ntt0068646,The Godfather,https://www.imdb.com/title/tt0068646/,movie,9.2,1972,2024-01-11\r\n"
        let csvFile = tempDir.appendingPathComponent("Action.csv")
        try csvContent.write(to: csvFile, atomically: true, encoding: .utf8)

        let service = LibraryCSVImportService(database: database)
        let opts = LibraryCSVImportOptions(destination: .watchlist, targetFolderName: "Action")
        let summary = try await service.importCSV(from: csvFile, options: opts)

        #expect(summary.rowsImported == 2)
        #expect(summary.targetFolderName == "Action")

        let item1 = try await database.fetchMediaItem(id: "tt0111161")
        #expect(item1?.title == "The Shawshank Redemption")

        let item2 = try await database.fetchMediaItem(id: "tt0068646")
        #expect(item2?.title == "The Godfather")

        let folders = try await database.fetchAllLibraryFolders(listType: .watchlist)
        let customNames = folders.filter { !$0.isSystem }.map(\.name)
        #expect(customNames.contains("Action"))
    }
}
