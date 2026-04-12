import Foundation
import Observation
import os

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

struct SearchFilterDraft: Sendable, Equatable {
    var sortOption: DiscoverFilters.SortOption = .popularityDesc
    var selectedYear: Int? = nil
    var selectedLanguages: Set<String> = ["en-US"]
    var selectedGenre: Genre? = nil

    var inferredYearRangePreset: YearRangePreset? {
        guard let selectedYear else { return nil }
        return YearRangePreset.allCases.first { $0.contains(year: selectedYear) }
    }
}

@Observable
@MainActor
final class SearchViewModel {
    private static let logger = Logger(subsystem: "com.vpstudio", category: "search-view-model")
    /// The most recently committed text query backing active/paginated search results.
    /// Raw typing lives in `queryDraft` so the Search field can change without constantly
    /// mutating the committed search state used by load-more and reload paths.
    var query = "" {
        didSet {
            guard queryDraft != query else { return }
            queryDraft = query
        }
    }

    /// Raw text currently shown in the Search field. This can change freely while the user
    /// types, but it is only committed back into `query` when an actual search executes.
    var queryDraft = "" {
        didSet {
            let trimmed = queryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextHasQueryText = !trimmed.isEmpty

            if hasQueryText != nextHasQueryText {
                hasQueryText = nextHasQueryText
            }

            let nextHasAttemptedTextSearch = !submittedQuery.isEmpty && trimmed == submittedQuery
            if hasAttemptedTextSearch != nextHasAttemptedTextSearch {
                hasAttemptedTextSearch = nextHasAttemptedTextSearch

                if !nextHasAttemptedTextSearch {
                    error = nil
                }
            }

            if !nextHasQueryText, submittedQuery != "" {
                submittedQuery = ""
            }

            if !nextHasQueryText {
                cancelInFlightWork()
                replaceResults([])
                error = nil
                currentPage = 1
                totalPages = 1
                isSearching = false
                isLoadingMore = false
                lastPaginationTime = nil

                if !query.isEmpty {
                    query = ""
                }
            }

            refreshExplorePhaseIfNeeded()
        }
    }
    var results: [MediaPreview] = [] {
        didSet {
            if shouldRebuildResultIDCache {
                resultIDCache = Set(results.map(\.id))
            } else {
                shouldRebuildResultIDCache = true
            }
            refreshExplorePhaseIfNeeded()
        }
    }
    var isSearching = false {
        didSet { refreshExplorePhaseIfNeeded() }
    }
    var error: AppError? {
        didSet { refreshExplorePhaseIfNeeded() }
    }
    var selectedType: MediaType? = nil
    var currentPage = 1
    var totalPages = 1
    var hasMore: Bool { currentPage < totalPages && currentPage < Self.maxPageLimit }

    // MARK: - Genre Filtering

    var genres: [Genre] = []
    var selectedGenre: Genre? {
        didSet { refreshExplorePhaseIfNeeded() }
    }
    private var genreCacheByType: [MediaType: [Genre]] = [:]
    private var genreLoadTask: Task<Void, Never>?
    private var genreLoadTaskType: MediaType?

    // MARK: - Sort & Filter

    var sortOption: DiscoverFilters.SortOption = .popularityDesc
    var yearFilter: Int?
    var yearRangePreset: YearRangePreset?
    var languageFilters: Set<String> = ["en-US"]
    private static let defaultLanguageCode = "en-US"

    /// Primary language sent to the API. When multiple languages are selected,
    /// this returns the first known non-default choice so the search path remains
    /// deterministic.
    var primaryLanguage: String? {
        preferredLanguageCode(in: languageFilters)
    }

    /// ISO 639-1 original-language code used for TMDB `with_original_language`.
    /// Delegates to `TMDBOriginalLanguagePolicy` so language-specific exceptions
    /// (for example Hindi and related Indian locales) can avoid over-filtering.
    var originalLanguageCode: String? {
        TMDBOriginalLanguagePolicy.originalLanguageCode(for: languageFilters)
    }

    /// The number of currently active non-default filters.
    var activeFilterCount: Int {
        var count = 0
        if sortOption != .popularityDesc { count += 1 }
        if yearFilter != nil || yearRangePreset != nil { count += 1 }
        if hasExplicitLanguageSelection { count += 1 }
        if selectedGenre != nil { count += 1 }
        return count
    }

    /// Whether any non-default filters are active.
    var hasActiveFilters: Bool { activeFilterCount > 0 }

    /// The mood card that is currently driving results (nil for text search or genre selection).
    private(set) var activeMoodCard: ExploreMoodCard? {
        didSet { refreshExplorePhaseIfNeeded() }
    }

    var currentFilterDraft: SearchFilterDraft {
        SearchFilterDraft(
            sortOption: sortOption,
            selectedYear: yearFilter,
            selectedLanguages: languageFilters,
            selectedGenre: selectedGenre
        )
    }

    // MARK: - AI Recommendations

    var aiRecommendations: [AIMovieRecommendation] = [] {
        didSet { refreshExplorePhaseIfNeeded() }
    }
    var isLoadingAI = false {
        didSet { refreshExplorePhaseIfNeeded() }
    }
    var aiError: String?

    // MARK: - Recent Searches

    var recentSearches: [String] = []

    // MARK: - Query UI State

    /// Low-churn signal used by the outer Search shell so raw keystrokes do not
    /// invalidate the full Explore layout on every character.
    private(set) var hasQueryText = false

    /// The most recently submitted non-empty text query. Empty-state copy and
    /// other shell chrome can depend on this instead of observing live typing.
    private(set) var submittedQuery = ""

    var emptyStateQuery: String {
        let trimmedSubmittedQuery = submittedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSubmittedQuery.isEmpty {
            return trimmedSubmittedQuery
        }

        if let selectedGenre {
            return selectedGenre.name
        }

        if let activeMoodCard {
            return activeMoodCard.title
        }

        return ""
    }

    // MARK: - Scroll Control

    /// Incremented each time the view should scroll back to the top (e.g. new search).
    var scrollToTopTrigger: Int = 0

    // MARK: - Explore Phase

    /// Stored separately from the high-churn source properties so views that only
    /// care about the lane phase do not observe every results mutation.
    private(set) var explorePhase: ExplorePhase = .idle

    /// Tracks whether the current non-empty text query has actually been submitted.
    /// This prevents the center pane from swapping out of the idle Explore grid on the
    /// very first keystroke before the debounced request even begins.
    private(set) var hasAttemptedTextSearch = false

    private var derivedExplorePhase: ExplorePhase {
        if isSearching { return .searching }
        if error != nil && results.isEmpty { return .error }
        let hasSubmittedTextQuery = hasAttemptedTextSearch && !queryDraft.trimmingCharacters(in: .whitespaces).isEmpty
        let hasResults = !results.isEmpty || !aiRecommendations.isEmpty
        if hasResults || isLoadingAI { return .results }
        if selectedGenre != nil || activeMoodCard != nil { return .empty }
        if hasSubmittedTextQuery { return .empty }
        return .idle
    }

    /// True when the current results came from a genre-browse discover call
    /// rather than a text search.
    var isGenreBrowsing: Bool { selectedGenre != nil && queryDraft.trimmingCharacters(in: .whitespaces).isEmpty }

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

    /// Cached alongside `results` so paginated appends can deduplicate without rebuilding
    /// an ID set from the full grid on every new page.
    private var resultIDCache: Set<String> = []
    private var shouldRebuildResultIDCache = true

    private var hasExplicitLanguageSelection: Bool {
        !languageFilters.isEmpty && languageFilters != [Self.defaultLanguageCode]
    }

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
        refreshExplorePhaseIfNeeded()
    }

    private func refreshExplorePhaseIfNeeded() {
        let nextPhase = derivedExplorePhase
        guard explorePhase != nextPhase else { return }
        explorePhase = nextPhase
    }

    private func replaceResults(_ items: [MediaPreview]) {
        resultIDCache = Set(items.map(\.id))
        shouldRebuildResultIDCache = false
        results = items
    }

    private func appendUniqueResults(_ items: [MediaPreview]) {
        guard !items.isEmpty else { return }

        var uniqueItems: [MediaPreview] = []
        uniqueItems.reserveCapacity(items.count)

        for item in items where resultIDCache.insert(item.id).inserted {
            uniqueItems.append(item)
        }

        guard !uniqueItems.isEmpty else { return }

        shouldRebuildResultIDCache = false
        results.append(contentsOf: uniqueItems)
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
        genreLoadTaskType = nil
    }

    // Note: cancelInFlightWork() should be called from .onDisappear in the view.
    // deinit cannot access @MainActor properties in Swift 6 strict concurrency.

    func configure(apiKey: String) {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty key means "search is not configured". Clear only services that were
        // previously configured through this key path; preserve explicitly injected
        // metadataService instances used by tests.
        if normalizedKey.isEmpty {
            guard configuredApiKey != nil else { return }
            cancelInFlightWork()
            metadataService = nil
            configuredApiKey = nil
            genreCacheByType.removeAll()
            genres = []
            selectedGenre = nil
            activeMoodCard = nil
            replaceResults([])
            error = nil
            isSearching = false
            isLoadingMore = false
            currentPage = 1
            totalPages = 1
            lastPaginationTime = nil
            scrollToTopTrigger += 1
            return
        }

        if let configuredApiKey {
            guard configuredApiKey != normalizedKey else { return }
            cancelInFlightWork()
            metadataService = metadataServiceFactory(normalizedKey)
            self.configuredApiKey = normalizedKey
            genreCacheByType.removeAll()
            genres = []
            return
        }

        guard metadataService == nil else { return }
        metadataService = metadataServiceFactory(normalizedKey)
        configuredApiKey = normalizedKey
    }

    // MARK: - Text Search

    /// Schedules a search after the debounce interval. Calling again before the interval
    /// expires cancels the previous pending search. Use this for live-as-you-type search.
    func debouncedSearch(queryText: String? = nil) {
        debounceTask?.cancel()

        let rawQuery = queryText ?? queryDraft
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Without configured metadata, keep raw typing in the lightweight idle state.
        // The explicit submit path still triggers `search()` so the TMDB setup gate can
        // appear once the user actually asks to search.
        guard metadataService != nil else { return }

        let interval = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self else { return }
            self.search(queryText: rawQuery)
        }
    }

    /// Retries the last failed operation (search or genre browse).
    func retry() {
        error = nil
        requery()
    }

    /// Immediately executes a search, cancelling any pending debounce and prior in-flight search.
    func search(queryText: String? = nil) {
        debounceTask?.cancel()
        debounceTask = nil

        let rawQuery = queryText ?? queryDraft
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if queryDraft != rawQuery {
            queryDraft = rawQuery
        }
        if query != rawQuery {
            query = rawQuery
        }

        submittedQuery = trimmed
        if !hasAttemptedTextSearch {
            hasAttemptedTextSearch = true
        }

        searchTask?.cancel()
        loadMoreTask?.cancel()
        isLoadingMore = false
        lastPaginationTime = nil
        error = nil
        currentPage = 1
        totalPages = 1

        guard let service = metadataService else {
            replaceResults([])
            error = .tmdbSetupRequired(feature: "Search")
            isSearching = false
            refreshExplorePhaseIfNeeded()
            return
        }

        searchGeneration += 1
        scrollToTopTrigger += 1
        let generation = searchGeneration
        isSearching = true
        let selectedType = selectedType
        let year = yearFilter
        let language = primaryLanguage
        searchTask = Task { [weak self] in
            do {
                let result = try await service.search(query: trimmed, type: selectedType, page: 1, year: year, language: language)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.replaceResults(result.items)
                self.totalPages = result.totalPages
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.replaceResults([])
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
                self.error = nil
                self.appendUniqueResults(result.items)
                self.currentPage = nextPage
                self.totalPages = result.totalPages
            } catch {
                guard let self else { return }
                self.publishPaginationFailure(error, generation: generation)
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
                self.error = nil
                self.appendUniqueResults(result.items)
                self.currentPage = nextPage
                self.totalPages = result.totalPages
            } catch {
                guard let self else { return }
                guard self.query.trimmingCharacters(in: .whitespaces) == expectedQuery else { return }
                self.publishPaginationFailure(error, generation: generation)
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
                self.error = nil
                self.appendUniqueResults(result.items)
                self.currentPage = nextPage
                self.totalPages = result.totalPages
            } catch {
                guard let self else { return }
                guard self.selectedGenre?.id == genre.id else { return }
                self.publishPaginationFailure(error, generation: generation)
            }
        }
    }

    private func publishPaginationFailure(_ error: Error, generation: Int) {
        guard !Task.isCancelled, searchGeneration == generation else { return }
        lastPaginationTime = nil
        self.error = AppError(
            error,
            fallback: .network(.transport("Couldn't load more results. Try again."))
        )
    }

    func clear() {
        cancelInFlightWork()
        query = ""
        submittedQuery = ""
        replaceResults([])
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

        // Return cached genres if available.
        if let cached = genreCacheByType[type] {
            genres = cached
            return
        }

        // If this exact type is already loading, keep the in-flight request instead of
        // cancel/restarting it (which can happen when the filter sheet is reopened quickly).
        if genreLoadTask != nil, genreLoadTaskType == type {
            return
        }

        genreLoadTask?.cancel()
        genreLoadTaskType = type
        genreLoadTask = Task { [weak self] in
            do {
                let loadedGenres = try await service.getGenres(type: type)
                guard !Task.isCancelled, let self else { return }
                self.genreCacheByType[type] = loadedGenres

                // Only publish into the currently displayed list when the loaded type is
                // still active; otherwise keep it warm in cache for later.
                if (self.selectedType ?? .movie) == type {
                    self.genres = loadedGenres
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                if (self.selectedType ?? .movie) == type {
                    self.genres = []
                }
                Self.logger.error("Genre load failed for \(type.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }

            guard let self, self.genreLoadTaskType == type else { return }
            self.genreLoadTask = nil
            self.genreLoadTaskType = nil
        }
    }

    func selectGenre(_ genre: Genre?) {
        selectedGenre = genre
        if let genre {
            browseGenre(genre)
        } else {
            // Clear genre selection — if there's a text query, re-search; otherwise clear results
            let trimmed = queryDraft.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                search()
            } else {
                replaceResults([])
                currentPage = 1
                totalPages = 1
            }
        }
    }

    func browseGenre(_ genre: Genre) {
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

        guard let service = metadataService else {
            replaceResults([])
            totalPages = 1
            error = .tmdbSetupRequired(feature: "Search")
            isSearching = false
            refreshExplorePhaseIfNeeded()
            return
        }

        searchTask = Task { [weak self] in
            do {
                let filters = DiscoverFilters(
                    genreId: genre.id, year: year, sortBy: sort, page: 1,
                    language: language, releaseDateLte: dateLte, originalLanguage: origLang
                )
                let result = try await service.discover(type: type, filters: filters)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.replaceResults(result.items)
                self.totalPages = result.totalPages
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.replaceResults([])
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

        guard let service = metadataService else {
            replaceResults([])
            totalPages = 1
            error = .tmdbSetupRequired(feature: "Search")
            isSearching = false
            refreshExplorePhaseIfNeeded()
            return
        }

        searchTask = Task { [weak self] in
            do {
                let filters = DiscoverFilters(
                    year: year, sortBy: sortBy, page: 1, language: language,
                    releaseDateGte: releaseDateGte, releaseDateLte: releaseDateLte,
                    originalLanguage: origLang
                )
                let result = try await service.discover(type: type, filters: filters)
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.replaceResults(result.items)
                self.totalPages = result.totalPages
                self.isSearching = false
            } catch {
                guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
                self.replaceResults([])
                self.error = AppError(error, fallback: .network(.transport(errorMessage)))
                self.isSearching = false
            }
        }
    }

    func handleSelectedTypeChange() {
        loadGenres()

        if let card = activeMoodCard {
            // Re-select mood cards so genre IDs are derived for the current media type.
            selectMoodCard(card)
            return
        }

        guard let currentGenre = selectedGenre else {
            requery()
            return
        }

        let type = selectedType ?? .movie
        if let cachedGenres = genreCacheByType[type],
           let remappedGenre = Self.remapGenre(currentGenre, in: cachedGenres) {
            selectGenre(remappedGenre)
            return
        }

        // Fallback: clear stale genre context so we don't keep querying a genre lane
        // that doesn't exist for the newly selected type.
        selectedGenre = nil

        let trimmed = queryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            search(queryText: trimmed)
        } else {
            replaceResults([])
            currentPage = 1
            totalPages = 1
            error = nil
            refreshExplorePhaseIfNeeded()
        }
    }

    nonisolated static func remapGenre(_ genre: Genre, in availableGenres: [Genre]) -> Genre? {
        if let byID = availableGenres.first(where: { $0.id == genre.id }) {
            return byID
        }

        return availableGenres.first(where: {
            $0.name.compare(genre.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
    }

    // MARK: - Sort Option

    func applySortOption(_ option: DiscoverFilters.SortOption) {
        sortOption = option
        requery()
    }

    func applyYearFilter(_ year: Int?) {
        yearFilter = year
        yearRangePreset = nil
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
        let nextSelection = Set(languages.filter { !$0.isEmpty })
        guard nextSelection != languageFilters else { return }

        languageFilters = nextSelection
        requery()
    }

    func toggleLanguage(_ code: String) {
        if code == Self.defaultLanguageCode {
            if languageFilters == [Self.defaultLanguageCode] {
                languageFilters = []
            } else {
                languageFilters = [Self.defaultLanguageCode]
            }
        } else if languageFilters.contains(code) {
            languageFilters.remove(code)
            if languageFilters.isEmpty {
                languageFilters = [Self.defaultLanguageCode]
            }
        } else {
            if languageFilters == [Self.defaultLanguageCode] {
                languageFilters.removeAll()
            }
            languageFilters.insert(code)
        }
        requery()
    }

    func applyFilterDraft(_ draft: SearchFilterDraft) {
        let yearPreset = draft.inferredYearRangePreset
        let stateChanged =
            sortOption != draft.sortOption ||
            yearFilter != draft.selectedYear ||
            yearRangePreset != yearPreset ||
            languageFilters != draft.selectedLanguages ||
            selectedGenre != draft.selectedGenre

        guard stateChanged else { return }

        sortOption = draft.sortOption
        yearFilter = draft.selectedYear
        yearRangePreset = yearPreset
        languageFilters = draft.selectedLanguages

        if selectedGenre != draft.selectedGenre {
            activeMoodCard = nil
            selectGenre(draft.selectedGenre)
            return
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
            let trimmed = queryDraft.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                search()
            }
        }
    }

    private func preferredLanguageCode(in selection: Set<String>) -> String? {
        guard !selection.isEmpty else { return nil }

        let prioritizedKnownCodes = SearchLanguageOption.common.map(\.code)
        if let preferred = prioritizedKnownCodes.first(where: { selection.contains($0) && $0 != Self.defaultLanguageCode }) {
            return preferred
        }

        if selection == [Self.defaultLanguageCode] {
            return nil
        }

        if let fallback = selection.first(where: { $0 != Self.defaultLanguageCode }) {
            return fallback
        }

        return nil
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let json = try await settingsManager.getString(key: SettingsKeys.recentSearches),
                      let data = json.data(using: .utf8) else {
                    self.recentSearches = []
                    return
                }
                self.recentSearches = try JSONDecoder().decode([String].self, from: data)
            } catch {
                self.recentSearches = []
                Self.logger.error("Recent search load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func saveRecentSearches(to settingsManager: SettingsManager) {
        let searches = recentSearches
        Task {
            do {
                let data = try JSONEncoder().encode(searches)
                guard let json = String(data: data, encoding: .utf8) else { return }
                try await settingsManager.setString(key: SettingsKeys.recentSearches, value: json)
            } catch {
                Self.logger.error("Recent search save failed: \(error.localizedDescription, privacy: .public)")
            }
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
        let trimmed = queryDraft.trimmingCharacters(in: .whitespaces)

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
