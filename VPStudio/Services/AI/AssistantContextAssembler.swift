import Foundation

/// Assembles a structured context string for the AI assistant by querying the database
/// for user taste profile, watch history, ratings, watchlist, favorites, and search history.
///
/// Follows the DebridStreamer `AssistantContextAssembler` pattern: query structured app data,
/// apply recency decay, and produce descriptive context notes and candidate titles.
actor AssistantContextAssembler {

    // MARK: - Snapshot Model

    struct ContextSnapshot: Codable, Sendable, Equatable {
        /// Up to 30 descriptive notes summarizing the user's taste and activity.
        let contextNotes: [String]
        /// Up to 100 unique title strings from the user's library, history, and ratings.
        let candidateTitles: [String]
        /// When this snapshot was assembled.
        let assembledAt: Date

        /// A snapshot is stale after 24 hours.
        var isStale: Bool { Date().timeIntervalSince(assembledAt) > AIContextSnapshot.staleness }

        static let empty = ContextSnapshot(contextNotes: [], candidateTitles: [], assembledAt: .distantPast)
    }

    // MARK: - Budget Constants

    static let maxContextNotes = 30
    static let maxCandidateTitles = 100
    static let maxWatchHistoryEntries = 80
    static let maxTasteEvents = 100
    static let maxWatchlistTitles = 50
    static let maxFavoritesTitles = 50
    static let maxSearchQueries = 20
    static let maxFolderNames = 20

    /// 90-day recency window, floored at 0.1
    static let recencyWindowDays: Double = 90.0
    static let recencyFloor: Double = 0.1

    // MARK: - Cached Snapshot

    private var cached: ContextSnapshot?
    private var forceRebuild = false

    // MARK: - Public API

    /// Returns a cached snapshot if fresh, otherwise assembles a new one.
    func cachedOrAssemble(from database: DatabaseManager) async throws -> ContextSnapshot {
        if !forceRebuild, let cached, !cached.isStale {
            return cached
        }

        // Try to load from database (skip if force rebuild was requested)
        if !forceRebuild, let dbSnapshot = try await database.fetchLatestContextSnapshot() {
            let decoded = try dbSnapshot.decoded()
            if !decoded.isStale {
                cached = decoded
                return decoded
            }
        }

        forceRebuild = false

        // Assemble fresh
        let snapshot = try await assembleContext(from: database)

        // Persist to database
        let record = try AIContextSnapshot.from(snapshot)
        try await database.saveContextSnapshot(record)

        cached = snapshot
        return snapshot
    }

    /// Forces a fresh assembly, bypassing the cache.
    func assembleContext(from database: DatabaseManager) async throws -> ContextSnapshot {
        let now = Date()
        var notes: [String] = []
        var candidateTitles: [String] = []
        var seenTitles = Set<String>()

        // 1. User taste profile
        if let profile = try await database.fetchUserTasteProfile() {
            appendTasteProfileNotes(profile: profile, to: &notes)
        }

        // 2. Watch history with recency decay
        let history = try await database.fetchWatchHistory(limit: Self.maxWatchHistoryEntries)
        appendWatchHistoryNotes(history: history, now: now, to: &notes)
        for entry in history {
            addUniqueTitle(entry.title, to: &candidateTitles, seen: &seenTitles)
        }

        // 3. Taste events / ratings with recency decay
        let tasteEvents = try await database.fetchTasteEvents(eventType: .rated, limit: Self.maxTasteEvents)
        let mediaIDs = Set(tasteEvents.compactMap(\.mediaId))
        let titleByMediaID = await resolveTitles(mediaIDs: mediaIDs, from: database)
        appendTasteEventNotes(events: tasteEvents, titleByMediaID: titleByMediaID, now: now, to: &notes)
        for event in tasteEvents {
            if let title = resolvedTitle(for: event, titleByMediaID: titleByMediaID) {
                addUniqueTitle(title, to: &candidateTitles, seen: &seenTitles)
            }
        }

        // 4. Watchlist titles
        let watchlistEntries = try await database.fetchLibraryEntries(listType: .watchlist)
        let watchlistMediaIDs = Set(watchlistEntries.map(\.mediaId))
        let watchlistTitles = await resolveTitles(mediaIDs: watchlistMediaIDs, from: database)
        let watchlistNames = watchlistEntries
            .prefix(Self.maxWatchlistTitles)
            .compactMap { watchlistTitles[$0.mediaId] }
        if !watchlistNames.isEmpty {
            notes.append("Watchlist (\(watchlistNames.count) titles): \(watchlistNames.prefix(15).joined(separator: ", "))")
            for title in watchlistNames {
                addUniqueTitle(title, to: &candidateTitles, seen: &seenTitles)
            }
        }

        // 5. Favorites titles
        let favoriteEntries = try await database.fetchLibraryEntries(listType: .favorites)
        let favMediaIDs = Set(favoriteEntries.map(\.mediaId))
        let favTitles = await resolveTitles(mediaIDs: favMediaIDs, from: database)
        let favoriteNames = favoriteEntries
            .prefix(Self.maxFavoritesTitles)
            .compactMap { favTitles[$0.mediaId] }
        if !favoriteNames.isEmpty {
            notes.append("Favorites (\(favoriteNames.count) titles): \(favoriteNames.prefix(15).joined(separator: ", "))")
            for title in favoriteNames {
                addUniqueTitle(title, to: &candidateTitles, seen: &seenTitles)
            }
        }

        // 6. Library folder names
        let folders = try await database.fetchAllLibraryFolders()
        let folderNames = folders
            .filter { !$0.isSystem }
            .prefix(Self.maxFolderNames)
            .map(\.name)
        if !folderNames.isEmpty {
            notes.append("Library folders: \(folderNames.joined(separator: ", "))")
        }

        // 7. Recent search queries
        if let searchesJSON = try await database.getSetting(key: SettingsKeys.recentSearches),
           let data = searchesJSON.data(using: .utf8),
           let queries = try? JSONDecoder().decode([String].self, from: data) {
            let recent = Array(queries.prefix(Self.maxSearchQueries))
            if !recent.isEmpty {
                notes.append("Recent searches: \(recent.joined(separator: ", "))")
            }
        }

        // Trim to budget
        let trimmedNotes = Array(notes.prefix(Self.maxContextNotes))
        let trimmedTitles = Array(candidateTitles.prefix(Self.maxCandidateTitles))

        let snapshot = ContextSnapshot(
            contextNotes: trimmedNotes,
            candidateTitles: trimmedTitles,
            assembledAt: now
        )

        cached = snapshot
        return snapshot
    }

    /// Invalidates the in-memory cache, forcing the next `cachedOrAssemble` to rebuild.
    /// Also sets `forceRebuild` so the DB snapshot is ignored on the next call.
    func invalidateCache() {
        cached = nil
        forceRebuild = true
    }

    // MARK: - Recency Decay

    /// Calculates a recency weight using a linear decay over a 90-day window, floored at 0.1.
    static func recencyDecay(from date: Date, now: Date = Date()) -> Double {
        let daysSince = now.timeIntervalSince(date) / 86400
        return max(recencyFloor, 1.0 - (daysSince / recencyWindowDays))
    }

    // MARK: - Private Helpers

    private func appendTasteProfileNotes(profile: UserTasteProfile, to notes: inout [String]) {
        if !profile.likedGenres.isEmpty {
            notes.append("Liked genres: \(profile.likedGenres.joined(separator: ", "))")
        }
        if !profile.dislikedGenres.isEmpty {
            notes.append("Disliked genres: \(profile.dislikedGenres.joined(separator: ", "))")
        }
        if !profile.preferredDecades.isEmpty {
            notes.append("Preferred decades: \(profile.preferredDecades.joined(separator: ", "))")
        }
        if !profile.preferredLanguages.isEmpty {
            notes.append("Preferred languages: \(profile.preferredLanguages.joined(separator: ", "))")
        }
    }

    private func appendWatchHistoryNotes(history: [WatchHistory], now: Date, to notes: inout [String]) {
        guard !history.isEmpty else { return }

        var recentTitles: [String] = []
        var olderTitles: [String] = []
        var seenForNotes = Set<String>()

        for entry in history {
            let key = entry.title.lowercased()
            guard seenForNotes.insert(key).inserted else { continue }

            let decay = Self.recencyDecay(from: entry.watchedAt, now: now)
            let daysAgo = Int(now.timeIntervalSince(entry.watchedAt) / 86400)
            let progressPct = Int(entry.progressPercent * 100)
            let decayStr = String(format: "%.1f", decay)

            let note = "\(entry.title) (\(daysAgo)d ago, \(progressPct)% watched, weight \(decayStr))"

            if daysAgo <= 7 {
                recentTitles.append(note)
            } else {
                olderTitles.append(note)
            }
        }

        if !recentTitles.isEmpty {
            notes.append("Recently watched (last 7 days): \(recentTitles.prefix(10).joined(separator: "; "))")
        }
        if !olderTitles.isEmpty {
            notes.append("Watch history: \(olderTitles.prefix(15).joined(separator: "; "))")
        }
    }

    private func appendTasteEventNotes(
        events: [TasteEvent],
        titleByMediaID: [String: String],
        now: Date,
        to notes: inout [String]
    ) {
        guard !events.isEmpty else { return }

        var likedWithDecay: [(String, Double)] = []
        var dislikedWithDecay: [(String, Double)] = []

        for event in events {
            guard let value = event.feedbackValue else { continue }
            let scale = (event.feedbackScale ?? .oneToTen).canonicalMode
            guard let title = resolvedTitle(for: event, titleByMediaID: titleByMediaID) else { continue }

            let decay = Self.recencyDecay(from: event.createdAt, now: now)
            let sentiment = scale.sentiment(for: value)
            let rating = scale.format(value)

            switch sentiment {
            case .liked:
                likedWithDecay.append(("\(title) (\(rating), weight \(String(format: "%.1f", decay)))", decay))
            case .disliked:
                dislikedWithDecay.append(("\(title) (\(rating), weight \(String(format: "%.1f", decay)))", decay))
            case .neutral:
                break
            }
        }

        likedWithDecay.sort { $0.1 > $1.1 }
        dislikedWithDecay.sort { $0.1 > $1.1 }

        if !likedWithDecay.isEmpty {
            let items = likedWithDecay.prefix(10).map(\.0)
            notes.append("Liked titles: \(items.joined(separator: "; "))")
        }
        if !dislikedWithDecay.isEmpty {
            let items = dislikedWithDecay.prefix(5).map(\.0)
            notes.append("Disliked titles: \(items.joined(separator: "; "))")
        }
    }

    private func resolvedTitle(for event: TasteEvent, titleByMediaID: [String: String]) -> String? {
        if let metadataTitle = event.metadata["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !metadataTitle.isEmpty {
            return metadataTitle
        }
        if let mediaID = event.mediaId,
           let mediaTitle = titleByMediaID[mediaID] {
            return mediaTitle
        }
        return nil
    }

    private func resolveTitles(mediaIDs: Set<String>, from database: DatabaseManager) async -> [String: String] {
        var result: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for mediaID in mediaIDs {
                group.addTask {
                    let title = try? await database.fetchMediaItem(id: mediaID)?.title
                    return (mediaID, title)
                }
            }
            for await (mediaID, title) in group {
                if let title, !title.isEmpty {
                    result[mediaID] = title
                }
            }
        }
        return result
    }

    private func addUniqueTitle(_ title: String, to titles: inout [String], seen: inout Set<String>) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = trimmed.lowercased()
        if seen.insert(key).inserted {
            titles.append(trimmed)
        }
    }
}
