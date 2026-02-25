import SwiftUI

struct DiscoverView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: DiscoverViewModel
    @State private var selectedItem: MediaPreview?
    @State private var currentHeroIndex = 0
    @State private var tmdbReloadTask: Task<Void, Never>?
    @State private var userRatings: [String: TasteEvent] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if viewModel.isLoading {
                    DiscoverSkeletonView()
                        .transition(.opacity)
                } else {
                    // Cinematic hero carousel
                    if !viewModel.featuredBackdrops.isEmpty {
                        TabView(selection: $currentHeroIndex) {
                            ForEach(Array(viewModel.featuredBackdrops.enumerated()), id: \.element.id) { index, featured in
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

                    if !viewModel.continueWatching.isEmpty {
                        MediaRow(
                            title: "Continue Watching",
                            symbol: "play.circle",
                            items: viewModel.continueWatching.map(\.preview),
                            userRatings: userRatings,
                            animationDelay: 0.02
                        ) { item in
                            selectedItem = item
                        }
                    }

                    aiCuratedSection

                    MediaRow(
                        title: "Trending Now",
                        symbol: "flame",
                        items: viewModel.trendingMovies,
                        userRatings: userRatings,
                        animationDelay: 0.05
                    ) { item in
                        selectedItem = item
                    }
                    MediaRow(
                        title: "Trending TV Shows",
                        symbol: "tv",
                        items: viewModel.trendingShows,
                        userRatings: userRatings,
                        animationDelay: 0.12
                    ) { item in
                        selectedItem = item
                    }
                    MediaRow(
                        title: "Popular",
                        symbol: "star",
                        items: viewModel.popularMovies,
                        userRatings: userRatings,
                        animationDelay: 0.19
                    ) { item in
                        selectedItem = item
                    }
                    MediaRow(
                        title: "Top Rated",
                        symbol: "trophy",
                        items: viewModel.topRatedMovies,
                        userRatings: userRatings,
                        animationDelay: 0.26
                    ) { item in
                        selectedItem = item
                    }
                    MediaRow(
                        title: "Now Playing",
                        symbol: "film",
                        items: viewModel.nowPlayingMovies,
                        userRatings: userRatings,
                        animationDelay: 0.33
                    ) { item in
                        selectedItem = item
                    }
                }
            }
            .animation(.easeInOut(duration: 0.45), value: viewModel.isLoading)
            .padding(.horizontal, 4)
            .padding(.bottom, 24)
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(item: $selectedItem) { item in
            DetailView(preview: item)
        }
        .appErrorAlert(
            "Discover Error",
            error: Binding(
                get: { viewModel.error },
                set: { viewModel.error = $0 }
            ),
            onRetry: {
                Task { await viewModel.refresh() }
            }
        )
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
                guard !viewModel.featuredBackdrops.isEmpty else { continue }
                withAnimation(.easeInOut(duration: 0.8)) {
                    currentHeroIndex = (currentHeroIndex + 1) % viewModel.featuredBackdrops.count
                }
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
            Task {
                await loadUserRatings()
                let ratedTitles = Set(userRatings.values.compactMap { $0.metadata["title"]?.lowercased() })
                let ratedMediaIds = Set(userRatings.values.compactMap(\.mediaId))
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.aiRecommendations.removeAll { rec in
                        let titleLower = rec.title.lowercased()
                        if ratedTitles.contains(titleLower) { return true }
                        if let tmdbId = rec.tmdbId {
                            let mediaId = "\(rec.type.rawValue)-tmdb-\(tmdbId)"
                            if ratedMediaIds.contains(mediaId) { return true }
                        }
                        return false
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in
            Task {
                await removeLibraryItemsFromAIRecommendations()
            }
        }
    }

    // MARK: - AI Curated Section

    @ViewBuilder
    private var aiCuratedSection: some View {
        if viewModel.aiRecommendationsEnabled {
            VStack(alignment: .leading, spacing: 16) {
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
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Regenerate")
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
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }
                .padding(.horizontal, 8)

                if viewModel.isLoadingAIRecommendations {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0 ..< 5, id: \.self) { _ in
                                SkeletonBlock(width: 210, height: 120, cornerRadius: 14)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                } else if !viewModel.aiRecommendations.isEmpty {
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
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
    private func removeLibraryItemsFromAIRecommendations() async {
        let watchlist = (try? await appState.database.fetchLibraryEntries(listType: .watchlist)) ?? []
        let favorites = (try? await appState.database.fetchLibraryEntries(listType: .favorites)) ?? []
        let libraryMediaIds = Set((watchlist + favorites).map(\.mediaId))

        // Resolve titles for title-based matching
        var libraryTitles = Set<String>()
        for entry in watchlist + favorites {
            if let cached = try? await appState.database.fetchMediaItem(id: entry.mediaId) {
                libraryTitles.insert(cached.title.lowercased())
            }
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            viewModel.aiRecommendations.removeAll { rec in
                let titleLower = rec.title.lowercased()
                if libraryTitles.contains(titleLower) { return true }
                if let tmdbId = rec.tmdbId {
                    let mediaId = "\(rec.type.rawValue)-tmdb-\(tmdbId)"
                    if libraryMediaIds.contains(mediaId) { return true }
                }
                return false
            }
        }
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

// MARK: - FeaturedHeroView

struct FeaturedHeroView: View {
    let item: MediaPreview
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image — edge-to-edge
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
