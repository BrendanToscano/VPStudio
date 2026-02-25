import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct AssistantContextAssemblerTests {

    // MARK: - Helpers

    private func makeTemporaryDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, tempDir)
    }

    // MARK: - Recency Decay

    @Test
    func recencyDecayTodayIsOne() {
        let now = Date()
        let decay = AssistantContextAssembler.recencyDecay(from: now, now: now)
        #expect(decay == 1.0)
    }

    @Test
    func recencyDecayAt45DaysIsAboutHalf() {
        let now = Date()
        let date = now.addingTimeInterval(-45 * 86400)
        let decay = AssistantContextAssembler.recencyDecay(from: date, now: now)
        #expect(abs(decay - 0.5) < 0.01)
    }

    @Test
    func recencyDecayAt90DaysIsFloor() {
        let now = Date()
        let date = now.addingTimeInterval(-90 * 86400)
        let decay = AssistantContextAssembler.recencyDecay(from: date, now: now)
        #expect(abs(decay - 0.1) < 0.001)
    }

    @Test
    func recencyDecayBeyond90DaysIsFloor() {
        let now = Date()
        let date = now.addingTimeInterval(-180 * 86400)
        let decay = AssistantContextAssembler.recencyDecay(from: date, now: now)
        #expect(decay == AssistantContextAssembler.recencyFloor)
    }

    @Test
    func recencyDecayAt30DaysIsAboutTwoThirds() {
        let now = Date()
        let date = now.addingTimeInterval(-30 * 86400)
        let decay = AssistantContextAssembler.recencyDecay(from: date, now: now)
        let expected = 1.0 - (30.0 / 90.0) // ~0.667
        #expect(abs(decay - expected) < 0.01)
    }

    // MARK: - Snapshot Staleness

    @Test
    func snapshotIsStaleAfter24Hours() {
        let old = AssistantContextAssembler.ContextSnapshot(
            contextNotes: ["test"],
            candidateTitles: [],
            assembledAt: Date().addingTimeInterval(-86401) // 24h + 1s
        )
        #expect(old.isStale)
    }

    @Test
    func snapshotIsNotStaleBefore24Hours() {
        let fresh = AssistantContextAssembler.ContextSnapshot(
            contextNotes: ["test"],
            candidateTitles: [],
            assembledAt: Date().addingTimeInterval(-86399) // 24h - 1s
        )
        #expect(!fresh.isStale)
    }

    @Test
    func emptySnapshotIsStale() {
        let empty = AssistantContextAssembler.ContextSnapshot.empty
        #expect(empty.isStale)
    }

    // MARK: - Assembly with Empty Database

    @Test
    func assemblyWithEmptyDatabaseProducesValidButSparseContext() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-empty.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        #expect(snapshot.contextNotes.isEmpty)
        #expect(snapshot.candidateTitles.isEmpty)
        #expect(!snapshot.isStale)
    }

    // MARK: - Assembly with Data

    @Test
    func assemblyIncludesTasteProfileGenres() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-profile.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let profile = UserTasteProfile(
            id: "default",
            likedGenres: ["Sci-Fi", "Thriller"],
            dislikedGenres: ["Romance"],
            preferredDecades: ["2010s"],
            preferredLanguages: ["English"]
        )
        try await database.saveUserTasteProfile(profile)

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        let hasLikedGenres = snapshot.contextNotes.contains { $0.contains("Liked genres") && $0.contains("Sci-Fi") }
        let hasDislikedGenres = snapshot.contextNotes.contains { $0.contains("Disliked genres") && $0.contains("Romance") }
        let hasDecades = snapshot.contextNotes.contains { $0.contains("Preferred decades") && $0.contains("2010s") }

        #expect(hasLikedGenres)
        #expect(hasDislikedGenres)
        #expect(hasDecades)
    }

    @Test
    func assemblyIncludesWatchHistoryWithRecencyDecay() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-history.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let recent = WatchHistory(
            id: "h1",
            mediaId: "tt0133093",
            title: "The Matrix",
            progress: 8000,
            duration: 8160,
            watchedAt: Date().addingTimeInterval(-2 * 86400),
            isCompleted: true
        )
        try await database.saveWatchHistory(recent)

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        let hasRecentWatched = snapshot.contextNotes.contains { $0.contains("Recently watched") && $0.contains("The Matrix") }
        #expect(hasRecentWatched)
        #expect(snapshot.candidateTitles.contains("The Matrix"))
    }

    @Test
    func assemblyIncludesRatedTitles() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-ratings.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let event = TasteEvent(
            id: "te1",
            mediaId: "tt0133093",
            eventType: .rated,
            feedbackScale: .oneToTen,
            feedbackValue: 9,
            metadata: ["title": "The Matrix"],
            createdAt: Date().addingTimeInterval(-5 * 86400)
        )
        try await database.saveTasteEvent(event)

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        let hasLikedTitles = snapshot.contextNotes.contains { $0.contains("Liked titles") && $0.contains("The Matrix") }
        #expect(hasLikedTitles)
        #expect(snapshot.candidateTitles.contains("The Matrix"))
    }

    @Test
    func assemblyIncludesWatchlistAndFavorites() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-library.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a media item
        let item = MediaItem(
            id: "tt0110912",
            type: .movie,
            title: "Pulp Fiction",
            year: 1994,
            lastFetched: Date()
        )
        try await database.saveMediaItem(item)

        // Add to watchlist
        let watchlistFolderID = try await database.fetchSystemLibraryFolderID(listType: .watchlist)
        let entry = UserLibraryEntry(
            id: "tt0110912-watchlist",
            mediaId: "tt0110912",
            folderId: watchlistFolderID,
            listType: .watchlist,
            addedAt: Date()
        )
        try await database.addToLibrary(entry)

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        let hasWatchlist = snapshot.contextNotes.contains { $0.contains("Watchlist") && $0.contains("Pulp Fiction") }
        #expect(hasWatchlist)
        #expect(snapshot.candidateTitles.contains("Pulp Fiction"))
    }

    @Test
    func assemblyIncludesLibraryFolderNames() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-folders.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        _ = try await database.createLibraryFolder(name: "IMDb Watchlist 2024", listType: .watchlist)

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        let hasFolders = snapshot.contextNotes.contains { $0.contains("Library folders") && $0.contains("IMDb Watchlist 2024") }
        #expect(hasFolders)
    }

    @Test
    func assemblyIncludesRecentSearches() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-searches.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let searches = ["interstellar", "blade runner", "dune"]
        let data = try JSONEncoder().encode(searches)
        let json = String(data: data, encoding: .utf8)!
        try await database.setSetting(key: SettingsKeys.recentSearches, value: json)

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        let hasSearches = snapshot.contextNotes.contains { $0.contains("Recent searches") && $0.contains("interstellar") }
        #expect(hasSearches)
    }

    // MARK: - Token Budget / Limiting

    @Test
    func contextNotesRespectMaxBudget() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-budget.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create many watch history entries to produce many notes
        for i in 0..<200 {
            let history = WatchHistory(
                id: "h\(i)",
                mediaId: "tt\(String(format: "%07d", i))",
                title: "Movie \(i)",
                progress: 100,
                duration: 100,
                watchedAt: Date().addingTimeInterval(-Double(i) * 86400),
                isCompleted: true
            )
            try await database.saveWatchHistory(history)
        }

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        #expect(snapshot.contextNotes.count <= AssistantContextAssembler.maxContextNotes)
        #expect(snapshot.candidateTitles.count <= AssistantContextAssembler.maxCandidateTitles)
    }

    // MARK: - Caching

    @Test
    func cachedOrAssembleReturnsCachedWhenFresh() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-cache.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let assembler = AssistantContextAssembler()

        // First call assembles fresh
        let first = try await assembler.cachedOrAssemble(from: database)
        #expect(!first.isStale)

        // Add data that would change the output
        let profile = UserTasteProfile(likedGenres: ["Action"])
        try await database.saveUserTasteProfile(profile)

        // Second call returns the cached version (no Action genre)
        let second = try await assembler.cachedOrAssemble(from: database)
        #expect(first.assembledAt == second.assembledAt)
    }

    @Test
    func invalidateCacheForcesRebuild() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-invalidate.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let assembler = AssistantContextAssembler()

        let first = try await assembler.cachedOrAssemble(from: database)

        // Add data
        let profile = UserTasteProfile(likedGenres: ["Action"])
        try await database.saveUserTasteProfile(profile)

        // Invalidate and rebuild
        await assembler.invalidateCache()
        let second = try await assembler.cachedOrAssemble(from: database)

        let hasAction = second.contextNotes.contains { $0.contains("Action") }
        #expect(hasAction)
        #expect(second.assembledAt >= first.assembledAt)
    }

    // MARK: - Snapshot Persistence

    @Test
    func snapshotPersistsToAndLoadsFromDatabase() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-persist.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = AssistantContextAssembler.ContextSnapshot(
            contextNotes: ["Liked genres: Sci-Fi", "Watchlist (3 titles): Dune, Alien, Blade Runner"],
            candidateTitles: ["Dune", "Alien", "Blade Runner"],
            assembledAt: Date()
        )

        let record = try AIContextSnapshot.from(original)
        try await database.saveContextSnapshot(record)

        let fetched = try await database.fetchLatestContextSnapshot()
        #expect(fetched != nil)

        let decoded = try fetched!.decoded()
        #expect(decoded.contextNotes == original.contextNotes)
        #expect(decoded.candidateTitles == original.candidateTitles)
    }

    @Test
    func saveContextSnapshotReplacesExisting() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-replace.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let first = AssistantContextAssembler.ContextSnapshot(
            contextNotes: ["First"],
            candidateTitles: [],
            assembledAt: Date().addingTimeInterval(-100)
        )
        try await database.saveContextSnapshot(try AIContextSnapshot.from(first))

        let second = AssistantContextAssembler.ContextSnapshot(
            contextNotes: ["Second"],
            candidateTitles: ["Title"],
            assembledAt: Date()
        )
        try await database.saveContextSnapshot(try AIContextSnapshot.from(second))

        let fetched = try await database.fetchLatestContextSnapshot()
        let decoded = try fetched!.decoded()
        #expect(decoded.contextNotes == ["Second"])
        #expect(decoded.candidateTitles == ["Title"])
    }

    // MARK: - Disliked Titles in Ratings

    @Test
    func assemblyIncludesDislikedRatings() async throws {
        let (database, tempDir) = try await makeTemporaryDatabase(named: "assembler-disliked.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let event = TasteEvent(
            id: "te-disliked",
            mediaId: "tt9999999",
            eventType: .rated,
            feedbackScale: .oneToTen,
            feedbackValue: 2,
            metadata: ["title": "Bad Movie"],
            createdAt: Date()
        )
        try await database.saveTasteEvent(event)

        let assembler = AssistantContextAssembler()
        let snapshot = try await assembler.assembleContext(from: database)

        let hasDisliked = snapshot.contextNotes.contains { $0.contains("Disliked titles") && $0.contains("Bad Movie") }
        #expect(hasDisliked)
    }
}
