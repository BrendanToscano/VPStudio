import SwiftUI

struct DiscoverMediaRowSpec: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let items: [MediaPreview]
    let animationDelay: Double
}

enum DiscoverHeroPresentationPolicy {
    static func heroItems(
        featuredBackdrops: [MediaPreview],
        trendingMovies: [MediaPreview],
        trendingShows: [MediaPreview],
        popularMovies: [MediaPreview],
        topRatedMovies: [MediaPreview],
        nowPlayingMovies: [MediaPreview],
        continueWatching: [MediaPreview]
    ) -> [MediaPreview] {
        if !featuredBackdrops.isEmpty {
            return Array(featuredBackdrops.prefix(5))
        }

        let fallbackSources = [
            trendingMovies,
            trendingShows,
            popularMovies,
            topRatedMovies,
            nowPlayingMovies,
            continueWatching,
        ]

        return fallbackSources.first(where: { !$0.isEmpty }).map { Array($0.prefix(5)) } ?? []
    }
}

enum DiscoverHierarchyPolicy {
    static let continueWatchingDelay = 0.02
    static let firstCatalogDelay = 0.05
    static let catalogDelayStep = 0.07

    static func shouldShowContinueWatching(count: Int) -> Bool {
        count > 0
    }

    static func animationDelay(forVisibleCatalogIndex index: Int) -> Double {
        firstCatalogDelay + (Double(index) * catalogDelayStep)
    }

    static func visibleCatalogRows(
        trendingMovies: [MediaPreview],
        trendingShows: [MediaPreview],
        popularMovies: [MediaPreview],
        topRatedMovies: [MediaPreview],
        nowPlayingMovies: [MediaPreview]
    ) -> [DiscoverMediaRowSpec] {
        let candidates: [(id: String, title: String, symbol: String, items: [MediaPreview])] = [
            ("trending-movies", "Trending Now", "flame", trendingMovies),
            ("trending-shows", "Trending TV Shows", "tv", trendingShows),
            ("popular-movies", "Popular", "star", popularMovies),
            ("top-rated-movies", "Top Rated", "trophy", topRatedMovies),
            ("now-playing-movies", "Now Playing", "film", nowPlayingMovies),
        ]

        return candidates
            .filter { !$0.items.isEmpty }
            .enumerated()
            .map { index, row in
                DiscoverMediaRowSpec(
                    id: row.id,
                    title: row.title,
                    symbol: row.symbol,
                    items: row.items,
                    animationDelay: animationDelay(forVisibleCatalogIndex: index)
                )
            }
    }
}

struct DiscoverAICuratedSectionState: Equatable {
    let isLoading: Bool
    let isRegenerateEnabled: Bool
    let primaryRecommendation: AIMovieRecommendation?
    let primaryPreview: MediaPreview?
    let supportingRecommendations: [AIMovieRecommendation]
    let showsEmptyState: Bool
}

enum DiscoverAICuratedSectionPolicy {
    static let helperCopy = "Picked from your watchlist, favorites, ratings, and recent activity."
    static let maxSupportingRecommendations = 3

    static func makeState(
        enabled: Bool,
        isLoading: Bool,
        heroPreview: MediaPreview?,
        recommendations: [AIMovieRecommendation]
    ) -> DiscoverAICuratedSectionState? {
        guard enabled else { return nil }

        if isLoading {
            return DiscoverAICuratedSectionState(
                isLoading: true,
                isRegenerateEnabled: false,
                primaryRecommendation: nil,
                primaryPreview: nil,
                supportingRecommendations: [],
                showsEmptyState: false
            )
        }

        return DiscoverAICuratedSectionState(
            isLoading: false,
            isRegenerateEnabled: true,
            primaryRecommendation: recommendations.first,
            primaryPreview: heroPreview,
            supportingRecommendations: Array(recommendations.dropFirst().prefix(maxSupportingRecommendations)),
            showsEmptyState: recommendations.isEmpty
        )
    }
}

enum DiscoverLoadingPresentationMode: Equatable {
    case blockingSkeleton
    case refreshingRetainedContent
    case content
}

enum DiscoverLoadingPresentationPolicy {
    static let refreshTitle = "Refreshing Discover"

    static func presentationMode(
        isLoading: Bool,
        featuredBackdropCount: Int,
        continueWatchingCount: Int,
        catalogRowCount: Int,
        aiRecommendationCount: Int
    ) -> DiscoverLoadingPresentationMode {
        guard isLoading else { return .content }

        let hasRenderableContent = featuredBackdropCount > 0
            || continueWatchingCount > 0
            || catalogRowCount > 0
            || aiRecommendationCount > 0

        return hasRenderableContent ? .refreshingRetainedContent : .blockingSkeleton
    }
}

struct DiscoverView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: DiscoverViewModel
    @State private var selectedItem: MediaPreview?
    @State private var currentHeroIndex = 0
    @State private var tmdbReloadTask: Task<Void, Never>?
    @State private var userRatingsReloadTask: Task<Void, Never>?
    @State private var recommendationsFilterTask: Task<Void, Never>?
    @State private var userRatings: [String: TasteEvent] = [:]

    private var catalogRows: [DiscoverMediaRowSpec] {
        DiscoverHierarchyPolicy.visibleCatalogRows(
            trendingMovies: viewModel.trendingMovies,
            trendingShows: viewModel.trendingShows,
            popularMovies: viewModel.popularMovies,
            topRatedMovies: viewModel.topRatedMovies,
            nowPlayingMovies: viewModel.nowPlayingMovies
        )
    }

    private var aiCuratedSectionState: DiscoverAICuratedSectionState? {
        DiscoverAICuratedSectionPolicy.makeState(
            enabled: viewModel.aiRecommendationsEnabled,
            isLoading: viewModel.isLoadingAIRecommendations,
            heroPreview: viewModel.aiHeroPreview,
            recommendations: viewModel.aiRecommendations
        )
    }

    private var heroItems: [MediaPreview] {
        DiscoverHeroPresentationPolicy.heroItems(
            featuredBackdrops: viewModel.featuredBackdrops,
            trendingMovies: viewModel.trendingMovies,
            trendingShows: viewModel.trendingShows,
            popularMovies: viewModel.popularMovies,
            topRatedMovies: viewModel.topRatedMovies,
            nowPlayingMovies: viewModel.nowPlayingMovies,
            continueWatching: viewModel.continueWatching.map(\.preview)
        )
    }

    private var discoverLoadingPresentation: DiscoverLoadingPresentationMode {
        DiscoverLoadingPresentationPolicy.presentationMode(
            isLoading: viewModel.isLoading,
            featuredBackdropCount: viewModel.featuredBackdrops.count,
            continueWatchingCount: viewModel.continueWatching.count,
            catalogRowCount: catalogRows.count,
            aiRecommendationCount: viewModel.aiRecommendations.count
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if let error = viewModel.error {
                    discoverStatePanel(error: error)
                }

                if discoverLoadingPresentation == .blockingSkeleton {
                    DiscoverSkeletonView()
                        .transition(.opacity)
                } else {
                    if discoverLoadingPresentation == .refreshingRetainedContent {
                        InlineLoadingStatusView(title: DiscoverLoadingPresentationPolicy.refreshTitle)
                            .padding(.horizontal, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Cinematic hero carousel
                    if !heroItems.isEmpty {
                        TabView(selection: $currentHeroIndex) {
                            ForEach(Array(heroItems.enumerated()), id: \.element.id) { index, featured in
                                FeaturedHeroView(item: featured) {
                                    selectedItem = featured
                                }
                                .tag(index)
                            }
                        }
                        #if !os(macOS)
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        #endif
                        .frame(height: 440)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if DiscoverHierarchyPolicy.shouldShowContinueWatching(count: viewModel.continueWatching.count) {
                        MediaRow(
                            title: "Continue Watching",
                            symbol: "play.circle",
                            items: viewModel.continueWatching.map(\.preview),
                            userRatings: userRatings,
                            animationDelay: DiscoverHierarchyPolicy.continueWatchingDelay
                        ) { item in
                            selectedItem = item
                        }
                    }

                    aiCuratedSection

                    ForEach(catalogRows) { row in
                        MediaRow(
                            title: row.title,
                            symbol: row.symbol,
                            items: row.items,
                            userRatings: userRatings,
                            animationDelay: row.animationDelay
                        ) { item in
                            selectedItem = item
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.25), value: discoverLoadingPresentation)
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
        .background {
            VPMenuBackground()
                .ignoresSafeArea()
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(item: $selectedItem) { item in
            DetailView(preview: item)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            guard !viewModel.hasPerformedInitialLoad else { return }
            viewModel.hasPerformedInitialLoad = true
            await reloadDiscoverForLatestTMDBKey()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { break }
                guard !heroItems.isEmpty else { continue }
                withAnimation(.easeInOut(duration: 0.8)) {
                    currentHeroIndex = (currentHeroIndex + 1) % heroItems.count
                }
            }
        }
        .onChange(of: heroItems.map(\.id)) { _, newIDs in
            if currentHeroIndex >= newIDs.count {
                currentHeroIndex = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tmdbApiKeyDidChange)) { _ in
            tmdbReloadTask?.cancel()
            tmdbReloadTask = Task { await reloadDiscoverForLatestTMDBKey() }
        }
        .task {
            await loadUserRatings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tasteProfileDidChange)) { _ in
            userRatingsReloadTask?.cancel()
            userRatingsReloadTask = Task {
                await loadUserRatings()
                await viewModel.refreshLocalPersonalizationState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in
            recommendationsFilterTask?.cancel()
            recommendationsFilterTask = Task {
                await viewModel.refreshLocalPersonalizationState()
            }
        }
        .onDisappear {
            tmdbReloadTask?.cancel()
            userRatingsReloadTask?.cancel()
            recommendationsFilterTask?.cancel()
        }
    }

    @ViewBuilder
    private func discoverStatePanel(error: AppError) -> some View {
        let setupError = error.requiresTMDBSetupAction
        let artworkName = setupError ? "genre-art-new" : "genre-art-deep"
        let accent: Color = setupError ? .yellow : .orange

        CinematicStateCard(
            accent: accent,
            artworkName: artworkName,
            minHeight: 228
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: setupError ? "sparkles.rectangle.stack.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(accent.opacity(0.26), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        GlassTag(
                            text: setupError ? "Setup needed" : "Discover needs attention",
                            tintColor: accent.opacity(0.22),
                            symbol: setupError ? "sparkles" : "arrow.clockwise"
                        )
                        Text(setupError ? "Finish setup to unlock Discover" : (error.errorDescription ?? "Discover hit a snag"))
                            .font(.title3.weight(.semibold))
                        Text(discoverInlineMessage(for: error, setupError: setupError))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Button {
                        viewModel.error = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                FlowLayout(spacing: 10) {
                    if setupError {
                        SpatialButton(title: "Open Settings", icon: "gearshape.fill", tint: .yellow) {
                            appState.selectedTab = .settings
                            viewModel.error = nil
                        }
                    }

                    Button {
                        Task { await viewModel.refresh() }
                        viewModel.error = nil
                    } label: {
                        GlassTag(text: setupError ? "Retry Later" : "Retry", tintColor: .white.opacity(0.18), symbol: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.selectedTab = .library
                        viewModel.error = nil
                    } label: {
                        GlassTag(text: "Go to Library", tintColor: .white.opacity(0.18), symbol: "books.vertical")
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.selectedTab = .downloads
                        viewModel.error = nil
                    } label: {
                        GlassTag(text: "Open Downloads", tintColor: .white.opacity(0.18), symbol: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func discoverInlineMessage(for error: AppError, setupError: Bool) -> String {
        if setupError {
            return "Add your TMDB key in Settings, then come back here for live trending rows and hero art. Library and Downloads keep working in the meantime."
        }

        if let suggestion = error.recoverySuggestion, !suggestion.isEmpty {
            return suggestion
        }

        return error.errorDescription ?? "Something went wrong."
    }

    // MARK: - AI Curated Section

    @ViewBuilder
    private var aiCuratedSection: some View {
        if let state = aiCuratedSectionState {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.purple)
                        Text("Curated For You")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            Task {
                                await viewModel.regenerateAIRecommendations(
                                    aiManager: appState.aiAssistantManager,
                                    settingsManager: appState.settingsManager
                                )
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if state.isLoading {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.trianglehead.2.clockwise")
                                        .font(.system(size: 12, weight: .semibold))
                                }

                                Text(state.isLoading ? "Refreshing…" : "Regenerate")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
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
                        .disabled(!state.isRegenerateEnabled)
                        .opacity(state.isRegenerateEnabled ? 1 : 0.7)
                        #if os(visionOS)
                        .hoverEffect(.highlight)
                        #endif
                    }

                    Text(DiscoverAICuratedSectionPolicy.helperCopy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)

                if state.isLoading {
                    aiCuratedLoadingView
                } else if state.showsEmptyState {
                    aiCuratedEmptyState
                } else if let primaryRecommendation = state.primaryRecommendation {
                    let primaryPreview = state.primaryPreview ?? primaryRecommendation.toMediaPreview()

                    VStack(alignment: .leading, spacing: 14) {
                        AICuratedHeroCard(
                            preview: primaryPreview,
                            recommendation: primaryRecommendation
                        ) {
                            selectedItem = primaryPreview
                        }

                        if !state.supportingRecommendations.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(state.supportingRecommendations) { recommendation in
                                    AICuratedSupportingRow(recommendation: recommendation) {
                                        selectedItem = recommendation.toMediaPreview()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var aiCuratedLoadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(width: 560, height: 236, cornerRadius: 22)

            ForEach(0 ..< 3, id: \.self) { _ in
                SkeletonBlock(width: 420, height: 62, cornerRadius: 16)
            }
        }
        .padding(.horizontal, 8)
    }

    private var aiCuratedEmptyState: some View {
        ContentUnavailableView(
            "No AI picks yet",
            systemImage: "sparkles.tv",
            description: Text("Rate a few titles or add more to your library, then regenerate for fresh recommendations.")
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .glassStroke(cornerRadius: 20)
        .glassShadow()
    }

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
    private func reloadDiscoverForLatestTMDBKey() async {
        let key = (try? await appState.settingsManager.getString(key: SettingsKeys.tmdbApiKey)) ?? ""
        viewModel.configure(database: appState.database)
        currentHeroIndex = 0
        await viewModel.load(apiKey: key)
        await viewModel.loadAIRecommendationsIfNeeded(
            aiManager: appState.aiAssistantManager,
            settingsManager: appState.settingsManager
        )
    }
}

// MARK: - AI Curated Views

struct AICuratedHeroCard: View {
    let preview: MediaPreview
    let recommendation: AIMovieRecommendation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: preview.backdropURL ?? preview.posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.08, blue: 0.22),
                                Color(red: 0.05, green: 0.04, blue: 0.09),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 236)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.2), location: 0.32),
                        .init(color: .black.opacity(0.78), location: 0.68),
                        .init(color: .black.opacity(0.96), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        GlassTag(text: "AI PICK", tintColor: .purple.opacity(0.24), symbol: "sparkles")

                        if let score = recommendation.score {
                            GlassTag(
                                text: String(format: "%.0f%% match", score * 100),
                                tintColor: .purple.opacity(0.18),
                                weight: .bold
                            )
                        }
                    }

                    Text(recommendation.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Text(recommendation.type.displayName.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))

                        if let year = recommendation.year {
                            Circle()
                                .fill(.white.opacity(0.4))
                                .frame(width: 4, height: 4)

                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.74))
                        }

                        if let rating = preview.imdbRating, rating > 0 {
                            Circle()
                                .fill(.white.opacity(0.4))
                                .frame(width: 4, height: 4)

                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                        }
                    }

                    Text(recommendation.reason)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(3)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.caption.weight(.semibold))
                        Text("Open details")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.82))
                }
                .padding(22)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 236)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }
}

struct AICuratedSupportingRow: View {
    let recommendation: AIMovieRecommendation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(recommendation.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let score = recommendation.score {
                            GlassTag(
                                text: String(format: "%.0f%%", score * 100),
                                tintColor: .purple.opacity(0.18),
                                weight: .bold
                            )
                        }
                    }

                    HStack(spacing: 8) {
                        Text(recommendation.type.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let year = recommendation.year {
                            Text("• \(year)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(recommendation.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .glassStroke(cornerRadius: 18)
            .glassShadow()
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }
}

// MARK: - FeaturedHeroView

struct FeaturedHeroView: View {
    let item: MediaPreview
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image — edge-to-edge.
            // Using .id(item.id) on the content prevents SwiftUI from destroying and
            // re-fetching the image every time TabView auto-advances to the next hero card.
            AsyncImage(url: backdropURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .scaleEffect(isHovered ? 1.03 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                default:
                    Rectangle().fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.06, blue: 0.14),
                                Color(red: 0.04, green: 0.03, blue: 0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .id(item.id)
            .frame(height: 440)
            .clipped()

            // Cinematic gradient fade to dark at bottom
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.25), location: 0.35),
                    .init(color: .black.opacity(0.7), location: 0.65),
                    .init(color: .black.opacity(0.95), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content overlay
            VStack(alignment: .leading, spacing: 14) {
                // Title with red/white gradient fill — large, bold, italic
                Text(item.title.uppercased())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .italic()
                    .foregroundStyle(.linearGradient(
                        colors: [.white, .vpRed, .vpRedLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .shadow(color: .vpRed.opacity(0.4), radius: 16, y: 4)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)

                // Metadata row
                HStack(spacing: 12) {
                    Text(item.type.displayName.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white.opacity(0.8))

                    Circle()
                        .fill(.white.opacity(0.4))
                        .frame(width: 4, height: 4)

                    if let year = item.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if let rating = item.imdbRating, rating > 0 {
                        Circle()
                            .fill(.white.opacity(0.4))
                            .frame(width: 4, height: 4)

                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    // HDR badge
                    GlassTag(text: "HDR", symbol: "sparkles", weight: .bold)
                }

                // Action buttons
                HStack(spacing: 12) {
                    // Primary play button — red pill
                    Button(action: onTap) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14))
                            Text("Play Now")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(.linearGradient(
                                colors: [.vpRed, .vpRedLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        )
                        .shadow(color: .vpRed.opacity(0.5), radius: 16, y: 4)
                    }
                    .buttonStyle(.plain)
                    #if os(visionOS)
                    .hoverEffect(.lift)
                    #endif

                    // Secondary: More info
                    Button(action: onTap) {
                        Image(systemName: "info")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle().strokeBorder(
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
                .padding(.top, 6)
            }
            .padding(32)
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isHovered ? 0.25 : 0.08),
                            .white.opacity(isHovered ? 0.06 : 0.01),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(isHovered ? 0.35 : 0.13), radius: isHovered ? 18 : 8, x: 0, y: isHovered ? 10 : 4)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    private var backdropURL: URL? {
        // Prefer landscape backdrop for cinematic hero; fall back to poster if unavailable
        guard let path = item.backdropPath ?? item.posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w1280\(path)")
    }
}

// MARK: - MediaRow

struct MediaRow: View {
    let title: String
    var symbol: String = ""
    let items: [MediaPreview]
    var userRatings: [String: TasteEvent] = [:]
    var animationDelay: Double = 0
    let onSelect: (MediaPreview) -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(spacing: 8) {
                if !symbol.isEmpty {
                    Image(systemName: symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            MediaCardView(item: item, userRating: userRatings[item.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(animationDelay)) {
                appeared = true
            }
        }
    }
}
