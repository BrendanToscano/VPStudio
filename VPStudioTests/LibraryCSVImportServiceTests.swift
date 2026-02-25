import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct LibraryCSVImportServiceTests {
    @Test
    func importsIMDbWatchlistIntoLibraryAndMediaCache() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-import-watchlist.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Created,Title,Type,You rated,IMDb Rating,Year,URL
            tt0060196,2024-01-10,"The Good, the Bad and the Ugly",movie,,8.8,1966,https://www.imdb.com/title/tt0060196/
            tt0903747,2024-01-11,Breaking Bad,tvSeries,,9.5,2008,https://www.imdb.com/title/tt0903747/
            """,
            name: "imdb-watchlist.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(destination: .watchlist, importRatings: false)
        )

        #expect(summary.detectedFormat == .imdbWatchlist)
        #expect(summary.rowsRead == 2)
        #expect(summary.rowsImported == 2)
        #expect(summary.watchlistImported == 2)
        #expect(summary.ratingsImported == 0)

        let watchlistEntries = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(watchlistEntries.count == 2)

        let movie = try await database.fetchMediaItem(id: "tt0060196")
        let show = try await database.fetchMediaItem(id: "tt0903747")
        #expect(movie?.title == "The Good, the Bad and the Ugly")
        #expect(show?.type == .series)
    }

    @Test
    func importsIMDbRatingsIntoTasteProfileAndPromotesLikedTitlesWhenAuto() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-import-ratings.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Year
            tt0133093,9,2026-01-15,The Matrix,https://www.imdb.com/title/tt0133093/,movie,8.7,1999
            tt0110912,3,2026-01-16,Pulp Fiction,https://www.imdb.com/title/tt0110912/,movie,8.9,1994
            """,
            name: "imdb-ratings.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: .auto,
                importRatings: true,
                promoteLikedRatingsToFavorites: true
            )
        )

        #expect(summary.detectedFormat == .imdbRatings)
        #expect(summary.rowsImported == 2)
        #expect(summary.ratingsImported == 2)
        #expect(summary.favoritesImported == 1)
        // Non-liked items now go to watchlist instead of being silently dropped
        #expect(summary.watchlistImported == 1)

        let favorites = try await database.fetchLibraryEntries(listType: .favorites)
        #expect(favorites.count == 1)
        #expect(favorites.first?.mediaId == "tt0133093")

        let watchlist = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(watchlist.count == 1)
        #expect(watchlist.first?.mediaId == "tt0110912")

        let ratings = try await database.fetchTasteEvents(eventType: .rated, limit: 20)
        #expect(ratings.count == 2)
        #expect(ratings.allSatisfy { $0.feedbackScale?.canonicalMode == .oneToTen })
    }

    @Test
    func importsGenericCSVIntoHistoryAndRatings() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-import-history.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            imdb_id,title,year,rating,watched_at,type
            tt2488496,Star Wars: The Force Awakens,2015,78,2026-01-20,movie
            """,
            name: "generic-history.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: .history,
                importRatings: true,
                promoteLikedRatingsToFavorites: false
            )
        )

        #expect(summary.detectedFormat == .generic)
        #expect(summary.historyImported == 1)
        #expect(summary.watchlistImported == 1) // history destination also creates watchlist entry
        #expect(summary.ratingsImported == 1)

        let history = try await database.fetchWatchHistory(limit: 20)
        #expect(history.count == 1)
        #expect(history.first?.mediaId == "tt2488496")
        #expect(history.first?.isCompleted == true)

        let watchlist = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(watchlist.count == 1, "History items should also appear in watchlist")

        let ratings = try await database.fetchTasteEvents(eventType: .rated, limit: 20)
        #expect(ratings.count == 1)
        #expect(ratings.first?.feedbackScale?.canonicalMode == .oneToHundred)
        #expect(ratings.first?.feedbackValue == 78)
    }

    @Test(arguments: [
        ("Watchlist.csv", LibraryCSVImportDestination.watchlist),
        ("To Watch.csv", .watchlist),
        ("Currently Watching.csv", .watchlist),
        ("Release Wait.csv", .watchlist),
        ("Long Break.csv", .watchlist),
        ("WatchHistory.csv", .history),
        ("Watch History.csv", .history),
        ("My WatchHistory.csv", .history),
        ("watchhistory-2024.csv", .history),
        ("Favorites.csv", .favorites),
        ("My Favourites.csv", .favorites),
        ("History.csv", .history),
        ("Watched.csv", .history),
        ("Completed.csv", .history),
    ])
    func inferredDestinationFromFilename(filename: String, expected: LibraryCSVImportDestination) {
        let url = URL(fileURLWithPath: "/tmp/\(filename)")
        let inferred = LibraryCSVImportService.inferredDestination(from: url)
        #expect(inferred == expected)
    }

    @Test
    func inferredDestinationReturnsNilForUnknown() {
        let url = URL(fileURLWithPath: "/tmp/random-data.csv")
        let inferred = LibraryCSVImportService.inferredDestination(from: url)
        #expect(inferred == nil)
    }

    @Test
    func folderDedupMergesExistingCaseInsensitive() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-dedup-folder.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder1 = try await database.createLibraryFolder(name: "Watchlist", listType: .watchlist)
        let folder2 = try await database.createLibraryFolder(name: "watchlist", listType: .watchlist)
        let folder3 = try await database.createLibraryFolder(name: "WATCHLIST", listType: .watchlist)

        // All should return the same folder ID (the first one created)
        #expect(folder1.id == folder2.id)
        #expect(folder1.id == folder3.id)
    }

    @Test
    func importsIntoCorrectDestinationBasedOnFilename() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-filename-dest.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A "History" CSV — items should go to history AND watchlist (so they're visible in library)
        let csvURL = try writeCSV(
            """
            Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Year
            tt0133093,,2026-01-15,The Matrix,https://www.imdb.com/title/tt0133093/,movie,8.7,1999
            """,
            name: "History.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        // Use .history destination (simulating what inferredDestination would pick)
        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(destination: .history, importRatings: false)
        )

        #expect(summary.historyImported == 1)
        #expect(summary.watchlistImported == 1) // history items also visible in watchlist

        let history = try await database.fetchWatchHistory(limit: 20)
        #expect(history.count == 1)
        #expect(history.first?.mediaId == "tt0133093")

        let watchlist = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(watchlist.count == 1, "History items should also appear in watchlist")
    }

    /// End-to-end test using the exact format of the user's real IMDb CSV exports.
    @Test
    func importsRealIMDbWatchlistFormat() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-real-watchlist.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Exact format from user's Watchlist.csv
        let csvURL = try writeCSV(
            """
            Position,Const,Created,Modified,Description,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
            1,tt30460310,2026-02-16,2026-02-16,,Spider-Noir,https://www.imdb.com/title/tt30460310/,tvSeries,0.0,,2026,"Mystery, Crime, Action & Adventure",,,
            2,tt30825738,2026-02-16,2026-02-16,,Star Wars: The Mandalorian and Grogu,https://www.imdb.com/title/tt30825738/,movie,0.0,,2026,"Action, Adventure, Science Fiction",,,
            """,
            name: "Watchlist.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let dest = LibraryCSVImportService.inferredDestination(from: csvURL)
        #expect(dest == .watchlist)

        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: dest ?? .auto,
                importRatings: true,
                targetFolderName: "Watchlist"
            )
        )

        #expect(summary.rowsImported == 2)
        #expect(summary.watchlistImported == 2)
        #expect(summary.targetFolderName == "Watchlist")

        let items = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(items.count == 2)

        let media = try await database.fetchMediaItem(id: "tt30460310")
        #expect(media?.title == "Spider-Noir")
        #expect(media?.type == .series)
    }

    /// End-to-end test for Favorites.csv (IMDb ratings format, items with ratings)
    @Test
    func importsRealIMDbFavoritesFormat() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-real-favorites.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Exact format from user's Favorites.csv
        let csvURL = try writeCSV(
            """
            Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
            tt1187043,8,2026-02-24,3 Idiots,https://www.imdb.com/title/tt1187043/,movie,8.0,171,2009,"Drama, Comedy",,,
            tt0988824,10,2026-02-24,Naruto Shippūden,https://www.imdb.com/title/tt0988824/,tvSeries,8.5,25,2007,"Animation, Action & Adventure, Sci-Fi & Fantasy",,,
            """,
            name: "Favorites.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let dest = LibraryCSVImportService.inferredDestination(from: csvURL)
        #expect(dest == .favorites)

        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: dest ?? .auto,
                importRatings: true,
                targetFolderName: "Favorites"
            )
        )

        #expect(summary.rowsImported == 2)
        #expect(summary.favoritesImported == 2)
        #expect(summary.ratingsImported == 2)
    }

    /// Currently Watching.csv — ratings format but many items have NO rating
    @Test
    func importsCurrentlyWatchingWithMixedRatings() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-currently-watching.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
            tt3551096,,2026-02-24,Fresh Off the Boat,https://www.imdb.com/title/tt3551096/,tvSeries,7.2,,2015,Comedy,,,
            tt8622160,5,2026-02-08,Star Trek: Starfleet Academy,https://www.imdb.com/title/tt8622160/,tvSeries,4.8,,2026,"Sci-Fi & Fantasy, Action & Adventure",,,
            """,
            name: "Currently Watching.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let dest = LibraryCSVImportService.inferredDestination(from: csvURL)
        #expect(dest == .watchlist)

        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: dest ?? .auto,
                importRatings: true,
                targetFolderName: "Currently Watching"
            )
        )

        #expect(summary.rowsImported == 2)
        // Both items should land in watchlist (destination overrides auto logic)
        #expect(summary.watchlistImported == 2)
        // Only the one with rating gets a taste event
        #expect(summary.ratingsImported == 1)
    }

    /// History.csv — should go to history, not watchlist
    @Test
    func importsHistoryCSVIntoWatchHistory() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-real-history.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
            tt8622160,5,2026-02-24,Star Trek: Starfleet Academy,https://www.imdb.com/title/tt8622160/,tvSeries,4.8,,2026,"Sci-Fi & Fantasy, Action & Adventure",,,
            tt27497448,,2026-02-24,A Knight of the Seven Kingdoms,https://www.imdb.com/title/tt27497448/,tvSeries,8.5,,2026,"Drama, Sci-Fi & Fantasy, Action & Adventure",,,
            """,
            name: "History.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)
        let dest = LibraryCSVImportService.inferredDestination(from: csvURL)
        #expect(dest == .history)

        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: dest ?? .auto,
                importRatings: true
            )
        )

        #expect(summary.rowsImported == 2)
        #expect(summary.historyImported == 2)
        #expect(summary.watchlistImported == 2) // history items also appear in watchlist
        #expect(summary.favoritesImported == 0)

        let history = try await database.fetchWatchHistory(limit: 20)
        #expect(history.count == 2)

        let watchlist = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(watchlist.count == 2, "History items should also appear in watchlist")
    }

    /// Uses the EXACT content from the user's WatchHistory CSVs to verify import
    @Test
    func importsExactWatchHistoryCurrentlyWatching() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-exact-cw.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = """
        Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
        tt3551096,,2026-02-24,Fresh Off the Boat,https://www.imdb.com/title/tt3551096/,tvSeries,7.2,,2015,Comedy,,,
        tt8622160,5,2026-02-08,Star Trek: Starfleet Academy,https://www.imdb.com/title/tt8622160/,tvSeries,4.8,,2026,"Sci-Fi & Fantasy, Action & Adventure",,,
        tt31938062,9,2026-01-31,The Pitt,https://www.imdb.com/title/tt31938062/,tvSeries,8.7,,2025,Drama,,,
        """
        let csvURL = try writeCSV(content, name: "Currently Watching.csv", in: tempDir)

        let service = LibraryCSVImportService(database: database)

        // Verify destination inference
        let dest = LibraryCSVImportService.inferredDestination(from: csvURL)
        #expect(dest == .watchlist, "Currently Watching should infer .watchlist")

        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: dest ?? .auto,
                importRatings: true,
                promoteLikedRatingsToFavorites: true,
                targetFolderName: "Currently Watching"
            )
        )

        #expect(summary.rowsRead == 3, "Should read 3 rows, got \(summary.rowsRead)")
        #expect(summary.rowsImported == 3, "Should import 3 rows, got \(summary.rowsImported)")
        #expect(summary.rowsSkipped == 0, "Should skip 0 rows, got \(summary.rowsSkipped)")
        #expect(summary.watchlistImported == 3, "Should import 3 to watchlist, got \(summary.watchlistImported)")
        #expect(summary.ratingsImported == 2, "Should import 2 ratings, got \(summary.ratingsImported)")

        // Verify media items were created
        let fresh = try await database.fetchMediaItem(id: "tt3551096")
        #expect(fresh != nil, "Fresh Off the Boat media item should exist")
        #expect(fresh?.title == "Fresh Off the Boat")

        let pitt = try await database.fetchMediaItem(id: "tt31938062")
        #expect(pitt != nil, "The Pitt media item should exist")

        // Verify library entries
        let watchlist = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(watchlist.count == 3, "Should have 3 watchlist entries, got \(watchlist.count)")
    }

    /// Uses exact content from user's WatchHistory/Favorites.csv
    @Test
    func importsExactWatchHistoryFavorites() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-exact-fav.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = """
        Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
        tt1187043,8,2026-02-24,3 Idiots,https://www.imdb.com/title/tt1187043/,movie,8.0,171,2009,"Drama, Comedy",,,
        tt0988824,10,2026-02-24,Naruto Shippūden,https://www.imdb.com/title/tt0988824/,tvSeries,8.5,25,2007,"Animation, Action & Adventure, Sci-Fi & Fantasy",,,
        """
        let csvURL = try writeCSV(content, name: "Favorites.csv", in: tempDir)

        let service = LibraryCSVImportService(database: database)
        let dest = LibraryCSVImportService.inferredDestination(from: csvURL)
        #expect(dest == .favorites)

        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: dest ?? .auto,
                importRatings: true,
                targetFolderName: "Favorites"
            )
        )

        #expect(summary.rowsImported == 2, "Got \(summary.rowsImported)")
        #expect(summary.favoritesImported == 2, "Got \(summary.favoritesImported)")
        #expect(summary.ratingsImported == 2, "Got \(summary.ratingsImported)")

        let favs = try await database.fetchLibraryEntries(listType: .favorites)
        #expect(favs.count == 2, "Got \(favs.count)")
    }

    @Test
    func importsCRLFIMDbFavoritesFormat() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-crlf-favorites.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = [
            "Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors",
            "tt1187043,8,2026-02-24,3 Idiots,https://www.imdb.com/title/tt1187043/,movie,8.0,171,2009,\"Drama, Comedy\",,,",
            "tt0988824,10,2026-02-24,Naruto Shippūden,https://www.imdb.com/title/tt0988824/,tvSeries,8.5,25,2007,\"Animation, Action & Adventure, Sci-Fi & Fantasy\",,,",
        ].joined(separator: "\r\n")

        let csvURL = try writeCSV(content, name: "Favorites.csv", in: tempDir)

        let service = LibraryCSVImportService(database: database)
        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(destination: .favorites, importRatings: true)
        )

        #expect(summary.rowsRead == 2, "CRLF rows should be read, got \(summary.rowsRead)")
        #expect(summary.rowsImported == 2, "CRLF rows should import, got \(summary.rowsImported)")
        #expect(summary.favoritesImported == 2, "CRLF favorites should import, got \(summary.favoritesImported)")
        #expect(summary.ratingsImported == 2, "CRLF ratings should import, got \(summary.ratingsImported)")
    }

    /// Regression test: IMDb WatchHistory CSVs must populate both watch history
    /// and visible library entries.
    @Test
    func watchHistoryCSVsAppearInLibrary() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-watchhistory-regression.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Your Rating,Date Rated,Title,URL,Title Type,IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,Directors
            tt0133093,9,2026-01-15,The Matrix,https://www.imdb.com/title/tt0133093/,movie,8.7,,1999,Action,,,
            tt0903747,10,2026-01-16,Breaking Bad,https://www.imdb.com/title/tt0903747/,tvSeries,9.5,,2008,Drama,,,
            """,
            name: "WatchHistory.csv",
            in: tempDir
        )

        // Verify filename inference routes WatchHistory into history imports.
        let dest = LibraryCSVImportService.inferredDestination(from: csvURL)
        #expect(dest == .history, "WatchHistory should infer .history, got \(String(describing: dest))")

        let service = LibraryCSVImportService(database: database)
        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(
                destination: dest ?? .auto,
                importRatings: true,
                targetFolderName: "WatchHistory"
            )
        )

        #expect(summary.rowsImported == 2)
        #expect(summary.watchlistImported == 2, "Items must appear in watchlist, got \(summary.watchlistImported)")
        #expect(summary.historyImported == 2, "WatchHistory imports should write watch history, got \(summary.historyImported)")
        #expect(summary.ratingsImported == 2)

        // Critical assertions: items are visible in the library and in history.
        let watchlist = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(watchlist.count == 2, "WatchHistory items MUST appear in library, got \(watchlist.count)")

        let history = try await database.fetchWatchHistory(limit: 20)
        #expect(history.count == 2, "WatchHistory items MUST be persisted to history, got \(history.count)")
    }

    /// Ensures standalone "History.csv" still routes to history (+ watchlist for visibility)
    @Test
    func standaloneHistoryCSVStillRoutesToHistory() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-standalone-history.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            Const,Title,URL,Title Type,Year
            tt0133093,The Matrix,https://www.imdb.com/title/tt0133093/,movie,1999
            """,
            name: "History.csv",
            in: tempDir
        )

        let dest = LibraryCSVImportService.inferredDestination(from: csvURL)
        #expect(dest == .history, "Standalone 'History.csv' should infer .history")

        let service = LibraryCSVImportService(database: database)
        let summary = try await service.importCSV(
            from: csvURL,
            options: LibraryCSVImportOptions(destination: dest ?? .auto, importRatings: false)
        )

        #expect(summary.historyImported == 1, "Should create history entry")
        #expect(summary.watchlistImported == 1, "History items should also appear in watchlist for visibility")

        let history = try await database.fetchWatchHistory(limit: 20)
        #expect(history.count == 1)

        let watchlist = try await database.fetchLibraryEntries(listType: .watchlist)
        #expect(watchlist.count == 1, "History items must also be visible in library")
    }

    @Test
    func throwsWhenFileHasNoRecognizableColumns() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "csv-no-columns.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = try writeCSV(
            """
            foo,bar
            baz,qux
            """,
            name: "unknown.csv",
            in: tempDir
        )

        let service = LibraryCSVImportService(database: database)

        do {
            _ = try await service.importCSV(from: csvURL)
            Issue.record("Expected missingHeader when no recognizable columns are present")
        } catch let error as LibraryCSVImportError {
            #expect(error == .missingHeader)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

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
}
