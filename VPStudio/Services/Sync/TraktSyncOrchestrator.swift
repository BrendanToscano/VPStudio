import Foundation

/// Coordinates bi-directional sync between Trakt and the local database.
///
/// **Pull (Trakt -> Local):**
/// - Watchlist items become `UserLibraryEntry(listType: .watchlist)`
/// - Ratings become `TasteEvent(eventType: .rated)` with 1-10 scale
/// - History items become `WatchHistory` records (isCompleted=true) **and**
///   `UserLibraryEntry(listType: .history)` for backwards compatibility.
///   Pull paginates up to 20 pages (1,000 items) per media type.
///
/// **Push (Local -> Trakt):**
/// - Local watchlist entries with IMDb IDs are added to Trakt watchlist
/// - Local rated taste events are pushed as Trakt ratings
/// - Completed local `WatchHistory` entries with IMDb IDs are pushed to Trakt history
///
/// The orchestrator is resilient: individual operation failures are logged in
/// `SyncResult.errors` rather than thrown, so a single Trakt API failure does
/// not prevent other sync operations from completing.
actor TraktSyncOrchestrator {
    private let traktService: TraktSyncService
    private let database: DatabaseManager
    private let settingsManager: SettingsManager

    init(
        traktService: TraktSyncService,
        database: DatabaseManager,
        settingsManager: SettingsManager
    ) {
        self.traktService = traktService
        self.database = database
        self.settingsManager = settingsManager
    }

    /// Performs a full bi-directional sync based on current toggle settings.
    func sync() async -> SyncResult {
        var result = SyncResult()

        let syncWatchlist = (try? await settingsManager.getBool(
            key: SettingsKeys.traktSyncWatchlist, default: true
        )) ?? true

        let syncHistory = (try? await settingsManager.getBool(
            key: SettingsKeys.traktSyncHistory, default: true
        )) ?? true

        let syncRatings = (try? await settingsManager.getBool(
            key: SettingsKeys.traktSyncRatings, default: true
        )) ?? true

        // --- Pull ---

        if syncWatchlist {
            let pullResult = await pullWatchlist()
            result.watchlistPulled = pullResult.count
            result.errors.append(contentsOf: pullResult.errors)
        }

        if syncRatings {
            let pullResult = await pullRatings()
            result.ratingsPulled = pullResult.count
            result.errors.append(contentsOf: pullResult.errors)
        }

        if syncHistory {
            let pullResult = await pullHistory()
            result.historyPulled = pullResult.count
            result.errors.append(contentsOf: pullResult.errors)
        }

        // --- Push ---

        if syncWatchlist {
            let pushResult = await pushWatchlist()
            result.watchlistPushed = pushResult.count
            result.errors.append(contentsOf: pushResult.errors)
        }

        if syncRatings {
            let pushResult = await pushRatings()
            result.ratingsPushed = pushResult.count
            result.errors.append(contentsOf: pushResult.errors)
        }

        if syncHistory {
            let pushResult = await pushHistory()
            result.historyPushed = pushResult.count
            result.errors.append(contentsOf: pushResult.errors)
        }

        // --- Folders (bi-directional, uses Trakt custom lists) ---

        let syncFolders = (try? await settingsManager.getBool(
            key: SettingsKeys.traktSyncFolders, default: false
        )) ?? false

        if syncFolders {
            let folderResult = await syncCustomLists()
            result.foldersPulled = folderResult.pulled
            result.foldersPushed = folderResult.pushed
            result.errors.append(contentsOf: folderResult.errors)
        }

        // Record last sync timestamp
        let formatter = ISO8601DateFormatter()
        try? await settingsManager.setString(
            key: SettingsKeys.traktLastSyncDate,
            value: formatter.string(from: Date())
        )

        return result
    }

    // MARK: - Pull Operations

    private func pullWatchlist() async -> OperationResult {
        var created = 0
        var errors: [String] = []

        for mediaType in [MediaType.movie, MediaType.series] {
            do {
                let items = try await traktService.getWatchlist(type: mediaType)
                for item in items {
                    guard let mediaId = extractMediaId(from: item) else { continue }
                    do {
                        let exists = try await database.isInLibrary(
                            mediaId: mediaId, listType: .watchlist
                        )
                        if !exists {
                            let entry = UserLibraryEntry(
                                id: UUID().uuidString,
                                mediaId: mediaId,
                                folderId: LibraryFolder.systemFolderID(for: .watchlist),
                                listType: .watchlist,
                                addedAt: Date()
                            )
                            try await database.addToLibrary(entry)
                            created += 1
                        }
                        // Ensure a stub MediaItem exists so LibraryView can display it
                        try? await ensureMediaItem(from: item, mediaId: mediaId)
                    } catch {
                        errors.append("Pull watchlist entry \(mediaId): \(error.localizedDescription)")
                    }
                }
            } catch {
                errors.append("Pull watchlist (\(mediaType.rawValue)): \(error.localizedDescription)")
            }
        }

        return OperationResult(count: created, errors: errors)
    }

    private func pullRatings() async -> OperationResult {
        var created = 0
        var errors: [String] = []

        for mediaType in [MediaType.movie, MediaType.series] {
            do {
                let items = try await traktService.getRatings(type: mediaType)
                for item in items {
                    guard let mediaId = extractRatingMediaId(from: item) else { continue }
                    do {
                        let existing = try await database.fetchLatestTasteRating(mediaId: mediaId)
                        if existing == nil {
                            let event = TasteEvent(
                                userId: "default",
                                mediaId: mediaId,
                                eventType: .rated,
                                signalStrength: 1.0,
                                feedbackScale: .oneToTen,
                                feedbackValue: Double(item.rating),
                                source: .automatic,
                                metadata: ["trakt_synced": "true"]
                            )
                            try await database.saveTasteEvent(event)
                            created += 1
                        }
                    } catch {
                        errors.append("Pull rating \(mediaId): \(error.localizedDescription)")
                    }
                }
            } catch {
                errors.append("Pull ratings (\(mediaType.rawValue)): \(error.localizedDescription)")
            }
        }

        return OperationResult(count: created, errors: errors)
    }

    /// Maximum number of pages to fetch during history pull (each page = 50 items).
    static let maxHistoryPages = 20

    private func pullHistory() async -> OperationResult {
        var created = 0
        var errors: [String] = []

        for mediaType in [MediaType.movie, MediaType.series] {
            do {
                var page = 1
                var keepPaging = true

                while keepPaging, page <= Self.maxHistoryPages {
                    let items = try await traktService.getHistory(type: mediaType, page: page)

                    for item in items {
                        guard let mediaId = extractHistoryMediaId(from: item) else { continue }
                        do {
                            // Write to WatchHistory table (what the app actually displays)
                            let existingWatch = try await database.fetchWatchHistory(mediaId: mediaId)
                            if existingWatch == nil {
                                let title = extractHistoryTitle(from: item)
                                let watchedAt = parseHistoryDate(item.watchedAt) ?? Date()

                                let watchHistory = WatchHistory(
                                    id: UUID().uuidString,
                                    mediaId: mediaId,
                                    episodeId: nil,
                                    title: title,
                                    progress: 0,
                                    duration: 0,
                                    quality: nil,
                                    debridService: nil,
                                    streamURL: nil,
                                    watchedAt: watchedAt,
                                    isCompleted: true
                                )
                                try await database.saveWatchHistory(watchHistory)
                                created += 1
                            }

                            // Also keep UserLibraryEntry for backwards compatibility
                            let libraryExists = try await database.isInLibrary(
                                mediaId: mediaId, listType: .history
                            )
                            if !libraryExists {
                                let entry = UserLibraryEntry(
                                    id: UUID().uuidString,
                                    mediaId: mediaId,
                                    folderId: LibraryFolder.systemFolderID(for: .history),
                                    listType: .history,
                                    addedAt: Date()
                                )
                                try await database.addToLibrary(entry)
                            }
                        } catch {
                            errors.append("Pull history entry \(mediaId): \(error.localizedDescription)")
                        }
                    }

                    // Stop paging if this page had fewer than 50 items (last page)
                    keepPaging = items.count >= 50
                    page += 1
                }
            } catch {
                errors.append("Pull history (\(mediaType.rawValue)): \(error.localizedDescription)")
            }
        }

        return OperationResult(count: created, errors: errors)
    }

    // MARK: - Push Operations

    private func pushWatchlist() async -> OperationResult {
        var pushed = 0
        var errors: [String] = []

        do {
            let localEntries = try await database.fetchLibraryEntries(listType: .watchlist)
            // Fetch remote watchlist IMDb IDs for deduplication
            let remoteImdbIds = await fetchRemoteWatchlistImdbIds()

            for entry in localEntries {
                let mediaId = entry.mediaId
                // Only push items that look like IMDb IDs (the format Trakt expects)
                guard mediaId.hasPrefix("tt") else { continue }
                guard !remoteImdbIds.contains(mediaId) else { continue }

                do {
                    // Determine media type from the mediaId by checking cached media items
                    let mediaType = await resolveMediaType(for: mediaId)
                    try await traktService.addToWatchlist(imdbId: mediaId, type: mediaType)
                    pushed += 1
                } catch {
                    errors.append("Push watchlist \(mediaId): \(error.localizedDescription)")
                }
            }
        } catch {
            errors.append("Push watchlist fetch: \(error.localizedDescription)")
        }

        return OperationResult(count: pushed, errors: errors)
    }

    private func pushRatings() async -> OperationResult {
        var pushed = 0
        var errors: [String] = []

        do {
            let events = try await database.fetchTasteEvents(eventType: .rated, limit: 500)
            // Fetch remote ratings for deduplication
            let remoteRatedIds = await fetchRemoteRatedImdbIds()

            // Deduplicate: only the latest rating per mediaId
            var seenMediaIds = Set<String>()
            for event in events {
                guard let mediaId = event.mediaId, mediaId.hasPrefix("tt") else { continue }
                guard !seenMediaIds.contains(mediaId) else { continue }
                seenMediaIds.insert(mediaId)

                guard !remoteRatedIds.contains(mediaId) else { continue }
                guard let feedbackValue = event.feedbackValue else { continue }

                do {
                    let mediaType = await resolveMediaType(for: mediaId)
                    let rating = Int(feedbackValue.rounded())
                    let clampedRating = max(1, min(10, rating))
                    try await traktService.addRating(
                        imdbId: mediaId, rating: clampedRating, type: mediaType
                    )
                    pushed += 1
                } catch {
                    errors.append("Push rating \(mediaId): \(error.localizedDescription)")
                }
            }
        } catch {
            errors.append("Push ratings fetch: \(error.localizedDescription)")
        }

        return OperationResult(count: pushed, errors: errors)
    }

    private func pushHistory() async -> OperationResult {
        var pushed = 0
        var errors: [String] = []

        do {
            let localEntries = try await database.fetchCompletedWatchHistory()
            // Fetch remote history IMDb IDs for deduplication
            let remoteImdbIds = await fetchRemoteHistoryImdbIds()

            for entry in localEntries {
                let mediaId = entry.mediaId
                // Only push items that look like IMDb IDs (the format Trakt expects)
                guard mediaId.hasPrefix("tt") else { continue }
                guard !remoteImdbIds.contains(mediaId) else { continue }

                do {
                    let mediaType = await resolveMediaType(for: mediaId)
                    try await traktService.addToHistory(
                        imdbId: mediaId, type: mediaType, watchedAt: entry.watchedAt
                    )
                    pushed += 1
                } catch {
                    errors.append("Push history \(mediaId): \(error.localizedDescription)")
                }
            }
        } catch {
            errors.append("Push history fetch: \(error.localizedDescription)")
        }

        return OperationResult(count: pushed, errors: errors)
    }

    // MARK: - Custom List / Folder Sync

    private struct FolderSyncResult {
        var pulled: Int
        var pushed: Int
        var errors: [String]
    }

    /// Bi-directional sync between local Library folders and Trakt custom lists.
    ///
    /// **Pull:** Trakt lists without a local mapping create a new local folder + mapping.
    ///           Items in each Trakt list are added to the corresponding local folder.
    /// **Push:** Local custom folders without a Trakt mapping create a new Trakt list + mapping.
    ///           Items in each local folder are pushed to the corresponding Trakt list.
    private func syncCustomLists() async -> FolderSyncResult {
        var pulled = 0
        var pushed = 0
        var errors: [String] = []

        // --- Pull: Trakt lists → local folders ---

        do {
            let remoteLists = try await traktService.getCustomLists()
            let existingMappings = try await database.fetchAllTraktListMappings()
            let mappedTraktIds = Set(existingMappings.map(\.traktListId))

            for list in remoteLists {
                let traktId = list.ids.trakt

                if mappedTraktIds.contains(traktId) {
                    // Already mapped — sync items into the existing folder
                    guard let mapping = existingMappings.first(where: { $0.traktListId == traktId }) else { continue }
                    do {
                        let itemsPulled = try await pullListItems(
                            traktListId: traktId,
                            localFolderId: mapping.localFolderId,
                            listType: mapping.listType
                        )
                        pulled += itemsPulled
                    } catch {
                        errors.append("Pull list items \(list.name): \(error.localizedDescription)")
                    }
                } else {
                    // New Trakt list — create local folder + mapping
                    do {
                        let folder = try await database.createLibraryFolder(
                            name: list.name,
                            listType: .watchlist
                        )
                        let mapping = TraktListMapping(
                            traktListId: traktId,
                            traktListSlug: list.ids.slug,
                            localFolderId: folder.id,
                            listType: .watchlist
                        )
                        try await database.saveTraktListMapping(mapping)

                        let itemsPulled = try await pullListItems(
                            traktListId: traktId,
                            localFolderId: folder.id,
                            listType: .watchlist
                        )
                        pulled += itemsPulled
                    } catch {
                        errors.append("Create folder for Trakt list \(list.name): \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            errors.append("Fetch Trakt custom lists: \(error.localizedDescription)")
        }

        // --- Push: local folders → Trakt lists ---

        do {
            let allFolders = try await database.fetchAllLibraryFolders(listType: .watchlist)
            let customFolders = allFolders.filter { !$0.isSystem && $0.folderKind == .manual }
            let existingMappings = try await database.fetchAllTraktListMappings()
            let mappedFolderIds = Set(existingMappings.map(\.localFolderId))

            for folder in customFolders {
                if mappedFolderIds.contains(folder.id) {
                    // Already mapped — push local items not yet on the Trakt list
                    guard let mapping = existingMappings.first(where: { $0.localFolderId == folder.id }) else { continue }
                    do {
                        let itemsPushed = try await pushFolderItems(
                            localFolderId: folder.id,
                            traktListId: mapping.traktListId,
                            listType: mapping.listType
                        )
                        pushed += itemsPushed
                    } catch {
                        errors.append("Push folder items \(folder.name): \(error.localizedDescription)")
                    }
                } else {
                    // New local folder — create Trakt list + mapping
                    do {
                        let traktList = try await traktService.createCustomList(name: folder.name)
                        let mapping = TraktListMapping(
                            traktListId: traktList.ids.trakt,
                            traktListSlug: traktList.ids.slug,
                            localFolderId: folder.id,
                            listType: .watchlist
                        )
                        try await database.saveTraktListMapping(mapping)

                        let itemsPushed = try await pushFolderItems(
                            localFolderId: folder.id,
                            traktListId: traktList.ids.trakt,
                            listType: .watchlist
                        )
                        pushed += itemsPushed
                    } catch {
                        errors.append("Create Trakt list for folder \(folder.name): \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            errors.append("Fetch local folders: \(error.localizedDescription)")
        }

        return FolderSyncResult(pulled: pulled, pushed: pushed, errors: errors)
    }

    /// Pulls items from a Trakt list into a local folder.
    private func pullListItems(
        traktListId: Int,
        localFolderId: String,
        listType: UserLibraryEntry.ListType
    ) async throws -> Int {
        let items = try await traktService.getListItems(listId: traktListId)
        var created = 0

        for item in items {
            let mediaId: String?
            if let imdb = item.movie?.ids.imdb, !imdb.isEmpty { mediaId = imdb }
            else if let imdb = item.show?.ids.imdb, !imdb.isEmpty { mediaId = imdb }
            else if let tmdb = item.movie?.ids.tmdb { mediaId = "tmdb-\(tmdb)" }
            else if let tmdb = item.show?.ids.tmdb { mediaId = "tmdb-\(tmdb)" }
            else { mediaId = nil }

            guard let mediaId else { continue }

            let exists = try await database.isInLibrary(mediaId: mediaId, listType: listType)
            if !exists {
                let entry = UserLibraryEntry(
                    id: "\(mediaId)-\(listType.rawValue)",
                    mediaId: mediaId,
                    folderId: localFolderId,
                    listType: listType,
                    addedAt: Date()
                )
                try await database.addToLibrary(entry)
                created += 1
            }
            // Ensure a stub MediaItem exists so LibraryView can display it
            let traktItem = TraktItem(
                rank: nil, listedAt: nil,
                movie: item.movie, show: item.show
            )
            try? await ensureMediaItem(from: traktItem, mediaId: mediaId)
        }

        return created
    }

    /// Pushes items from a local folder to a Trakt list.
    private func pushFolderItems(
        localFolderId: String,
        traktListId: Int,
        listType: UserLibraryEntry.ListType
    ) async throws -> Int {
        let entries = try await database.fetchLibraryEntries(
            listType: listType,
            folderId: localFolderId
        )

        // Get existing items on the Trakt list for dedup
        let remoteItems = try await traktService.getListItems(listId: traktListId)
        var remoteImdbIds = Set<String>()
        for item in remoteItems {
            if let imdb = item.movie?.ids.imdb { remoteImdbIds.insert(imdb) }
            if let imdb = item.show?.ids.imdb { remoteImdbIds.insert(imdb) }
        }

        // Collect items to push
        var toPush: [(id: String, type: MediaType)] = []
        for entry in entries {
            guard entry.mediaId.hasPrefix("tt") else { continue }
            guard !remoteImdbIds.contains(entry.mediaId) else { continue }
            let mediaType = await resolveMediaType(for: entry.mediaId)
            toPush.append((id: entry.mediaId, type: mediaType))
        }

        if !toPush.isEmpty {
            try await traktService.addToCustomList(listId: traktListId, imdbIds: toPush)
        }

        return toPush.count
    }

    // MARK: - Helpers

    /// Extracts the IMDb ID from a TraktItem, preferring the IMDb ID, falling back to tmdb-prefixed.
    private func extractMediaId(from item: TraktItem) -> String? {
        if let imdb = item.movie?.ids.imdb, !imdb.isEmpty { return imdb }
        if let imdb = item.show?.ids.imdb, !imdb.isEmpty { return imdb }
        if let tmdb = item.movie?.ids.tmdb { return "tmdb-\(tmdb)" }
        if let tmdb = item.show?.ids.tmdb { return "tmdb-\(tmdb)" }
        return nil
    }

    private func extractRatingMediaId(from item: TraktRatingItem) -> String? {
        if let imdb = item.movie?.ids.imdb, !imdb.isEmpty { return imdb }
        if let imdb = item.show?.ids.imdb, !imdb.isEmpty { return imdb }
        if let tmdb = item.movie?.ids.tmdb { return "tmdb-\(tmdb)" }
        if let tmdb = item.show?.ids.tmdb { return "tmdb-\(tmdb)" }
        return nil
    }

    private func extractHistoryMediaId(from item: TraktHistoryItem) -> String? {
        if let imdb = item.movie?.ids.imdb, !imdb.isEmpty { return imdb }
        if let imdb = item.show?.ids.imdb, !imdb.isEmpty { return imdb }
        if let tmdb = item.movie?.ids.tmdb { return "tmdb-\(tmdb)" }
        if let tmdb = item.show?.ids.tmdb { return "tmdb-\(tmdb)" }
        return nil
    }

    /// Fetches all IMDb IDs in the remote Trakt watchlist for deduplication during push.
    private func fetchRemoteWatchlistImdbIds() async -> Set<String> {
        var ids = Set<String>()
        for mediaType in [MediaType.movie, MediaType.series] {
            if let items = try? await traktService.getWatchlist(type: mediaType) {
                for item in items {
                    if let imdb = item.movie?.ids.imdb ?? item.show?.ids.imdb {
                        ids.insert(imdb)
                    }
                }
            }
        }
        return ids
    }

    /// Fetches all IMDb IDs that already have ratings on Trakt for deduplication during push.
    private func fetchRemoteRatedImdbIds() async -> Set<String> {
        var ids = Set<String>()
        for mediaType in [MediaType.movie, MediaType.series] {
            if let items = try? await traktService.getRatings(type: mediaType) {
                for item in items {
                    if let imdb = item.movie?.ids.imdb ?? item.show?.ids.imdb {
                        ids.insert(imdb)
                    }
                }
            }
        }
        return ids
    }

    /// Fetches all IMDb IDs that already exist in Trakt history for deduplication during push.
    private func fetchRemoteHistoryImdbIds() async -> Set<String> {
        var ids = Set<String>()
        for mediaType in [MediaType.movie, MediaType.series] {
            if let items = try? await traktService.getHistory(type: mediaType) {
                for item in items {
                    if let imdb = item.movie?.ids.imdb ?? item.show?.ids.imdb {
                        ids.insert(imdb)
                    }
                }
            }
        }
        return ids
    }

    /// Extracts a display title from a Trakt history item.
    private func extractHistoryTitle(from item: TraktHistoryItem) -> String {
        item.movie?.title ?? item.show?.title ?? "Unknown"
    }

    /// Parses an ISO 8601 date string from Trakt into a `Date`.
    private func parseHistoryDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) { return date }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) { return date }
        // Fallback: date-only
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: dateString)
    }

    /// Creates a stub MediaItem from Trakt data if one doesn't already exist locally.
    /// This ensures LibraryView can display the entry even before TMDB metadata is fetched.
    private func ensureMediaItem(from item: TraktItem, mediaId: String) async throws {
        if (try? await database.fetchMediaItem(id: mediaId)) != nil { return }
        let title = item.movie?.title ?? item.show?.title ?? "Unknown"
        let year = item.movie?.year ?? item.show?.year
        let type: MediaType = item.show != nil ? .series : .movie
        let tmdbId = item.movie?.ids.tmdb ?? item.show?.ids.tmdb
        let stub = MediaItem(
            id: mediaId,
            type: type,
            title: title,
            year: year,
            posterPath: nil,
            backdropPath: nil,
            overview: nil,
            genres: [],
            imdbRating: nil,
            runtime: nil,
            status: nil,
            tmdbId: tmdbId,
            lastFetched: nil
        )
        try await database.saveMediaItem(stub)
    }

    /// Resolves the media type for a given mediaId by checking the cached media item.
    /// Falls back to `.movie` if not found.
    private func resolveMediaType(for mediaId: String) async -> MediaType {
        if let item = try? await database.fetchMediaItem(id: mediaId) {
            return item.type
        }
        return .movie
    }
}

// MARK: - SyncResult

extension TraktSyncOrchestrator {
    struct SyncResult: Sendable, Equatable {
        var watchlistPulled: Int = 0
        var watchlistPushed: Int = 0
        var ratingsPulled: Int = 0
        var ratingsPushed: Int = 0
        var historyPulled: Int = 0
        var historyPushed: Int = 0
        var foldersPulled: Int = 0
        var foldersPushed: Int = 0
        var errors: [String] = []

        var totalPulled: Int { watchlistPulled + ratingsPulled + historyPulled + foldersPulled }
        var totalPushed: Int { watchlistPushed + ratingsPushed + historyPushed + foldersPushed }
        var hasErrors: Bool { !errors.isEmpty }

        var summary: String {
            var parts: [String] = []
            if watchlistPulled > 0 { parts.append("\(watchlistPulled) watchlist pulled") }
            if watchlistPushed > 0 { parts.append("\(watchlistPushed) watchlist pushed") }
            if ratingsPulled > 0 { parts.append("\(ratingsPulled) ratings pulled") }
            if ratingsPushed > 0 { parts.append("\(ratingsPushed) ratings pushed") }
            if historyPulled > 0 { parts.append("\(historyPulled) history pulled") }
            if historyPushed > 0 { parts.append("\(historyPushed) history pushed") }
            if foldersPulled > 0 { parts.append("\(foldersPulled) folder items pulled") }
            if foldersPushed > 0 { parts.append("\(foldersPushed) folder items pushed") }
            if parts.isEmpty && !hasErrors { return "Everything is up to date." }
            if parts.isEmpty && hasErrors { return "Sync completed with \(errors.count) error(s)." }
            var message = parts.joined(separator: ", ") + "."
            if hasErrors { message += " \(errors.count) error(s)." }
            return message
        }
    }

    /// Internal result type for individual pull/push operations.
    private struct OperationResult {
        let count: Int
        let errors: [String]
    }
}
