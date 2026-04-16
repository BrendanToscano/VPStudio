import Foundation
import GRDB
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SchemaPruningTests {
    @Test
    func migrateDoesNotCreateDeprecatedTables() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("schema-pruning.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()

        let tableNames = try sqliteTableNames(at: dbPath)

        let expectedCoreTables: Set<String> = [
            "media_cache",
            "episodes",
            "watch_history",
            "user_library",
            "library_folders",
            "debrid_configs",
            "indexer_configs",
            "user_taste_profiles",
            "taste_events",
            "app_settings",
            "download_tasks",
            "environment_assets",
        ]

        for table in expectedCoreTables {
            #expect(tableNames.contains(table), "Missing expected table: \(table)")
        }

        let removedTables: Set<String> = [
            "torrent_cache",
            "assistant_memory_chunks",
            "discover_ai_cache",
            "viewing_preferences",
        ]

        for table in removedTables {
            #expect(tableNames.contains(table) == false, "Deprecated table still created: \(table)")
        }
    }

    private func sqliteTableNames(at path: String) throws -> Set<String> {
        let queue = try DatabaseQueue(path: path)
        return try queue.read { db in
            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table';")
            return Set(names)
        }
    }
}
