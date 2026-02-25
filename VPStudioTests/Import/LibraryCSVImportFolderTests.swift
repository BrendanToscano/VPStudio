import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct LibraryCSVImportFolderTests {

    // MARK: - Helpers

    private func makeTemporaryDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, tempDir)
    }

    private func writeCSV(_ content: String, name: String, in directory: URL) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Target Folder Name

    @Test
    func importWithTargetFolderNameCreatesFolderAndImportsIntoIt() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-folder-create.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0060196,2024-01-10,"The Good, the Bad and the Ugly",movie,1966
            tt0903747,2024-01-11,Breaking Bad,tvSeries,2008
            """,
            name: "westerns.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let options = LibraryCSVImportOptions(
            destination: .watchlist,
            importRatings: false,
            targetFolderName: "My Western Collection"
        )
        let summary = try await service.importCSV(from: csvURL, options: options)

        #expect(summary.watchlistImported == 2)
        #expect(summary.targetFolderName == "My Western Collection")
        #expect(summary.targetFolderID != nil)

        // Verify the folder was created
        let folders = try await database.fetchAllLibraryFolders(listType: .watchlist)
        let customFolder = folders.first { $0.name == "My Western Collection" && !$0.isSystem }
        #expect(customFolder != nil)

        // Verify entries are in the custom folder
        let entries = try await database.fetchLibraryEntries(
            listType: .watchlist,
            folderId: customFolder!.id
        )
        #expect(entries.count == 2)
    }

    @Test
    func importWithExistingFolderNameReusesIt() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-folder-reuse.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Pre-create the folder
        let existingFolder = try await database.createLibraryFolder(
            name: "IMDb Import",
            listType: .watchlist
        )

        let csvURL = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0133093,2024-01-15,The Matrix,movie,1999
            """,
            name: "matrix.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let options = LibraryCSVImportOptions(
            destination: .watchlist,
            importRatings: false,
            targetFolderName: "IMDb Import"
        )
        let summary = try await service.importCSV(from: csvURL, options: options)

        #expect(summary.watchlistImported == 1)
        #expect(summary.targetFolderName == "IMDb Import")

        // Verify no duplicate folder was created
        let folders = try await database.fetchAllLibraryFolders(listType: .watchlist)
        let matchingFolders = folders.filter { $0.name == "IMDb Import" && !$0.isSystem }
        #expect(matchingFolders.count == 1)
        #expect(matchingFolders.first?.id == existingFolder.id)

        // Verify entries are in the existing folder
        let entries = try await database.fetchLibraryEntries(
            listType: .watchlist,
            folderId: existingFolder.id
        )
        #expect(entries.count == 1)
    }

    @Test
    func importWithExistingFolderNameIsCaseInsensitive() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-folder-case.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingFolder = try await database.createLibraryFolder(
            name: "My Movies",
            listType: .watchlist
        )

        let csvURL = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0133093,2024-01-15,The Matrix,movie,1999
            """,
            name: "test.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let options = LibraryCSVImportOptions(
            destination: .watchlist,
            importRatings: false,
            targetFolderName: "my movies" // Different case
        )
        let summary = try await service.importCSV(from: csvURL, options: options)

        #expect(summary.watchlistImported == 1)

        // Should reuse the existing folder
        let folders = try await database.fetchAllLibraryFolders(listType: .watchlist)
        let matchingFolders = folders.filter {
            $0.name.caseInsensitiveCompare("My Movies") == .orderedSame && !$0.isSystem
        }
        #expect(matchingFolders.count == 1)
        #expect(matchingFolders.first?.id == existingFolder.id)
    }

    // MARK: - Default Folder Name from Filename

    @Test
    func defaultFolderNameFromFilename() {
        let url1 = URL(fileURLWithPath: "/tmp/imdb-watchlist.csv")
        #expect(LibraryCSVImportService.defaultFolderName(from: url1) == "imdb-watchlist")

        let url2 = URL(fileURLWithPath: "/tmp/My Movies 2024.csv")
        #expect(LibraryCSVImportService.defaultFolderName(from: url2) == "My Movies 2024")

        let url3 = URL(fileURLWithPath: "/tmp/ratings.CSV")
        #expect(LibraryCSVImportService.defaultFolderName(from: url3) == "ratings")
    }

    @Test
    func resolvedFolderNameReturnsNilWhenNoExplicitName() {
        let url = URL(fileURLWithPath: "/tmp/test.csv")
        let result = LibraryCSVImportService.resolvedFolderName(from: nil, fileURL: url)
        #expect(result == nil)
    }

    @Test
    func resolvedFolderNameTrimsWhitespace() {
        let url = URL(fileURLWithPath: "/tmp/test.csv")
        let result = LibraryCSVImportService.resolvedFolderName(from: "  My Folder  ", fileURL: url)
        #expect(result == "My Folder")
    }

    @Test
    func resolvedFolderNameReturnsNilForEmptyString() {
        let url = URL(fileURLWithPath: "/tmp/test.csv")
        let result = LibraryCSVImportService.resolvedFolderName(from: "   ", fileURL: url)
        #expect(result == nil)
    }

    // MARK: - Without Folder Targeting

    @Test
    func importWithoutTargetFolderUsesSystemRoot() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-no-folder.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Created,Title,Type,Year
            tt0133093,2024-01-15,The Matrix,movie,1999
            """,
            name: "test.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let options = LibraryCSVImportOptions(
            destination: .watchlist,
            importRatings: false,
            targetFolderName: nil
        )
        let summary = try await service.importCSV(from: csvURL, options: options)

        #expect(summary.watchlistImported == 1)
        #expect(summary.targetFolderID == nil)
        #expect(summary.targetFolderName == nil)

        // Verify entries are in the system root folder
        let systemFolderID = try await database.fetchSystemLibraryFolderID(listType: .watchlist)
        let entries = try await database.fetchLibraryEntries(
            listType: .watchlist,
            folderId: systemFolderID
        )
        #expect(entries.count == 1)
    }

    // MARK: - Favorites with Folder

    @Test
    func importAutoPromotesToFavoritesInTargetFolder() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-folder-favs.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Your Rating,Date Rated,Title,URL,Title Type,Year
            tt0133093,9,2026-01-15,The Matrix,https://www.imdb.com/title/tt0133093/,movie,1999
            """,
            name: "ratings.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let options = LibraryCSVImportOptions(
            destination: .auto,
            importRatings: true,
            promoteLikedRatingsToFavorites: true,
            targetFolderName: "High Rated"
        )
        let summary = try await service.importCSV(from: csvURL, options: options)

        #expect(summary.favoritesImported == 1)
        #expect(summary.targetFolderName == "High Rated")

        // Verify a folder was created for favorites
        let favFolders = try await database.fetchAllLibraryFolders(listType: .favorites)
        let customFolder = favFolders.first { $0.name == "High Rated" && !$0.isSystem }
        #expect(customFolder != nil)

        // Verify the entry is in the custom folder
        let entries = try await database.fetchLibraryEntries(
            listType: .favorites,
            folderId: customFolder!.id
        )
        #expect(entries.count == 1)
    }
}
