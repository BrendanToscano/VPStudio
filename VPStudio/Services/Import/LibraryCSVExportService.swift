import Foundation

/// Summary of a CSV export operation.
struct LibraryCSVExportSummary: Sendable, Equatable {
    var filesWritten: Int = 0
    var totalItemsExported: Int = 0
    var folderNames: [String] = []
}

/// Exports library entries as IMDb-compatible CSV files.
/// Each folder/list becomes a separate CSV file inside an output directory.
actor LibraryCSVExportService {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    /// Exports all library lists and folders as IMDb-compatible CSVs into a temporary directory.
    /// Returns the directory URL containing all CSV files and a summary.
    func exportAll() async throws -> (directoryURL: URL, summary: LibraryCSVExportSummary) {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VPStudio-Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var summary = LibraryCSVExportSummary()

        // Export each list type
        for listType in UserLibraryEntry.ListType.allCases {
            let folders = try await database.fetchAllLibraryFolders(listType: listType)

            if listType == .history {
                // History has no folders — export as a single file
                let entries = try await database.fetchWatchHistory(limit: 10000)
                if !entries.isEmpty {
                    let mediaItems = await fetchMediaItems(for: entries.map(\.mediaId))
                    let ratings = await fetchRatings(for: entries.map(\.mediaId))
                    let csv = buildHistoryCSV(entries: entries, mediaItems: mediaItems, ratings: ratings)
                    let fileName = sanitizeFileName("History") + ".csv"
                    let fileURL = outputDir.appendingPathComponent(fileName)
                    try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                    summary.filesWritten += 1
                    summary.totalItemsExported += entries.count
                    summary.folderNames.append("History")
                }
                continue
            }

            // For watchlist/favorites, export each folder separately
            for folder in folders {
                let entries = try await database.fetchLibraryEntries(
                    listType: listType,
                    folderId: folder.id
                )
                guard !entries.isEmpty else { continue }

                let mediaIds = entries.map(\.mediaId)
                let mediaItems = await fetchMediaItems(for: mediaIds)
                let ratings = await fetchRatings(for: mediaIds)

                let csv = buildLibraryCSV(
                    entries: entries,
                    mediaItems: mediaItems,
                    ratings: ratings,
                    listType: listType
                )

                let displayName = folder.isSystem ? listType.displayName : folder.name
                let fileName = sanitizeFileName(displayName) + ".csv"
                let fileURL = outputDir.appendingPathComponent(fileName)
                try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                summary.filesWritten += 1
                summary.totalItemsExported += entries.count
                summary.folderNames.append(displayName)
            }
        }

        return (outputDir, summary)
    }

    /// Exports a single list/folder as an IMDb-compatible CSV string.
    func exportFolder(
        listType: UserLibraryEntry.ListType,
        folderId: String?
    ) async throws -> (csv: String, itemCount: Int) {
        if listType == .history {
            let entries = try await database.fetchWatchHistory(limit: 10000)
            let mediaItems = await fetchMediaItems(for: entries.map(\.mediaId))
            let ratings = await fetchRatings(for: entries.map(\.mediaId))
            let csv = buildHistoryCSV(entries: entries, mediaItems: mediaItems, ratings: ratings)
            return (csv, entries.count)
        }

        let entries = try await database.fetchLibraryEntries(
            listType: listType,
            folderId: folderId
        )
        let mediaIds = entries.map(\.mediaId)
        let mediaItems = await fetchMediaItems(for: mediaIds)
        let ratings = await fetchRatings(for: mediaIds)
        let csv = buildLibraryCSV(
            entries: entries,
            mediaItems: mediaItems,
            ratings: ratings,
            listType: listType
        )
        return (csv, entries.count)
    }

    // MARK: - CSV Building

    /// IMDb watchlist CSV headers
    private static let watchlistHeaders = [
        "Position", "Const", "Created", "Modified", "Description",
        "Title", "URL", "Title Type", "IMDb Rating", "Runtime (mins)",
        "Year", "Genres", "Num Votes", "Release Date", "Directors"
    ]

    /// IMDb ratings CSV headers
    private static let ratingsHeaders = [
        "Const", "Your Rating", "Date Rated", "Title", "URL",
        "Title Type", "IMDb Rating", "Runtime (mins)", "Year",
        "Genres", "Num Votes", "Release Date", "Directors"
    ]

    private func buildLibraryCSV(
        entries: [UserLibraryEntry],
        mediaItems: [String: MediaItem],
        ratings: [String: TasteEvent],
        listType: UserLibraryEntry.ListType
    ) -> String {
        let hasRatings = !ratings.isEmpty
        let headers = hasRatings ? Self.ratingsHeaders : Self.watchlistHeaders

        var lines: [String] = [headers.joined(separator: ",")]

        for (index, entry) in entries.enumerated() {
            let item = mediaItems[entry.mediaId]
            let rating = ratings[entry.mediaId]

            let imdbId = entry.mediaId.hasPrefix("tt") ? entry.mediaId : ""
            let title = escapeCSV(item?.title ?? "")
            let url = imdbId.isEmpty ? "" : "https://www.imdb.com/title/\(imdbId)/"
            let titleType = imdbTitleType(for: item?.type ?? .movie)
            let imdbRating = item?.imdbRating.map { String(format: "%.1f", $0) } ?? ""
            let runtime = item?.runtime.map(String.init) ?? ""
            let year = item?.year.map(String.init) ?? ""
            let genres = escapeCSV((item?.genres ?? []).joined(separator: ", "))
            let dateStr = Self.dateFormatter.string(from: entry.addedAt)

            if hasRatings {
                let yourRating = ratingValue(from: rating)
                let row = [
                    imdbId, yourRating, dateStr, title, url,
                    titleType, imdbRating, runtime, year,
                    genres, "", "", ""
                ]
                lines.append(row.joined(separator: ","))
            } else {
                let row = [
                    String(index + 1), imdbId, dateStr, dateStr, "",
                    title, url, titleType, imdbRating, runtime,
                    year, genres, "", "", ""
                ]
                lines.append(row.joined(separator: ","))
            }
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func buildHistoryCSV(
        entries: [WatchHistory],
        mediaItems: [String: MediaItem],
        ratings: [String: TasteEvent]
    ) -> String {
        var lines: [String] = [Self.ratingsHeaders.joined(separator: ",")]

        // Deduplicate by mediaId (keep latest)
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.mediaId).inserted }

        for entry in unique {
            let item = mediaItems[entry.mediaId]
            let rating = ratings[entry.mediaId]

            let imdbId = entry.mediaId.hasPrefix("tt") ? entry.mediaId : ""
            let title = escapeCSV(item?.title ?? entry.title)
            let url = imdbId.isEmpty ? "" : "https://www.imdb.com/title/\(imdbId)/"
            let titleType = imdbTitleType(for: item?.type ?? .movie)
            let imdbRating = item?.imdbRating.map { String(format: "%.1f", $0) } ?? ""
            let runtime = item?.runtime.map(String.init) ?? ""
            let year = item?.year.map(String.init) ?? ""
            let genres = escapeCSV((item?.genres ?? []).joined(separator: ", "))
            let dateStr = Self.dateFormatter.string(from: entry.watchedAt)
            let yourRating = ratingValue(from: rating)

            let row = [
                imdbId, yourRating, dateStr, title, url,
                titleType, imdbRating, runtime, year,
                genres, "", "", ""
            ]
            lines.append(row.joined(separator: ","))
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func fetchMediaItems(for mediaIds: [String]) async -> [String: MediaItem] {
        var result: [String: MediaItem] = [:]
        let unique = Set(mediaIds)
        for id in unique {
            if let item = try? await database.fetchMediaItem(id: id) {
                result[id] = item
            }
        }
        return result
    }

    private func fetchRatings(for mediaIds: [String]) async -> [String: TasteEvent] {
        let events = (try? await database.fetchTasteEvents(eventType: .rated, limit: 5000)) ?? []
        var dict: [String: TasteEvent] = [:]
        for event in events {
            if let mediaId = event.mediaId {
                dict[mediaId] = event
            }
        }
        // Filter to only the mediaIds we care about
        let relevant = Set(mediaIds)
        return dict.filter { relevant.contains($0.key) }
    }

    private func ratingValue(from event: TasteEvent?) -> String {
        guard let event, let value = event.feedbackValue else { return "" }
        let scale = (event.feedbackScale ?? .oneToTen).canonicalMode
        switch scale {
        case .oneToTen:
            return String(Int(scale.clamp(value).rounded()))
        case .oneToHundred:
            // Convert 1-100 to 1-10 for IMDb
            let normalized = scale.normalizedValue(value)
            let imdbScale = 1.0 + (normalized * 9.0)
            return String(Int(imdbScale.rounded()))
        case .likeDislike:
            return value >= 0.5 ? "8" : "3"
        default:
            return String(Int(value.rounded()))
        }
    }

    private func imdbTitleType(for type: MediaType) -> String {
        switch type {
        case .movie: return "movie"
        case .series: return "tvSeries"
        }
    }

    /// Escapes a field for CSV: wraps in quotes if it contains commas, quotes, or newlines.
    static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func escapeCSV(_ value: String) -> String {
        Self.escapeCSV(value)
    }

    private func sanitizeFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[/\\\\:*?\"<>|]", with: "-", options: .regularExpression)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Export" : String(trimmed.prefix(100))
    }
}
