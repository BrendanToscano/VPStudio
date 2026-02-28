import Foundation
import Testing
@testable import VPStudio

@Suite("DiscoverViewModel - Continue Watching")
@MainActor
struct DiscoverContinueWatchingTests {
    private func makeDB() async throws -> DatabaseManager {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("discover-test.sqlite").path
        let db = try DatabaseManager(path: dbPath)
        try await db.migrate()
        return db
    }

    private func seedHistory(db: DatabaseManager, mediaId: String, title: String, progress: Double, duration: Double, completed: Bool) async throws {
        let item = MediaItem(
            id: mediaId, type: .movie, title: title, year: 2025,
            posterPath: "/poster.jpg", backdropPath: nil, overview: nil,
            genres: [], imdbRating: 7.0, runtime: 120, status: nil,
            tmdbId: 100, lastFetched: Date()
        )
        try await db.saveMediaItem(item)

        let history = WatchHistory(
            id: "\(mediaId)-history",
            mediaId: mediaId,
            episodeId: nil,
            title: title,
            progress: progress,
            duration: duration,
            quality: nil,
            debridService: nil,
            streamURL: nil,
            watchedAt: Date(),
            isCompleted: completed
        )
        try await db.saveWatchHistory(history)
    }

    @Test func continueWatchingLoadsInProgressItems() async throws {
        let db = try await makeDB()
        try await seedHistory(db: db, mediaId: "tt1234567", title: "Test Movie", progress: 3600, duration: 7200, completed: false)

        let vm = DiscoverViewModel(database: db)
        await vm.loadContinueWatching()

        #expect(vm.continueWatching.count == 1)
        #expect(vm.continueWatching.first?.preview.title == "Test Movie")
    }

    @Test func continueWatchingExcludesCompletedItems() async throws {
        let db = try await makeDB()
        try await seedHistory(db: db, mediaId: "tt1111111", title: "Finished Movie", progress: 7000, duration: 7200, completed: true)

        let vm = DiscoverViewModel(database: db)
        await vm.loadContinueWatching()

        #expect(vm.continueWatching.isEmpty)
    }

    @Test func continueWatchingExcludesNearlyFinished() async throws {
        let db = try await makeDB()
        // 96% progress — should be excluded (>95% threshold)
        try await seedHistory(db: db, mediaId: "tt2222222", title: "Almost Done", progress: 6912, duration: 7200, completed: false)

        let vm = DiscoverViewModel(database: db)
        await vm.loadContinueWatching()

        #expect(vm.continueWatching.isEmpty)
    }

    @Test func continueWatchingExcludesBarelyScrubbed() async throws {
        let db = try await makeDB()
        // 1% progress (72/7200) — should be excluded (<5% threshold)
        try await seedHistory(db: db, mediaId: "tt3333333", title: "Barely Started", progress: 72, duration: 7200, completed: false)

        let vm = DiscoverViewModel(database: db)
        await vm.loadContinueWatching()

        #expect(vm.continueWatching.isEmpty)
    }

    @Test func continueWatchingIncludesAt5Percent() async throws {
        let db = try await makeDB()
        // 5% progress (360/7200) — should be included (>=5% threshold)
        try await seedHistory(db: db, mediaId: "tt4444444", title: "Just Started", progress: 360, duration: 7200, completed: false)

        let vm = DiscoverViewModel(database: db)
        await vm.loadContinueWatching()

        #expect(vm.continueWatching.count == 1)
    }

    @Test func continueWatchingEmptyWhenNoHistory() async throws {
        let db = try await makeDB()

        let vm = DiscoverViewModel(database: db)
        await vm.loadContinueWatching()

        #expect(vm.continueWatching.isEmpty)
    }

    @Test func continueWatchingLimitsTo10() async throws {
        let db = try await makeDB()

        for i in 0..<15 {
            try await seedHistory(
                db: db,
                mediaId: "tt\(String(format: "%07d", i))",
                title: "Movie \(i)",
                progress: 3600,
                duration: 7200,
                completed: false
            )
        }

        let vm = DiscoverViewModel(database: db)
        await vm.loadContinueWatching()

        #expect(vm.continueWatching.count == 10)
    }
}
