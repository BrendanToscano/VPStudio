import Testing
import Foundation
@testable import VPStudio

// MARK: - Database Layer Tests

@Suite("Episode Watch Tracking - Database")
struct EpisodeWatchTrackingDatabaseTests {

    private func makeDatabase() async throws -> DatabaseManager {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent("episode_watch_test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return database
    }

    // MARK: - fetchEpisodeWatchStates

    @Test func fetchEpisodeWatchStatesReturnsEmptyForNewMedia() async throws {
        let db = try await makeDatabase()
        let states = try await db.fetchEpisodeWatchStates(mediaId: "tt999999")
        #expect(states.isEmpty)
    }

    @Test func fetchEpisodeWatchStatesReturnsSavedEntries() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt100001"

        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: "ep-s01e01", title: "S01E01 - Pilot")
        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: "ep-s01e02", title: "S01E02 - Second")

        let states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states.count == 2)
        #expect(states["ep-s01e01"]?.isCompleted == true)
        #expect(states["ep-s01e02"]?.isCompleted == true)
    }

    @Test func fetchEpisodeWatchStatesIgnoresEntriesWithoutEpisodeId() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt100002"

        // Save a movie-level watch history (no episodeId)
        let movieHistory = WatchHistory(
            id: "\(mediaId)-watched",
            mediaId: mediaId,
            title: "Some Movie",
            progress: 1.0,
            duration: 1.0,
            watchedAt: Date(),
            isCompleted: true
        )
        try await db.saveWatchHistory(movieHistory)

        let states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states.isEmpty)
    }

    @Test func fetchEpisodeWatchStatesKeepsMostRecentPerEpisode() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt100003"
        let episodeId = "ep-s01e01"

        // Save an older entry (incomplete)
        let older = WatchHistory(
            id: "\(mediaId)-\(episodeId)-old",
            mediaId: mediaId,
            episodeId: episodeId,
            title: "S01E01 - Pilot",
            progress: 0.5,
            duration: 1.0,
            watchedAt: Date().addingTimeInterval(-3600),
            isCompleted: false
        )
        try await db.saveWatchHistory(older)

        // Save a newer entry (completed)
        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: episodeId, title: "S01E01 - Pilot")

        let states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states.count == 1)
        // Most recent should be the completed one
        #expect(states[episodeId]?.isCompleted == true)
    }

    @Test func fetchEpisodeWatchStatesDoesNotLeakAcrossMedia() async throws {
        let db = try await makeDatabase()

        try await db.markEpisodeWatched(mediaId: "tt111", episodeId: "ep-1", title: "Ep 1")
        try await db.markEpisodeWatched(mediaId: "tt222", episodeId: "ep-2", title: "Ep 2")

        let states111 = try await db.fetchEpisodeWatchStates(mediaId: "tt111")
        let states222 = try await db.fetchEpisodeWatchStates(mediaId: "tt222")

        #expect(states111.count == 1)
        #expect(states111["ep-1"] != nil)
        #expect(states222.count == 1)
        #expect(states222["ep-2"] != nil)
    }

    // MARK: - markEpisodeWatched

    @Test func markEpisodeWatchedCreatesCompletedEntry() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt200001"
        let episodeId = "ep-s02e05"

        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: episodeId, title: "S02E05 - Title")

        let history = try await db.fetchWatchHistory(mediaId: mediaId, episodeId: episodeId)
        #expect(history != nil)
        #expect(history?.isCompleted == true)
        #expect(history?.progress == 1.0)
        #expect(history?.duration == 1.0)
        #expect(history?.episodeId == episodeId)
        #expect(history?.title == "S02E05 - Title")
    }

    @Test func markEpisodeWatchedIdempotent() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt200002"
        let episodeId = "ep-s01e01"

        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: episodeId, title: "Pilot")
        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: episodeId, title: "Pilot")

        let states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states.count == 1)
    }

    // MARK: - markEpisodeUnwatched

    @Test func markEpisodeUnwatchedDeletesAllEntriesForEpisode() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt300001"
        let episodeId = "ep-s01e03"

        // Create multiple entries for the same episode
        let entry1 = WatchHistory(
            id: "\(mediaId)-\(episodeId)-partial",
            mediaId: mediaId,
            episodeId: episodeId,
            title: "S01E03",
            progress: 0.5,
            duration: 1.0,
            watchedAt: Date().addingTimeInterval(-3600),
            isCompleted: false
        )
        try await db.saveWatchHistory(entry1)
        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: episodeId, title: "S01E03")

        // Verify entries exist
        let beforeStates = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(!beforeStates.isEmpty)

        // Delete
        try await db.markEpisodeUnwatched(mediaId: mediaId, episodeId: episodeId)

        let afterStates = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(afterStates.isEmpty)
    }

    @Test func markEpisodeUnwatchedDoesNotAffectOtherEpisodes() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt300002"

        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: "ep-1", title: "Ep 1")
        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: "ep-2", title: "Ep 2")

        try await db.markEpisodeUnwatched(mediaId: mediaId, episodeId: "ep-1")

        let states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states.count == 1)
        #expect(states["ep-2"]?.isCompleted == true)
        #expect(states["ep-1"] == nil)
    }

    @Test func markEpisodeUnwatchedDoesNotAffectOtherMedia() async throws {
        let db = try await makeDatabase()

        try await db.markEpisodeWatched(mediaId: "tt-a", episodeId: "ep-1", title: "Ep 1 of A")
        try await db.markEpisodeWatched(mediaId: "tt-b", episodeId: "ep-1", title: "Ep 1 of B")

        try await db.markEpisodeUnwatched(mediaId: "tt-a", episodeId: "ep-1")

        let statesA = try await db.fetchEpisodeWatchStates(mediaId: "tt-a")
        let statesB = try await db.fetchEpisodeWatchStates(mediaId: "tt-b")
        #expect(statesA.isEmpty)
        #expect(statesB.count == 1)
    }

    @Test func markEpisodeUnwatchedNoOpForNonexistent() async throws {
        let db = try await makeDatabase()
        // Should not throw
        try await db.markEpisodeUnwatched(mediaId: "tt-nonexistent", episodeId: "ep-nonexistent")
    }

    // MARK: - Round-trip workflow

    @Test func watchUnwatchRewatchRoundTrip() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt400001"
        let episodeId = "ep-s03e07"

        // 1. Mark watched
        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: episodeId, title: "Episode 7")
        var states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states[episodeId]?.isCompleted == true)

        // 2. Mark unwatched
        try await db.markEpisodeUnwatched(mediaId: mediaId, episodeId: episodeId)
        states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states[episodeId] == nil)

        // 3. Mark watched again
        try await db.markEpisodeWatched(mediaId: mediaId, episodeId: episodeId, title: "Episode 7")
        states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states[episodeId]?.isCompleted == true)
    }

    @Test func bulkMarkAndUnmarkSeason() async throws {
        let db = try await makeDatabase()
        let mediaId = "tt500001"
        let episodeIds = (1...10).map { "ep-s01e\(String(format: "%02d", $0))" }

        // Mark all watched
        for (i, epId) in episodeIds.enumerated() {
            try await db.markEpisodeWatched(mediaId: mediaId, episodeId: epId, title: "Episode \(i + 1)")
        }

        var states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states.count == 10)
        for epId in episodeIds {
            #expect(states[epId]?.isCompleted == true)
        }

        // Unmark all
        for epId in episodeIds {
            try await db.markEpisodeUnwatched(mediaId: mediaId, episodeId: epId)
        }

        states = try await db.fetchEpisodeWatchStates(mediaId: mediaId)
        #expect(states.isEmpty)
    }
}

// MARK: - ViewModel Layer Tests

@Suite("Episode Watch Tracking - ViewModel")
struct EpisodeWatchTrackingViewModelTests {

    private func makeDatabase() async throws -> DatabaseManager {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent("episode_vm_test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return database
    }

    private func makeSeriesItem(id: String, title: String) -> MediaItem {
        MediaItem(id: id, type: .series, title: title)
    }

    private func makeMovieItem(id: String, title: String) -> MediaItem {
        MediaItem(id: id, type: .movie, title: title)
    }

    private func makeEpisode(id: String, seasonNumber: Int, episodeNumber: Int, title: String? = nil) -> Episode {
        Episode(
            id: id,
            mediaId: "tt-test",
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            title: title
        )
    }

    @MainActor
    @Test func loadEpisodeWatchStatesPopulatesDict() async throws {
        let db = try await makeDatabase()
        let appState = AppState(database: db)
        let vm = DetailViewModel(appState: appState)

        vm.mediaItem = makeSeriesItem(id: "tt-test", title: "Test Show")

        // Pre-seed watch data
        try await db.markEpisodeWatched(mediaId: "tt-test", episodeId: "ep-1", title: "Ep 1")
        try await db.markEpisodeWatched(mediaId: "tt-test", episodeId: "ep-2", title: "Ep 2")

        await vm.loadEpisodeWatchStates()

        #expect(vm.episodeWatchStates.count == 2)
        #expect(vm.episodeWatchStates["ep-1"]?.isCompleted == true)
        #expect(vm.episodeWatchStates["ep-2"]?.isCompleted == true)
    }

    @MainActor
    @Test func loadEpisodeWatchStatesNoOpForMovies() async throws {
        let db = try await makeDatabase()
        let appState = AppState(database: db)
        let vm = DetailViewModel(appState: appState)

        vm.mediaItem = makeMovieItem(id: "tt-movie", title: "Test Movie")

        try await db.markEpisodeWatched(mediaId: "tt-movie", episodeId: "ep-1", title: "Ep 1")

        await vm.loadEpisodeWatchStates()

        // Should remain empty since it's a movie
        #expect(vm.episodeWatchStates.isEmpty)
    }

    @MainActor
    @Test func toggleEpisodeWatchedMarksUnwatchedAsWatched() async throws {
        let db = try await makeDatabase()
        let appState = AppState(database: db)
        let vm = DetailViewModel(appState: appState)

        vm.mediaItem = makeSeriesItem(id: "tt-toggle", title: "Toggle Show")

        let episode = makeEpisode(id: "ep-toggle-1", seasonNumber: 1, episodeNumber: 1, title: "Pilot")

        #expect(vm.episodeWatchStates["ep-toggle-1"] == nil)

        await vm.toggleEpisodeWatched(episode)

        #expect(vm.episodeWatchStates["ep-toggle-1"]?.isCompleted == true)
    }

    @MainActor
    @Test func toggleEpisodeWatchedMarksWatchedAsUnwatched() async throws {
        let db = try await makeDatabase()
        let appState = AppState(database: db)
        let vm = DetailViewModel(appState: appState)

        vm.mediaItem = makeSeriesItem(id: "tt-toggle2", title: "Toggle Show 2")

        let episode = makeEpisode(id: "ep-toggle-2", seasonNumber: 1, episodeNumber: 1, title: "Pilot")

        // Pre-mark as watched
        try await db.markEpisodeWatched(mediaId: "tt-toggle2", episodeId: "ep-toggle-2", title: "S01E01 - Pilot")
        await vm.loadEpisodeWatchStates()
        #expect(vm.episodeWatchStates["ep-toggle-2"]?.isCompleted == true)

        // Toggle off
        await vm.toggleEpisodeWatched(episode)

        #expect(vm.episodeWatchStates["ep-toggle-2"] == nil)
    }

    @MainActor
    @Test func markSeasonWatchedMarksAllEpisodes() async throws {
        let db = try await makeDatabase()
        let appState = AppState(database: db)
        let vm = DetailViewModel(appState: appState)

        vm.mediaItem = makeSeriesItem(id: "tt-season", title: "Season Show")

        let episodes = (1...5).map { makeEpisode(id: "ep-s1e\($0)", seasonNumber: 1, episodeNumber: $0, title: "Ep \($0)") }
        vm.episodes = episodes

        // Mark one as already watched
        try await db.markEpisodeWatched(mediaId: "tt-season", episodeId: "ep-s1e1", title: "S01E01 - Ep 1")
        await vm.loadEpisodeWatchStates()

        await vm.markSeasonWatched()

        #expect(vm.episodeWatchStates.count == 5)
        for ep in episodes {
            #expect(vm.episodeWatchStates[ep.id]?.isCompleted == true)
        }
    }

    @MainActor
    @Test func markSeasonUnwatchedClearsAllEpisodes() async throws {
        let db = try await makeDatabase()
        let appState = AppState(database: db)
        let vm = DetailViewModel(appState: appState)

        vm.mediaItem = makeSeriesItem(id: "tt-unseason", title: "Unseason Show")

        let episodes = (1...3).map { makeEpisode(id: "ep-us-e\($0)", seasonNumber: 1, episodeNumber: $0, title: "Ep \($0)") }
        vm.episodes = episodes

        // Mark all as watched
        for ep in episodes {
            try await db.markEpisodeWatched(mediaId: "tt-unseason", episodeId: ep.id, title: ep.displayTitle)
        }
        await vm.loadEpisodeWatchStates()
        #expect(vm.episodeWatchStates.count == 3)

        await vm.markSeasonUnwatched()

        // All current season episodes should be cleared from the local state
        for ep in episodes {
            #expect(vm.episodeWatchStates[ep.id] == nil)
        }

        // Verify DB is also cleared
        let dbStates = try await db.fetchEpisodeWatchStates(mediaId: "tt-unseason")
        #expect(dbStates.isEmpty)
    }

    @MainActor
    @Test func markSeasonUnwatchedPreservesOtherSeasonData() async throws {
        let db = try await makeDatabase()
        let appState = AppState(database: db)
        let vm = DetailViewModel(appState: appState)

        vm.mediaItem = makeSeriesItem(id: "tt-multi", title: "Multi Season")

        // Mark episodes from season 1 and season 2
        try await db.markEpisodeWatched(mediaId: "tt-multi", episodeId: "s1e1", title: "S1 E1")
        try await db.markEpisodeWatched(mediaId: "tt-multi", episodeId: "s2e1", title: "S2 E1")
        await vm.loadEpisodeWatchStates()
        #expect(vm.episodeWatchStates.count == 2)

        // Set current episodes to only season 1
        vm.episodes = [makeEpisode(id: "s1e1", seasonNumber: 1, episodeNumber: 1)]

        await vm.markSeasonUnwatched()

        // Season 2 data should still be in the local dict
        #expect(vm.episodeWatchStates["s1e1"] == nil)
        #expect(vm.episodeWatchStates["s2e1"]?.isCompleted == true)
    }

    @MainActor
    @Test func episodeWatchStatesStartsEmpty() async throws {
        let appState = AppState(testHooks: .init())
        let vm = DetailViewModel(appState: appState)
        #expect(vm.episodeWatchStates.isEmpty)
    }

    @MainActor
    @Test func loadEpisodeWatchStatesNoOpWhenMediaItemNil() async throws {
        let db = try await makeDatabase()
        let appState = AppState(database: db)
        let vm = DetailViewModel(appState: appState)

        // No mediaItem set
        await vm.loadEpisodeWatchStates()
        #expect(vm.episodeWatchStates.isEmpty)
    }

    @MainActor
    @Test func toggleEpisodeWatchedNoOpWhenMediaItemNil() async throws {
        let appState = AppState(testHooks: .init())
        let vm = DetailViewModel(appState: appState)

        let episode = makeEpisode(id: "ep-1", seasonNumber: 1, episodeNumber: 1)
        await vm.toggleEpisodeWatched(episode)
        #expect(vm.episodeWatchStates.isEmpty)
    }

    @MainActor
    @Test func markSeasonWatchedNoOpWhenMediaItemNil() async throws {
        let appState = AppState(testHooks: .init())
        let vm = DetailViewModel(appState: appState)

        vm.episodes = [makeEpisode(id: "ep-1", seasonNumber: 1, episodeNumber: 1)]
        await vm.markSeasonWatched()
        #expect(vm.episodeWatchStates.isEmpty)
    }

    @MainActor
    @Test func markSeasonUnwatchedNoOpWhenMediaItemNil() async throws {
        let appState = AppState(testHooks: .init())
        let vm = DetailViewModel(appState: appState)

        vm.episodes = [makeEpisode(id: "ep-1", seasonNumber: 1, episodeNumber: 1)]
        await vm.markSeasonUnwatched()
        #expect(vm.episodeWatchStates.isEmpty)
    }
}
