import Combine
import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SearchViewModel()
    @State private var selectedItem: MediaPreview?
    @State private var tmdbReloadTask: Task<Void, Never>?
    @State private var selectedYear: Int? = nil
    @State private var selectedLanguages: Set<String> = ["en-US"]
    @State private var isShowingFilters = false
    @State private var userRatings: [String: TasteEvent] = [:]

    var body: some View {
        VStack(spacing: 0) {
            exploreHeader
            searchBarSection
            typeFilterSection
            inlineFilterBar

            ZStack {
                switch viewModel.explorePhase {
                case .idle:
                    exploreIdleContent
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                case .searching:
                    ExploreSkeletonView()
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                case .empty:
                    ExploreEmptyView(query: viewModel.query)
                        .frame(maxHeight: .infinity)
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                case .error:
                    errorContent
                        .frame(maxHeight: .infinity)
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                case .results:
                    resultsSection
                        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.explorePhase)
        }
        .navigationTitle("Explore")
        .navigationDestination(item: $selectedItem) { item in
            DetailView(preview: item)
        }
        .task {
            await reloadTMDBConfigurationAndSearch()
        }
        .task {
            await loadUserRatings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tasteProfileDidChange)) { _ in
            Task { await loadUserRatings() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tmdbApiKeyDidChange)) { _ in
            tmdbReloadTask?.cancel()
            tmdbReloadTask = Task { await reloadTMDBConfigurationAndSearch() }
        }
        .onDisappear {
            viewModel.cancelInFlightWork()
            tmdbReloadTask?.cancel()
            tmdbReloadTask = nil
            viewModel.saveRecentSearches(to: appState.settingsManager)
        }
        .sheet(isPresented: $isShowingFilters) {
            ExploreFilterSheet(
                sortOption: Bindable(viewModel).sortOption,
                selectedYear: $selectedYear,
                selectedLanguages: $selectedLanguages,
                genres: viewModel.genres,
                selectedGenre: Binding(
                    get: { viewModel.selectedGenre },
                    set: { viewModel.selectGenre($0) }
                ),
                displayedSortOptions: displayedSortOptions,
                onApply: {
                    viewModel.applyYearFilter(selectedYear)
                    viewModel.applyLanguageFilters(selectedLanguages)
                }
            )
        }
        .onChange(of: isShowingFilters) { _, showing in
            if showing {
                // Sync local filter state from viewModel when sheet opens
                selectedYear = viewModel.yearFilter
                selectedLanguages = viewModel.languageFilters
                // Ensure genres are loaded for the filter sheet
                if viewModel.genres.isEmpty {
                    viewModel.loadGenres()
                }
            }
        }
    }

    // MARK: - Explore Header

    private var exploreHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explore")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Movies, TV shows, and more")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Search Bar

    private var searchBarSection: some View {
        HStack(spacing: 10) {
            HStack {
                ZStack {
                    if viewModel.isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.isSearching)
                .frame(width: 20, height: 20)

                TextField("Movies, TV shows, and more\u{2026}", text: Bindable(viewModel).query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: viewModel.query) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            viewModel.cancelInFlightWork()
                            viewModel.results = []
                            viewModel.error = nil
                            viewModel.currentPage = 1
                            viewModel.totalPages = 1
                        } else {
                            viewModel.debouncedSearch()
                        }
                    }
                    .onSubmit {
                        viewModel.search()
                        let trimmed = viewModel.query.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            viewModel.addRecentSearch(trimmed)
                            viewModel.saveRecentSearches(to: appState.settingsManager)
                        }
                    }

                if !viewModel.query.isEmpty {
                    Button { viewModel.clear() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }

            askAIButton

            // More Filters button with badge
            moreFiltersButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    // MARK: - AI Button

    private var aiButtonEnabled: Bool {
        !viewModel.isLoadingAI
    }

    private var askAIButton: some View {
        SpatialButton(
            title: "Curate For Me",
            icon: "sparkles",
            tint: aiButtonEnabled ? .purple : .gray
        ) {
            guard aiButtonEnabled else { return }
            viewModel.fetchAIRecommendations(aiManager: appState.aiAssistantManager)
        }
        .opacity(aiButtonEnabled ? 1.0 : 0.5)
        .allowsHitTesting(aiButtonEnabled)
    }

    // MARK: - More Filters Button

    private var moreFiltersButton: some View {
        Button {
            isShowingFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
                    .shadow(color: .black.opacity(0.13), radius: 8, y: 4)

                // Filter count badge
                if viewModel.activeFilterCount > 0 {
                    Text("\(viewModel.activeFilterCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.activeFilterCount)
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    // MARK: - Inline Filter Bar

    @ViewBuilder
    private var inlineFilterBar: some View {
        let showBar = viewModel.hasActiveFilters
            || !viewModel.query.isEmpty
            || viewModel.selectedGenre != nil

        if showBar {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Year range presets
                    ForEach(YearRangePreset.allCases) { preset in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.applyYearRangePreset(preset)
                            }
                        } label: {
                            InlineFilterChip(
                                text: preset.displayName,
                                symbol: "calendar",
                                isActive: viewModel.yearRangePreset == preset
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(
                            .asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }

                    // Active year filter (if set to a specific year, not a preset)
                    if let year = viewModel.yearFilter, viewModel.yearRangePreset == nil {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.applyYearFilter(nil)
                            }
                        } label: {
                            InlineFilterChip(
                                text: String(year),
                                symbol: "xmark.circle.fill",
                                isActive: true
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(
                            .asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }

                    // Divider if we have both year and language chips
                    if viewModel.yearFilter != nil || viewModel.yearRangePreset != nil {
                        chipDivider
                    }

                    // Active language chips
                    ForEach(activeLanguageChips, id: \.code) { lang in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.toggleLanguage(lang.code)
                            }
                        } label: {
                            InlineFilterChip(
                                text: lang.name,
                                symbol: "xmark.circle.fill",
                                isActive: true,
                                tint: .blue
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(
                            .asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }

                    // Add language button
                    addLanguageMenu

                    // Active genre chip
                    if let genre = viewModel.selectedGenre {
                        chipDivider

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectGenre(nil)
                            }
                        } label: {
                            InlineFilterChip(
                                text: genre.name,
                                symbol: "xmark.circle.fill",
                                isActive: true,
                                tint: .orange
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(
                            .asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }

                    // Non-default sort indicator
                    if viewModel.sortOption != .popularityDesc {
                        chipDivider

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.applySortOption(.popularityDesc)
                            }
                        } label: {
                            InlineFilterChip(
                                text: viewModel.sortOption.displayName,
                                symbol: "xmark.circle.fill",
                                isActive: true,
                                tint: .green
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(
                            .asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }

                    // Clear All button
                    if viewModel.hasActiveFilters {
                        chipDivider

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.clearAllFilters()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Clear All")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15), in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                            }
                            .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        #if os(visionOS)
                        .hoverEffect(.highlight)
                        #endif
                        .transition(
                            .asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.yearRangePreset)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.yearFilter)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.languageFilters)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.selectedGenre?.id)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.sortOption)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Tiny vertical divider between filter chip groups.
    private var chipDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.quaternary)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }

    /// Language chips currently shown as active (non-default selections).
    private var activeLanguageChips: [SearchLanguageOption.Option] {
        // Show removable chips for all selected languages except the default "en-US"
        // when it's the only one selected
        if viewModel.languageFilters == ["en-US"] { return [] }
        return SearchLanguageOption.common.filter { viewModel.languageFilters.contains($0.code) }
    }

    /// Menu button to add additional languages.
    private var addLanguageMenu: some View {
        Menu {
            ForEach(
                SearchLanguageOption.common,
                id: \SearchLanguageOption.Option.code
            ) { option in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.toggleLanguage(option.code)
                    }
                } label: {
                    HStack {
                        Text(option.name)
                        if viewModel.languageFilters.contains(option.code) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Type Filter

    private var typeFilterSection: some View {
        Picker("Type", selection: Bindable(viewModel).selectedType) {
            Text("All").tag(nil as MediaType?)
            Text("Movies").tag(MediaType.movie as MediaType?)
            Text("TV Shows").tag(MediaType.series as MediaType?)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .onChange(of: viewModel.selectedType) { _, _ in
            if let card = viewModel.activeMoodCard {
                // Re-select the mood card so genre IDs are re-derived for the new type
                viewModel.selectMoodCard(card)
            } else if viewModel.selectedGenre != nil {
                viewModel.loadGenres()
                viewModel.selectGenre(viewModel.selectedGenre)
            } else {
                viewModel.requery()
            }
        }
    }

    // MARK: - Idle Content (Explore)

    private var exploreIdleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !viewModel.recentSearches.isEmpty {
                    RecentSearchesSection(
                        searches: viewModel.recentSearches,
                        onSelect: { term in
                            viewModel.query = term
                            viewModel.search()
                            viewModel.addRecentSearch(term)
                            viewModel.saveRecentSearches(to: appState.settingsManager)
                        },
                        onRemove: { term in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.removeRecentSearch(term)
                            }
                            viewModel.saveRecentSearches(to: appState.settingsManager)
                        },
                        onClear: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.clearRecentSearches()
                            }
                            viewModel.saveRecentSearches(to: appState.settingsManager)
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ExploreGenreGrid(
                    cards: ExploreGenreCatalog.cards,
                    onSelect: { card in
                        viewModel.selectMoodCard(card)
                    }
                )
            }
            .padding(24)
        }
    }

    // MARK: - Error Content

    private var errorContent: some View {
        VStack {
            if let error = viewModel.error {
                ExploreErrorView(error: error) {
                    viewModel.retry()
                }
            }
        }
    }

    // MARK: - Active Filter Summary

    private var activeFilterSummary: some View {
        HStack(spacing: 8) {
            if viewModel.sortOption != .popularityDesc {
                GlassTag(text: viewModel.sortOption.displayName, symbol: "arrow.up.arrow.down")
            }

            if let genre = viewModel.selectedGenre {
                Button { viewModel.selectGenre(nil) } label: {
                    GlassTag(text: genre.name, tintColor: .accentColor, symbol: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }

            if viewModel.languageFilters != ["en-US"], !viewModel.languageFilters.isEmpty {
                GlassTag(
                    text: SearchLanguageOption.summaryName(for: viewModel.languageFilters),
                    tintColor: .accentColor,
                    symbol: "globe"
                )
            }

            if let year = viewModel.yearFilter {
                GlassTag(text: String(year), symbol: "calendar")
            }

            Spacer()

            GlassIconButton(icon: "line.3.horizontal.decrease", size: 32) {
                isShowingFilters = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .task {
            if viewModel.genres.isEmpty {
                viewModel.loadGenres()
            }
        }
    }

    /// Expose a useful subset of sort options for the menu.
    private var displayedSortOptions: [DiscoverFilters.SortOption] {
        [.popularityDesc, .ratingDesc, .releaseDateDesc, .titleAsc]
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(spacing: 0) {
            activeFilterSummary

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear
                            .frame(height: 0)
                            .id("results-top")

                        aiRecommendationsSection

                        SearchResultsGrid(
                            viewModel: viewModel,
                            selectedItem: $selectedItem,
                            userRatings: userRatings
                        )

                        if viewModel.isLoadingMore {
                            PaginationLoadingView()
                                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        }
                    }
                    .padding(24)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.results.count)
                }
                .onChange(of: viewModel.scrollToTopTrigger) { _, _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo("results-top", anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var aiRecommendationsSection: some View {
        if viewModel.isLoadingAI {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Getting AI recommendations\u{2026}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if let aiError = viewModel.aiError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                Text(aiError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .glassStroke(cornerRadius: 10)
            .transition(.opacity)
        }

        if !viewModel.aiRecommendations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI Picks", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.clearAIRecommendations()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.aiRecommendations) { rec in
                            Button {
                                selectedItem = rec.toMediaPreview()
                            } label: {
                                AIRecommendationCard(recommendation: rec)
                            }
                            .buttonStyle(.plain)
                            #if os(visionOS)
                            .hoverEffect(.lift)
                            #endif
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Helpers

    @MainActor
    private func loadUserRatings() async {
        let events = (try? await appState.database.fetchTasteEvents(eventType: .rated, limit: 500)) ?? []
        var dict: [String: TasteEvent] = [:]
        for event in events {
            if let mediaId = event.mediaId {
                dict[mediaId] = event
            }
        }
        userRatings = dict
    }

    @MainActor
    private func reloadTMDBConfigurationAndSearch() async {
        let key = (try? await appState.settingsManager.getString(key: SettingsKeys.tmdbApiKey)) ?? ""
        let existingQuery = viewModel.query
        let existingType = viewModel.selectedType
        let existingGenre = viewModel.selectedGenre
        let existingSort = viewModel.sortOption
        let existingYear = viewModel.yearFilter
        let existingYearPreset = viewModel.yearRangePreset
        let existingLanguages = viewModel.languageFilters
        let existingRecents = viewModel.recentSearches
        let shouldSearch = !existingQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        viewModel.cancelInFlightWork()

        let refreshedViewModel = SearchViewModel()
        refreshedViewModel.query = existingQuery
        refreshedViewModel.selectedType = existingType
        refreshedViewModel.selectedGenre = existingGenre
        refreshedViewModel.sortOption = existingSort
        refreshedViewModel.yearFilter = existingYear
        refreshedViewModel.yearRangePreset = existingYearPreset
        refreshedViewModel.languageFilters = existingLanguages
        refreshedViewModel.recentSearches = existingRecents
        refreshedViewModel.configure(apiKey: key)
        viewModel = refreshedViewModel

        // Genres are loaded lazily when the filter summary appears — no eager fetch here.
        viewModel.loadRecentSearches(from: appState.settingsManager)

        if existingGenre != nil {
            viewModel.requery()
        } else if shouldSearch {
            viewModel.search()
        }
    }
}

// MARK: - Search Results Grid (extracted to minimize re-renders)

/// Extracted from SearchView so that only this subview re-renders when `results` or
/// `isLoadingMore` change. The parent SearchView's header, search bar, type filter,
/// and filter summary are not invalidated by results list mutations.
private struct SearchResultsGrid: View {
    @Bindable var viewModel: SearchViewModel
    @Binding var selectedItem: MediaPreview?
    var userRatings: [String: TasteEvent] = [:]

    private static let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 16) {
            ForEach(viewModel.results) { item in
                Button { selectedItem = item } label: {
                    MediaCardView(item: item, userRating: userRatings[item.id])
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif
                .onAppear {
                    if viewModel.shouldTriggerPagination(for: item.id) {
                        viewModel.loadMore()
                    }
                }
            }
        }
    }
}

// MARK: - Inline Filter Chip

/// A compact pill chip for use in the inline filter bar.
/// Active state uses tinted background and bold text. Inactive uses glass material.
struct InlineFilterChip: View {
    let text: String
    var symbol: String?
    var isActive: Bool = false
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(chipBackground, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    isActive
                        ? AnyShapeStyle(tint.opacity(0.45))
                        : AnyShapeStyle(LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )),
                    lineWidth: 1
                )
        }
        .foregroundStyle(isActive ? tint : .primary)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }

    private var chipBackground: AnyShapeStyle {
        if isActive {
            AnyShapeStyle(tint.opacity(0.18))
        } else {
            AnyShapeStyle(.ultraThinMaterial)
        }
    }
}

// MARK: - Language Options

enum SearchLanguageOption {
    struct Option: Identifiable {
        var id: String { code }
        let code: String
        let name: String
    }

    static let common: [Option] = [
        Option(code: "en-US", name: "English"),
        Option(code: "es-ES", name: "Spanish"),
        Option(code: "fr-FR", name: "French"),
        Option(code: "de-DE", name: "German"),
        Option(code: "it-IT", name: "Italian"),
        Option(code: "pt-BR", name: "Portuguese"),
        Option(code: "ja-JP", name: "Japanese"),
        Option(code: "ko-KR", name: "Korean"),
        Option(code: "zh-CN", name: "Chinese"),
        Option(code: "hi-IN", name: "Hindi"),
        Option(code: "ar-SA", name: "Arabic"),
        Option(code: "ru-RU", name: "Russian"),
        Option(code: "nl-NL", name: "Dutch"),
        Option(code: "sv-SE", name: "Swedish"),
        Option(code: "pl-PL", name: "Polish"),
        Option(code: "tr-TR", name: "Turkish"),
        Option(code: "th-TH", name: "Thai"),
    ]

    static func displayName(for code: String?) -> String {
        guard let code else { return "Language" }
        return common.first(where: { $0.code == code })?.name ?? code
    }

    static func summaryName(for codes: Set<String>) -> String {
        if codes.isEmpty { return "Any" }
        if codes.count == 1, let code = codes.first {
            return displayName(for: code)
        }
        let names = codes.compactMap { code in common.first(where: { $0.code == code })?.name }
        if names.count <= 2 {
            return names.sorted().joined(separator: ", ")
        }
        return "\(names.count) languages"
    }
}

