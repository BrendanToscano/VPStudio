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

@Suite(.serialized)
struct LibraryFolderSortOrderTests {

    @Test func createFolderAssignsIncrementingSortOrder() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "folder-sort-create.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderA = try await db.createLibraryFolder(name: "Alpha", listType: .watchlist)
        let folderB = try await db.createLibraryFolder(name: "Bravo", listType: .watchlist)
        let folderC = try await db.createLibraryFolder(name: "Charlie", listType: .watchlist)

        #expect(folderA.sortOrder == 0)
        #expect(folderB.sortOrder == 1)
        #expect(folderC.sortOrder == 2)
    }

    @Test func fetchAllLibraryFoldersRespectsSortOrder() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "folder-sort-fetch.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create folders in reverse alphabetical order
        _ = try await db.createLibraryFolder(name: "Zebra", listType: .watchlist)
        _ = try await db.createLibraryFolder(name: "Alpha", listType: .watchlist)
        _ = try await db.createLibraryFolder(name: "Middle", listType: .watchlist)

        let folders = try await db.fetchAllLibraryFolders(listType: .watchlist)
        let manualFolders = folders.filter { !$0.isSystem }

        // Should be in creation order (sortOrder 0, 1, 2), not alphabetical
        #expect(manualFolders.count == 3)
        #expect(manualFolders[0].name == "Zebra")
        #expect(manualFolders[1].name == "Alpha")
        #expect(manualFolders[2].name == "Middle")
    }

    @Test func reorderLibraryFoldersSetsCorrectSortOrderValues() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "folder-sort-reorder.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderA = try await db.createLibraryFolder(name: "Alpha", listType: .favorites)
        let folderB = try await db.createLibraryFolder(name: "Bravo", listType: .favorites)
        let folderC = try await db.createLibraryFolder(name: "Charlie", listType: .favorites)

        // Reverse the order: C, B, A
        try await db.reorderLibraryFolders(
            ids: [folderC.id, folderB.id, folderA.id],
            listType: .favorites
        )

        let folders = try await db.fetchAllLibraryFolders(listType: .favorites)
        let manualFolders = folders.filter { !$0.isSystem }

        #expect(manualFolders.count == 3)
        #expect(manualFolders[0].name == "Charlie")
        #expect(manualFolders[1].name == "Bravo")
        #expect(manualFolders[2].name == "Alpha")
    }

    @Test func reorderPreservesSystemFolders() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "folder-sort-system.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderA = try await db.createLibraryFolder(name: "Alpha", listType: .watchlist)
        let folderB = try await db.createLibraryFolder(name: "Bravo", listType: .watchlist)

        // Reorder manual folders
        try await db.reorderLibraryFolders(
            ids: [folderB.id, folderA.id],
            listType: .watchlist
        )

        let folders = try await db.fetchAllLibraryFolders(listType: .watchlist)

        // System folders should still appear first
        #expect(folders.first?.isSystem == true)
        #expect(folders.first?.folderKind == .systemRoot)

        let manualFolders = folders.filter { !$0.isSystem }
        #expect(manualFolders[0].name == "Bravo")
        #expect(manualFolders[1].name == "Alpha")
    }

    @Test func reorderDoesNotAffectOtherListTypes() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "folder-sort-cross-list.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let watchA = try await db.createLibraryFolder(name: "Watch-A", listType: .watchlist)
        let watchB = try await db.createLibraryFolder(name: "Watch-B", listType: .watchlist)
        let favA = try await db.createLibraryFolder(name: "Fav-A", listType: .favorites)
        let favB = try await db.createLibraryFolder(name: "Fav-B", listType: .favorites)

        // Reorder only watchlist folders
        try await db.reorderLibraryFolders(
            ids: [watchB.id, watchA.id],
            listType: .watchlist
        )

        // Favorites should be unaffected
        let favFolders = try await db.fetchAllLibraryFolders(listType: .favorites)
        let manualFavFolders = favFolders.filter { !$0.isSystem }
        #expect(manualFavFolders[0].name == "Fav-A")
        #expect(manualFavFolders[1].name == "Fav-B")
    }

    @Test func createFolderAfterReorderAppendsCorrectly() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "folder-sort-append.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderA = try await db.createLibraryFolder(name: "Alpha", listType: .watchlist)
        let folderB = try await db.createLibraryFolder(name: "Bravo", listType: .watchlist)

        // Reorder: B, A (sortOrder 0, 1)
        try await db.reorderLibraryFolders(
            ids: [folderB.id, folderA.id],
            listType: .watchlist
        )

        // New folder should get sortOrder 2
        let folderC = try await db.createLibraryFolder(name: "Charlie", listType: .watchlist)
        #expect(folderC.sortOrder == 2)

        let folders = try await db.fetchAllLibraryFolders(listType: .watchlist)
        let manualFolders = folders.filter { !$0.isSystem }
        #expect(manualFolders.count == 3)
        #expect(manualFolders[0].name == "Bravo")
        #expect(manualFolders[1].name == "Alpha")
        #expect(manualFolders[2].name == "Charlie")
    }

    @Test func sortOrderModelDefaultIsZero() {
        let folder = LibraryFolder(
            id: "test",
            name: "Test",
            listType: .watchlist
        )
        #expect(folder.sortOrder == 0)
    }

    @Test func sortOrderModelAcceptsCustomValue() {
        let folder = LibraryFolder(
            id: "test",
            name: "Test",
            listType: .watchlist,
            sortOrder: 42
        )
        #expect(folder.sortOrder == 42)
    }

    @Test func fetchLibraryEntriesWithDateAddedDescSort() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "entries-sort-date-desc.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderId = try await db.fetchSystemLibraryFolderID(listType: .watchlist)

        let earlier = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        try await db.addToLibrary(UserLibraryEntry(
            id: "e1", mediaId: "m1", folderId: folderId, listType: .watchlist, addedAt: earlier
        ))
        try await db.addToLibrary(UserLibraryEntry(
            id: "e2", mediaId: "m2", folderId: folderId, listType: .watchlist, addedAt: later
        ))

        let entries = try await db.fetchLibraryEntries(
            listType: .watchlist,
            folderId: nil,
            sortOption: .dateAddedDesc
        )
        #expect(entries.count == 2)
        #expect(entries[0].mediaId == "m2")
        #expect(entries[1].mediaId == "m1")
    }

    @Test func fetchLibraryEntriesWithDateAddedAscSort() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "entries-sort-date-asc.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderId = try await db.fetchSystemLibraryFolderID(listType: .watchlist)

        let earlier = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        try await db.addToLibrary(UserLibraryEntry(
            id: "e1", mediaId: "m1", folderId: folderId, listType: .watchlist, addedAt: earlier
        ))
        try await db.addToLibrary(UserLibraryEntry(
            id: "e2", mediaId: "m2", folderId: folderId, listType: .watchlist, addedAt: later
        ))

        let entries = try await db.fetchLibraryEntries(
            listType: .watchlist,
            folderId: nil,
            sortOption: .dateAddedAsc
        )
        #expect(entries.count == 2)
        #expect(entries[0].mediaId == "m1")
        #expect(entries[1].mediaId == "m2")
    }

    @Test func fetchLibraryEntriesWithTitleSort() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "entries-sort-title.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderId = try await db.fetchSystemLibraryFolderID(listType: .watchlist)

        // Save media items so the JOIN can find titles
        let itemA = MediaItem(id: "m-a", type: .movie, title: "Alpha", genres: [])
        let itemZ = MediaItem(id: "m-z", type: .movie, title: "Zebra", genres: [])
        try await db.saveMediaItem(itemA)
        try await db.saveMediaItem(itemZ)

        try await db.addToLibrary(UserLibraryEntry(
            id: "e1", mediaId: "m-z", folderId: folderId, listType: .watchlist, addedAt: Date()
        ))
        try await db.addToLibrary(UserLibraryEntry(
            id: "e2", mediaId: "m-a", folderId: folderId, listType: .watchlist, addedAt: Date()
        ))

        let ascending = try await db.fetchLibraryEntries(
            listType: .watchlist,
            folderId: nil,
            sortOption: .titleAsc
        )
        #expect(ascending[0].mediaId == "m-a")
        #expect(ascending[1].mediaId == "m-z")

        let descending = try await db.fetchLibraryEntries(
            listType: .watchlist,
            folderId: nil,
            sortOption: .titleDesc
        )
        #expect(descending[0].mediaId == "m-z")
        #expect(descending[1].mediaId == "m-a")
    }

    @Test func fetchLibraryEntriesWithYearSort() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "entries-sort-year.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderId = try await db.fetchSystemLibraryFolderID(listType: .watchlist)

        let itemOld = MediaItem(id: "m-old", type: .movie, title: "Old Movie", year: 1990, genres: [])
        let itemNew = MediaItem(id: "m-new", type: .movie, title: "New Movie", year: 2024, genres: [])
        let itemNil = MediaItem(id: "m-nil", type: .movie, title: "No Year", genres: [])
        try await db.saveMediaItem(itemOld)
        try await db.saveMediaItem(itemNew)
        try await db.saveMediaItem(itemNil)

        try await db.addToLibrary(UserLibraryEntry(
            id: "e1", mediaId: "m-old", folderId: folderId, listType: .watchlist, addedAt: Date()
        ))
        try await db.addToLibrary(UserLibraryEntry(
            id: "e2", mediaId: "m-new", folderId: folderId, listType: .watchlist, addedAt: Date()
        ))
        try await db.addToLibrary(UserLibraryEntry(
            id: "e3", mediaId: "m-nil", folderId: folderId, listType: .watchlist, addedAt: Date()
        ))

        let newest = try await db.fetchLibraryEntries(
            listType: .watchlist,
            folderId: nil,
            sortOption: .yearDesc
        )
        #expect(newest.count == 3)
        // yearDesc: real years descending first, nil-year items last
        #expect(newest[0].mediaId == "m-new")
        #expect(newest[1].mediaId == "m-old")
        #expect(newest[2].mediaId == "m-nil")

        let oldest = try await db.fetchLibraryEntries(
            listType: .watchlist,
            folderId: nil,
            sortOption: .yearAsc
        )
        #expect(oldest.count == 3)
        // yearAsc: real years ascending first, nil-year items last
        #expect(oldest[0].mediaId == "m-old")
        #expect(oldest[1].mediaId == "m-new")
        #expect(oldest[2].mediaId == "m-nil")
    }

    @Test func deleteFolderDoesNotCorruptSortOrder() async throws {
        let (db, tempDir) = try await makeTemporaryDatabase(named: "folder-sort-delete.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folderA = try await db.createLibraryFolder(name: "Alpha", listType: .watchlist)
        _ = try await db.createLibraryFolder(name: "Bravo", listType: .watchlist)
        let folderC = try await db.createLibraryFolder(name: "Charlie", listType: .watchlist)

        // Delete middle folder
        try await db.deleteLibraryFolder(id: folderA.id, listType: .watchlist)

        let folders = try await db.fetchAllLibraryFolders(listType: .watchlist)
        let manualFolders = folders.filter { !$0.isSystem }

        // Remaining folders should still be in sortOrder
        #expect(manualFolders.count == 2)
        #expect(manualFolders[0].name == "Bravo")
        #expect(manualFolders[1].name == "Charlie")
    }
}
