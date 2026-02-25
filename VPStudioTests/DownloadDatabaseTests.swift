import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct DownloadDatabaseTests {
    @Test func migrationSupportsDownloadTaskCRUDRoundTrip() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-db-roundtrip.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let task = DownloadTask(
            id: "download-1",
            mediaId: "tt123",
            episodeId: "ep-1",
            streamURL: "https://cdn.example.com/a.mkv",
            fileName: "a.mkv",
            status: .queued,
            progress: 0,
            bytesWritten: 0,
            totalBytes: nil,
            destinationPath: nil,
            errorMessage: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await database.saveDownloadTask(task)

        let fetched = try await database.fetchDownloadTask(id: task.id)
        #expect(fetched?.id == task.id)
        #expect(fetched?.status == .queued)

        try await database.updateDownloadTaskProgress(
            id: task.id,
            progress: 0.42,
            bytesWritten: 420,
            totalBytes: 1000,
            destinationPath: "/tmp/a.mkv"
        )
        try await database.updateDownloadTaskStatus(id: task.id, status: .downloading, errorMessage: nil)

        let updated = try await database.fetchDownloadTask(id: task.id)
        #expect(updated?.progress == 0.42)
        #expect(updated?.status == .downloading)
        #expect(updated?.destinationPath == "/tmp/a.mkv")

        try await database.deleteDownloadTask(id: task.id)
        let deleted = try await database.fetchDownloadTask(id: task.id)
        #expect(deleted == nil)
    }

    @Test func statusUpdateRefreshesUpdatedAt() async throws {
        let (database, rootDir) = try await makeDatabase(named: "download-db-updated-at.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let initialDate = Date(timeIntervalSince1970: 1_000)
        let task = DownloadTask(
            id: "download-2",
            mediaId: "tt456",
            episodeId: nil,
            streamURL: "https://cdn.example.com/b.mkv",
            fileName: "b.mkv",
            status: .queued,
            progress: 0,
            bytesWritten: 0,
            totalBytes: nil,
            destinationPath: nil,
            errorMessage: nil,
            createdAt: initialDate,
            updatedAt: initialDate
        )

        try await database.saveDownloadTask(task)
        try await Task.sleep(for: .milliseconds(10))
        try await database.updateDownloadTaskStatus(id: task.id, status: .failed, errorMessage: "failed")

        let updated = try await database.fetchDownloadTask(id: task.id)
        #expect(updated?.status == .failed)
        #expect((updated?.updatedAt ?? initialDate) > initialDate)
    }

    private func makeDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, rootDir)
    }
}
