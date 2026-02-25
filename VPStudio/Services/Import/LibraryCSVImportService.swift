import Foundation

enum LibraryCSVImportError: LocalizedError, Equatable {
    case unreadableFile
    case unsupportedEncoding
    case emptyFile
    case missingHeader

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Could not read the selected CSV file."
        case .unsupportedEncoding:
            return "CSV file encoding is unsupported."
        case .emptyFile:
            return "CSV file is empty."
        case .missingHeader:
            return "CSV file is missing a valid header row or required columns."
        }
    }
}

enum LibraryCSVImportDestination: String, CaseIterable, Sendable, Identifiable {
    case auto
    case watchlist
    case favorites
    case history

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .watchlist:
            return "Watchlist"
        case .favorites:
            return "Favorites"
        case .history:
            return "History"
        }
    }
}

enum LibraryCSVDetectedFormat: String, Sendable, Equatable {
    case imdbWatchlist = "imdb_watchlist"
    case imdbRatings = "imdb_ratings"
    case generic = "generic"

    var displayName: String {
        switch self {
        case .imdbWatchlist:
            return "IMDb Watchlist"
        case .imdbRatings:
            return "IMDb Ratings"
        case .generic:
            return "Generic CSV"
        }
    }
}

struct LibraryCSVImportOptions: Sendable, Equatable {
    var destination: LibraryCSVImportDestination
    var importRatings: Bool
    var promoteLikedRatingsToFavorites: Bool
    var userId: String
    /// If set, create or find a manual folder with this name and import entries into it
    /// instead of the default system root folders.
    var targetFolderName: String?

    init(
        destination: LibraryCSVImportDestination = .auto,
        importRatings: Bool = true,
        promoteLikedRatingsToFavorites: Bool = true,
        userId: String = "default",
        targetFolderName: String? = nil
    ) {
        self.destination = destination
        self.importRatings = importRatings
        self.promoteLikedRatingsToFavorites = promoteLikedRatingsToFavorites
        self.userId = userId
        self.targetFolderName = targetFolderName
    }
}

struct LibraryCSVImportSummary: Sendable, Equatable {
    var detectedFormat: LibraryCSVDetectedFormat
    var rowsRead: Int
    var rowsImported: Int
    var rowsSkipped: Int
    var mediaItemsCreated: Int
    var mediaItemsUpdated: Int
    var watchlistImported: Int
    var favoritesImported: Int
    var historyImported: Int
    var ratingsImported: Int
    /// The folder ID items were imported into, if a target folder was used.
    var targetFolderID: String?
    /// The resolved folder name, if a target folder was used.
    var targetFolderName: String?
}

actor LibraryCSVImportService {
    private struct ParsedRow: Sendable {
        var mediaID: String
        var title: String
        var mediaType: MediaType
        var year: Int?
        var imdbRating: Double?
        var userRating: Double?
        var userRatingScale: FeedbackScaleMode?
        var occurredAt: Date
    }

    private enum HeaderKeys {
        static let mediaID: Set<String> = [
            "const", "tconst", "imdbid", "imdbconst", "titleconst", "id", "imdb"
        ]
        static let url: Set<String> = [
            "url", "imdburl", "link", "titleurl"
        ]
        static let title: Set<String> = [
            "title", "name", "primarytitle", "originaltitle", "movie", "show"
        ]
        static let mediaType: Set<String> = [
            "type", "titletype", "mediatype", "kind"
        ]
        static let year: Set<String> = [
            "year", "releaseyear", "startyear"
        ]
        static let userRating: Set<String> = [
            "yourrating", "userrating", "rating", "myscore", "myrating", "score", "yourscore", "you rated"
        ]
        static let imdbRating: Set<String> = [
            "imdbrating", "imdbscore"
        ]
        static let liked: Set<String> = [
            "liked", "favorite", "favourite", "isliked"
        ]
        static let disliked: Set<String> = [
            "disliked", "isdisliked"
        ]
        static let date: Set<String> = [
            "created", "daterated", "dateadded", "watcheddate", "watchedat", "added", "date"
        ]
    }

    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    func importCSV(
        from fileURL: URL,
        options: LibraryCSVImportOptions = .init()
    ) async throws -> LibraryCSVImportSummary {
        let text = try Self.readCSVText(from: fileURL)
        let records = Self.parseCSVRecords(text)
        guard !records.isEmpty else {
            throw LibraryCSVImportError.emptyFile
        }

        guard let header = records.first else {
            throw LibraryCSVImportError.missingHeader
        }

        let rows = Array(records.dropFirst())
        let normalizedHeaders = header.map(Self.normalizeHeader)
        let format = Self.detectedFormat(from: normalizedHeaders)
        let mappedRows = Self.mappedRows(headers: normalizedHeaders, values: rows)

        var summary = LibraryCSVImportSummary(
            detectedFormat: format,
            rowsRead: mappedRows.count,
            rowsImported: 0,
            rowsSkipped: 0,
            mediaItemsCreated: 0,
            mediaItemsUpdated: 0,
            watchlistImported: 0,
            favoritesImported: 0,
            historyImported: 0,
            ratingsImported: 0
        )

        // Resolve target folder if requested — only for list types that support folders
        // and that match the destination to avoid creating phantom folders everywhere.
        let resolvedFolderName = Self.resolvedFolderName(
            from: options.targetFolderName,
            fileURL: fileURL
        )

        var targetFolderIDs: [UserLibraryEntry.ListType: String] = [:]
        if let folderName = resolvedFolderName {
            // Only create a folder for the destination list type (or both watchlist/favorites for .auto)
            let listTypesNeedingFolder: [UserLibraryEntry.ListType]
            switch options.destination {
            case .watchlist: listTypesNeedingFolder = [.watchlist]
            case .favorites: listTypesNeedingFolder = [.favorites]
            case .history: listTypesNeedingFolder = [] // history has no folders
            case .auto: listTypesNeedingFolder = [.watchlist, .favorites]
            }

            for listType in listTypesNeedingFolder where listType.supportsFolders {
                let folderID = try await resolveOrCreateFolder(
                    named: folderName,
                    listType: listType
                )
                targetFolderIDs[listType] = folderID
            }
            summary.targetFolderName = folderName
            summary.targetFolderID = targetFolderIDs.values.first
        }

        let watchlistFolderID: String
        if let cached = targetFolderIDs[.watchlist] {
            watchlistFolderID = cached
        } else {
            watchlistFolderID = try await database.fetchSystemLibraryFolderID(listType: .watchlist)
        }
        let favoritesFolderID: String
        if let cached = targetFolderIDs[.favorites] {
            favoritesFolderID = cached
        } else {
            favoritesFolderID = try await database.fetchSystemLibraryFolderID(listType: .favorites)
        }

        for row in mappedRows {
            guard let parsed = Self.parse(row: row) else {
                summary.rowsSkipped += 1
                continue
            }

            summary.rowsImported += 1
            try await upsertMediaItem(from: parsed, summary: &summary)

            var importedSentiment: FeedbackSentiment?
            if options.importRatings,
               let rawRating = parsed.userRating,
               let ratingScale = parsed.userRatingScale {
                importedSentiment = try await importRating(
                    for: parsed,
                    rawRating: rawRating,
                    scale: ratingScale,
                    options: options
                )
                summary.ratingsImported += 1
            }

            let importPlan = Self.destinationPlan(
                format: format,
                destination: options.destination,
                sentiment: importedSentiment,
                promoteLikedRatingsToFavorites: options.promoteLikedRatingsToFavorites
            )

            if importPlan.importWatchlist {
                let isNew = try await addLibraryEntryIfNeeded(
                    mediaID: parsed.mediaID,
                    listType: .watchlist,
                    folderID: watchlistFolderID,
                    addedAt: parsed.occurredAt
                )
                if isNew {
                    summary.watchlistImported += 1
                }
            }

            if importPlan.importFavorites {
                let isNew = try await addLibraryEntryIfNeeded(
                    mediaID: parsed.mediaID,
                    listType: .favorites,
                    folderID: favoritesFolderID,
                    addedAt: parsed.occurredAt
                )
                if isNew {
                    summary.favoritesImported += 1
                }
            }

            if importPlan.importHistory {
                let isNew = try await saveHistoryIfNeeded(for: parsed)
                if isNew {
                    summary.historyImported += 1
                }
            }
        }

        if mappedRows.count > 0 && summary.rowsImported == 0 {
            throw LibraryCSVImportError.missingHeader
        }

        return summary
    }

    /// Resolves the folder name: uses the explicit name if provided, otherwise
    /// derives it from the CSV filename (without extension). Returns nil if
    /// no folder targeting should be applied.
    static func resolvedFolderName(from explicitName: String?, fileURL: URL) -> String? {
        if let explicitName {
            let trimmed = explicitName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    /// Derives a default folder name from the CSV file URL (filename without extension).
    static func defaultFolderName(from fileURL: URL) -> String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    /// Infers the best import destination from the CSV filename.
    /// Returns nil when the filename doesn't map to any obvious list type.
    static func inferredDestination(from fileURL: URL) -> LibraryCSVImportDestination? {
        let name = fileURL.deletingPathExtension().lastPathComponent.lowercased()

        // Watchlist / to-watch / currently watching / other planning lists
        if name.contains("watchlist")
            || name.contains("to watch") || name.contains("currently watching")
            || name.contains("plan") || name.contains("release") || name.contains("break") {
            return .watchlist
        }
        // Favorites / ratings
        if name.contains("favorite") || name.contains("favourite") || name.contains("ratings") {
            return .favorites
        }
        // History / completed (including IMDb WatchHistory exports)
        if name.contains("watchhistory") || name.contains("watch history")
            || name == "history" || name.contains("completed") || name == "watched" {
            return .history
        }
        return nil
    }

    /// Finds an existing manual folder by name and list type, or creates a new one.
    private func resolveOrCreateFolder(
        named name: String,
        listType: UserLibraryEntry.ListType
    ) async throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Never create manual folders that duplicate system root names.
        // Route "Watchlist"/"Favorites" back to their system roots.
        if listType.supportsFolders,
           normalized.caseInsensitiveCompare(LibraryFolder.systemFolderName(for: listType)) == .orderedSame {
            return LibraryFolder.systemFolderID(for: listType)
        }

        let existingFolders = try await database.fetchAllLibraryFolders(listType: listType)
        if let existing = existingFolders.first(where: {
            !$0.isSystem && $0.name.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            return existing.id
        }
        let folder = try await database.createLibraryFolder(name: normalized, listType: listType)
        return folder.id
    }

    private func upsertMediaItem(
        from row: ParsedRow,
        summary: inout LibraryCSVImportSummary
    ) async throws {
        if var existing = try await database.fetchMediaItem(id: row.mediaID) {
            var didUpdate = false

            if existing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.title = row.title
                didUpdate = true
            }
            if existing.year == nil, let year = row.year {
                existing.year = year
                didUpdate = true
            }
            if existing.imdbRating == nil, let imdbRating = row.imdbRating {
                existing.imdbRating = imdbRating
                didUpdate = true
            }

            if didUpdate {
                try await database.saveMediaItem(existing)
                summary.mediaItemsUpdated += 1
            }
        } else {
            let item = MediaItem(
                id: row.mediaID,
                type: row.mediaType,
                title: row.title,
                year: row.year,
                imdbRating: row.imdbRating,
                lastFetched: Date()
            )
            try await database.saveMediaItem(item)
            summary.mediaItemsCreated += 1
        }
    }

    private func importRating(
        for row: ParsedRow,
        rawRating: Double,
        scale: FeedbackScaleMode,
        options: LibraryCSVImportOptions
    ) async throws -> FeedbackSentiment {
        let canonicalScale = scale.canonicalMode
        let clamped = canonicalScale.clamp(rawRating)
        let normalized = canonicalScale.normalizedValue(clamped)
        let sentiment = canonicalScale.sentiment(for: clamped)

        let event = TasteEvent(
            id: Self.tasteEventID(mediaID: row.mediaID, value: clamped, occurredAt: row.occurredAt),
            userId: options.userId,
            mediaId: row.mediaID,
            episodeId: nil,
            eventType: .rated,
            signalStrength: normalized,
            watchedState: nil,
            feedbackScale: canonicalScale,
            feedbackValue: clamped,
            source: .manual,
            metadata: [
                "title": row.title,
                "imported": "true",
                "source": "csv"
            ],
            createdAt: row.occurredAt
        )
        try await database.saveTasteEvent(event)

        return sentiment
    }

    private func addLibraryEntryIfNeeded(
        mediaID: String,
        listType: UserLibraryEntry.ListType,
        folderID: String,
        addedAt: Date
    ) async throws -> Bool {
        let exists = try await database.isInLibrary(mediaId: mediaID, listType: listType)
        let entry = UserLibraryEntry(
            id: "\(mediaID)-\(listType.rawValue)",
            mediaId: mediaID,
            folderId: folderID,
            listType: listType,
            addedAt: addedAt
        )
        try await database.addToLibrary(entry)
        return !exists
    }

    private func saveHistoryIfNeeded(for row: ParsedRow) async throws -> Bool {
        let existing = try await database.fetchWatchHistory(mediaId: row.mediaID)
        let isDuplicate = existing?.isCompleted == true
            && abs((existing?.watchedAt.timeIntervalSince1970 ?? 0) - row.occurredAt.timeIntervalSince1970) < 1

        let history = WatchHistory(
            id: Self.historyID(mediaID: row.mediaID, occurredAt: row.occurredAt),
            mediaId: row.mediaID,
            episodeId: nil,
            title: row.title,
            progress: 1,
            duration: 1,
            quality: nil,
            debridService: nil,
            streamURL: nil,
            watchedAt: row.occurredAt,
            isCompleted: true
        )
        try await database.saveWatchHistory(history)
        return !isDuplicate
    }

    private struct DestinationPlan {
        var importWatchlist: Bool
        var importFavorites: Bool
        var importHistory: Bool
    }

    private static func destinationPlan(
        format: LibraryCSVDetectedFormat,
        destination: LibraryCSVImportDestination,
        sentiment: FeedbackSentiment?,
        promoteLikedRatingsToFavorites: Bool
    ) -> DestinationPlan {
        switch destination {
        case .watchlist:
            return DestinationPlan(importWatchlist: true, importFavorites: false, importHistory: false)
        case .favorites:
            return DestinationPlan(importWatchlist: false, importFavorites: true, importHistory: false)
        case .history:
            // Also add to watchlist so items are visible in the main library grid
            return DestinationPlan(importWatchlist: true, importFavorites: false, importHistory: true)
        case .auto:
            if let sentiment, promoteLikedRatingsToFavorites, sentiment == .liked {
                return DestinationPlan(importWatchlist: false, importFavorites: true, importHistory: false)
            }
            // All imported items should appear somewhere — default to watchlist
            return DestinationPlan(importWatchlist: true, importFavorites: false, importHistory: false)
        }
    }

    private static func readCSVText(from fileURL: URL) throws -> String {
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
            throw LibraryCSVImportError.unreadableFile
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        if let latin = String(data: data, encoding: .isoLatin1) {
            return latin
        }

        throw LibraryCSVImportError.unsupportedEncoding
    }

    private static func parseCSVRecords(_ text: String) -> [[String]] {
        // Swift may treat CRLF as a single grapheme cluster ("\r\n"), which can
        // bypass character == "\r"/"\n" checks. Normalize first so row splitting
        // is deterministic for Windows-style CSV exports.
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var records: [[String]] = []
        var currentRecord: [String] = []
        var currentField = ""
        var isInsideQuotes = false

        var index = normalizedText.startIndex
        while index < normalizedText.endIndex {
            let character = normalizedText[index]

            if character == "\"" {
                let next = normalizedText.index(after: index)
                if isInsideQuotes, next < normalizedText.endIndex, normalizedText[next] == "\"" {
                    currentField.append("\"")
                    index = next
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == ",", !isInsideQuotes {
                currentRecord.append(currentField)
                currentField = ""
            } else if character == "\n", !isInsideQuotes {
                currentRecord.append(currentField)
                if !currentRecord.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    records.append(currentRecord)
                }
                currentRecord = []
                currentField = ""
            } else {
                currentField.append(character)
            }

            index = normalizedText.index(after: index)
        }

        currentRecord.append(currentField)
        if !currentRecord.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            records.append(currentRecord)
        }

        return records
    }

    private static func detectedFormat(from headers: [String]) -> LibraryCSVDetectedFormat {
        let hasConst = headers.contains("const") || headers.contains("tconst")
        let hasTitle = headers.contains("title")
        let hasCreated = headers.contains("created")
        let hasYourRating = headers.contains("yourrating") || headers.contains("yourated")
        let hasDateRated = headers.contains("daterated")

        if hasConst, hasTitle {
            if hasDateRated {
                return .imdbRatings
            }
            if hasCreated {
                return .imdbWatchlist
            }
            if hasYourRating {
                return .imdbRatings
            }
        }
        return .generic
    }

    private static func mappedRows(headers: [String], values: [[String]]) -> [[String: String]] {
        values.compactMap { row in
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return nil
            }

            var mapped: [String: String] = [:]
            for (index, header) in headers.enumerated() where !header.isEmpty {
                let value = index < row.count ? row[index] : ""
                mapped[header] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return mapped
        }
    }

    private static func parse(row: [String: String]) -> ParsedRow? {
        let title = normalizedText(firstValue(in: row, keys: HeaderKeys.title))
        let year = parseYear(firstValue(in: row, keys: HeaderKeys.year))
        let mediaType = parseMediaType(firstValue(in: row, keys: HeaderKeys.mediaType))

        let imdbIDFromColumn = parseIMDbID(
            firstValue(in: row, keys: HeaderKeys.mediaID)
        )
        let imdbIDFromURL = parseIMDbID(
            firstValue(in: row, keys: HeaderKeys.url)
        )

        let resolvedTitle = title ?? imdbIDFromColumn ?? imdbIDFromURL ?? ""
        if resolvedTitle.isEmpty {
            return nil
        }

        let mediaID = imdbIDFromColumn
            ?? imdbIDFromURL
            ?? fallbackMediaID(title: resolvedTitle, year: year)

        let imdbRating = parseDouble(firstValue(in: row, keys: HeaderKeys.imdbRating))
        let occurredAt = parseDate(firstValue(in: row, keys: HeaderKeys.date)) ?? Date()

        var userRating = parseDouble(firstValue(in: row, keys: HeaderKeys.userRating))
        var userRatingScale: FeedbackScaleMode?
        if let userRating {
            userRatingScale = inferredScale(for: userRating)
        } else {
            let liked = parseBool(firstValue(in: row, keys: HeaderKeys.liked))
            let disliked = parseBool(firstValue(in: row, keys: HeaderKeys.disliked))
            if liked == true {
                userRating = 1
                userRatingScale = .likeDislike
            } else if disliked == true {
                userRating = 0
                userRatingScale = .likeDislike
            }
        }

        return ParsedRow(
            mediaID: mediaID,
            title: resolvedTitle,
            mediaType: mediaType,
            year: year,
            imdbRating: imdbRating,
            userRating: userRating,
            userRatingScale: userRatingScale,
            occurredAt: occurredAt
        )
    }

    private static func parseIMDbID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if let directMatch = raw.range(of: "tt\\d+", options: .regularExpression) {
            return String(raw[directMatch]).lowercased()
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("tt"), trimmed.dropFirst(2).allSatisfy(\.isNumber) {
            return trimmed.lowercased()
        }
        return nil
    }

    private static func parseMediaType(_ raw: String?) -> MediaType {
        guard let raw = normalizedText(raw)?.lowercased() else { return .movie }
        if raw.contains("tv") || raw.contains("series") || raw.contains("show") || raw.contains("episode") {
            return .series
        }
        return .movie
    }

    private static func parseYear(_ raw: String?) -> Int? {
        guard let raw = normalizedText(raw) else { return nil }
        if let parsed = Int(raw), parsed >= 1800, parsed <= 3000 {
            return parsed
        }

        let digits = raw.filter(\.isNumber)
        if digits.count >= 4 {
            let candidate = String(digits.prefix(4))
            if let parsed = Int(candidate), parsed >= 1800, parsed <= 3000 {
                return parsed
            }
        }
        return nil
    }

    private static func parseDouble(_ raw: String?) -> Double? {
        guard let raw = normalizedText(raw) else { return nil }

        if raw.contains("/"), let numerator = raw.split(separator: "/").first {
            return Double(String(numerator).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let sanitized = raw.replacingOccurrences(of: ",", with: ".")
        return Double(sanitized)
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let raw = normalizedText(raw)?.lowercased() else { return nil }
        switch raw {
        case "1", "true", "yes", "y", "liked", "favorite", "favourite":
            return true
        case "0", "false", "no", "n", "disliked":
            return false
        default:
            return nil
        }
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw = normalizedText(raw), !raw.isEmpty else { return nil }

        let dateFormats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: raw) {
            return date
        }

        return nil
    }

    private static func inferredScale(for rawRating: Double) -> FeedbackScaleMode {
        if rawRating <= 1 {
            return .likeDislike
        }
        if rawRating <= 10 {
            return .oneToTen
        }
        return .oneToHundred
    }

    private static func firstValue(
        in row: [String: String],
        keys: Set<String>
    ) -> String? {
        for key in keys {
            if let raw = row[normalizeHeader(key)],
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return raw
            }
        }
        return nil
    }

    private static func normalizedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizeHeader(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func fallbackMediaID(title: String, year: Int?) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let trimmedSlug = String(slug.prefix(48))
        let yearPart = year.map(String.init) ?? "0"
        return "csv-\(trimmedSlug)-\(yearPart)"
    }

    private static func tasteEventID(mediaID: String, value: Double, occurredAt: Date) -> String {
        let seconds = Int(occurredAt.timeIntervalSince1970)
        let score = Int((value * 100).rounded())
        return "csv-rating-\(mediaID)-\(seconds)-\(score)"
    }

    private static func historyID(mediaID: String, occurredAt: Date) -> String {
        let seconds = Int(occurredAt.timeIntervalSince1970)
        return "csv-history-\(mediaID)-\(seconds)"
    }
}
