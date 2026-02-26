import Foundation
import Observation

enum ExplorePhase: Equatable {
    case idle
    case searching
    case results
    case empty
    case error
}

/// Preset year-range filters for quick access in the inline filter bar.
enum YearRangePreset: Hashable, Sendable, Identifiable, CaseIterable {
    case recent      // 2024-2026
    case twenties    // 2020s
    case tens        // 2010s
    case classic     // Pre-2000

    var id: Self { self }

    var displayName: String {
        switch self {
        case .recent: return "2024-2026"
        case .twenties: return "2020s"
        case .tens: return "2010s"
        case .classic: return "Classic"
        }
    }

    /// Returns the year range (inclusive) for this preset.
    var yearRange: ClosedRange<Int> {
        switch self {
        case .recent: return 2024...2026
        case .twenties: return 2020...2029
        case .tens: return 2010...2019
        case .classic: return 1900...1999
        }
    }

    /// Returns the single year value passed to the API for this preset.
    /// For ranges, we use the start year as the filter and rely on sort order.
    /// For "recent", we pass nil (no year restriction, sorted by newest).
    var filterYear: Int? {
        switch self {
        case .recent: return nil
        case .twenties: return nil
        case .tens: return nil
        case .classic: return nil
        }
    }

    /// Returns whether a specific year falls within this preset's range.
    func contains(year: Int) -> Bool {
        yearRange.contains(year)
    }
}

@Observable
@MainActor
final class SearchViewModel {
    var query = ""
    var results: [MediaPreview] = []
    var isSearching = false
    var error: AppError?
    var selectedType: MediaType? = nil
    var currentPage = 1
    var totalPages = 1
    var hasMore: Bool { currentPage < totalPages && currentPage < Self.maxPageLimit }

    // MARK: - Genre Filtering

    var genres: [Genre] = []
    var selectedGenre: Genre?
    private var genreCacheByType: [MediaType: [Genre]] = [:]
    private var genreLoadTask: Task<Void, Never>?

    // MARK: - Sort & Filter

    var sortOption: DiscoverFilters.SortOption = .popularityDesc
    var yearFilter: Int?
    var yearRangePreset: YearRangePreset?
    var languageFilters: Set<String> = ["en-US"]

    /// Primary language sent to the API (first from set, fallback "en-US").
    var primaryLanguage: String? {
        languageFilters.isEmpty ? nil : (languageFilters.sorted().first ?? "en-US")
    }

    /// ISO 639-1 original-language code derived from `languageFilters`, used for TMDB `with_original_language`.
    /// Returns nil when filters contain the default "en-US" only (to avoid over-filtering), or when multiple
    /// languages are selected (TMDB only supports a single `with_original_language` value).
    var originalLanguageCode: String? {
        // Only apply original language filtering when a single non-default language is selected
        guard languageFilters.count == 1,
              let code = languageFilters.first,
              code != "en-US"
        else { return nil }
        return DiscoverFilters.iso639LanguageCode(from: code)
    }

    /// The number of currently active non-default filters.
    var activeFilterCount: Int {
        var count = 0
        if sortOption != .popularityDesc { count += 1 }
        if yearFilter != nil || yearRangePreset != nil { count += 1 }
        if languageFilters != ["en-US"] { count += 1 }
        if selectedGenre != nil { count += 1 }
        return count
    }

    /// Whether any non-default filters are active.
    var hasActiveFilters: Bool { activeFilterCount > 0 }

    /// The mood card that is currently driving results (nil for text search or genre selection).
    private(set) var activeMoodCard: ExploreMoodCard?

    // MARK: - AI Recommendations

    var aiRecommendations: [AIMovieRecommendation] = []
    var isLoadingAI = false
    var aiError: String?

    // MARK: - Recent Searches

    var recentSearches: [String] = []

    // MARK: - Scroll Control

    /// Incremented each time the view should scroll back to the top (e.g. new search).
    var scrollToTopTrigger: Int = 0

    // MARK: - Explore Phase

    var explorePhase: ExplorePhase {
        if isSearching { return .searching }
        if error != nil && results.isEmpty { return .error }
        let hasQuery = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let hasResults = !results.isEmpty || !aiRecommendations.isEmpty
        if hasResults || isLoadingAI || selectedGenre != nil || activeMoodCard != nil { return .results }
        if hasQuery { return .empty }
        return .idle
    }

    /// True when the current results came from a genre-browse discover call
    /// rather than a text search.
    var isGenreBrowsing: Bool { selectedGenre != nil && query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var metadataService: (any MetadataProvider)?
    private let metadataServiceFactory: @Sendable (String) -> any MetadataProvider
    private var configuredApiKey: String?

    /// Monotonically-increasing counter used to discard stale search/loadMore results.
    private(set) var searchGeneration: Int = 0

    /// True while a loadMore page request is in flight — prevents duplicate pagination requests.
    private(set) var isLoadingMore = false

    /// The debounce interval used by `debouncedSearch()`. Configurable for testing.
    let debounceInterval: Duration

    /// Minimum interval between successive `loadMore()` calls to prevent rapid-fire pagination
    /// when fast scrolling causes multiple `.onAppear` triggers in quick succession.
    let paginationCooldown: Duration

    /// Hard cap on the maximum page number that can be requested. Prevents unbounded pagination
    /// from consuming excessive memory and network resources.
    static let maxPageLimit = 500

    /// Timestamp of the last successful `loadMore()` initiation, used with `paginationCooldown`.
    private var lastPaginationTime: ContinuousClock.Instant?

    init(
        metadataService: (any MetadataProvider)? = nil,
        metadataServiceFactory: @escaping @Sendable (String) -> any MetadataProvider = { TMDBService(apiKey: $0) },
        debounceInterval: Duration = .milliseconds(300),
        paginationCooldown: Duration = .milliseconds(500)
    ) {
        self.metadataService = metadataService
        self.metadataServiceFactory = metadataServiceFactory
        self.debounceInterval = debounceInterval
        self.paginationCooldown = paginationCooldown
    }

    func cancelInFlightWork() {
        searchTask?.cancel()
        searchTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        aiTask?.cancel()
        aiTask = nil
        genreLoadTask?.cancel()
        genreLoadTask = nil
    }

    func configure(apiKey: String) {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { return }

        if let configuredApiKey {
            guard configuredApiKey != normalizedKey else { return }
            metadataService = metadataServiceFactory(normalizedKey)
            self.configuredApiKey = normalizedKey
            return
        }

        guard metadataService == nil else { return }
        metadataService = metadataServiceFactory(normalizedKey)
        configuredApiKey = normalizedKey
    }

    // MARK: - Text Search

    /// Schedules a search after the debounce interval. Calling again before the interval
    /// expires cancels the previous pending search. Use this for live-as-you-type search.
    func debouncedSearch() {
        debounceTask?.cancel()
        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self else { return }
            self.search()
        }
    }

    /// Retries the last failed operation (search or genre browse).
    func retry() {
        error = nil
        requery()
    }

    /// Immediately executes a search, cancelling any pending debounce and prior in-flight search.
    func search() {
        debounceTask?.cancel()
        debounceTask = nil

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let service = metadataService else { return }

        searchTask?.cancel()
        loadMoreTask?.cancel()
        isLoadingMore = false
        lastPaginationTime = nil
        searchGeneration += 1
        scrollToTopTrigger += 1
        let generation = searchGeneration
        isSearching = true
        error = nil
        currentPage = 1
        let selectedType = selectedType
        let year = yearFilter
        let language = primaryLanguage
        searchTask = Task { [weak self] in
            do {
                let result = try await service.search(query: trimmed, type: selectedType, page: 1, year: year, language: language)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.results = result.items
                self.totalPages = result.totalPages
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.results = []
                self.error = AppError(error, fallback: .network(.transport("Search failed.")))
                self.isSearching = false
            }
        }
    }

    func loadMore() {
        let service = metadataService
        guard hasMore, !isSearching, !isLoadingMore, service != nil else { return }

        // Enforce cooldown between pagination requests to prevent rapid-fire triggers
        // from fast scrolling through multiple `.onAppear` items.
        if let lastTime = lastPaginationTime {
            let elapsed = ContinuousClock.now - lastTime
            guard elapsed >= paginationCooldown else { return }
        }

        lastPaginationTime = ContinuousClock.now

        if let card = activeMoodCard, card.isSpecialCard, selectedGenre == nil {
            loadMoreMoodCard(card)
        } else if isGenreBrowsing {
            loadMoreGenreBrowse()
        } else {
            loadMoreSearch()
        }
    }

    private func loadMoreMoodCard(_ card: ExploreMoodCard) {
        guard let service = metadataService else { return }
        let nextPage = currentPage + 1
        let type = selectedType ?? .movie
        let sort = sortOption
        let year = yearFilter
        let language = primaryLanguage
        let origLang = originalLanguageCode
        let generation = searchGeneration

        let dateGte: String?
        let dateLte: String?
        if card.isNewReleases {
            dateGte = DiscoverFilters.dateString(daysFromNow: -90)
            dateLte = DiscoverFilters.todayString()
        } else if card.isFutureReleases {
            dateGte = DiscoverFilters.dateString(daysFromNow: 1)
            dateLte = DiscoverFilters.dateString(daysFromNow: 365)
        } else {
            dateGte = nil
            dateLte = DiscoverFilters.todayString()
        }

        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            defer { self?.isLoadingMore = false }
            do {
                let filters = DiscoverFilters(
                    year: year, sortBy: sort, page: nextPage, language: language,
                    releaseDateGte: dateGte, releaseDateLte: dateLte,
                    originalLanguage: origLang
                )
                let result = try await service.discover(type: type, filters: filters)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                let existingIDs = Set(self.results.map(\.id))
                let newItems = result.items.filter { !existingIDs.contains($0.id) }
                self.results.append(contentsOf: newItems)
                self.currentPage = nextPage
                self.totalPages = result.totalPages
            } catch {
                // silently fail pagination
            }
        }
    }

    private func loadMoreSearch() {
        guard let service = metadataService else { return }
        let nextPage = currentPage + 1
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let expectedQuery = trimmed
        let selectedType = selectedType
        let year = yearFilter
        let language = primaryLanguage
        let generation = searchGeneration

        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            defer { self?.isLoadingMore = false }
            do {
                let result = try await service.search(query: expectedQuery, type: selectedType, page: nextPage, year: year, language: language)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                guard self.query.trimmingCharacters(in: .whitespaces) == expectedQuery else { return }
                let existingIDs = Set(self.results.map(\.id))
                let newItems = result.items.filter { !existingIDs.contains($0.id) }
                self.results.append(contentsOf: newItems)
                self.currentPage = nextPage
                self.totalPages = result.totalPages
            } catch {
                // silently fail pagination
            }
        }
    }

    private func loadMoreGenreBrowse() {
        guard let service = metadataService, let genre = selectedGenre else { return }
        let nextPage = currentPage + 1
        let type = selectedType ?? .movie
        let sort = sortOption
        let year = yearFilter
        let language = primaryLanguage
        let origLang = originalLanguageCode
        let generation = searchGeneration

        // Re-derive the same date constraints used by the initial browse or mood card
        let moodCard = activeMoodCard
        let dateLte: String?
        let dateGte: String?
        if let card = moodCard, card.isNewReleases {
            dateGte = DiscoverFilters.dateString(daysFromNow: -90)
            dateLte = DiscoverFilters.todayString()
        } else if let card = moodCard, card.isFutureReleases {
            dateGte = DiscoverFilters.dateString(daysFromNow: 1)
            dateLte = DiscoverFilters.dateString(daysFromNow: 365)
        } else {
            dateGte = nil
            dateLte = DiscoverFilters.todayString()
        }

        isLoadingMore = true
        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            defer { self?.isLoadingMore = false }
            do {
                let filters = DiscoverFilters(
                    genreId: genre.id, year: year, sortBy: sort, page: nextPage,
                    language: language, releaseDateGte: dateGte, releaseDateLte: dateLte,
                    originalLanguage: origLang
                )
                let result = try await service.discover(type: type, filters: filters)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                guard self.selectedGenre?.id == genre.id else { return }
                let existingIDs = Set(self.results.map(\.id))
                let newItems = result.items.filter { !existingIDs.contains($0.id) }
                self.results.append(contentsOf: newItems)
                self.currentPage = nextPage
                self.totalPages = result.totalPages
            } catch {
                // silently fail pagination
            }
        }
    }

    func clear() {
        cancelInFlightWork()
        query = ""
        results = []
        currentPage = 1
        totalPages = 1
        selectedGenre = nil
        activeMoodCard = nil
        aiRecommendations = []
        aiError = nil
        error = nil
        yearFilter = nil
        yearRangePreset = nil
        languageFilters = ["en-US"]
        sortOption = .popularityDesc
        isLoadingMore = false
        lastPaginationTime = nil
        scrollToTopTrigger += 1
    }

    /// Resets all filters to their defaults without clearing the query or results.
    func clearAllFilters() {
        sortOption = .popularityDesc
        yearFilter = nil
        yearRangePreset = nil
        languageFilters = ["en-US"]
        if selectedGenre != nil {
            selectGenre(nil)
        } else {
            requery()
        }
    }

    // MARK: - Genre Loading & Browsing

    func loadGenres() {
        guard let service = metadataService else { return }
        let type = selectedType ?? .movie

        // Return cached genres if available
        if let cached = genreCacheByType[type] {
            genres = cached
            return
        }

        genreLoadTask?.cancel()
        genreLoadTask = Task { [weak self] in
            do {
                let loadedGenres = try await service.getGenres(type: type)
                guard !Task.isCancelled, let self else { return }
                self.genreCacheByType[type] = loadedGenres
                self.genres = loadedGenres
            } catch {
                // Non-fatal — genres are optional UI enhancement
            }
        }
    }

    func selectGenre(_ genre: Genre?) {
        selectedGenre = genre
        if let genre {
            browseGenre(genre)
        } else {
            // Clear genre selection — if there's a text query, re-search; otherwise clear results
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                search()
            } else {
                results = []
                currentPage = 1
                totalPages = 1
            }
        }
    }

    func browseGenre(_ genre: Genre) {
        guard let service = metadataService else { return }

        debounceTask?.cancel()
        debounceTask = nil
        searchTask?.cancel()
        loadMoreTask?.cancel()
        isLoadingMore = false
        lastPaginationTime = nil
        searchGeneration += 1
        scrollToTopTrigger += 1
        let generation = searchGeneration
        isSearching = true
        error = nil
        currentPage = 1
        let type = selectedType ?? .movie
        let sort = sortOption
        let year = yearFilter
        let language = primaryLanguage
        let origLang = originalLanguageCode
        // Date-limit regular genre browsing so future/unannounced content doesn't appear
        let dateLte = DiscoverFilters.todayString()

        searchTask = Task { [weak self] in
            do {
                let filters = DiscoverFilters(
                    genreId: genre.id, year: year, sortBy: sort, page: 1,
                    language: language, releaseDateLte: dateLte, originalLanguage: origLang
                )
                let result = try await service.discover(type: type, filters: filters)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.results = result.items
                self.totalPages = result.totalPages
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.results = []
                self.error = AppError(error, fallback: .network(.transport("Genre browse failed.")))
                self.isSearching = false
            }
        }
    }

    // MARK: - Mood Card Selection

    func selectMoodCard(_ card: ExploreMoodCard) {
        let type = selectedType ?? .movie
        activeMoodCard = card

        if card.isNewReleases {
            // New Releases: recent content from 90 days ago up to today, sorted newest first
            discoverMoodCard(
                type: type,
                sortBy: .releaseDateDesc,
                releaseDateGte: DiscoverFilters.dateString(daysFromNow: -90),
                releaseDateLte: DiscoverFilters.todayString(),
                errorMessage: "Failed to load new releases."
            )
        } else if card.isFutureReleases {
            // Future Releases: popular upcoming content within the next year
            discoverMoodCard(
                type: type,
                sortBy: .popularityDesc,
                releaseDateGte: DiscoverFilters.dateString(daysFromNow: 1),
                releaseDateLte: DiscoverFilters.dateString(daysFromNow: 365),
                errorMessage: "Failed to load upcoming releases."
            )
        } else {
            // Regular genre card — date-limited to today via browseGenre
            let genreId = type == .series ? card.tvGenreId : card.movieGenreId
            let genre = Genre(id: genreId, name: card.title)
            selectGenre(genre)
        }
    }

    /// Shared discover call for special mood cards (New Releases, Future Releases).
    private func discoverMoodCard(
        type: MediaType,
        sortBy: DiscoverFilters.SortOption,
        releaseDateGte: String?,
        releaseDateLte: String?,
        errorMessage: String
    ) {
        sortOption = sortBy
        selectedGenre = nil
        guard let service = metadataService else { return }

        debounceTask?.cancel()
        debounceTask = nil
        searchTask?.cancel()
        loadMoreTask?.cancel()
        isLoadingMore = false
        lastPaginationTime = nil
        searchGeneration += 1
        scrollToTopTrigger += 1
        let generation = searchGeneration
        isSearching = true
        error = nil
        currentPage = 1
        let year = yearFilter
        let language = primaryLanguage
        let origLang = originalLanguageCode

        searchTask = Task { [weak self] in
            do {
                let filters = DiscoverFilters(
                    year: year, sortBy: sortBy, page: 1, language: language,
                    releaseDateGte: releaseDateGte, releaseDateLte: releaseDateLte,
                    originalLanguage: origLang
                )
                let result = try await service.discover(type: type, filters: filters)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.results = result.items
                self.totalPages = result.totalPages
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.results = []
                self.error = AppError(error, fallback: .network(.transport(errorMessage)))
                self.isSearching = false
            }
        }
    }

    // MARK: - Sort Option

    func applySortOption(_ option: DiscoverFilters.SortOption) {
        sortOption = option
        requery()
    }

    func applyYearFilter(_ year: Int?) {
        yearFilter = year
        // Clear preset if setting a specific year that doesn't match any preset
        if let year {
            yearRangePreset = YearRangePreset.allCases.first(where: { $0.contains(year: year) })
        } else {
            yearRangePreset = nil
        }
        requery()
    }

    /// Applies a year range preset, mapping it to the appropriate year filter.
    func applyYearRangePreset(_ preset: YearRangePreset?) {
        if let preset {
            if yearRangePreset == preset {
                // Toggle off
                yearRangePreset = nil
                yearFilter = nil
            } else {
                yearRangePreset = preset
                // Use the start of the range as the filter year
                yearFilter = preset.yearRange.lowerBound
            }
        } else {
            yearRangePreset = nil
            yearFilter = nil
        }
        requery()
    }

    func applyLanguageFilters(_ languages: Set<String>) {
        languageFilters = languages
        requery()
    }

    func toggleLanguage(_ code: String) {
        if languageFilters.contains(code) {
            languageFilters.remove(code)
        } else {
            languageFilters.insert(code)
        }
        requery()
    }

    /// Re-executes the current query or genre browse with the updated filters.
    func requery() {
        if let genre = selectedGenre {
            browseGenre(genre)
        } else if let card = activeMoodCard, card.isSpecialCard {
            selectMoodCard(card)
        } else {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                search()
            }
        }
    }

    // MARK: - Recent Searches

    func addRecentSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 20 {
            recentSearches = Array(recentSearches.prefix(20))
        }
    }

    func removeRecentSearch(_ term: String) {
        recentSearches.removeAll { $0 == term }
    }

    func clearRecentSearches() {
        recentSearches = []
    }

    func loadRecentSearches(from settingsManager: SettingsManager) {
        Task { [weak self] in
            guard let json = try? await settingsManager.getString(key: SettingsKeys.recentSearches),
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return }
            self?.recentSearches = decoded
        }
    }

    func saveRecentSearches(to settingsManager: SettingsManager) {
        let searches = recentSearches
        Task { [weak self] in
            guard let data = try? JSONEncoder().encode(searches),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            try? await settingsManager.setString(key: SettingsKeys.recentSearches, value: json)
        }
    }

    // MARK: - Pagination Trigger

    /// Number of items from the end of the results list that should trigger a `loadMore()` call.
    static let paginationTriggerThreshold = 5

    /// Returns true if the item at the given ID is near the end of the results list.
    /// Use this from `.onAppear` in the results grid to trigger pagination.
    /// Avoids O(n) `firstIndex(where:)` by using a pre-built ID-to-index lookup.
    func shouldTriggerPagination(for itemID: String) -> Bool {
        guard hasMore else { return false }
        // Walk backward through the last N items to check if this ID matches
        let count = results.count
        let start = max(0, count - Self.paginationTriggerThreshold)
        for i in start ..< count where results[i].id == itemID {
            return true
        }
        return false
    }

    // MARK: - AI Recommendations

    func fetchAIRecommendations(aiManager: AIAssistantManager) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        aiTask?.cancel()
        isLoadingAI = true
        aiError = nil

        let moodHint: String? = trimmed.isEmpty ? nil : trimmed
        aiTask = Task { [weak self] in
            do {
                var context = AssistantContext()
                context.currentMood = moodHint
                let recommendations = try await aiManager.getRecommendations(context: context)
                guard !Task.isCancelled, let self else { return }
                self.aiRecommendations = recommendations
                self.isLoadingAI = false
            } catch AIError.noProviderConfigured {
                guard !Task.isCancelled, let self else { return }
                self.aiError = "No AI provider configured. Set one up in Settings \u{2192} AI Assistant."
                self.isLoadingAI = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.aiError = error.localizedDescription
                self.isLoadingAI = false
            }
        }
    }

    func clearAIRecommendations() {
        aiTask?.cancel()
        aiTask = nil
        aiRecommendations = []
        aiError = nil
        isLoadingAI = false
    }
}
