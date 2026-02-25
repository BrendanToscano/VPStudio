import Foundation
import GRDB

struct UserLibraryEntry: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "user_library"

    var id: String
    var mediaId: String
    var folderId: String
    var listType: ListType
    var addedAt: Date
    var customListName: String?
    var releaseDateHint: String?
    var renewalStatus: String?

    enum ListType: String, Codable, Sendable, CaseIterable, CustomStringConvertible {
        case watchlist
        case favorites
        case history

        static var libraryTopTabs: [Self] {
            [.watchlist, .favorites, .history]
        }

        static func fromStoredValue(_ rawValue: String?) -> Self {
            guard let rawValue else { return .favorites }
            switch rawValue {
            case Self.watchlist.rawValue:
                return .watchlist
            case Self.favorites.rawValue:
                return .favorites
            case Self.history.rawValue:
                return .history
            case "custom":
                // Backward compatibility for older builds that used a "custom" library tab.
                return .favorites
            default:
                return .favorites
            }
        }

        var displayName: String {
            switch self {
            case .watchlist: return "Watchlist"
            case .favorites: return "Favorites"
            case .history: return "History"
            }
        }

        var description: String { displayName }

        var supportsFolders: Bool {
            switch self {
            case .watchlist, .favorites: return true
            case .history: return false
            }
        }
    }

    enum Columns: String, ColumnExpression {
        case id, mediaId, folderId, listType, addedAt
        case customListName, releaseDateHint, renewalStatus
    }

    init(
        id: String,
        mediaId: String,
        folderId: String,
        listType: ListType,
        addedAt: Date,
        customListName: String? = nil,
        releaseDateHint: String? = nil,
        renewalStatus: String? = nil
    ) {
        self.id = id
        self.mediaId = mediaId
        self.folderId = folderId
        self.listType = listType
        self.addedAt = addedAt
        self.customListName = customListName
        self.releaseDateHint = releaseDateHint
        self.renewalStatus = renewalStatus
    }

    init(row: Row) throws {
        id = row[Columns.id]
        mediaId = row[Columns.mediaId]
        folderId = row[Columns.folderId]
        listType = ListType.fromStoredValue(row[Columns.listType])
        addedAt = row[Columns.addedAt]
        customListName = row[Columns.customListName]
        releaseDateHint = row[Columns.releaseDateHint]
        renewalStatus = row[Columns.renewalStatus]
    }
}

struct LibraryFolder: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "library_folders"

    enum FolderKind: String, Codable, Sendable, CaseIterable {
        case systemRoot = "system_root"
        case manual
        case watched
        case releaseWait = "release_wait"
    }

    var id: String
    var name: String
    var parentId: String?
    var listType: UserLibraryEntry.ListType
    var folderKind: FolderKind
    var isSystem: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, name, parentId, listType, folderKind, isSystem, sortOrder, createdAt, updatedAt
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.parentId] = parentId
        container[Columns.listType] = listType.rawValue
        container[Columns.folderKind] = folderKind.rawValue
        container[Columns.isSystem] = isSystem
        container[Columns.sortOrder] = sortOrder
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }

    init(row: Row) throws {
        id = row[Columns.id]
        name = row[Columns.name]
        parentId = row[Columns.parentId]
        listType = UserLibraryEntry.ListType.fromStoredValue(row[Columns.listType])
        isSystem = row[Columns.isSystem]
        let storedKind: String? = row[Columns.folderKind]
        folderKind = storedKind.flatMap(FolderKind.init(rawValue:)) ?? (isSystem ? .systemRoot : .manual)
        sortOrder = row[Columns.sortOrder] ?? 0
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    init(
        id: String,
        name: String,
        parentId: String? = nil,
        listType: UserLibraryEntry.ListType,
        folderKind: FolderKind = .manual,
        isSystem: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.listType = listType
        self.folderKind = folderKind
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func systemFolderID(for listType: UserLibraryEntry.ListType) -> String {
        "system-\(listType.rawValue)"
    }

    static let watchedFolderID = "system-favorites-watched"
    static let releaseWaitFolderID = "system-favorites-release-wait"

    static func systemFolderName(for listType: UserLibraryEntry.ListType) -> String {
        switch listType {
        case .watchlist: return "Watchlist"
        case .favorites: return "Favorites"
        case .history: return "History"
        }
    }
}

// MARK: - Trakt List Mapping

struct TraktListMapping: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "trakt_list_mappings"

    var id: String
    var traktListId: Int
    var traktListSlug: String?
    var localFolderId: String
    var listType: UserLibraryEntry.ListType
    var lastSyncedAt: Date

    enum Columns: String, ColumnExpression {
        case id, traktListId, traktListSlug, localFolderId, listType, lastSyncedAt
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.traktListId] = traktListId
        container[Columns.traktListSlug] = traktListSlug
        container[Columns.localFolderId] = localFolderId
        container[Columns.listType] = listType.rawValue
        container[Columns.lastSyncedAt] = lastSyncedAt
    }

    init(row: Row) throws {
        id = row[Columns.id]
        traktListId = row[Columns.traktListId]
        traktListSlug = row[Columns.traktListSlug]
        localFolderId = row[Columns.localFolderId]
        listType = UserLibraryEntry.ListType.fromStoredValue(row[Columns.listType])
        lastSyncedAt = row[Columns.lastSyncedAt]
    }

    init(
        id: String = UUID().uuidString,
        traktListId: Int,
        traktListSlug: String? = nil,
        localFolderId: String,
        listType: UserLibraryEntry.ListType = .watchlist,
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.traktListId = traktListId
        self.traktListSlug = traktListSlug
        self.localFolderId = localFolderId
        self.listType = listType
        self.lastSyncedAt = lastSyncedAt
    }
}
