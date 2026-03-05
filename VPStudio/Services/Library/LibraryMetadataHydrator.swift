import Foundation

actor LibraryMetadataHydrator {
    struct Configuration: Sendable {
        var successCooldown: TimeInterval
        var failureCooldown: TimeInterval

        init(
            successCooldown: TimeInterval = 6 * 60 * 60,
            failureCooldown: TimeInterval = 5 * 60
        ) {
            self.successCooldown = successCooldown
            self.failureCooldown = failureCooldown
        }
    }

    private let configuration: Configuration
    private let nowProvider: @Sendable () -> Date
    private let metadataServiceFactory: @Sendable (String) -> any MetadataProvider

    private var inFlight: [String: Task<MediaItem?, Never>] = [:]
    private var lastSuccessAt: [String: Date] = [:]
    private var lastFailureAt: [String: Date] = [:]

    init(
        configuration: Configuration = .init(),
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        metadataServiceFactory: @escaping @Sendable (String) -> any MetadataProvider = { TMDBService(apiKey: $0) }
    ) {
        self.configuration = configuration
        self.nowProvider = nowProvider
        self.metadataServiceFactory = metadataServiceFactory
    }

    static func requiresHydration(_ item: MediaItem?) -> Bool {
        guard let item else { return true }
        let missingTitle = isMissingTitle(item.title)
        let missingPoster = (item.posterPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return missingTitle || missingPoster
    }

    func hydrate(mediaID: String, existingItem: MediaItem?, apiKey: String) async -> MediaItem? {
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAPIKey.isEmpty else { return nil }

        let now = nowProvider()
        if let lastSuccessAt = lastSuccessAt[mediaID],
           now.timeIntervalSince(lastSuccessAt) < configuration.successCooldown {
            return nil
        }
        if let lastFailureAt = lastFailureAt[mediaID],
           now.timeIntervalSince(lastFailureAt) < configuration.failureCooldown {
            return nil
        }

        if let inFlightTask = inFlight[mediaID] {
            return await inFlightTask.value
        }

        let seed = existingItem ?? MediaItem(
            id: mediaID,
            type: Self.inferType(from: mediaID),
            title: mediaID,
            year: nil,
            posterPath: nil,
            backdropPath: nil,
            overview: nil,
            genres: [],
            imdbRating: nil,
            runtime: nil,
            status: nil,
            tmdbId: nil,
            lastFetched: nil
        )

        let task = Task<MediaItem?, Never> { [metadataServiceFactory] in
            let service = metadataServiceFactory(normalizedAPIKey)
            return await Self.resolveHydratedItem(
                mediaID: mediaID,
                existingItem: seed,
                service: service
            )
        }
        inFlight[mediaID] = task

        let hydrated = await task.value
        inFlight[mediaID] = nil

        let completedAt = nowProvider()
        if hydrated != nil {
            lastSuccessAt[mediaID] = completedAt
            lastFailureAt.removeValue(forKey: mediaID)
        } else {
            lastFailureAt[mediaID] = completedAt
        }

        return hydrated
    }

    private static func resolveHydratedItem(
        mediaID: String,
        existingItem: MediaItem,
        service: any MetadataProvider
    ) async -> MediaItem? {
        let type = inferType(from: mediaID, fallback: existingItem.type)

        for identifier in preferredDetailIdentifiers(mediaID: mediaID, existingItem: existingItem) {
            if let detail = try? await service.getDetail(id: identifier, type: type),
               hasImprovedMetadata(hydrated: detail, comparedTo: existingItem) {
                return mergedItem(
                    mediaID: mediaID,
                    existingItem: existingItem,
                    hydratedItem: detail,
                    fallbackType: type
                )
            }
        }

        guard let query = normalizedSearchQuery(title: existingItem.title, mediaID: mediaID),
              let searchResult = try? await service.search(
                  query: query,
                  type: type,
                  page: 1,
                  year: existingItem.year,
                  language: nil
              )
        else {
            return nil
        }

        guard let preview = bestSearchCandidate(from: searchResult.items, matching: existingItem),
              let detailIdentifier = preview.tmdbId.map(String.init) ?? extractTMDBIdentifier(from: preview.id),
              let detail = try? await service.getDetail(id: detailIdentifier, type: preview.type)
        else {
            return nil
        }

        return mergedItem(
            mediaID: mediaID,
            existingItem: existingItem,
            hydratedItem: detail,
            fallbackType: type
        )
    }

    private static func hasImprovedMetadata(hydrated: MediaItem, comparedTo existingItem: MediaItem) -> Bool {
        let hydratedHasTitle = !isMissingTitle(hydrated.title)
        let existingHasTitle = !isMissingTitle(existingItem.title)
        let hydratedHasPoster = !(hydrated.posterPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let existingHasPoster = !(existingItem.posterPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return (hydratedHasTitle && !existingHasTitle) || (hydratedHasPoster && !existingHasPoster)
    }

    private static func mergedItem(
        mediaID: String,
        existingItem: MediaItem,
        hydratedItem: MediaItem,
        fallbackType: MediaType
    ) -> MediaItem {
        var merged = hydratedItem
        merged.id = mediaID
        merged.type = existingItem.type
        if isMissingTitle(merged.title) {
            merged.title = existingItem.title
        }
        if merged.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.title = mediaID
        }
        if merged.year == nil {
            merged.year = existingItem.year
        }
        if merged.posterPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            merged.posterPath = existingItem.posterPath
        }
        if merged.backdropPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            merged.backdropPath = existingItem.backdropPath
        }
        if merged.overview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            merged.overview = existingItem.overview
        }
        if merged.genres.isEmpty {
            merged.genres = existingItem.genres
        }
        if merged.imdbRating == nil {
            merged.imdbRating = existingItem.imdbRating
        }
        if merged.runtime == nil {
            merged.runtime = existingItem.runtime
        }
        if merged.status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            merged.status = existingItem.status
        }
        if merged.tmdbId == nil {
            merged.tmdbId = existingItem.tmdbId
        }
        if merged.lastFetched == nil {
            merged.lastFetched = Date()
        }

        if merged.type == .movie, fallbackType == .series {
            merged.type = fallbackType
        }

        return merged
    }

    private static func preferredDetailIdentifiers(mediaID: String, existingItem: MediaItem) -> [String] {
        var identifiers: [String] = []

        if let tmdbId = existingItem.tmdbId {
            identifiers.append(String(tmdbId))
        }

        if let extracted = extractTMDBIdentifier(from: mediaID),
           !identifiers.contains(extracted) {
            identifiers.append(extracted)
        }

        if !mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !identifiers.contains(mediaID) {
            identifiers.append(mediaID)
        }

        return identifiers
    }

    private static func bestSearchCandidate(from items: [MediaPreview], matching existingItem: MediaItem) -> MediaPreview? {
        guard !items.isEmpty else { return nil }
        let normalizedTitle = normalizedComparisonTitle(existingItem.title)

        if let normalizedTitle {
            if let exactMatch = items.first(where: {
                normalizedComparisonTitle($0.title) == normalizedTitle
                    && ($0.year == nil || existingItem.year == nil || $0.year == existingItem.year)
                    && ($0.tmdbId != nil || extractTMDBIdentifier(from: $0.id) != nil)
            }) {
                return exactMatch
            }
        }

        if let year = existingItem.year,
           let yearMatch = items.first(where: {
               $0.year == year && ($0.tmdbId != nil || extractTMDBIdentifier(from: $0.id) != nil)
           }) {
            return yearMatch
        }

        if let tmdbMatch = items.first(where: { $0.tmdbId != nil || extractTMDBIdentifier(from: $0.id) != nil }) {
            return tmdbMatch
        }

        return items.first
    }

    private static func normalizedSearchQuery(title: String, mediaID: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isMissingTitle(trimmed) {
            return nil
        }

        if trimmed.caseInsensitiveCompare(mediaID) == .orderedSame {
            return nil
        }

        return trimmed
    }

    private static func inferType(from mediaID: String, fallback: MediaType = .movie) -> MediaType {
        if mediaID.hasPrefix("series-") || mediaID.hasPrefix("tv-") {
            return .series
        }
        if mediaID.hasPrefix("movie-") {
            return .movie
        }
        return fallback
    }

    private static func extractTMDBIdentifier(from value: String) -> String? {
        if value.hasPrefix("tmdb-") {
            let suffix = String(value.dropFirst(5))
            if suffix.allSatisfy(\.isNumber) { return suffix }
        }

        if value.contains("tmdb-"),
           let suffix = value.split(separator: "-").last,
           suffix.allSatisfy(\.isNumber) {
            return String(suffix)
        }

        return nil
    }

    private static func normalizedComparisonTitle(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func isMissingTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let lowered = trimmed.lowercased()
        if lowered == "unknown" { return true }
        if lowered.hasPrefix("imdb:") { return true }

        return false
    }
}
