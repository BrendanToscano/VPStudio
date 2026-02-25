import Testing
import Foundation
@testable import VPStudio

private func makeTemporaryDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbURL = tempDir.appendingPathComponent(fileName)
    let database = try DatabaseManager(path: dbURL.path)
    try await database.migrate()
    return (database, tempDir)
}

// MARK: - Database Media Cache Tests

@Suite(.serialized)
struct DatabaseMediaCacheTests {

    @Test func saveAndFetchMediaItem() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "media-cache.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let item = MediaItem(
            id: "movie-1", type: .movie, title: "Dune",
            year: 2021, genres: ["Sci-Fi", "Drama"], imdbRating: 8.0, runtime: 155
        )
        try await db.saveMediaItem(item)

        let fetched = try await db.fetchMediaItem(id: "movie-1")
        #expect(fetched != nil)
        #expect(fetched?.title == "Dune")
        #expect(fetched?.year == 2021)
        #expect(fetched?.genres == ["Sci-Fi", "Drama"])
        #expect(fetched?.imdbRating == 8.0)
        #expect(fetched?.runtime == 155)
    }

    @Test func fetchMediaItemReturnsNilForMissingId() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "media-cache-miss.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fetched = try await db.fetchMediaItem(id: "nonexistent")
        #expect(fetched == nil)
    }

    @Test func saveMediaItemOverwritesExisting() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "media-cache-update.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = MediaItem(id: "movie-1", type: .movie, title: "Dune", year: 2021)
        try await db.saveMediaItem(original)

        let updated = MediaItem(id: "movie-1", type: .movie, title: "Dune: Part Two", year: 2024)
        try await db.saveMediaItem(updated)

        let fetched = try await db.fetchMediaItem(id: "movie-1")
        #expect(fetched?.title == "Dune: Part Two")
        #expect(fetched?.year == 2024)
    }
}

// MARK: - Database Watch History Tests

@Suite(.serialized)
struct DatabaseWatchHistoryTests {

    @Test func saveAndFetchWatchHistory() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "watch-history.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let history = WatchHistory(
            id: "wh-1", mediaId: "movie-1", title: "Dune",
            progress: 3600, duration: 7200, watchedAt: Date(), isCompleted: false
        )
        try await db.saveWatchHistory(history)

        let results = try await db.fetchWatchHistory(limit: 10)
        #expect(results.count == 1)
        #expect(results.first?.mediaId == "movie-1")
        #expect(results.first?.progress == 3600)
    }

    @Test func fetchWatchHistoryByMediaId() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "watch-history-media.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let h1 = WatchHistory(id: "wh-1", mediaId: "movie-1", title: "A", progress: 100, duration: 200, watchedAt: Date(), isCompleted: false)
        let h2 = WatchHistory(id: "wh-2", mediaId: "movie-2", title: "B", progress: 50, duration: 100, watchedAt: Date(), isCompleted: false)
        try await db.saveWatchHistory(h1)
        try await db.saveWatchHistory(h2)

        let result = try await db.fetchWatchHistory(mediaId: "movie-1")
        #expect(result?.id == "wh-1")
    }

    @Test func fetchWatchHistoryRespectsLimit() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "watch-history-limit.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for i in 0..<5 {
            let h = WatchHistory(id: "wh-\(i)", mediaId: "m-\(i)", title: "Movie \(i)", progress: 0, duration: 100, watchedAt: Date().addingTimeInterval(Double(i)), isCompleted: false)
            try await db.saveWatchHistory(h)
        }

        let results = try await db.fetchWatchHistory(limit: 3)
        #expect(results.count == 3)
    }
}

// MARK: - Database Retention Policy Tests

@Suite(.serialized)
struct DatabaseRetentionPolicyTests {

    @Test func watchHistoryRetentionAppliesTTLThenCap() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "watch-history-retention.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oneDay: TimeInterval = 24 * 60 * 60

        let entries = [
            WatchHistory(id: "wh-expired-1", mediaId: "movie-1", title: "Expired 1", progress: 0, duration: 100, watchedAt: now.addingTimeInterval(-40 * oneDay), isCompleted: false),
            WatchHistory(id: "wh-expired-2", mediaId: "movie-2", title: "Expired 2", progress: 0, duration: 100, watchedAt: now.addingTimeInterval(-15 * oneDay), isCompleted: false),
            WatchHistory(id: "wh-older", mediaId: "movie-3", title: "Older", progress: 0, duration: 100, watchedAt: now.addingTimeInterval(-6 * oneDay), isCompleted: false),
            WatchHistory(id: "wh-newer", mediaId: "movie-4", title: "Newer", progress: 0, duration: 100, watchedAt: now.addingTimeInterval(-2 * 60 * 60), isCompleted: false),
            WatchHistory(id: "wh-newest", mediaId: "movie-5", title: "Newest", progress: 0, duration: 100, watchedAt: now.addingTimeInterval(-1 * 60 * 60), isCompleted: false),
        ]

        for entry in entries {
            try await db.saveWatchHistory(entry)
        }

        let deleted = try await db.applyWatchHistoryRetentionPolicy(
            maxEntries: 2,
            ttl: 7 * oneDay,
            now: now
        )
        #expect(deleted == 3)

        let retained = try await db.fetchWatchHistory(limit: 10)
        #expect(retained.map(\.id) == ["wh-newest", "wh-newer"])
    }

    @Test func tasteEventsRetentionAppliesTTLAndCapForScopedUser() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "taste-events-retention.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oneDay: TimeInterval = 24 * 60 * 60

        let defaultUserEvents = [
            TasteEvent(id: "evt-default-expired", userId: "default", mediaId: "movie-1", eventType: .watched, createdAt: now.addingTimeInterval(-30 * oneDay)),
            TasteEvent(id: "evt-default-older", userId: "default", mediaId: "movie-2", eventType: .watched, createdAt: now.addingTimeInterval(-2 * oneDay)),
            TasteEvent(id: "evt-default-newer", userId: "default", mediaId: "movie-3", eventType: .watched, createdAt: now.addingTimeInterval(-2 * 60 * 60)),
            TasteEvent(id: "evt-default-newest", userId: "default", mediaId: "movie-4", eventType: .watched, createdAt: now.addingTimeInterval(-1 * 60 * 60)),
        ]
        let secondaryUserEvents = [
            TasteEvent(id: "evt-secondary-expired", userId: "secondary", mediaId: "movie-5", eventType: .watched, createdAt: now.addingTimeInterval(-30 * oneDay)),
            TasteEvent(id: "evt-secondary-newest", userId: "secondary", mediaId: "movie-6", eventType: .watched, createdAt: now.addingTimeInterval(-30 * 60)),
        ]

        for event in defaultUserEvents + secondaryUserEvents {
            try await db.saveTasteEvent(event)
        }

        let deleted = try await db.applyTasteEventsRetentionPolicy(
            userId: "default",
            maxEntries: 2,
            ttl: 7 * oneDay,
            now: now
        )
        #expect(deleted == 2)

        let defaultRetained = try await db.fetchTasteEvents(userId: "default", limit: 10)
        #expect(defaultRetained.map(\.id) == ["evt-default-newest", "evt-default-newer"])

        let secondaryRetained = try await db.fetchTasteEvents(userId: "secondary", limit: 10)
        #expect(secondaryRetained.map(\.id) == ["evt-secondary-newest", "evt-secondary-expired"])
    }

    @Test func saveWatchHistoryAutomaticallyPrunesExpiredEntries() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "watch-history-auto-retention.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oneDay: TimeInterval = 24 * 60 * 60
        let now = Date()
        let stale = WatchHistory(
            id: "wh-stale-auto",
            mediaId: "movie-stale",
            title: "Stale",
            progress: 10,
            duration: 100,
            watchedAt: now.addingTimeInterval(-400 * oneDay),
            isCompleted: false
        )
        let fresh = WatchHistory(
            id: "wh-fresh-auto",
            mediaId: "movie-fresh",
            title: "Fresh",
            progress: 20,
            duration: 100,
            watchedAt: now,
            isCompleted: false
        )

        try await db.saveWatchHistory(stale)
        try await db.saveWatchHistory(fresh)

        let retained = try await db.fetchWatchHistory(limit: 10)
        #expect(retained.map(\.id) == [fresh.id])
    }

    @Test func saveTasteEventAutomaticallyPrunesExpiredEntriesForUser() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "taste-events-auto-retention.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oneDay: TimeInterval = 24 * 60 * 60
        let now = Date()
        let stale = TasteEvent(
            id: "evt-stale-auto",
            userId: "default",
            mediaId: "movie-stale",
            eventType: .rated,
            feedbackScale: .likeDislike,
            feedbackValue: 1,
            createdAt: now.addingTimeInterval(-400 * oneDay)
        )
        let fresh = TasteEvent(
            id: "evt-fresh-auto",
            userId: "default",
            mediaId: "movie-fresh",
            eventType: .rated,
            feedbackScale: .likeDislike,
            feedbackValue: 1,
            createdAt: now
        )

        try await db.saveTasteEvent(stale)
        try await db.saveTasteEvent(fresh)

        let retained = try await db.fetchTasteEvents(userId: "default", limit: 10)
        #expect(retained.map(\.id) == [fresh.id])
    }
}

// MARK: - Database Episodes Tests

@Suite(.serialized)
struct DatabaseEpisodesTests {

    @Test func saveAndFetchEpisodes() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "episodes.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let episodes = [
            Episode(id: "ep-1", mediaId: "show-1", seasonNumber: 1, episodeNumber: 1, title: "Pilot"),
            Episode(id: "ep-2", mediaId: "show-1", seasonNumber: 1, episodeNumber: 2, title: "Second"),
            Episode(id: "ep-3", mediaId: "show-1", seasonNumber: 2, episodeNumber: 1, title: "S2 Premiere"),
        ]
        try await db.saveEpisodes(episodes)

        let s1Episodes = try await db.fetchEpisodes(mediaId: "show-1", season: 1)
        #expect(s1Episodes.count == 2)
        #expect(s1Episodes[0].episodeNumber == 1)
        #expect(s1Episodes[1].episodeNumber == 2)

        let s2Episodes = try await db.fetchEpisodes(mediaId: "show-1", season: 2)
        #expect(s2Episodes.count == 1)
    }

    @Test func fetchEpisodesReturnsEmptyForMissingSeason() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "episodes-empty.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let episodes = try await db.fetchEpisodes(mediaId: "nonexistent", season: 1)
        #expect(episodes.isEmpty)
    }
}

// MARK: - Database Download Tasks Tests

@Suite(.serialized)
struct DatabaseDownloadTaskTests {

    @Test func saveAndFetchDownloadTask() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "downloads.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let task = DownloadTask(
            id: "dl-1", mediaId: "movie-1",
            streamURL: "https://cdn.example.com/movie.mkv",
            fileName: "movie.mkv", status: .queued
        )
        try await db.saveDownloadTask(task)

        let fetched = try await db.fetchDownloadTask(id: "dl-1")
        #expect(fetched != nil)
        #expect(fetched?.status == .queued)
        #expect(fetched?.fileName == "movie.mkv")
    }

    @Test func updateDownloadTaskStatus() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "downloads-status.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let task = DownloadTask(id: "dl-1", mediaId: "m1", streamURL: "https://x.com/a.mkv", fileName: "a.mkv")
        try await db.saveDownloadTask(task)

        try await db.updateDownloadTaskStatus(id: "dl-1", status: .downloading)
        let updated = try await db.fetchDownloadTask(id: "dl-1")
        #expect(updated?.status == .downloading)

        try await db.updateDownloadTaskStatus(id: "dl-1", status: .failed, errorMessage: "Network error")
        let failed = try await db.fetchDownloadTask(id: "dl-1")
        #expect(failed?.status == .failed)
        #expect(failed?.errorMessage == "Network error")
    }

    @Test func updateDownloadTaskProgress() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "downloads-progress.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let task = DownloadTask(id: "dl-1", mediaId: "m1", streamURL: "https://x.com/a.mkv", fileName: "a.mkv")
        try await db.saveDownloadTask(task)

        try await db.updateDownloadTaskProgress(id: "dl-1", progress: 0.5, bytesWritten: 500_000, totalBytes: 1_000_000)
        let updated = try await db.fetchDownloadTask(id: "dl-1")
        #expect(abs((updated?.progress ?? 0) - 0.5) < 0.001)
        #expect(updated?.bytesWritten == 500_000)
        #expect(updated?.totalBytes == 1_000_000)
    }

    @Test func deleteDownloadTask() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "downloads-delete.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let task = DownloadTask(id: "dl-1", mediaId: "m1", streamURL: "https://x.com/a.mkv", fileName: "a.mkv")
        try await db.saveDownloadTask(task)
        try await db.deleteDownloadTask(id: "dl-1")

        let fetched = try await db.fetchDownloadTask(id: "dl-1")
        #expect(fetched == nil)
    }

    @Test func fetchDownloadTasksOrdersByUpdatedAtDescending() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "downloads-order.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let now = Date()
        for i in 0..<3 {
            let task = DownloadTask(
                id: "dl-\(i)", mediaId: "m\(i)",
                streamURL: "https://x.com/\(i).mkv", fileName: "\(i).mkv",
                createdAt: now, updatedAt: now.addingTimeInterval(Double(i) * 60)
            )
            try await db.saveDownloadTask(task)
        }

        let tasks = try await db.fetchDownloadTasks()
        #expect(tasks.count == 3)
        #expect(tasks[0].id == "dl-2") // most recently updated first
    }
}

// MARK: - Database Environment Assets Tests

@Suite(.serialized)
struct DatabaseEnvironmentAssetTests {

    @Test func saveAndFetchEnvironmentAssets() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "env-assets.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let asset = EnvironmentAsset(
            id: "env-1", name: "Theater", sourceType: .bundled,
            assetPath: "/theater.usdz", isActive: true
        )
        try await db.saveEnvironmentAsset(asset)

        let assets = try await db.fetchEnvironmentAssets()
        #expect(assets.count == 1)
        #expect(assets.first?.name == "Theater")
    }

    @Test func setActiveEnvironmentDeactivatesOthers() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "env-assets-active.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let a1 = EnvironmentAsset(id: "env-1", name: "Theater", sourceType: .bundled, assetPath: "/a.usdz", isActive: true)
        let a2 = EnvironmentAsset(id: "env-2", name: "Void", sourceType: .bundled, assetPath: "/b.usdz", isActive: false)
        try await db.saveEnvironmentAsset(a1)
        try await db.saveEnvironmentAsset(a2)

        try await db.setActiveEnvironmentAsset(id: "env-2")

        let active = try await db.fetchActiveEnvironmentAsset()
        #expect(active?.id == "env-2")
    }

    @Test func fetchActiveEnvironmentReturnsNilWhenNoneActive() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "env-assets-none.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let a = EnvironmentAsset(id: "env-1", name: "Test", sourceType: .bundled, assetPath: "/a.usdz", isActive: false)
        try await db.saveEnvironmentAsset(a)

        let active = try await db.fetchActiveEnvironmentAsset()
        #expect(active == nil)
    }

    @Test func deleteEnvironmentAsset() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "env-assets-delete.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let a = EnvironmentAsset(id: "env-1", name: "Test", sourceType: .bundled, assetPath: "/a.usdz")
        try await db.saveEnvironmentAsset(a)
        try await db.deleteEnvironmentAsset(id: "env-1")

        let assets = try await db.fetchEnvironmentAssets()
        #expect(assets.isEmpty)
    }
}

// MARK: - Database Settings Tests

@Suite(.serialized)
struct DatabaseSettingsTests {

    @Test func setAndGetSetting() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.setSetting(key: "test_key", value: "test_value")
        let value = try await db.getSetting(key: "test_key")
        #expect(value == "test_value")
    }

    @Test func getSettingReturnsNilForMissingKey() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-miss.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let value = try await db.getSetting(key: "nonexistent")
        #expect(value == nil)
    }

    @Test func setSettingNilDeletesKey() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-delete.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.setSetting(key: "key", value: "value")
        try await db.setSetting(key: "key", value: nil)
        let value = try await db.getSetting(key: "key")
        #expect(value == nil)
    }

    @Test func setSettingOverwritesExisting() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-overwrite.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.setSetting(key: "key", value: "first")
        try await db.setSetting(key: "key", value: "second")
        let value = try await db.getSetting(key: "key")
        #expect(value == "second")
    }
}

// MARK: - Database Debrid Config Tests

@Suite(.serialized)
struct DatabaseDebridConfigTests {

    @Test func saveAndFetchDebridConfigs() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "debrid-config.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = DebridConfig(serviceType: .realDebrid, apiTokenRef: "ref-1", isActive: true, priority: 0)
        try await db.saveDebridConfig(config)

        let configs = try await db.fetchDebridConfigs()
        #expect(configs.count == 1)
        #expect(configs.first?.serviceType == .realDebrid)
    }

    @Test func fetchDebridConfigsOnlyReturnsActive() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "debrid-config-active.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let active = DebridConfig(id: "c1", serviceType: .realDebrid, apiTokenRef: "ref-1", isActive: true, priority: 0)
        let inactive = DebridConfig(id: "c2", serviceType: .allDebrid, apiTokenRef: "ref-2", isActive: false, priority: 1)
        try await db.saveDebridConfig(active)
        try await db.saveDebridConfig(inactive)

        let configs = try await db.fetchDebridConfigs()
        #expect(configs.count == 1)
        #expect(configs.first?.id == "c1")

        let allConfigs = try await db.fetchAllDebridConfigs()
        #expect(allConfigs.count == 2)
    }

    @Test func deleteDebridConfig() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "debrid-config-delete.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = DebridConfig(id: "c1", serviceType: .realDebrid, apiTokenRef: "ref-1")
        try await db.saveDebridConfig(config)
        try await db.deleteDebridConfig(id: "c1")

        let configs = try await db.fetchAllDebridConfigs()
        #expect(configs.isEmpty)
    }
}

// MARK: - Database Indexer Config Tests

@Suite(.serialized)
struct DatabaseIndexerConfigTests {

    @Test func saveAndFetchIndexerConfigs() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "indexer-config.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = IndexerConfig(id: "ix-1", name: "YTS", indexerType: .yts, isActive: true, priority: 0)
        try await db.saveIndexerConfig(config)

        let configs = try await db.fetchIndexerConfigs()
        #expect(configs.count == 1)
        #expect(configs.first?.name == "YTS")
    }

    @Test func fetchIndexerConfigsOnlyReturnsActive() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "indexer-config-active.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let active = IndexerConfig(id: "ix-1", name: "YTS", indexerType: .yts, isActive: true, priority: 0)
        let inactive = IndexerConfig(id: "ix-2", name: "EZTV", indexerType: .eztv, isActive: false, priority: 1)
        try await db.saveIndexerConfig(active)
        try await db.saveIndexerConfig(inactive)

        let configs = try await db.fetchIndexerConfigs()
        #expect(configs.count == 1)

        let allConfigs = try await db.fetchAllIndexerConfigs()
        #expect(allConfigs.count == 2)
    }

    @Test func saveBatchIndexerConfigs() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "indexer-config-batch.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configs = [
            IndexerConfig(id: "ix-1", name: "YTS", indexerType: .yts, isActive: true, priority: 0),
            IndexerConfig(id: "ix-2", name: "EZTV", indexerType: .eztv, isActive: true, priority: 1),
        ]
        try await db.saveIndexerConfigs(configs)

        let fetched = try await db.fetchIndexerConfigs()
        #expect(fetched.count == 2)
    }

    @Test func deleteIndexerConfig() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "indexer-config-delete.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = IndexerConfig(id: "ix-1", name: "YTS", indexerType: .yts, isActive: true, priority: 0)
        try await db.saveIndexerConfig(config)
        try await db.deleteIndexerConfig(id: "ix-1")

        let configs = try await db.fetchAllIndexerConfigs()
        #expect(configs.isEmpty)
    }
}

// MARK: - Database Taste Profile Tests

@Suite(.serialized)
struct DatabaseTasteProfileTests {

    @Test func saveAndFetchTasteProfile() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "taste-profile.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let profile = UserTasteProfile(
            id: "default",
            likedGenres: ["Sci-Fi", "Action"],
            dislikedGenres: ["Horror"],
            preferredDecades: ["2020s"],
            preferredLanguages: ["en"],
            eventCount: 42
        )
        try await db.saveUserTasteProfile(profile)

        let fetched = try await db.fetchUserTasteProfile()
        #expect(fetched != nil)
        #expect(fetched?.likedGenres == ["Sci-Fi", "Action"])
        #expect(fetched?.dislikedGenres == ["Horror"])
        #expect(fetched?.eventCount == 42)
    }

    @Test func saveTasteEvent() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "taste-event.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let watchedEvent = TasteEvent(
            id: "evt-1", mediaId: "movie-1",
            eventType: .watched, signalStrength: 1.0,
            watchedState: .completed, source: .automatic
        )
        let ratedEvent = TasteEvent(
            id: "evt-2",
            mediaId: "movie-1",
            eventType: .rated,
            signalStrength: 0.9,
            feedbackScale: .oneToTen,
            feedbackValue: 9,
            source: .manual
        )
        try await db.saveTasteEvent(watchedEvent)
        try await db.saveTasteEvent(ratedEvent)

        let ratedOnly = try await db.fetchTasteEvents(eventType: .rated, limit: 20)
        #expect(ratedOnly.count == 1)
        #expect(ratedOnly.first?.id == "evt-2")
        #expect(ratedOnly.first?.feedbackScale?.canonicalMode == .oneToTen)

        let latestRating = try await db.fetchLatestTasteRating(mediaId: "movie-1")
        #expect(latestRating?.id == "evt-2")
        #expect(latestRating?.feedbackValue == 9)
    }

    @Test func fetchTasteProfileReturnsNilWhenEmpty() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "taste-profile-empty.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fetched = try await db.fetchUserTasteProfile()
        #expect(fetched == nil)
    }
}

// MARK: - Database Library Folder Tests

@Suite(.serialized)
struct DatabaseLibraryFolderTests {

    @Test func systemFoldersAreCreatedAutomatically() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-folders.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let _ = try await db.fetchSystemLibraryFolderID(listType: .watchlist)
        let folders = try await db.fetchAllLibraryFolders()

        // All three system folders should exist
        let systemFolders = folders.filter { $0.isSystem }
        #expect(systemFolders.count == 3) // watchlist, favorites, history
        #expect(systemFolders.contains(where: { $0.listType == .watchlist }))
        #expect(systemFolders.contains(where: { $0.listType == .favorites }))
        #expect(systemFolders.contains(where: { $0.listType == .history }))
    }

    @Test func fetchLibraryFoldersFiltersByListType() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-folders-filter.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let _ = try await db.fetchSystemLibraryFolderID(listType: .watchlist)

        let watchlistFolders = try await db.fetchAllLibraryFolders(listType: .watchlist)
        #expect(watchlistFolders.count == 1)
        #expect(watchlistFolders.first?.listType == .watchlist)
    }

    @Test func addToLibraryWithEmptyFolderIdUsesSystemFolder() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-auto-folder.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let entry = UserLibraryEntry(
            id: "entry-1", mediaId: "movie-1",
            folderId: "", listType: .watchlist, addedAt: Date()
        )
        try await db.addToLibrary(entry)

        let entries = try await db.fetchLibraryEntries(listType: .watchlist)
        #expect(entries.count == 1)
        #expect(entries.first?.folderId == LibraryFolder.systemFolderID(for: .watchlist))
    }

    @Test func isInLibraryReturnsFalseAfterRemoval() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-removal.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderId = try await db.fetchSystemLibraryFolderID(listType: .favorites)
        let entry = UserLibraryEntry(
            id: "entry-1", mediaId: "movie-1",
            folderId: folderId, listType: .favorites, addedAt: Date()
        )
        try await db.addToLibrary(entry)
        #expect(try await db.isInLibrary(mediaId: "movie-1", listType: .favorites) == true)

        try await db.removeFromLibrary(mediaId: "movie-1", listType: .favorites)
        #expect(try await db.isInLibrary(mediaId: "movie-1", listType: .favorites) == false)
    }

    @Test func createLibraryFolderCreatesManualFolderForWatchlist() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-create-folder.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder = try await db.createLibraryFolder(name: "Weekend Picks", listType: .watchlist)
        let folders = try await db.fetchAllLibraryFolders(listType: .watchlist)

        #expect(folder.listType == .watchlist)
        #expect(folder.isSystem == false)
        #expect(folder.folderKind == .manual)
        #expect(folder.parentId == LibraryFolder.systemFolderID(for: .watchlist))
        #expect(folders.contains(where: { $0.id == folder.id && $0.name == "Weekend Picks" }))
    }

    @Test func fetchLibraryEntriesCanFilterByFolder() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-folder-filter.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderA = try await db.createLibraryFolder(name: "A", listType: .favorites)
        let folderB = try await db.createLibraryFolder(name: "B", listType: .favorites)

        try await db.addToLibrary(
            UserLibraryEntry(
                id: "fav-a",
                mediaId: "movie-a",
                folderId: folderA.id,
                listType: .favorites,
                addedAt: Date()
            )
        )
        try await db.addToLibrary(
            UserLibraryEntry(
                id: "fav-b",
                mediaId: "movie-b",
                folderId: folderB.id,
                listType: .favorites,
                addedAt: Date()
            )
        )

        let inFolderA = try await db.fetchLibraryEntries(listType: .favorites, folderId: folderA.id)
        let inFolderB = try await db.fetchLibraryEntries(listType: .favorites, folderId: folderB.id)
        let allFavorites = try await db.fetchLibraryEntries(listType: .favorites, folderId: nil)

        #expect(inFolderA.map(\.mediaId) == ["movie-a"])
        #expect(inFolderB.map(\.mediaId) == ["movie-b"])
        #expect(allFavorites.count == 2)
    }

    @Test func moveLibraryEntryUpdatesFolderId() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-move-folder.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFolder = try await db.createLibraryFolder(name: "Source", listType: .watchlist)
        let destinationFolder = try await db.createLibraryFolder(name: "Destination", listType: .watchlist)

        try await db.addToLibrary(
            UserLibraryEntry(
                id: "wl-1",
                mediaId: "movie-1",
                folderId: sourceFolder.id,
                listType: .watchlist,
                addedAt: Date()
            )
        )

        try await db.moveLibraryEntry(mediaId: "movie-1", listType: .watchlist, toFolderId: destinationFolder.id)
        let movedEntries = try await db.fetchLibraryEntries(listType: .watchlist, folderId: destinationFolder.id)

        #expect(movedEntries.count == 1)
        #expect(movedEntries.first?.folderId == destinationFolder.id)
    }

    @Test func deleteLibraryFolderMovesEntriesToRootFolder() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-delete-folder.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manualFolder = try await db.createLibraryFolder(name: "To Delete", listType: .watchlist)
        let rootFolderID = try await db.fetchSystemLibraryFolderID(listType: .watchlist)

        try await db.addToLibrary(
            UserLibraryEntry(
                id: "wl-del-1",
                mediaId: "movie-delete-1",
                folderId: manualFolder.id,
                listType: .watchlist,
                addedAt: Date()
            )
        )

        try await db.deleteLibraryFolder(id: manualFolder.id, listType: .watchlist)

        let remainingFolders = try await db.fetchAllLibraryFolders(listType: .watchlist)
        #expect(remainingFolders.contains(where: { $0.id == manualFolder.id }) == false)

        let rootEntries = try await db.fetchLibraryEntries(listType: .watchlist, folderId: rootFolderID)
        #expect(rootEntries.contains(where: { $0.mediaId == "movie-delete-1" && $0.folderId == rootFolderID }))
    }

    @Test func deleteLibraryFolderRejectsSystemFolder() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-delete-system-folder.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootFolderID = try await db.fetchSystemLibraryFolderID(listType: .watchlist)

        do {
            try await db.deleteLibraryFolder(id: rootFolderID, listType: .watchlist)
            Issue.record("Expected deleteLibraryFolder to reject deleting a system folder")
        } catch {
            #expect(error.localizedDescription.contains("System folders cannot be deleted."))
        }
    }

    @Test func deleteLibraryFolderRejectsMismatchedListType() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-delete-folder-mismatch.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let favoritesFolder = try await db.createLibraryFolder(name: "Fav Only", listType: .favorites)

        do {
            try await db.deleteLibraryFolder(id: favoritesFolder.id, listType: .watchlist)
            Issue.record("Expected deleteLibraryFolder to reject list-type mismatch")
        } catch {
            #expect(error.localizedDescription.contains("does not belong"))
        }
    }

    @Test func createLibraryFolderRejectsHistoryList() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "library-history-folder-reject.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            _ = try await db.createLibraryFolder(name: "Invalid", listType: .history)
            Issue.record("Expected createLibraryFolder to reject .history")
        } catch {
            #expect(error.localizedDescription.contains("not supported"))
        }
    }
}

// MARK: - SettingsManager Tests

@Suite(.serialized)
struct SettingsManagerTests {

    @Test func regularSettingStoresInDatabase() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-mgr.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = SettingsManager(database: db, secretStore: TestSecretStore())
        try await settings.setString(key: SettingsKeys.preferredQuality, value: "1080p")
        let value = try await settings.getString(key: SettingsKeys.preferredQuality)
        #expect(value == "1080p")
    }

    @Test func secretSettingStoresInSecretStore() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-secret.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let settings = SettingsManager(database: db, secretStore: secretStore)

        try await settings.setValue("my-api-key", forKey: SettingsKeys.tmdbApiKey)
        let value = try await settings.getTMDBApiKey()
        #expect(value == "my-api-key")

        // Database should have a keychain reference, not the raw value
        let raw = try await db.getSetting(key: SettingsKeys.tmdbApiKey)
        #expect(raw?.hasPrefix("keychain:") == true)
    }

    @Test func clearingSecretSettingDeletesFromBoth() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-clear-secret.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretStore = TestSecretStore()
        let settings = SettingsManager(database: db, secretStore: secretStore)

        try await settings.setValue("key-123", forKey: SettingsKeys.openSubtitlesApiKey)
        try await settings.setValue(nil, forKey: SettingsKeys.openSubtitlesApiKey)

        let value = try await settings.getValue(forKey: SettingsKeys.openSubtitlesApiKey)
        #expect(value == nil)
    }

    @Test func getBoolReturnsDefaultWhenUnset() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-bool-default.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = SettingsManager(database: db, secretStore: TestSecretStore())
        let value = try await settings.getBool(key: "unset_key", default: true)
        #expect(value == true)
    }

    @Test func boolRoundTrip() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-bool-roundtrip.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = SettingsManager(database: db, secretStore: TestSecretStore())
        try await settings.setBool(key: SettingsKeys.autoPlayNext, value: true)
        #expect(try await settings.getBool(key: SettingsKeys.autoPlayNext) == true)

        try await settings.setBool(key: SettingsKeys.autoPlayNext, value: false)
        #expect(try await settings.getBool(key: SettingsKeys.autoPlayNext) == false)
    }

    @Test func getPreferredQualityDefaultsTo1080p() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-quality-default.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = SettingsManager(database: db, secretStore: TestSecretStore())
        let quality = try await settings.getPreferredQuality()
        #expect(quality == .hd1080p)
    }

    @Test func getPreferredQualityParsesStoredValue() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-quality-stored.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = SettingsManager(database: db, secretStore: TestSecretStore())
        try await settings.setString(key: SettingsKeys.preferredQuality, value: VideoQuality.uhd4k.rawValue)
        let quality = try await settings.getPreferredQuality()
        #expect(quality == .uhd4k)
    }

    @Test func getFeedbackScaleModeDefaultsToLikeDislike() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-feedback-default.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = SettingsManager(database: db, secretStore: TestSecretStore())
        let mode = try await settings.getFeedbackScaleMode()
        #expect(mode == .likeDislike)
    }

    @Test func getFeedbackScaleModeParsesStoredValue() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "settings-feedback-stored.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = SettingsManager(database: db, secretStore: TestSecretStore())
        try await settings.setString(key: SettingsKeys.feedbackScaleMode, value: FeedbackScaleMode.oneToHundred.rawValue)
        let mode = try await settings.getFeedbackScaleMode()
        #expect(mode == .oneToHundred)
    }
}
