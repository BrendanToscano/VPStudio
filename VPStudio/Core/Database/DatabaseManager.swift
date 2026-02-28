import Foundation
import GRDB

actor DatabaseManager {
    private let dbPool: DatabasePool
    private static let watchHistoryRetentionCap = 2_000
    private static let watchHistoryRetentionTTL: TimeInterval = 365 * 24 * 60 * 60
    private static let tasteEventsRetentionCap = 4_000
    private static let tasteEventsRetentionTTL: TimeInterval = 365 * 24 * 60 * 60

    init(path: String? = nil) throws {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Application Support directory unavailable"])
            }
            let dbDir = appSupport.appendingPathComponent("VPStudio", isDirectory: true)
            try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            dbPath = dbDir.appendingPathComponent("vpstudio.sqlite").path
        }

        var config = Configuration()
        #if DEBUG
        if ProcessInfo.processInfo.environment["VPSTUDIO_SQL_TRACE"] != nil {
            config.prepareDatabase { db in
                db.trace { print("SQL: \($0)") }
            }
        }
        #endif

        dbPool = try DatabasePool(path: dbPath, configuration: config)
    }

    func migrate() async throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "media_cache") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("year", .integer)
                t.column("posterPath", .text)
                t.column("backdropPath", .text)
                t.column("overview", .text)
                t.column("genres", .blob)
                t.column("imdbRating", .double)
                t.column("runtime", .integer)
                t.column("status", .text)
                t.column("tmdbId", .integer)
                t.column("lastFetched", .datetime)
            }

            try db.create(table: "episodes") { t in
                t.primaryKey("id", .text)
                t.column("mediaId", .text).notNull().indexed()
                t.column("seasonNumber", .integer).notNull()
                t.column("episodeNumber", .integer).notNull()
                t.column("title", .text)
                t.column("overview", .text)
                t.column("airDate", .text)
                t.column("stillPath", .text)
                t.column("runtime", .integer)
            }

            try db.create(table: "watch_history") { t in
                t.primaryKey("id", .text)
                t.column("mediaId", .text).notNull().indexed()
                t.column("episodeId", .text)
                t.column("title", .text).notNull()
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("quality", .text)
                t.column("debridService", .text)
                t.column("streamURL", .text)
                t.column("watchedAt", .datetime).notNull()
                t.column("isCompleted", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "user_library") { t in
                t.primaryKey("id", .text)
                t.column("mediaId", .text).notNull().indexed()
                t.column("folderId", .text).notNull()
                t.column("listType", .text).notNull()
                t.column("addedAt", .datetime).notNull()
                t.column("customListName", .text)
                t.column("releaseDateHint", .text)
                t.column("renewalStatus", .text)
            }

            try db.create(table: "library_folders") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("parentId", .text)
                t.column("listType", .text).notNull()
                t.column("folderKind", .text).notNull().defaults(to: "manual")
                t.column("isSystem", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "debrid_configs") { t in
                t.primaryKey("id", .text)
                t.column("serviceType", .text).notNull()
                t.column("apiTokenRef", .text).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "indexer_configs") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("indexerType", .text).notNull()
                t.column("baseURL", .text)
                t.column("apiKey", .text)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("providerSubtype", .text).notNull().defaults(to: IndexerConfig.ProviderSubtype.builtIn.rawValue)
                t.column("endpointPath", .text).notNull().defaults(to: "")
                t.column("categoryFilter", .text)
                t.column("apiKeyTransport", .text).notNull().defaults(to: IndexerConfig.APIKeyTransport.query.rawValue)
            }

            try db.create(table: "user_taste_profiles") { t in
                t.primaryKey("id", .text)
                t.column("likedGenres", .blob)
                t.column("dislikedGenres", .blob)
                t.column("preferredDecades", .blob)
                t.column("preferredLanguages", .blob)
                t.column("eventCount", .integer).notNull().defaults(to: 0)
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "taste_events") { t in
                t.primaryKey("id", .text)
                t.column("userId", .text).notNull().defaults(to: "default")
                t.column("mediaId", .text)
                t.column("episodeId", .text)
                t.column("eventType", .text).notNull()
                t.column("signalStrength", .double).notNull().defaults(to: 1.0)
                t.column("watchedState", .text)
                t.column("feedbackScale", .text)
                t.column("feedbackValue", .double)
                t.column("source", .text)
                t.column("metadata", .blob)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "app_settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text)
            }
        }

        migrator.registerMigration("v2_downloads_and_environments") { db in
            try db.create(table: "download_tasks", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("mediaId", .text).notNull().indexed()
                t.column("episodeId", .text)
                t.column("streamURL", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("status", .text).notNull().defaults(to: DownloadStatus.queued.rawValue)
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("bytesWritten", .integer).notNull().defaults(to: 0)
                t.column("totalBytes", .integer)
                t.column("destinationPath", .text)
                t.column("errorMessage", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull().indexed()
            }

            try db.create(table: "environment_assets", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sourceType", .text).notNull()
                t.column("assetPath", .text).notNull()
                t.column("thumbnailPath", .text)
                t.column("licenseName", .text)
                t.column("sourceAttributionURL", .text)
                t.column("previewImagePath", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: false).indexed()
            }
        }

        migrator.registerMigration("v3_indexers_and_environment_metadata") { db in
            func addColumnIfMissing(
                table: String,
                column: String,
                definition: String
            ) throws {
                let columns = try db.columns(in: table)
                let hasColumn = columns.contains { $0.name.caseInsensitiveCompare(column) == .orderedSame }
                if !hasColumn {
                    let quotedTable = "\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\""
                    let quotedColumn = "\"\(column.replacingOccurrences(of: "\"", with: "\"\""))\""
                    try db.execute(sql: "ALTER TABLE \(quotedTable) ADD COLUMN \(quotedColumn) \(definition)")
                }
            }

            try addColumnIfMissing(
                table: "indexer_configs",
                column: "providerSubtype",
                definition: "TEXT NOT NULL DEFAULT '\(IndexerConfig.ProviderSubtype.builtIn.rawValue)'"
            )
            try addColumnIfMissing(
                table: "indexer_configs",
                column: "endpointPath",
                definition: "TEXT NOT NULL DEFAULT ''"
            )
            try addColumnIfMissing(
                table: "indexer_configs",
                column: "categoryFilter",
                definition: "TEXT"
            )
            try addColumnIfMissing(
                table: "indexer_configs",
                column: "apiKeyTransport",
                definition: "TEXT NOT NULL DEFAULT '\(IndexerConfig.APIKeyTransport.query.rawValue)'"
            )

            try addColumnIfMissing(
                table: "environment_assets",
                column: "licenseName",
                definition: "TEXT"
            )
            try addColumnIfMissing(
                table: "environment_assets",
                column: "sourceAttributionURL",
                definition: "TEXT"
            )
            try addColumnIfMissing(
                table: "environment_assets",
                column: "previewImagePath",
                definition: "TEXT"
            )

            try addColumnIfMissing(
                table: "environment_assets",
                column: "hdriYawOffset",
                definition: "REAL"
            )
        }

        // v4: no-op, column already added in v3
        migrator.registerMigration("v4_hdri_yaw_offset") { _ in }

        migrator.registerMigration("v5_ai_usage_log") { db in
            try db.create(table: "ai_usage_log", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("estimatedCostUSD", .double).notNull().defaults(to: 0)
                t.column("requestType", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v6_ai_context_snapshots") { db in
            try db.create(table: "ai_context_snapshots", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("snapshotJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v7_library_folder_sort_order") { db in
            try db.alter(table: "library_folders") { t in
                t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
            }

            // Backfill existing manual folders with alphabetical rank per listType.
            let listTypes = ["watchlist", "favorites"]
            for listType in listTypes {
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id FROM library_folders
                    WHERE listType = ? AND isSystem = 0
                    ORDER BY name COLLATE NOCASE ASC
                    """, arguments: [listType])
                for (index, row) in rows.enumerated() {
                    let folderId: String = row["id"]
                    try db.execute(
                        sql: "UPDATE library_folders SET sortOrder = ? WHERE id = ?",
                        arguments: [index, folderId]
                    )
                }
            }
        }

        migrator.registerMigration("v8_download_metadata") { db in
            func addColumnIfMissing(table: String, column: String, definition: String) throws {
                let columns = try db.columns(in: table)
                let hasColumn = columns.contains { $0.name.caseInsensitiveCompare(column) == .orderedSame }
                if !hasColumn {
                    let quotedTable = "\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\""
                    let quotedColumn = "\"\(column.replacingOccurrences(of: "\"", with: "\"\""))\""
                    try db.execute(sql: "ALTER TABLE \(quotedTable) ADD COLUMN \(quotedColumn) \(definition)")
                }
            }

            try addColumnIfMissing(table: "download_tasks", column: "mediaTitle", definition: "TEXT NOT NULL DEFAULT ''")
            try addColumnIfMissing(table: "download_tasks", column: "mediaType", definition: "TEXT NOT NULL DEFAULT 'movie'")
            try addColumnIfMissing(table: "download_tasks", column: "posterPath", definition: "TEXT")
            try addColumnIfMissing(table: "download_tasks", column: "seasonNumber", definition: "INTEGER")
            try addColumnIfMissing(table: "download_tasks", column: "episodeNumber", definition: "INTEGER")
            try addColumnIfMissing(table: "download_tasks", column: "episodeTitle", definition: "TEXT")
        }

        migrator.registerMigration("v9_trakt_list_mappings") { db in
            try db.create(table: "trakt_list_mappings", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("traktListId", .integer).notNull()
                t.column("traktListSlug", .text)
                t.column("localFolderId", .text).notNull()
                t.column("listType", .text).notNull().defaults(to: "watchlist")
                t.column("lastSyncedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_trakt_list_mappings_trakt_id",
                on: "trakt_list_mappings",
                columns: ["traktListId"],
                unique: true,
                ifNotExists: true
            )
            try db.create(
                index: "idx_trakt_list_mappings_folder_id",
                on: "trakt_list_mappings",
                columns: ["localFolderId"],
                unique: true,
                ifNotExists: true
            )
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            migrator.asyncMigrate(dbPool) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Media Cache

    func saveMediaItem(_ item: MediaItem) async throws {
        try await dbPool.write { db in try item.save(db) }
    }

    func fetchMediaItem(id: String) async throws -> MediaItem? {
        try await dbPool.read { db in try MediaItem.fetchOne(db, key: id) }
    }

    // MARK: - Watch History

    func saveWatchHistory(_ history: WatchHistory) async throws {
        try await dbPool.write { db in try history.save(db) }
        _ = try await applyWatchHistoryRetentionPolicy()
    }

    func fetchWatchHistory(limit: Int = 50) async throws -> [WatchHistory] {
        try await dbPool.read { db in
            try WatchHistory
                .order(WatchHistory.Columns.watchedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchCompletedWatchHistory(limit: Int = 1000) async throws -> [WatchHistory] {
        try await dbPool.read { db in
            try WatchHistory
                .filter(WatchHistory.Columns.isCompleted == true)
                .order(WatchHistory.Columns.watchedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchWatchHistory(mediaId: String, episodeId: String? = nil) async throws -> WatchHistory? {
        try await dbPool.read { db in
            var request = WatchHistory
                .filter(WatchHistory.Columns.mediaId == mediaId)
            if let episodeId {
                request = request.filter(WatchHistory.Columns.episodeId == episodeId)
            }
            return try request
                .order(WatchHistory.Columns.watchedAt.desc)
                .fetchOne(db)
        }
    }

    /// Fetches all watch history entries for a given media (series), returning a dictionary keyed by episodeId.
    func fetchEpisodeWatchStates(mediaId: String) async throws -> [String: WatchHistory] {
        try await dbPool.read { db in
            let entries = try WatchHistory
                .filter(WatchHistory.Columns.mediaId == mediaId)
                .filter(WatchHistory.Columns.episodeId != nil)
                .order(WatchHistory.Columns.watchedAt.desc)
                .fetchAll(db)
            var dict: [String: WatchHistory] = [:]
            for entry in entries {
                guard let episodeId = entry.episodeId else { continue }
                // Keep the most recent entry per episode (already ordered desc)
                if dict[episodeId] == nil {
                    dict[episodeId] = entry
                }
            }
            return dict
        }
    }

    /// Marks an episode as watched (creates a completed WatchHistory entry).
    func markEpisodeWatched(mediaId: String, episodeId: String, title: String) async throws {
        let history = WatchHistory(
            id: "\(mediaId)-\(episodeId)-watched",
            mediaId: mediaId,
            episodeId: episodeId,
            title: title,
            progress: 1.0,
            duration: 1.0,
            watchedAt: Date(),
            isCompleted: true
        )
        try await saveWatchHistory(history)
    }

    /// Marks an episode as unwatched by deleting its watch history entry.
    func markEpisodeUnwatched(mediaId: String, episodeId: String) async throws {
        _ = try await dbPool.write { db in
            try WatchHistory
                .filter(WatchHistory.Columns.mediaId == mediaId)
                .filter(WatchHistory.Columns.episodeId == episodeId)
                .deleteAll(db)
        }
    }

    @discardableResult
    func applyWatchHistoryRetentionPolicy(
        maxEntries: Int = DatabaseManager.watchHistoryRetentionCap,
        ttl: TimeInterval = DatabaseManager.watchHistoryRetentionTTL,
        now: Date = Date()
    ) async throws -> Int {
        try await dbPool.write { db in
            let effectiveMaxEntries = max(maxEntries, 0)
            let effectiveTTL = max(ttl, 0)
            let cutoffDate = now.addingTimeInterval(-effectiveTTL)

            let beforeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM watch_history") ?? 0

            try db.execute(
                sql: """
                DELETE FROM watch_history
                WHERE watchedAt < ?
                """,
                arguments: [cutoffDate]
            )

            try db.execute(
                sql: """
                DELETE FROM watch_history
                WHERE id IN (
                    SELECT id
                    FROM watch_history
                    ORDER BY watchedAt DESC, id DESC
                    LIMIT -1 OFFSET ?
                )
                """,
                arguments: [effectiveMaxEntries]
            )

            let afterCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM watch_history") ?? 0
            return max(beforeCount - afterCount, 0)
        }
    }

    // MARK: - Library

    func fetchLibraryEntries(listType: UserLibraryEntry.ListType) async throws -> [UserLibraryEntry] {
        try await fetchLibraryEntries(listType: listType, folderId: nil)
    }

    func fetchLibraryEntries(
        listType: UserLibraryEntry.ListType,
        folderId: String?,
        sortOption: LibrarySortOption = .dateAddedDesc
    ) async throws -> [UserLibraryEntry] {
        switch sortOption {
        case .dateAddedDesc, .dateAddedAsc:
            return try await dbPool.read { db in
                let ordering: SQLOrderingTerm = sortOption == .dateAddedDesc
                    ? UserLibraryEntry.Columns.addedAt.desc
                    : UserLibraryEntry.Columns.addedAt.asc
                var request = UserLibraryEntry
                    .filter(UserLibraryEntry.Columns.listType == listType.rawValue)
                    .order(ordering)
                if let folderId {
                    request = request.filter(UserLibraryEntry.Columns.folderId == folderId)
                }
                return try request.fetchAll(db)
            }
        case .titleAsc, .titleDesc, .yearAsc, .yearDesc:
            return try await fetchLibraryEntriesSortedByMedia(
                listType: listType,
                folderId: folderId,
                sortOption: sortOption
            )
        }
    }

    private func fetchLibraryEntriesSortedByMedia(
        listType: UserLibraryEntry.ListType,
        folderId: String?,
        sortOption: LibrarySortOption
    ) async throws -> [UserLibraryEntry] {
        try await dbPool.read { db in
            let orderClause: String
            switch sortOption {
            case .titleAsc: orderClause = "m.title COLLATE NOCASE ASC"
            case .titleDesc: orderClause = "m.title COLLATE NOCASE DESC"
            case .yearAsc: orderClause = "CASE WHEN m.year IS NULL THEN 1 ELSE 0 END, m.year ASC, m.title COLLATE NOCASE ASC"
            case .yearDesc: orderClause = "CASE WHEN m.year IS NULL THEN 1 ELSE 0 END, m.year DESC, m.title COLLATE NOCASE ASC"
            default: orderClause = "ul.addedAt DESC"
            }

            var sql = """
                SELECT ul.* FROM user_library ul
                LEFT JOIN media_cache m ON m.id = ul.mediaId
                WHERE ul.listType = ?
                """
            var arguments: [any DatabaseValueConvertible] = [listType.rawValue]

            if let folderId {
                sql += " AND ul.folderId = ?"
                arguments.append(folderId)
            }

            sql += " ORDER BY \(orderClause)"

            return try UserLibraryEntry.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    func addToLibrary(_ entry: UserLibraryEntry) async throws {
        try await dbPool.write { db in
            try Self.ensureSystemLibraryFolders(in: db)

            var normalized = entry
            if normalized.folderId.isEmpty {
                normalized.folderId = LibraryFolder.systemFolderID(for: normalized.listType)
            }
            try normalized.save(db)
        }
    }

    func removeFromLibrary(mediaId: String, listType: UserLibraryEntry.ListType) async throws {
        try await dbPool.write { db in
            _ = try UserLibraryEntry
                .filter(UserLibraryEntry.Columns.mediaId == mediaId)
                .filter(UserLibraryEntry.Columns.listType == listType.rawValue)
                .deleteAll(db)
        }
    }

    /// Post-import cleanup: collapses duplicate entries in a list based on
    /// normalized title equivalence (name-only match), keeping the "best" row.
    /// Ranking preference: latest user rating, then IMDb rating, then newest add date.
    func dedupeLibraryEntriesByTitleEquivalence(listType: UserLibraryEntry.ListType) async throws -> Int {
        struct Candidate {
            let entryID: String
            let mediaID: String
            let key: String
            let userRating: Double?
            let imdbRating: Double?
            let addedAt: Date
        }

        return try await dbPool.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    ul.id AS entryId,
                    ul.mediaId AS mediaId,
                    ul.addedAt AS addedAt,
                    m.title AS mediaTitle,
                    m.imdbRating AS imdbRating,
                    (
                        SELECT te.feedbackValue
                        FROM taste_events te
                        WHERE te.mediaId = ul.mediaId
                          AND te.eventType = 'rated'
                        ORDER BY te.createdAt DESC
                        LIMIT 1
                    ) AS latestRating
                FROM user_library ul
                LEFT JOIN media_cache m ON m.id = ul.mediaId
                WHERE ul.listType = ?
                """,
                arguments: [listType.rawValue]
            )

            let candidates: [Candidate] = rows.compactMap { row in
                guard let entryID: String = row["entryId"],
                      let mediaID: String = row["mediaId"],
                      let addedAt: Date = row["addedAt"]
                else { return nil }

                let title: String = row["mediaTitle"] ?? mediaID
                let key = Self.normalizedTitleEquivalenceKey(title)
                if key.isEmpty {
                    return nil
                }

                let userRating: Double? = row["latestRating"]
                let imdbRating: Double? = row["imdbRating"]

                return Candidate(
                    entryID: entryID,
                    mediaID: mediaID,
                    key: key,
                    userRating: userRating,
                    imdbRating: imdbRating,
                    addedAt: addedAt
                )
            }

            var grouped: [String: [Candidate]] = [:]
            for candidate in candidates {
                grouped[candidate.key, default: []].append(candidate)
            }

            var idsToDelete: [String] = []
            idsToDelete.reserveCapacity(max(0, candidates.count / 4))

            for group in grouped.values where group.count > 1 {
                let ranked = group.sorted { lhs, rhs in
                    let lhsUser = lhs.userRating ?? -Double.greatestFiniteMagnitude
                    let rhsUser = rhs.userRating ?? -Double.greatestFiniteMagnitude
                    if lhsUser != rhsUser { return lhsUser > rhsUser }

                    let lhsIMDb = lhs.imdbRating ?? -Double.greatestFiniteMagnitude
                    let rhsIMDb = rhs.imdbRating ?? -Double.greatestFiniteMagnitude
                    if lhsIMDb != rhsIMDb { return lhsIMDb > rhsIMDb }

                    if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }

                    return lhs.mediaID.localizedCaseInsensitiveCompare(rhs.mediaID) == .orderedAscending
                }

                idsToDelete.append(contentsOf: ranked.dropFirst().map(\.entryID))
            }

            for entryID in idsToDelete {
                try db.execute(
                    sql: "DELETE FROM user_library WHERE id = ?",
                    arguments: [entryID]
                )
            }

            return idsToDelete.count
        }
    }

    func isInLibrary(mediaId: String, listType: UserLibraryEntry.ListType) async throws -> Bool {
        try await dbPool.read { db in
            try UserLibraryEntry
                .filter(UserLibraryEntry.Columns.mediaId == mediaId)
                .filter(UserLibraryEntry.Columns.listType == listType.rawValue)
                .fetchCount(db) > 0
        }
    }

    func fetchSystemLibraryFolderID(listType: UserLibraryEntry.ListType) async throws -> String {
        try await dbPool.write { db in
            try Self.ensureSystemLibraryFolders(in: db)
            return LibraryFolder.systemFolderID(for: listType)
        }
    }

    func fetchAllLibraryFolders(listType: UserLibraryEntry.ListType? = nil) async throws -> [LibraryFolder] {
        try await dbPool.write { db in
            try Self.ensureSystemLibraryFolders(in: db)
            var request = LibraryFolder.order(
                LibraryFolder.Columns.isSystem.desc,
                LibraryFolder.Columns.sortOrder.asc,
                LibraryFolder.Columns.name.asc
            )
            if let listType {
                request = request.filter(LibraryFolder.Columns.listType == listType.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    func createLibraryFolder(
        name: String,
        listType: UserLibraryEntry.ListType,
        parentId: String? = nil
    ) async throws -> LibraryFolder {
        try await dbPool.write { db in
            try Self.ensureSystemLibraryFolders(in: db)

            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw DatabaseError(message: "Folder name cannot be empty.")
            }
            guard listType.supportsFolders else {
                throw DatabaseError(message: "Folders are not supported for this library list.")
            }

            // Enforce no duplicate folder names (case-insensitive) — merge with existing
            let existing = try LibraryFolder
                .filter(LibraryFolder.Columns.listType == listType.rawValue)
                .filter(LibraryFolder.Columns.isSystem == false)
                .fetchAll(db)
            if let match = existing.first(where: {
                $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
            }) {
                return match
            }

            let maxSortOrder = try Int.fetchOne(db, sql: """
                SELECT COALESCE(MAX(sortOrder), -1) FROM library_folders
                WHERE listType = ? AND isSystem = 0
                """, arguments: [listType.rawValue]) ?? -1

            let resolvedParentID = parentId ?? LibraryFolder.systemFolderID(for: listType)
            let folder = LibraryFolder(
                id: UUID().uuidString,
                name: trimmedName,
                parentId: resolvedParentID,
                listType: listType,
                folderKind: .manual,
                isSystem: false,
                sortOrder: maxSortOrder + 1,
                createdAt: Date(),
                updatedAt: Date()
            )
            try folder.save(db)
            return folder
        }
    }

    func deleteLibraryFolder(
        id folderId: String,
        listType: UserLibraryEntry.ListType
    ) async throws {
        try await dbPool.write { db in
            try Self.ensureSystemLibraryFolders(in: db)

            guard listType.supportsFolders else {
                throw DatabaseError(message: "Folders are not supported for this library list.")
            }

            guard let folder = try LibraryFolder.fetchOne(db, key: folderId) else { return }

            guard folder.listType == listType else {
                throw DatabaseError(message: "Folder does not belong to the selected list.")
            }

            guard folder.isSystem == false else {
                throw DatabaseError(message: "System folders cannot be deleted.")
            }

            let rootFolderID = LibraryFolder.systemFolderID(for: listType)

            try db.execute(
                sql: """
                UPDATE user_library
                SET folderId = ?
                WHERE listType = ? AND folderId = ?
                """,
                arguments: [rootFolderID, listType.rawValue, folderId]
            )

            try db.execute(
                sql: """
                UPDATE library_folders
                SET parentId = ?, updatedAt = ?
                WHERE listType = ? AND parentId = ?
                """,
                arguments: [rootFolderID, Date(), listType.rawValue, folderId]
            )

            _ = try LibraryFolder.deleteOne(db, key: folderId)
        }
    }

    /// Removes manual folders that contain zero library entries.
    func pruneEmptyManualFolders() async throws {
        try await dbPool.write { db in
            let emptyFolders = try Row.fetchAll(db, sql: """
                SELECT f.id, f.listType FROM library_folders f
                WHERE f.isSystem = 0
                AND NOT EXISTS (
                    SELECT 1 FROM user_library ul
                    WHERE ul.folderId = f.id AND ul.listType = f.listType
                )
                """)
            for row in emptyFolders {
                let folderId: String = row["id"]
                try db.execute(sql: "DELETE FROM library_folders WHERE id = ?", arguments: [folderId])
            }
        }
    }

    func reorderLibraryFolders(
        ids: [String],
        listType: UserLibraryEntry.ListType
    ) async throws {
        try await dbPool.write { db in
            for (index, folderId) in ids.enumerated() {
                try db.execute(
                    sql: """
                    UPDATE library_folders
                    SET sortOrder = ?, updatedAt = ?
                    WHERE id = ? AND listType = ? AND isSystem = 0
                    """,
                    arguments: [index, Date(), folderId, listType.rawValue]
                )
            }
        }
    }

    func moveLibraryEntry(
        mediaId: String,
        listType: UserLibraryEntry.ListType,
        toFolderId folderId: String
    ) async throws {
        try await dbPool.write { db in
            guard listType.supportsFolders else { return }

            guard let destination = try LibraryFolder.fetchOne(db, key: folderId),
                  destination.listType == listType else {
                throw DatabaseError(message: "Destination folder is invalid for the selected list.")
            }

            try db.execute(
                sql: """
                UPDATE user_library
                SET folderId = ?
                WHERE mediaId = ? AND listType = ?
                """,
                arguments: [folderId, mediaId, listType.rawValue]
            )
        }
    }

    // MARK: - Trakt List Mappings

    func saveTraktListMapping(_ mapping: TraktListMapping) async throws {
        try await dbPool.write { db in try mapping.save(db) }
    }

    func fetchTraktListMapping(traktListId: Int) async throws -> TraktListMapping? {
        try await dbPool.read { db in
            try TraktListMapping.filter(TraktListMapping.Columns.traktListId == traktListId).fetchOne(db)
        }
    }

    func fetchTraktListMapping(localFolderId: String) async throws -> TraktListMapping? {
        try await dbPool.read { db in
            try TraktListMapping.filter(TraktListMapping.Columns.localFolderId == localFolderId).fetchOne(db)
        }
    }

    func fetchAllTraktListMappings() async throws -> [TraktListMapping] {
        try await dbPool.read { db in
            try TraktListMapping.fetchAll(db)
        }
    }

    func deleteTraktListMapping(id: String) async throws {
        try await dbPool.write { db in
            _ = try TraktListMapping.deleteOne(db, key: id)
        }
    }

    func deleteTraktListMapping(traktListId: Int) async throws {
        try await dbPool.write { db in
            _ = try TraktListMapping.filter(TraktListMapping.Columns.traktListId == traktListId).deleteAll(db)
        }
    }

    // MARK: - Debrid Configs

    func saveDebridConfig(_ config: DebridConfig) async throws {
        try await dbPool.write { db in try config.save(db) }
    }

    func fetchDebridConfigs() async throws -> [DebridConfig] {
        try await dbPool.read { db in
            try DebridConfig
                .filter(DebridConfig.Columns.isActive == true)
                .order(DebridConfig.Columns.priority.asc)
                .fetchAll(db)
        }
    }

    func fetchAllDebridConfigs() async throws -> [DebridConfig] {
        try await dbPool.read { db in
            try DebridConfig.order(DebridConfig.Columns.priority.asc).fetchAll(db)
        }
    }

    func deleteDebridConfig(id: String) async throws {
        try await dbPool.write { db in _ = try DebridConfig.deleteOne(db, key: id) }
    }

    // MARK: - Indexer Configs

    func saveIndexerConfig(_ config: IndexerConfig) async throws {
        try await dbPool.write { db in try config.save(db) }
    }

    func saveIndexerConfigs(_ configs: [IndexerConfig]) async throws {
        try await dbPool.write { db in
            for config in configs {
                try config.save(db)
            }
        }
    }

    func fetchIndexerConfigs() async throws -> [IndexerConfig] {
        try await dbPool.read { db in
            try IndexerConfig
                .filter(IndexerConfig.Columns.isActive == true)
                .order(IndexerConfig.Columns.priority.asc)
                .fetchAll(db)
        }
    }

    func fetchAllIndexerConfigs() async throws -> [IndexerConfig] {
        try await dbPool.read { db in
            try IndexerConfig
                .order(IndexerConfig.Columns.priority.asc)
                .fetchAll(db)
        }
    }

    func deleteIndexerConfig(id: String) async throws {
        try await dbPool.write { db in
            _ = try IndexerConfig.deleteOne(db, key: id)
        }
    }

    // MARK: - Downloads

    func saveDownloadTask(_ task: DownloadTask) async throws {
        try await dbPool.write { db in try task.save(db) }
    }

    func fetchDownloadTask(id: String) async throws -> DownloadTask? {
        try await dbPool.read { db in try DownloadTask.fetchOne(db, key: id) }
    }

    func fetchDownloadTasks() async throws -> [DownloadTask] {
        try await dbPool.read { db in
            try DownloadTask
                .order(DownloadTask.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    func updateDownloadTaskStatus(id: String, status: DownloadStatus, errorMessage: String? = nil) async throws {
        try await dbPool.write { db in
            let now = Date()
            try db.execute(
                sql: """
                UPDATE download_tasks
                SET status = ?, errorMessage = ?, updatedAt = ?
                WHERE id = ?
                """,
                arguments: [status.rawValue, errorMessage, now, id]
            )
        }
    }

    func updateDownloadTaskProgress(
        id: String,
        progress: Double,
        bytesWritten: Int64,
        totalBytes: Int64?,
        destinationPath: String? = nil
    ) async throws {
        try await dbPool.write { db in
            let now = Date()
            try db.execute(
                sql: """
                UPDATE download_tasks
                SET progress = ?, bytesWritten = ?, totalBytes = ?, destinationPath = COALESCE(?, destinationPath), updatedAt = ?
                WHERE id = ?
                """,
                arguments: [progress, bytesWritten, totalBytes, destinationPath, now, id]
            )
        }
    }

    func deleteDownloadTask(id: String) async throws {
        try await dbPool.write { db in
            _ = try DownloadTask.deleteOne(db, key: id)
        }
    }

    // MARK: - Environment Assets

    func saveEnvironmentAsset(_ asset: EnvironmentAsset) async throws {
        try await dbPool.write { db in
            try asset.save(db)
        }
    }

    func fetchEnvironmentAssets() async throws -> [EnvironmentAsset] {
        try await dbPool.read { db in
            try EnvironmentAsset
                .order(EnvironmentAsset.Columns.isActive.desc, EnvironmentAsset.Columns.name.asc)
                .fetchAll(db)
        }
    }

    func fetchActiveEnvironmentAsset() async throws -> EnvironmentAsset? {
        try await dbPool.read { db in
            try EnvironmentAsset
                .filter(EnvironmentAsset.Columns.isActive == true)
                .fetchOne(db)
        }
    }

    func setActiveEnvironmentAsset(id: String) async throws {
        try await dbPool.write { db in
            try db.execute(sql: "UPDATE environment_assets SET isActive = 0")
            try db.execute(
                sql: "UPDATE environment_assets SET isActive = 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func deleteEnvironmentAsset(id: String) async throws {
        try await dbPool.write { db in
            _ = try EnvironmentAsset.deleteOne(db, key: id)
        }
    }

    // MARK: - Settings

    func setSetting(key: String, value: String?) async throws {
        try await dbPool.write { db in
            if let value {
                try db.execute(sql: "INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)", arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM app_settings WHERE key = ?", arguments: [key])
            }
        }
    }

    func getSetting(key: String) async throws -> String? {
        try await dbPool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_settings WHERE key = ?", arguments: [key])
        }
    }

    // MARK: - Episodes

    func saveEpisodes(_ episodes: [Episode]) async throws {
        try await dbPool.write { db in
            for episode in episodes { try episode.save(db) }
        }
    }

    func fetchEpisodes(mediaId: String, season: Int) async throws -> [Episode] {
        try await dbPool.read { db in
            try Episode
                .filter(Episode.Columns.mediaId == mediaId)
                .filter(Episode.Columns.seasonNumber == season)
                .order(Episode.Columns.episodeNumber.asc)
                .fetchAll(db)
        }
    }

    // MARK: - Taste Profile

    func saveUserTasteProfile(_ profile: UserTasteProfile) async throws {
        try await dbPool.write { db in try profile.save(db) }
    }

    func fetchUserTasteProfile(userId: String = "default") async throws -> UserTasteProfile? {
        try await dbPool.read { db in try UserTasteProfile.fetchOne(db, key: userId) }
    }

    func saveTasteEvent(_ event: TasteEvent) async throws {
        try await dbPool.write { db in try event.save(db) }
        _ = try await applyTasteEventsRetentionPolicy(userId: event.userId)
    }

    @discardableResult
    func applyTasteEventsRetentionPolicy(
        userId: String = "default",
        maxEntries: Int = DatabaseManager.tasteEventsRetentionCap,
        ttl: TimeInterval = DatabaseManager.tasteEventsRetentionTTL,
        now: Date = Date()
    ) async throws -> Int {
        try await dbPool.write { db in
            let effectiveMaxEntries = max(maxEntries, 0)
            let effectiveTTL = max(ttl, 0)
            let cutoffDate = now.addingTimeInterval(-effectiveTTL)

            let beforeCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM taste_events WHERE userId = ?",
                arguments: [userId]
            ) ?? 0

            try db.execute(
                sql: """
                DELETE FROM taste_events
                WHERE userId = ? AND createdAt < ?
                """,
                arguments: [userId, cutoffDate]
            )

            try db.execute(
                sql: """
                DELETE FROM taste_events
                WHERE userId = ?
                  AND id IN (
                    SELECT id
                    FROM taste_events
                    WHERE userId = ?
                    ORDER BY createdAt DESC, id DESC
                    LIMIT -1 OFFSET ?
                  )
                """,
                arguments: [userId, userId, effectiveMaxEntries]
            )

            let afterCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM taste_events WHERE userId = ?",
                arguments: [userId]
            ) ?? 0
            return max(beforeCount - afterCount, 0)
        }
    }

    func fetchTasteEvents(
        userId: String = "default",
        eventType: TasteEvent.EventType? = nil,
        limit: Int = 200
    ) async throws -> [TasteEvent] {
        try await dbPool.read { db in
            var request = TasteEvent
                .filter(TasteEvent.Columns.userId == userId)
                .order(TasteEvent.Columns.createdAt.desc)
                .limit(limit)
            if let eventType {
                request = request.filter(TasteEvent.Columns.eventType == eventType.rawValue)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchLatestTasteRating(
        mediaId: String,
        userId: String = "default"
    ) async throws -> TasteEvent? {
        try await dbPool.read { db in
            try TasteEvent
                .filter(TasteEvent.Columns.userId == userId)
                .filter(TasteEvent.Columns.mediaId == mediaId)
                .filter(TasteEvent.Columns.eventType == TasteEvent.EventType.rated.rawValue)
                .order(TasteEvent.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    func deleteLatestTasteRating(
        mediaId: String,
        userId: String = "default"
    ) async throws {
        try await dbPool.write { db in
            if let event = try TasteEvent
                .filter(TasteEvent.Columns.userId == userId)
                .filter(TasteEvent.Columns.mediaId == mediaId)
                .filter(TasteEvent.Columns.eventType == TasteEvent.EventType.rated.rawValue)
                .order(TasteEvent.Columns.createdAt.desc)
                .fetchOne(db)
            {
                try event.delete(db)
            }
        }
    }

    // MARK: - AI Usage Log

    func saveAIUsageRecord(_ record: AIUsageRecord) async throws {
        try await dbPool.write { db in try record.save(db) }
    }

    func fetchAIUsageRecords(since: Date? = nil, limit: Int = 200) async throws -> [AIUsageRecord] {
        try await dbPool.read { db in
            var request = AIUsageRecord
                .order(AIUsageRecord.Columns.createdAt.desc)
                .limit(limit)
            if let since {
                request = request.filter(AIUsageRecord.Columns.createdAt >= since)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchAIUsageSummary(since: Date? = nil) async throws -> AIUsageSummary {
        try await dbPool.read { db in
            var sql = """
                SELECT
                    COALESCE(SUM(inputTokens), 0) AS totalInput,
                    COALESCE(SUM(outputTokens), 0) AS totalOutput,
                    COALESCE(SUM(estimatedCostUSD), 0.0) AS totalCost,
                    COUNT(*) AS requestCount
                FROM ai_usage_log
                """
            var arguments: StatementArguments = []
            if let since {
                sql += " WHERE createdAt >= ?"
                arguments = [since]
            }

            let row = try Row.fetchOne(db, sql: sql, arguments: arguments)
            let totalInput: Int = row?["totalInput"] ?? 0
            let totalOutput: Int = row?["totalOutput"] ?? 0
            let totalCost: Double = row?["totalCost"] ?? 0
            let requestCount: Int = row?["requestCount"] ?? 0

            // Provider breakdown
            var breakdownSQL = """
                SELECT provider,
                    COALESCE(SUM(inputTokens), 0) AS provInput,
                    COALESCE(SUM(outputTokens), 0) AS provOutput,
                    COALESCE(SUM(estimatedCostUSD), 0.0) AS provCost,
                    COUNT(*) AS provCount
                FROM ai_usage_log
                """
            var breakdownArgs: StatementArguments = []
            if let since {
                breakdownSQL += " WHERE createdAt >= ?"
                breakdownArgs = [since]
            }
            breakdownSQL += " GROUP BY provider"

            let rows = try Row.fetchAll(db, sql: breakdownSQL, arguments: breakdownArgs)
            var byProvider: [AIProviderKind: ProviderUsage] = [:]
            for provRow in rows {
                let providerRaw: String = provRow["provider"]
                guard let providerKind = AIProviderKind(rawValue: providerRaw) else { continue }
                byProvider[providerKind] = ProviderUsage(
                    inputTokens: provRow["provInput"],
                    outputTokens: provRow["provOutput"],
                    costUSD: provRow["provCost"],
                    requestCount: provRow["provCount"]
                )
            }

            return AIUsageSummary(
                totalInputTokens: totalInput,
                totalOutputTokens: totalOutput,
                totalCostUSD: totalCost,
                byProvider: byProvider,
                requestCount: requestCount
            )
        }
    }

    func deleteAllAIUsageRecords() async throws {
        try await dbPool.write { db in
            try db.execute(sql: "DELETE FROM ai_usage_log")
        }
    }

    // MARK: - AI Context Snapshots

    func saveContextSnapshot(_ snapshot: AIContextSnapshot) async throws {
        try await dbPool.write { db in
            // Only keep one row — delete any existing before inserting
            try db.execute(sql: "DELETE FROM ai_context_snapshots")
            try snapshot.save(db)
        }
    }

    func fetchLatestContextSnapshot() async throws -> AIContextSnapshot? {
        try await dbPool.read { db in
            try AIContextSnapshot
                .order(AIContextSnapshot.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    func deleteContextSnapshots() async throws {
        try await dbPool.write { db in
            try db.execute(sql: "DELETE FROM ai_context_snapshots")
        }
    }

    /// Deletes all user data from every table. Used by the "Reset All Data" flow.
    func resetAllData() async throws {
        try await dbPool.write { db in
            let tables = [
                "ai_context_snapshots",
                "ai_usage_log",
                "environment_assets",
                "download_tasks",
                "app_settings",
                "taste_events",
                "user_taste_profiles",
                "indexer_configs",
                "debrid_configs",
                "trakt_list_mappings",
                "library_folders",
                "user_library",
                "watch_history",
                "episodes",
                "media_cache",
            ]
            for table in tables {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    private static func ensureSystemLibraryFolders(in db: Database) throws {
        for listType in UserLibraryEntry.ListType.allCases {
            let folderID = LibraryFolder.systemFolderID(for: listType)
            let existing = try LibraryFolder.fetchOne(db, key: folderID)
            if existing != nil {
                continue
            }

            let folder = LibraryFolder(
                id: folderID,
                name: LibraryFolder.systemFolderName(for: listType),
                parentId: nil,
                listType: listType,
                folderKind: .systemRoot,
                isSystem: true,
                createdAt: Date(),
                updatedAt: Date()
            )
            try folder.save(db)
        }
    }

    private static func normalizedTitleEquivalenceKey(_ title: String) -> String {
        let folded = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        var normalized = ""
        normalized.reserveCapacity(folded.count)
        var lastWasSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                normalized.append(" ")
                lastWasSeparator = true
            }
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DatabaseError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}
