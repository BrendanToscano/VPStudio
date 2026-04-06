import Combine
import SwiftUI

enum SearchShellCopyPolicy {
    static func title(
        explorePhase: ExplorePhase,
        submittedQuery: String,
        hasSelectedGenre: Bool,
        hasActiveMoodCard: Bool
    ) -> String {
        if explorePhase == .results || !submittedQuery.isEmpty {
            return "Search the catalog"
        }

        if hasSelectedGenre || hasActiveMoodCard {
            return "Hold the lane"
        }

        return "Find the next frame"
    }

    static func subtitle(
        activeMoodCardTitle: String?,
        selectedGenreName: String?,
        submittedQuery: String
    ) -> String {
        if let activeMoodCardTitle {
            return "You are already inside \(activeMoodCardTitle.lowercased()) picks. Tighten the lane with search and filters without losing the browse context."
        }

        if let selectedGenreName {
            return "You are browsing \(selectedGenreName.lowercased()) picks. Search can get precise while the editorial browse lane stays open."
        }

        if !submittedQuery.isEmpty {
            return "Tighten the query, switch type, or add filters without losing the current poster wall."
        }

        return "Start with a title, actor, or keyword, then drift into the browse rails below if you want a wider opening."
    }
}

enum SearchLoadingPresentationMode: Equatable {
    case idle
    case blockingSkeleton
    case refreshingRetainedResults
    case empty
    case error
    case results
}

enum SearchLoadingPresentationPolicy {
    static let refreshTitle = "Updating results…"

    static func presentationMode(
        explorePhase: ExplorePhase,
        resultCount: Int,
        aiRecommendationCount: Int
    ) -> SearchLoadingPresentationMode {
        let hasRetainedResults = resultCount > 0 || aiRecommendationCount > 0

        if explorePhase == .searching {
            return hasRetainedResults ? .refreshingRetainedResults : .blockingSkeleton
        }

        switch explorePhase {
        case .idle:
            return .idle
        case .searching:
            return .blockingSkeleton
        case .results:
            return .results
        case .empty:
            return .empty
        case .error:
            return .error
        }
    }
}

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SearchViewModel()
    @State private var selectedItem: MediaPreview?
    @State private var tmdbReloadTask: Task<Void, Never>?
    @State private var selectedYear: Int? = nil
    @State private var selectedLanguages: Set<String> = ["en-US"]
    @State private var isShowingFilters = false
    @State private var userRatings: [String: TasteEvent] = [:]
    @State private var hasLoadedUserRatings = false
    @State private var hasHydratedRecentSearches = false
    @State private var hasAppliedSearchQARuntime = false
    @State private var hasAutoOpenedQAResult = false
    @State private var suppressNextSearchDraftDebounce = false
    @State private var searchDraft = ""
    private let contentMaxWidth: CGFloat = 1080
    private let celestialSurface = Color(red: 0.09, green: 0.09, blue: 0.11)
    private let celestialSurfaceRaised = Color(red: 0.15, green: 0.15, blue: 0.18)
    private let celestialPurple = Color(red: 0.56, green: 0.58, blue: 1.0)
    private let celestialPurpleDeep = Color(red: 0.44, green: 0.45, blue: 1.0)
    private let celestialMint = Color(red: 0.80, green: 0.92, blue: 0.92)
    private let atmosphericBlue = Color(red: 0.08, green: 0.42, blue: 0.94)
    private let atmosphericGreen = Color(red: 0.14, green: 0.90, blue: 0.56)
    private let atmosphericPink = Color(red: 0.72, green: 0.24, blue: 0.96)
    private let atmosphericGold = Color(red: 0.92, green: 0.74, blue: 0.26)

    private var searchLoadingPresentation: SearchLoadingPresentationMode {
        SearchLoadingPresentationPolicy.presentationMode(
            explorePhase: viewModel.explorePhase,
            resultCount: viewModel.results.count,
            aiRecommendationCount: viewModel.aiRecommendations.count
        )
    }

    var body: some View {
        ZStack {
            VPMenuBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                searchBarSection
                inlineFilterBar

                ZStack {
                    switch searchLoadingPresentation {
                    case .idle:
                        exploreIdleContent
                            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    case .blockingSkeleton:
                        ExploreSkeletonView()
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    case .empty:
                        ExploreEmptyView(query: viewModel.submittedQuery)
                            .frame(maxHeight: .infinity)
                            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    case .error:
                        errorContent
                            .frame(maxHeight: .infinity)
                            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    case .refreshingRetainedResults, .results:
                        resultsSection(showRefreshIndicator: searchLoadingPresentation == .refreshingRetainedResults)
                            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: searchLoadingPresentation)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(item: $selectedItem) { item in
            DetailView(preview: item)
        }
        .task {
            if searchDraft.isEmpty {
                searchDraft = viewModel.queryDraft
            }
            hydrateRecentSearchesIfNeeded()
            await reloadTMDBConfigurationAndSearch()
            applySearchQARuntimeIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tasteProfileDidChange)) { _ in
            guard hasLoadedUserRatings else { return }
            Task { await loadUserRatings(force: true) }
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
        .onChange(of: viewModel.results.map(\.id)) { _, _ in
            applySearchResultQARuntimeIfNeeded()
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

    private func centeredStage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var searchAtmosphereBackground: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.04, blue: 0.09),
                        Color(red: 0.06, green: 0.09, blue: 0.17),
                        Color(red: 0.02, green: 0.03, blue: 0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                atmosphericGlow(color: atmosphericBlue, width: size.width * 0.42, height: size.height * 0.50)
                    .offset(x: -size.width * 0.18, y: -size.height * 0.08)

                atmosphericGlow(color: atmosphericPink, width: size.width * 0.32, height: size.height * 0.40)
                    .offset(x: -size.width * 0.02, y: -size.height * 0.10)

                atmosphericGlow(color: atmosphericGreen, width: size.width * 0.34, height: size.height * 0.42)
                    .offset(x: size.width * 0.12, y: -size.height * 0.08)

                atmosphericGlow(color: atmosphericPink, width: size.width * 0.30, height: size.height * 0.40)
                    .offset(x: size.width * 0.16, y: size.height * 0.12)

                atmosphericGlow(color: atmosphericGreen, width: size.width * 0.34, height: size.height * 0.42)
                    .offset(x: size.width * 0.30, y: size.height * 0.10)

                atmosphericGlow(color: atmosphericGold, width: size.width * 0.28, height: size.height * 0.34)
                    .offset(x: size.width * 0.38, y: size.height * 0.22)

                atmosphericOrb(color: atmosphericBlue, diameter: size.width * 0.10, blur: 20)
                    .offset(x: -size.width * 0.11, y: -size.height * 0.31)

                atmosphericOrb(color: atmosphericPink, diameter: size.width * 0.09, blur: 18)
                    .offset(x: size.width * 0.00, y: -size.height * 0.30)

                atmosphericOrb(color: atmosphericGreen, diameter: size.width * 0.10, blur: 20)
                    .offset(x: size.width * 0.10, y: -size.height * 0.30)

                atmosphericOrb(color: atmosphericGreen, diameter: size.width * 0.09, blur: 20)
                    .offset(x: size.width * 0.25, y: size.height * 0.02)

                atmosphericOrb(color: atmosphericGold, diameter: size.width * 0.09, blur: 18)
                    .offset(x: size.width * 0.34, y: size.height * 0.06)

                atmosphericOrb(color: atmosphericPink, diameter: size.width * 0.08, blur: 18)
                    .offset(x: size.width * 0.39, y: -size.height * 0.02)

                atmosphericOrb(color: atmosphericGreen, diameter: size.width * 0.10, blur: 34)
                    .offset(x: -size.width * 0.36, y: -size.height * 0.26)

                atmosphericOrb(color: atmosphericBlue, diameter: size.width * 0.07, blur: 20)
                    .offset(x: -size.width * 0.12, y: -size.height * 0.28)

                atmosphericOrb(color: atmosphericPink, diameter: size.width * 0.07, blur: 18)
                    .offset(x: size.width * 0.00, y: -size.height * 0.29)

                atmosphericOrb(color: atmosphericGreen, diameter: size.width * 0.08, blur: 20)
                    .offset(x: size.width * 0.13, y: -size.height * 0.25)

                atmosphericOrb(color: atmosphericGold, diameter: size.width * 0.08, blur: 26)
                    .offset(x: -size.width * 0.25, y: -size.height * 0.07)

                atmosphericOrb(color: atmosphericGold, diameter: size.width * 0.07, blur: 18)
                    .offset(x: -size.width * 0.19, y: -size.height * 0.17)

                atmosphericOrb(color: atmosphericGreen, diameter: size.width * 0.07, blur: 18)
                    .offset(x: -size.width * 0.18, y: size.height * 0.07)

                atmosphericOrb(color: atmosphericPink, diameter: size.width * 0.08, blur: 22)
                    .offset(x: -size.width * 0.08, y: size.height * 0.17)

                atmosphericOrb(color: atmosphericGold, diameter: size.width * 0.07, blur: 18)
                    .offset(x: size.width * 0.12, y: size.height * 0.23)

                atmosphericOrb(color: atmosphericBlue, diameter: size.width * 0.09, blur: 30)
                    .offset(x: -size.width * 0.06, y: -size.height * 0.02)

                atmosphericOrb(color: atmosphericPink, diameter: size.width * 0.11, blur: 34)
                    .offset(x: size.width * 0.08, y: -size.height * 0.18)

                atmosphericOrb(color: atmosphericGreen, diameter: size.width * 0.10, blur: 30)
                    .offset(x: size.width * 0.24, y: -size.height * 0.04)

                atmosphericOrb(color: atmosphericBlue, diameter: size.width * 0.09, blur: 28)
                    .offset(x: size.width * 0.34, y: -size.height * 0.22)

                atmosphericOrb(color: atmosphericBlue, diameter: size.width * 0.08, blur: 20)
                    .offset(x: size.width * 0.44, y: -size.height * 0.03)

                atmosphericOrb(color: atmosphericGold, diameter: size.width * 0.08, blur: 20)
                    .offset(x: -size.width * 0.33, y: size.height * 0.09)

                atmosphericOrb(color: atmosphericPink, diameter: size.width * 0.08, blur: 22)
                    .offset(x: size.width * 0.24, y: size.height * 0.17)

                atmosphericOrb(color: atmosphericGreen, diameter: size.width * 0.08, blur: 22)
                    .offset(x: size.width * 0.36, y: size.height * 0.11)

                atmosphericOrb(color: atmosphericGold, diameter: size.width * 0.07, blur: 18)
                    .offset(x: size.width * 0.45, y: size.height * 0.20)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.01),
                                Color.black.opacity(0.14),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private func atmosphericGlow(color: Color, width: CGFloat, height: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(0.70),
                        color.opacity(0.20),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width, height) * 0.5
                )
            )
            .frame(width: width, height: height)
            .blur(radius: 88)
            .blendMode(.screen)
    }

    private func atmosphericOrb(color: Color, diameter: CGFloat, blur: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(0.95),
                        color.opacity(0.36),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: blur)
            .blendMode(.screen)
    }

    // MARK: - Search Bar

    private var searchShellTitle: String {
        SearchShellCopyPolicy.title(
            explorePhase: viewModel.explorePhase,
            submittedQuery: viewModel.submittedQuery,
            hasSelectedGenre: viewModel.selectedGenre != nil,
            hasActiveMoodCard: viewModel.activeMoodCard != nil
        )
    }

    private var searchShellSubtitle: String {
        SearchShellCopyPolicy.subtitle(
            activeMoodCardTitle: viewModel.activeMoodCard?.title,
            selectedGenreName: viewModel.selectedGenre?.name,
            submittedQuery: viewModel.submittedQuery
        )
    }

        private var searchBarSection: some View {
        centeredStage {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(searchShellTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))

                    Text(searchShellSubtitle)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.32))
                        .lineLimit(2)
                }

                HStack(alignment: .center, spacing: 8) {
                    SearchQueryBar(
                        viewModel: viewModel,
                        seedQuery: searchDraft,
                        suppressNextDraftDebounce: $suppressNextSearchDraftDebounce,
                        placeholder: "Try: gritty sci-fi movies, cozy TV, or ask for AI picks",
                        onSubmit: { text in submitSearch(queryText: text) },
                        onClear: {
                            searchDraft = ""
                            viewModel.clear()
                        }
                    )
                    .frame(maxWidth: .infinity)

                    askAIButton

                    filterUtilityButton
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }


    private var searchHeroCompanionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.aiRecommendations.isEmpty ? "Curator" : "AI picks ready")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(
                viewModel.aiRecommendations.isEmpty
                    ? "Use the AI curator once you have the lane roughly framed."
                    : "\(viewModel.aiRecommendations.count) curated picks are ready below if you want a fast jump."
            )
            .font(.subheadline)
            .foregroundStyle(Color.primary.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)

            askAIButton
        }
        .frame(maxWidth: 278, alignment: .leading)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(celestialSurfaceRaised.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.08),
                                    celestialPurple.opacity(0.14),
                                    .clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .shadow(color: celestialPurple.opacity(0.08), radius: 22, y: 10)
    }

    private var searchHeroSupportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shouldShowTypeFilterSection ? "Focus" : "How To Start")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if shouldShowTypeFilterSection {
                typeFilterSection
                    .frame(maxWidth: 560, alignment: .leading)
            } else {
                Text("Search by title, performer, or keyword first. The browse composition below stays live so you can widen the search without resetting the page.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(celestialSurfaceRaised.opacity(0.52))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.06), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
    }

    // MARK: - AI Button

    private var shouldShowTypeFilterSection: Bool {
        !viewModel.submittedQuery.isEmpty
            || viewModel.selectedGenre != nil
            || viewModel.activeMoodCard != nil
            || viewModel.explorePhase == .results
            || viewModel.hasActiveFilters
    }

    private var aiButtonEnabled: Bool {
        !viewModel.isLoadingAI
    }

        private var askAIButton: some View {
        Button {
            guard aiButtonEnabled else { return }
            viewModel.fetchAIRecommendations(aiManager: appState.aiAssistantManager)
        } label: {
            HStack(spacing: 6) {
                if viewModel.isLoadingAI {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                }

                Text(viewModel.isLoadingAI ? "Curating" : "Curate For Me")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.12),
                                        Color(red: 0.48, green: 0.93, blue: 0.96).opacity(0.10),
                                        .clear,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.14), lineWidth: 0.8)
                    }
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        .opacity(aiButtonEnabled ? 1.0 : 0.5)
        .allowsHitTesting(aiButtonEnabled)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }


        private var filterUtilityButton: some View {
        Button {
            isShowingFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.05),
                                                .clear,
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(.white.opacity(0.11), lineWidth: 0.8)
                            }
                    }

                if viewModel.activeFilterCount > 0 {
                    Text("\(viewModel.activeFilterCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .offset(x: 4, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }


    private var curationBanner: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI CURATION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(celestialPurple.opacity(0.92))
                    .tracking(1.4)
                Text("Need a stronger nudge?")
                    .font(.headline)
                Text("Let VPStudio assemble a short list from your taste profile after you browse the rails.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            askAIButton
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    celestialSurface.opacity(0.72),
                                    celestialPurpleDeep.opacity(0.24),
                                    .white.opacity(0.05),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .shadow(color: celestialPurple.opacity(0.12), radius: 24, y: 10)
    }

    // MARK: - More Filters Button

    private var moreFiltersButton: some View {
        Button {
            isShowingFilters = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Refine")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Filters")
                        .font(.subheadline.weight(.semibold))

                    if viewModel.activeFilterCount > 0 {
                        Text("\(viewModel.activeFilterCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(celestialSurfaceRaised, in: Circle())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundStyle(.primary)
            }
            .frame(width: 134, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(celestialSurfaceRaised.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.08), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.activeFilterCount)
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    // MARK: - Inline Filter Bar

    private var inlineFilterBar: some View {
        centeredStage {
            VStack(spacing: shouldShowCompactFilterSummary ? 8 : 0) {
                typeFilterSection
                    .frame(maxWidth: .infinity, alignment: .center)

                if shouldShowCompactFilterSummary {
                    compactFilterSummaryRow
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: viewModel.activeFilterCount)
    }

    private var chipDivider: some View {
        Circle()
            .fill(.white.opacity(0.18))
            .frame(width: 4, height: 4)
            .padding(.horizontal, 4)
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
                    viewModel.toggleLanguage(option.code)
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
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                Text("Language")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }

    private var shouldShowCompactFilterSummary: Bool {
        viewModel.activeMoodCard != nil
            || viewModel.selectedGenre != nil
            || viewModel.sortOption != .popularityDesc
            || (viewModel.languageFilters != ["en-US"] && !viewModel.languageFilters.isEmpty)
            || viewModel.yearFilter != nil
            || viewModel.yearRangePreset != nil
    }

    private var compactFilterSummaryRow: some View {
        FlowLayout(spacing: 8) {
            if let card = viewModel.activeMoodCard {
                compactSummaryChip(
                    title: card.title,
                    symbol: card.symbol,
                    tint: card.color.opacity(0.28)
                )
            }

            if let genre = viewModel.selectedGenre {
                Button {
                    viewModel.selectGenre(nil)
                } label: {
                    compactSummaryChip(
                        title: genre.name,
                        symbol: "xmark.circle.fill",
                        tint: Color.orange.opacity(0.24)
                    )
                }
                .buttonStyle(.plain)
            }

            if viewModel.sortOption != .popularityDesc {
                compactSummaryChip(
                    title: viewModel.sortOption.displayName,
                    symbol: "arrow.up.arrow.down",
                    tint: Color.green.opacity(0.22)
                )
            }

            if viewModel.languageFilters != ["en-US"], !viewModel.languageFilters.isEmpty {
                compactSummaryChip(
                    title: SearchLanguageOption.summaryName(for: viewModel.languageFilters),
                    symbol: "globe",
                    tint: Color.blue.opacity(0.22)
                )
            }

            if let preset = viewModel.yearRangePreset {
                compactSummaryChip(
                    title: preset.displayName,
                    symbol: "calendar",
                    tint: Color.white.opacity(0.10)
                )
            } else if let year = viewModel.yearFilter {
                compactSummaryChip(
                    title: String(year),
                    symbol: "calendar",
                    tint: Color.white.opacity(0.10)
                )
            }

            if viewModel.hasActiveFilters {
                Button {
                    viewModel.clearAllFilters()
                } label: {
                    compactSummaryChip(
                        title: "Clear",
                        symbol: "xmark",
                        tint: Color.red.opacity(0.22)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func compactSummaryChip(title: String, symbol: String?, tint: Color) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(tint)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.10),
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
        }
    }

    // MARK: - Type Filter

        private var typeFilterSection: some View {
        HStack(spacing: 0) {
            typeFilterButton(title: "All", type: nil)
            typeFilterButton(title: "Movies", type: .movie)
            typeFilterButton(title: "TV Shows", type: .series)
        }
        .padding(2)
        .frame(maxWidth: 400)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.06),
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.09), lineWidth: 0.75)
                }
        }
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private func typeFilterButton(title: String, type: MediaType?) -> some View {
        let isSelected = viewModel.selectedType == type

        return Button {
            setSelectedType(type)
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color.black.opacity(0.84) : .white.opacity(0.62))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(red: 0.46, green: 0.93, blue: 0.95))
                            .shadow(color: Color(red: 0.46, green: 0.93, blue: 0.95).opacity(0.42), radius: 5, y: 0)
                    }
                }
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }


    private func setSelectedType(_ type: MediaType?) {
        guard viewModel.selectedType != type else { return }
        viewModel.selectedType = type
        viewModel.handleSelectedTypeChange()
    }

    // MARK: - Idle Content (Explore)

    private var exploreIdleContent: some View {
        ScrollView {
            centeredStage {
                VStack(alignment: .leading, spacing: 32) {
                    if !viewModel.recentSearches.isEmpty {
                        RecentSearchesSection(
                            searches: viewModel.recentSearches,
                            onSelect: { term in
                                submitSearch(queryText: term)
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
                        .transition(.opacity)
                    }

                    ExploreGenreGrid(
                        cards: ExploreGenreCatalog.cards,
                        onSelect: { card in
                            viewModel.selectMoodCard(card)
                        }
                    )
                }
                .padding(.horizontal, 40)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }


    // MARK: - Error Content

    private var errorContent: some View {
        VStack {
            if let error = viewModel.error {
                ExploreErrorView(
                    error: error,
                    onRetry: {
                        viewModel.retry()
                    },
                    onOpenSettings: {
                        appState.selectedTab = .settings
                    }
                )
            }
        }
    }

    // MARK: - Active Filter Summary

    private var selectedContentDescriptor: String {
        switch viewModel.selectedType {
        case .movie?: return "movies"
        case .series?: return "TV shows"
        case nil: return "movies and TV shows"
        }
    }

    private var resultsContextTitle: String {
        if let card = viewModel.activeMoodCard {
            return card.title
        }

        if let genre = viewModel.selectedGenre {
            return genre.name
        }

        if !viewModel.submittedQuery.isEmpty {
            return "Results for \"\(viewModel.submittedQuery)\""
        }

        return "Browse Results"
    }

    private var resultsContextSubtitle: String {
        if let card = viewModel.activeMoodCard {
            if card.isNewReleases {
                return "Fresh \(selectedContentDescriptor) sorted to surface what just landed."
            }

            if card.isFutureReleases {
                return "Upcoming \(selectedContentDescriptor) worth tracking before release."
            }

            return "Mood-led \(selectedContentDescriptor) you can tighten with filters or a direct search."
        }

        if let genre = viewModel.selectedGenre {
            return "Popular \(selectedContentDescriptor) in \(genre.name), ready for deeper filtering."
        }

        if !viewModel.submittedQuery.isEmpty {
            return "Refine the query or switch type without losing the current poster wall."
        }

        return "Browse rails and direct search stay in the same place so you can pivot quickly."
    }

    private var shouldShowResultsFilterSummary: Bool {
        viewModel.sortOption != .popularityDesc
            || viewModel.selectedGenre != nil
            || (viewModel.languageFilters != ["en-US"] && !viewModel.languageFilters.isEmpty)
            || viewModel.yearFilter != nil
            || viewModel.yearRangePreset != nil
    }

    private var activeFilterSummary: some View {
        FlowLayout(spacing: 8) {
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

            if let preset = viewModel.yearRangePreset {
                GlassTag(text: preset.displayName, symbol: "calendar")
            } else if let year = viewModel.yearFilter {
                GlassTag(text: String(year), symbol: "calendar")
            }
        }
    }

    private var resultsHeaderSection: some View {
        centeredStage {
            VStack(alignment: .leading, spacing: shouldShowResultsFilterSummary ? 14 : 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(resultsContextTitle)
                            .font(.title3.weight(.semibold))
                        Text(resultsContextSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 20)

                    GlassIconButton(icon: "line.3.horizontal.decrease", size: 36) {
                        isShowingFilters = true
                    }
                }

                if shouldShowResultsFilterSummary {
                    activeFilterSummary
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
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

    private func resultsSection(showRefreshIndicator: Bool) -> some View {
        VStack(spacing: 0) {
            resultsHeaderSection

            if showRefreshIndicator {
                centeredStage {
                    InlineLoadingStatusView(title: SearchLoadingPresentationPolicy.refreshTitle)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    centeredStage {
                        VStack(alignment: .leading, spacing: 24) {
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
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                }
                .id("results-scroll-\(viewModel.selectedType?.rawValue ?? "all")")
                .task {
                    await ensureUserRatingsLoaded()
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
                    .padding(.trailing, 24)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Helpers

    private func hydrateRecentSearchesIfNeeded() {
        guard !hasHydratedRecentSearches else { return }
        hasHydratedRecentSearches = true
        viewModel.loadRecentSearches(from: appState.settingsManager)
    }

    @MainActor
    private func ensureUserRatingsLoaded() async {
        guard !hasLoadedUserRatings else { return }
        await loadUserRatings(force: false)
    }

    @MainActor
    private func loadUserRatings(force: Bool) async {
        guard force || !hasLoadedUserRatings else { return }

        let events = (try? await appState.database.fetchTasteEvents(eventType: .rated, limit: 500)) ?? []
        var dict: [String: TasteEvent] = [:]
        for event in events {
            if let mediaId = event.mediaId {
                dict[mediaId] = event
            }
        }
        userRatings = dict
        hasLoadedUserRatings = true
    }

    @MainActor
    private func submitSearch(queryText: String? = nil) {
        let trimmed = (queryText ?? searchDraft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if searchDraft != trimmed {
            suppressNextSearchDraftDebounce = true
            searchDraft = trimmed
        }

        viewModel.search(queryText: trimmed)
        viewModel.addRecentSearch(trimmed)
        viewModel.saveRecentSearches(to: appState.settingsManager)
    }

    private func applySearchQARuntimeIfNeeded() {
        guard !hasAppliedSearchQARuntime else { return }
        guard let qaQuery = QARuntimeOptions.searchQuery?
            .trimmingCharacters(in: .whitespacesAndNewlines), !qaQuery.isEmpty else {
            return
        }

        hasAppliedSearchQARuntime = true
        suppressNextSearchDraftDebounce = true
        searchDraft = qaQuery

        if QARuntimeOptions.autoSubmitSearchQuery {
            submitSearch(queryText: qaQuery)
        }
    }

    @MainActor
    private func applySearchResultQARuntimeIfNeeded() {
        guard QARuntimeOptions.autoOpenFirstSearchResult else { return }
        guard !hasAutoOpenedQAResult else { return }
        guard selectedItem == nil else { return }
        guard !viewModel.results.isEmpty else { return }

        let preferredTitle = QARuntimeOptions.preferredResultTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let selectedResult =
            viewModel.results.first { result in
                guard let preferredTitle else { return false }
                return result.title.lowercased().contains(preferredTitle)
            }
            ?? viewModel.results.first

        guard let selectedResult else { return }
        hasAutoOpenedQAResult = true
        selectedItem = selectedResult
    }

    @MainActor
    private func reloadTMDBConfigurationAndSearch() async {
        let key = (try? await appState.settingsManager.getString(key: SettingsKeys.tmdbApiKey)) ?? ""
        let shouldRequery =
            !viewModel.submittedQuery.isEmpty ||
            viewModel.selectedGenre != nil ||
            viewModel.activeMoodCard != nil

        viewModel.configure(apiKey: key)

        // Genres are still loaded lazily when the filter summary appears.
        if shouldRequery {
            viewModel.requery()
        }
    }
}

private struct SearchQueryBar: View {
    @Bindable var viewModel: SearchViewModel
    let seedQuery: String
    @Binding var suppressNextDraftDebounce: Bool
    let placeholder: String
    let onSubmit: (String) -> Void
    let onClear: () -> Void

    @State private var localDraft: String
    @FocusState private var isSearchFieldFocused: Bool

    init(
        viewModel: SearchViewModel,
        seedQuery: String,
        suppressNextDraftDebounce: Binding<Bool>,
        placeholder: String = "Search titles, cast, or keywords",
        onSubmit: @escaping (String) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.seedQuery = seedQuery
        self._suppressNextDraftDebounce = suppressNextDraftDebounce
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.onClear = onClear
        self._localDraft = State(initialValue: seedQuery)
    }

    private var showsClearButton: Bool {
        !localDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.submittedQuery.isEmpty
    }

    private var trimmedDraft: String {
        localDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedDraft.isEmpty
    }

    private var leadingIndicator: some View {
        Group {
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .frame(width: 12, height: 12)
        .transition(.scale.combined(with: .opacity))
    }

    private var draftField: some View {
        TextField(placeholder, text: $localDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.90))
            .submitLabel(.search)
            .disableAutomaticTextEntryAdjustments()
            .focused($isSearchFieldFocused)
            .onChange(of: seedQuery) { _, newValue in
                guard newValue != localDraft else { return }
                localDraft = newValue
            }
            .onChange(of: localDraft) { _, newValue in
                if viewModel.queryDraft != newValue {
                    viewModel.queryDraft = newValue
                }

                if suppressNextDraftDebounce {
                    suppressNextDraftDebounce = false
                    return
                }

                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                viewModel.debouncedSearch(queryText: newValue)
            }
            .onSubmit {
                guard canSubmit else { return }
                isSearchFieldFocused = false
                onSubmit(localDraft)
            }
    }

    private var clearButton: some View {
        Button {
            localDraft = ""
            onClear()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .buttonStyle(.plain)
        .frame(width: 14, height: 14)
        .transition(.scale.combined(with: .opacity))
    }

    var body: some View {
        HStack(spacing: 8) {
            leadingIndicator
            draftField

            if showsClearButton {
                clearButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSearching)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.095))
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.05),
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.09), lineWidth: 0.75)
                }
        }
        .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        .contentShape(Capsule())
        .onTapGesture {
            isSearchFieldFocused = true
        }
        .animation(.easeInOut(duration: 0.18), value: showsClearButton)
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
    var tint: Color = Color(red: 0.78, green: 0.79, blue: 0.82)

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
        .padding(.vertical, 8)
        .background(chipBackground, in: Capsule())
        .foregroundStyle(isActive ? .white.opacity(0.96) : .primary)
        .shadow(color: isActive ? tint.opacity(0.18) : .clear, radius: 14, y: 6)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }

    private var chipBackground: AnyShapeStyle {
        if isActive {
            AnyShapeStyle(tint.opacity(0.24))
        } else {
            AnyShapeStyle(Color.white.opacity(0.07))
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
        Option(code: "as-IN", name: "Assamese"),
        Option(code: "bn-IN", name: "Bengali (India)"),
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
