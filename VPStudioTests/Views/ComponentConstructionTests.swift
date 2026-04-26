import SwiftUI
import Testing
@testable import VPStudio

#if os(macOS)
import AppKit
#endif

@Suite("Component Construction")
@MainActor
struct ComponentConstructionTests {
    private func makeDetailViewModel() -> DetailViewModel {
        DetailViewModel(appState: AppState(testHooks: .init()))
    }

    private func makeMediaItem(type: MediaType = .movie) -> MediaItem {
        MediaItem(
            id: "detail-fixture-\(type.rawValue)",
            type: type,
            title: type == .movie ? "Dune" : "The Expanse",
            year: 2021,
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            overview: "A compact overview for construction tests.",
            genres: ["Science Fiction", "Drama", "Adventure"],
            imdbRating: 8.2,
            runtime: 155,
            status: "Released",
            tmdbId: 438631
        )
    }

    private func makeMediaPreview(
        id: String = "preview-fixture",
        type: MediaType = .movie,
        title: String = "Dune",
        year: Int? = 2021
    ) -> MediaPreview {
        MediaPreview(
            id: id,
            type: type,
            title: title,
            year: year,
            posterPath: nil,
            backdropPath: nil,
            imdbRating: 8.2,
            tmdbId: 438631
        )
    }

    @Test
    func glassPillPickerBuildsBodyForSelectedOption() {
        let picker = GlassPillPicker(
            options: ["Watchlist", "Favorites"],
            selection: .constant("Watchlist")
        )

        _ = picker.body
        #expect(PillPickerAnimationPolicy.springResponse == 0.35)
        #expect(PillPickerAnimationPolicy.springDamping == 0.82)
        #expect(PillPickerAnimationPolicy.pillHeight == 36)
        #expect(PillPickerAnimationPolicy.horizontalPadding == 16)
    }

    #if os(macOS)
    @Test
    func glassPillPickerHostsSelectedAndUnselectedOptions() {
        var selection = "Watchlist"
        let picker = GlassPillPicker(
            options: ["Watchlist", "Favorites", "Downloads"],
            selection: Binding(get: { selection }, set: { selection = $0 })
        )

        let host = NSHostingView(rootView: picker.frame(width: 420, height: 64))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 64),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(selection == "Watchlist")
        #expect(host.fittingSize.width > 0)
    }

    @Test
    func asyncStateSurfacesHostWithReducedMotion() {
        let view = VStack {
            LoadingOverlay(title: "Loading", message: "Preparing")
            LoadingOverlay(title: "Loading", message: nil)
            InlineLoadingStatusView(title: "Refreshing")
            SkeletonBlock(width: 120, height: 24, cornerRadius: 8)
            DiscoverSkeletonView()
            DetailSkeletonView()
            LibrarySkeletonView()
            SettingsSkeletonView()
            ExploreSkeletonView()
            PaginationLoadingView()
        }

        let host = NSHostingView(rootView: view.frame(width: 640, height: 900))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(host.fittingSize.width > 0)
    }

    @Test
    func searchAndFilterSurfacesHostNestedRows() {
        var selectedTerm: String?
        var removedTerm: String?
        var cleared = false
        var sortOption = DiscoverFilters.SortOption.popularityDesc
        var selectedYear: Int? = nil
        var selectedLanguages: Set<String> = ["en-US", "fr-FR"]
        var selectedGenre: Genre? = nil
        var applied = false

        let view = VStack {
            RecentSearchesSection(
                searches: ["Dune", "Andor", "Foundation"],
                onSelect: { selectedTerm = $0 },
                onRemove: { removedTerm = $0 },
                onClear: { cleared = true }
            )
            ExploreFilterSheet(
                sortOption: Binding(get: { sortOption }, set: { sortOption = $0 }),
                selectedYear: Binding(get: { selectedYear }, set: { selectedYear = $0 }),
                selectedLanguages: Binding(get: { selectedLanguages }, set: { selectedLanguages = $0 }),
                genres: [
                    Genre(id: 12, name: "Adventure"),
                    Genre(id: 878, name: "Science Fiction"),
                ],
                selectedGenre: Binding(get: { selectedGenre }, set: { selectedGenre = $0 }),
                displayedSortOptions: [.popularityDesc, .ratingDesc, .releaseDateDesc, .titleAsc],
                onApply: { applied = true }
            )
        }

        let host = NSHostingView(rootView: view.frame(width: 640, height: 900))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(host.fittingSize.width > 0)
        #expect(selectedTerm == nil)
        #expect(removedTerm == nil)
        #expect(cleared == false)
        #expect(applied == false)
    }
    #endif

    #if os(macOS)
    @Test
    func primaryWindowSurfacesHostWithoutLaunchingNetworkPlayback() {
        let appState = AppState(testHooks: .init())
        let movie = makeMediaPreview(id: "discover-movie", title: "Arrival", year: 2016)
        let show = makeMediaPreview(id: "discover-show", type: .series, title: "Severance", year: 2022)
        let discoverViewModel = DiscoverViewModel()
        discoverViewModel.hasPerformedInitialLoad = true
        discoverViewModel.isLoading = false
        discoverViewModel.featuredBackdrops = [movie]
        discoverViewModel.trendingMovies = [movie]
        discoverViewModel.trendingShows = [show]
        discoverViewModel.popularMovies = [movie]
        discoverViewModel.topRatedMovies = [movie]
        discoverViewModel.nowPlayingMovies = [movie]
        discoverViewModel.aiRecommendationsEnabled = true
        discoverViewModel.aiRecommendations = [
            AIMovieRecommendation(
                title: "Arrival",
                year: 2016,
                type: .movie,
                reason: "Measured science fiction with emotional stakes.",
                tmdbId: 329865,
                score: 0.95
            ),
            AIMovieRecommendation(
                title: "Severance",
                year: 2022,
                type: .series,
                reason: "Stylish mystery with clean production design.",
                tmdbId: 95396,
                score: 0.9
            ),
        ]

        let surfaces: [AnyView] = [
            AnyView(ContentView().environment(appState)),
            AnyView(NavigationStack { SettingsView() }.environment(appState)),
            AnyView(NavigationStack { SetupWizardView() }.environment(appState)),
            AnyView(NavigationStack { SearchView() }.environment(appState)),
            AnyView(NavigationStack { LibraryView() }.environment(appState)),
            AnyView(NavigationStack { DownloadsView() }.environment(appState)),
            AnyView(NavigationStack { DiscoverView(viewModel: discoverViewModel) }.environment(appState)),
        ]

        for (index, surface) in surfaces.enumerated() {
            let host = NSHostingView(rootView: surface.frame(width: 980, height: 820))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))

            #expect(host.fittingSize.width > 0, "Hosted primary surface \(index) should lay out")
        }
    }

    @Test
    func playerViewBodyBuildsInitialPreparingSurfaceWithoutHostingPlayback() {
        let stream = Fixtures.stream(
            url: "https://cdn.example.com/movie.mp4",
            quality: .hd1080p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "Movie.2026.1080p.mp4"
        )
        let alternate = Fixtures.stream(
            url: "https://cdn.example.com/movie-720p.mp4",
            quality: .hd720p,
            codec: .h264,
            audio: .aac,
            source: .webDL,
            hdr: .sdr,
            fileName: "Movie.2026.720p.mp4"
        )
        let view = PlayerView(
            stream: stream,
            availableStreams: [alternate, stream],
            mediaTitle: "Movie",
            mediaId: "movie-2026",
            episodeId: nil,
            sessionID: UUID()
        )
        .environment(AppState(testHooks: .init()))
        .environment(VPPlayerEngine())

        let host = NSHostingView(rootView: view.frame(width: 980, height: 620))
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.width > 0)
        #expect(PlayerLifecyclePolicy.dismissesCurrentPresentationOnBack)
        #expect(PlayerTransportControlsPolicy.showsRightTransportEnvironmentControl() == false)
    }

    @Test
    func detailViewHostsMovieFallbackSurfaceAfterMetadataFailure() async throws {
        let appState = AppState(testHooks: .init())
        let preview = makeMediaPreview(
            id: "movie-detail-hosted",
            type: .movie,
            title: "Hosted Movie",
            year: 2026
        )
        let view = NavigationStack {
            DetailView(preview: preview)
                .environment(appState)
        }

        let host = NSHostingView(rootView: view.frame(width: 980, height: 920))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 920),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(nanoseconds: 250_000_000)
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.width > 0)
        #expect(DetailAutoSearchPolicy.shouldAutoSearch(
            previewType: preview.type,
            hasMediaItem: false,
            hasSelectedEpisode: false,
            hasExplicitEpisodeContext: false
        ) == false)
    }

    @Test
    func detailViewHostsSeriesResumeFallbackWithoutAutoplayingVoidPlayer() async throws {
        let appState = AppState(testHooks: .init())
        let preview = makeMediaPreview(
            id: "series-detail-hosted",
            type: .series,
            title: "Hosted Series",
            year: 2026
        )
        let view = NavigationStack {
            DetailView(preview: preview, initialAction: .resumePlayback)
                .environment(appState)
        }

        let host = NSHostingView(rootView: view.frame(width: 980, height: 920))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 920),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(nanoseconds: 250_000_000)
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.width > 0)
        #expect(appState.activePlayerSession == nil)
        #expect(DetailAutoSearchPolicy.shouldAutoSearch(
            previewType: preview.type,
            hasMediaItem: true,
            hasSelectedEpisode: false,
            hasExplicitEpisodeContext: false
        ) == false)
    }

    @Test
    func seriesDetailLayoutHostsPopulatedSeriesSurface() {
        let appState = AppState(testHooks: .init())
        let viewModel = makeDetailViewModel()
        let episode = Episode(
            id: "series-fixture-s01e02",
            mediaId: "series-fixture",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "The Second Signal",
            overview: "The crew follows a signal into a sharper mystery.",
            airDate: "2026-04-26",
            stillPath: nil,
            runtime: 44
        )
        viewModel.mediaItem = makeMediaItem(type: .series)
        viewModel.seasons = [
            Season(
                id: 1,
                seasonNumber: 1,
                name: "Season 1",
                overview: "Opening run",
                posterPath: nil,
                episodeCount: 2,
                airDate: "2026-01-01"
            ),
            Season(
                id: 2,
                seasonNumber: 2,
                name: "Season 2",
                overview: nil,
                posterPath: nil,
                episodeCount: 1,
                airDate: nil
            ),
        ]
        viewModel.episodes = [
            Episode(
                id: "series-fixture-s01e01",
                mediaId: "series-fixture",
                seasonNumber: 1,
                episodeNumber: 1,
                title: "Pilot",
                overview: nil,
                airDate: "2026-04-19",
                stillPath: nil,
                runtime: 42
            ),
            episode,
        ]
        viewModel.selectedSeason = 1
        viewModel.selectedEpisode = episode
        viewModel.episodeWatchStates[episode.id] = WatchHistory(
            id: "history-\(episode.id)",
            mediaId: episode.mediaId,
            episodeId: episode.id,
            title: episode.displayTitle,
            progress: 1,
            duration: 2_640,
            watchedAt: Date(),
            isCompleted: true
        )
        viewModel.aiAnalysis = AIPersonalizedAnalysis(
            personalizedDescription: "Matches the user's preference for thoughtful science fiction.",
            predictedRating: 8.5,
            verdict: .yes,
            reasons: ["Strong continuity", "Clean visual style"]
        )
        viewModel.torrents = [
            TorrentResult.fromSearch(
                infoHash: "abcdef1234567890abcdef1234567890abcdef12",
                title: "The.Expanse.S01E02.1080p.WEB-DL",
                sizeBytes: 2_400_000_000,
                seeders: 120,
                leechers: 8,
                indexerName: "Fixture"
            )
        ]
        viewModel.didSearch = true

        var isPlayerOpening = false
        var playerOpeningError: String?
        var playedTorrent: TorrentResult?
        var castCount = 0
        var ratingSheetCount = 0

        let view = NavigationStack {
            SeriesDetailLayout(
                viewModel: viewModel,
                title: "The Expanse",
                tmdbApiKey: "test-key",
                mediaType: .series,
                streamResultsAnchor: "streams",
                shareItem: "The Expanse",
                isPlayerOpening: Binding(get: { isPlayerOpening }, set: { isPlayerOpening = $0 }),
                playerOpeningError: Binding(get: { playerOpeningError }, set: { playerOpeningError = $0 }),
                onPlayTorrent: { playedTorrent = $0 },
                onCast: { castCount += 1 },
                onShowRatingSheet: { ratingSheetCount += 1 }
            )
            .environment(appState)
        }

        let host = NSHostingView(rootView: view.frame(width: 980, height: 1_100))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 1_100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        #expect(host.fittingSize.width > 0)
        #expect(playedTorrent == nil)
        #expect(castCount == 0)
        #expect(ratingSheetCount == 0)
        #expect(SeriesDetailPresentationPolicy.seriesWatchProgressLabel(watchedCount: 1, seasonEpisodeCounts: [2, 1]) == "1/3 watched")
    }

    @Test
    func seriesDetailLayoutHostsMovieSurfaceWithoutEpisodeSelection() {
        let appState = AppState(testHooks: .init())
        let viewModel = makeDetailViewModel()
        let movie = makeMediaItem(type: .movie)
        viewModel.mediaItem = movie
        viewModel.watchHistory = WatchHistory(
            id: "history-\(movie.id)",
            mediaId: movie.id,
            title: movie.title,
            progress: 3_600,
            duration: 7_200,
            quality: "1080p",
            debridService: DebridServiceType.realDebrid.rawValue,
            streamURL: "https://cdn.example.com/dune.mp4",
            watchedAt: Date(),
            isCompleted: false
        )
        viewModel.aiAnalysisError = "AI provider is not configured."
        viewModel.torrents = [
            TorrentResult.fromSearch(
                infoHash: "1234567890abcdef1234567890abcdef12345678",
                title: "Dune.2021.2160p.WEB-DL",
                sizeBytes: 8_000_000_000,
                seeders: 250,
                leechers: 12,
                indexerName: "Fixture"
            )
        ]
        viewModel.didSearch = true

        var isPlayerOpening = false
        var playerOpeningError: String?
        var playedTorrent: TorrentResult?

        let view = NavigationStack {
            SeriesDetailLayout(
                viewModel: viewModel,
                title: movie.title,
                tmdbApiKey: "test-key",
                mediaType: .movie,
                streamResultsAnchor: "streams",
                shareItem: movie.title,
                isPlayerOpening: Binding(get: { isPlayerOpening }, set: { isPlayerOpening = $0 }),
                playerOpeningError: Binding(get: { playerOpeningError }, set: { playerOpeningError = $0 }),
                onPlayTorrent: { playedTorrent = $0 },
                onCast: {},
                onShowRatingSheet: {}
            )
            .environment(appState)
        }

        let host = NSHostingView(rootView: view.frame(width: 980, height: 920))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 920),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        #expect(host.fittingSize.width > 0)
        #expect(playedTorrent == nil)
        #expect(SeriesDetailScrollPolicy.shouldShowTorrentsSection(
            mediaType: .movie,
            hasSelectedEpisode: false,
            isLoadingTorrentSearch: false,
            didSearch: true,
            hasTorrentResults: true
        ))
    }

    @Test
    func downloadsViewHostsSeededTaskRows() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let database = try DatabaseManager(path: rootDir.appendingPathComponent("downloads-view.sqlite").path)
        try await database.migrate()
        let appState = AppState(database: database, testHooks: .init())
        let now = Date()
        let tasks = [
            DownloadTask(
                id: "completed-download",
                mediaId: "movie-downloads",
                streamURL: "https://cdn.example.com/movie-complete.mp4",
                fileName: "movie-complete.mp4",
                status: .completed,
                progress: 1,
                bytesWritten: 2_000_000,
                totalBytes: 2_000_000,
                destinationPath: "/tmp/movie-complete.mp4",
                mediaTitle: "Offline Movie",
                mediaType: "movie",
                createdAt: now,
                updatedAt: now
            ),
            DownloadTask(
                id: "active-download",
                mediaId: "movie-downloads",
                streamURL: "https://cdn.example.com/movie-active.mp4",
                fileName: "movie-active.mp4",
                status: .downloading,
                progress: 0.25,
                bytesWritten: 500_000,
                totalBytes: 2_000_000,
                mediaTitle: "Offline Movie",
                mediaType: "movie",
                createdAt: now,
                updatedAt: now.addingTimeInterval(1)
            ),
            DownloadTask(
                id: "failed-episode",
                mediaId: "series-downloads",
                episodeId: "s01e02",
                streamURL: "https://cdn.example.com/show-s01e02.mp4",
                fileName: "show-s01e02.mp4",
                status: .failed,
                progress: 0.1,
                bytesWritten: 100_000,
                totalBytes: 1_000_000,
                errorMessage: "Network timed out",
                mediaTitle: "Offline Show",
                mediaType: "series",
                seasonNumber: 1,
                episodeNumber: 2,
                episodeTitle: "Second",
                createdAt: now,
                updatedAt: now.addingTimeInterval(2)
            ),
            DownloadTask(
                id: "queued-episode",
                mediaId: "series-downloads",
                episodeId: "s01e01",
                streamURL: "https://cdn.example.com/show-s01e01.mp4",
                fileName: "show-s01e01.mp4",
                status: .queued,
                progress: 0,
                bytesWritten: 0,
                totalBytes: 1_000_000,
                mediaTitle: "Offline Show",
                mediaType: "series",
                seasonNumber: 1,
                episodeNumber: 1,
                episodeTitle: "First",
                createdAt: now,
                updatedAt: now.addingTimeInterval(3)
            ),
        ]

        for task in tasks {
            try await appState.database.saveDownloadTask(task)
        }

        let host = NSHostingView(
            rootView: NavigationStack {
                DownloadsView()
                    .environment(appState)
            }
            .frame(width: 900, height: 760)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(nanoseconds: 250_000_000)
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.width > 0)
    }
    #endif

    @Test
    func aiRecommendationCardBuildsBodyWithAllOptionalFields() {
        let card = AIRecommendationCard(
            recommendation: AIMovieRecommendation(
                title: "Dune",
                year: 2021,
                type: .movie,
                reason: "Large-scale science fiction with strong atmosphere.",
                tmdbId: 438631,
                score: 0.92
            )
        )

        _ = card.body
    }

    @Test
    func aiRecommendationCardBuildsBodyWithoutOptionalFields() {
        let card = AIRecommendationCard(
            recommendation: AIMovieRecommendation(
                title: "Unknown Series",
                year: nil,
                type: .series,
                reason: "",
                tmdbId: nil,
                score: nil
            )
        )

        _ = card.body
    }

    @Test
    func textInputCompatibilityModifierBuildsOnTextField() {
        let view = TextField("Search", text: .constant(""))
            .disableAutomaticTextEntryAdjustments()

        _ = view
    }

    @Test
    func asyncStateViewsBuildCommonSurfaces() {
        _ = LoadingOverlay(title: "Loading", message: "Preparing results").body
        _ = LoadingOverlay(title: "Loading", message: nil).body
        _ = InlineLoadingStatusView(title: "Refreshing").body
        _ = AppErrorInlineView(error: .unknown("Inline failure")).body
        _ = SkeletonBlock(width: 120, height: 24, cornerRadius: 8).body
        _ = DiscoverSkeletonView().body
        _ = DetailSkeletonView().body
        _ = LibrarySkeletonView().body
        _ = SettingsSkeletonView().body
        _ = ExploreSkeletonView().body
        _ = PaginationLoadingView().body
    }

    @Test
    func exploreStateViewsBuildRetrySettingsAndEmptyBodies() {
        var retryCount = 0
        var settingsCount = 0
        let setupError = AppError.tmdbSetupRequired(feature: "Search")

        _ = ExploreErrorView(
            error: setupError,
            onRetry: { retryCount += 1 },
            onOpenSettings: { settingsCount += 1 }
        ).body
        _ = ExploreErrorView(
            error: .unknown("Generic failure"),
            onRetry: { retryCount += 1 },
            onOpenSettings: nil
        ).body
        _ = ExploreEmptyView(query: "rare title").body

        #expect(retryCount == 0)
        #expect(settingsCount == 0)
    }

    @Test
    func glassCardViewsBuildCommonControls() {
        var buttonTapCount = 0
        let tag = GlassTag(text: "HDR", tintColor: .orange, symbol: "sparkles", weight: .bold)
        let spatialButton = SpatialButton(title: "Play", icon: "play.fill", tint: .green) {
            buttonTapCount += 1
        }
        let iconButton = GlassIconButton(
            icon: "trash",
            tint: .red,
            size: 44,
            accessibilityLabel: "Delete",
            accessibilityHint: "Removes the item"
        ) {
            buttonTapCount += 1
        }
        let progress = GlassProgressBar(progress: 1.5, tint: .blue, height: 8)
        let fallback = ArtworkFallbackPosterView(
            title: "The Last of Us",
            type: .series,
            year: 2023,
            compact: false
        )
        let compactFallback = ArtworkFallbackPosterView(
            title: "",
            type: nil,
            year: nil,
            compact: true
        )
        let stateCard = CinematicStateCard(accent: .purple, artworkName: nil) {
            Text("Empty")
        }

        _ = tag.body
        _ = spatialButton.body
        _ = iconButton.body
        _ = progress.body
        _ = fallback.body
        _ = compactFallback.body
        _ = stateCard.body
        _ = Text("Card").glassCard()

        #expect(buttonTapCount == 0)
    }

    @Test
    func artworkFallbackStyleDerivesStableDisplayMetadata() {
        #expect(ArtworkFallbackStyle.initials(for: "") == "VP")
        #expect(ArtworkFallbackStyle.initials(for: "The Lord of the Rings") == "LR")
        #expect(ArtworkFallbackStyle.initials(for: "Dune") == "DU")
        #expect(ArtworkFallbackStyle.metadata(for: .movie, year: 2021) == "MOVIE • 2021")
        #expect(ArtworkFallbackStyle.metadata(for: .series, year: nil) == "TV SHOW")
        #expect(ArtworkFallbackStyle.metadata(for: nil, year: nil) == "FEATURE")
        #expect(ArtworkFallbackStyle.accentSymbol(for: .series) == "tv.fill")
        #expect(ArtworkFallbackStyle.accentSymbol(for: .movie) == "film.stack.fill")
        #expect(ArtworkFallbackStyle.palette(for: "Dune", type: .movie).count == 2)
        #expect(ArtworkFallbackStyle.palette(for: "Dune", type: .series).count == 2)
    }

    @Test
    func appErrorAlertModifierBuildsWithRetryBinding() {
        let error = Binding<AppError?>(
            get: { AppError.unknown("Alert failure") },
            set: { _ in }
        )
        let view = Text("Alert host").appErrorAlert("Problem", error: error) {}

        _ = view
    }

    @Test
    func mediaCardBuildsWithPosterMetadataAndPositiveRating() {
        let preview = MediaPreview(
            id: "movie-positive",
            type: .movie,
            title: "Dune",
            year: 2021,
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            imdbRating: 8.2,
            tmdbId: 438631
        )
        let rating = TasteEvent(
            mediaId: preview.id,
            eventType: .rated,
            feedbackScale: .oneToTen,
            feedbackValue: 9
        )

        _ = MediaCardView(
            item: preview,
            userRating: rating,
            interactionMode: .fullyAnimated
        ).body
    }

    @Test
    func mediaCardBuildsWithoutPosterAndNegativeLikeDislikeRating() {
        let preview = MediaPreview(
            id: "series-negative",
            type: .series,
            title: "Unknown Series",
            year: nil,
            posterPath: nil,
            backdropPath: nil,
            imdbRating: nil,
            tmdbId: nil
        )
        let rating = TasteEvent(
            mediaId: preview.id,
            eventType: .rated,
            feedbackScale: .likeDislike,
            feedbackValue: 0
        )

        _ = MediaCardView(
            item: preview,
            userRating: rating,
            interactionMode: .systemHoverOnly
        ).body
    }

    @Test
    func mediaCardBuildsWithNoUserRating() {
        let preview = MediaPreview(
            id: "movie-unrated",
            type: .movie,
            title: "Unrated",
            year: 2024,
            posterPath: nil,
            imdbRating: 0,
            tmdbId: nil
        )

        _ = MediaCardView(item: preview, userRating: nil).body
    }

    @Test
    func searchRecentAndFilterSurfacesBuildBodies() {
        var selectedTerm: String?
        var removedTerm: String?
        var cleared = false
        var sortOption = DiscoverFilters.SortOption.ratingDesc
        var selectedYear: Int? = 2024
        var selectedLanguages: Set<String> = ["en-US", "ja-JP"]
        var selectedGenre: Genre? = Genre(id: 878, name: "Science Fiction")
        var applied = false

        _ = RecentSearchesSection(
            searches: ["Dune", "Foundation"],
            onSelect: { selectedTerm = $0 },
            onRemove: { removedTerm = $0 },
            onClear: { cleared = true }
        ).body
        _ = RecentSearchesSection(
            searches: [],
            onSelect: { selectedTerm = $0 },
            onRemove: { removedTerm = $0 },
            onClear: { cleared = true }
        ).body
        _ = ExploreFilterSheet(
            sortOption: Binding(get: { sortOption }, set: { sortOption = $0 }),
            selectedYear: Binding(get: { selectedYear }, set: { selectedYear = $0 }),
            selectedLanguages: Binding(get: { selectedLanguages }, set: { selectedLanguages = $0 }),
            genres: [
                Genre(id: 28, name: "Action"),
                Genre(id: 878, name: "Science Fiction"),
            ],
            selectedGenre: Binding(get: { selectedGenre }, set: { selectedGenre = $0 }),
            displayedSortOptions: [.popularityDesc, .ratingDesc, .releaseDateDesc],
            onApply: { applied = true }
        ).body
        _ = ExploreFilterSheet(
            sortOption: Binding(get: { sortOption }, set: { sortOption = $0 }),
            selectedYear: Binding(get: { selectedYear }, set: { selectedYear = $0 }),
            selectedLanguages: Binding(get: { selectedLanguages }, set: { selectedLanguages = $0 }),
            genres: [],
            selectedGenre: Binding(get: { selectedGenre }, set: { selectedGenre = $0 }),
            displayedSortOptions: [.titleAsc],
            onApply: { applied = true }
        ).body

        #expect(selectedTerm == nil)
        #expect(removedTerm == nil)
        #expect(cleared == false)
        #expect(applied == false)
    }

    @Test
    func exploreGenreGridBuildsCatalogAndEmptyBodies() {
        var selectedCards: [ExploreMoodCard] = []

        _ = ExploreGenreGrid(cards: ExploreGenreCatalog.cards) { card in
            selectedCards.append(card)
        }.body
        _ = ExploreGenreGrid(cards: []) { card in
            selectedCards.append(card)
        }.body

        #if os(macOS)
        let host = NSHostingView(
            rootView: ExploreGenreGrid(cards: ExploreGenreCatalog.cards) { card in
                selectedCards.append(card)
            }
            .frame(width: 980, height: 460)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 460),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(host.fittingSize.width > 0)
        #endif

        #expect(selectedCards.isEmpty)
    }

    @Test
    func episodeCardsAndRowsBuildWatchedProgressAndFallbackStates() {
        let firstEpisode = Episode(
            id: "series-1-s1e1",
            mediaId: "series-1",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Arrival",
            overview: "The team finds a strange signal.",
            airDate: "2024-01-01",
            stillPath: "/still.jpg",
            runtime: 48
        )
        let secondEpisode = Episode(
            id: "series-1-s1e2",
            mediaId: "series-1",
            seasonNumber: 1,
            episodeNumber: 2,
            title: nil,
            overview: nil,
            airDate: nil,
            stillPath: nil,
            runtime: nil
        )
        let inProgress = WatchHistory(
            id: "history-1",
            mediaId: firstEpisode.mediaId,
            episodeId: firstEpisode.id,
            title: "Arrival",
            progress: 900,
            duration: 1800,
            watchedAt: Date(timeIntervalSince1970: 100),
            isCompleted: false
        )
        let completed = WatchHistory(
            id: "history-2",
            mediaId: secondEpisode.mediaId,
            episodeId: secondEpisode.id,
            title: secondEpisode.displayTitle,
            progress: 1800,
            duration: 1800,
            watchedAt: Date(timeIntervalSince1970: 200),
            isCompleted: true
        )
        var selectedEpisodes: [Episode] = []
        var toggledEpisodes: [Episode] = []

        _ = EpisodeCardView(
            episode: firstEpisode,
            watchState: inProgress,
            isSelected: true,
            onSelect: { selectedEpisodes.append(firstEpisode) },
            onToggleWatched: { toggledEpisodes.append(firstEpisode) }
        ).body
        _ = EpisodeCardView(
            episode: secondEpisode,
            watchState: completed,
            isSelected: false,
            onSelect: { selectedEpisodes.append(secondEpisode) },
            onToggleWatched: { toggledEpisodes.append(secondEpisode) }
        ).body
        _ = EpisodeCardView(
            episode: secondEpisode,
            watchState: nil,
            isSelected: false,
            onSelect: { selectedEpisodes.append(secondEpisode) },
            onToggleWatched: { toggledEpisodes.append(secondEpisode) }
        ).body
        _ = EpisodeRow(
            episodes: [firstEpisode, secondEpisode],
            episodeWatchStates: [
                firstEpisode.id: inProgress,
                secondEpisode.id: completed,
            ],
            selectedEpisodeID: firstEpisode.id,
            onSelectEpisode: { selectedEpisodes.append($0) },
            onToggleWatched: { toggledEpisodes.append($0) }
        ).body

        #expect(selectedEpisodes.isEmpty)
        #expect(toggledEpisodes.isEmpty)
    }

    @Test
    func torrentResultRowsBuildPlaybackAndDownloadStates() {
        let torrent = TorrentResult(
            infoHash: "abcdef123456",
            title: "Dune 2021 2160p DV Atmos WEB-DL",
            sizeBytes: 8_589_934_592,
            seeders: 52,
            leechers: 4,
            quality: .uhd4k,
            codec: .h265,
            audio: .atmos,
            source: .webDL,
            hdr: .dolbyVision,
            indexerName: "Fixture",
            magnetURI: "magnet:?xt=urn:btih:abcdef123456",
            isCached: true,
            cachedOnService: "Premiumize"
        )
        var isOpening = false
        var openingError: String?
        var playCount = 0
        var downloadCount = 0

        for state in [
            DownloadButtonState.idle,
            .resolving,
            .downloading,
            .completed,
            .failed,
        ] {
            _ = TorrentResultRow(
                torrent: torrent,
                isPlayerOpening: Binding(get: { isOpening }, set: { isOpening = $0 }),
                playerOpeningError: Binding(get: { openingError }, set: { openingError = $0 }),
                onPlay: { playCount += 1 },
                onDownload: { downloadCount += 1 },
                downloadState: state
            ).body
        }

        isOpening = true
        _ = TorrentResultRow(
            torrent: torrent,
            isPlayerOpening: Binding(get: { isOpening }, set: { isOpening = $0 }),
            playerOpeningError: Binding(get: { openingError }, set: { openingError = $0 }),
            onPlay: { playCount += 1 },
            onDownload: nil,
            downloadState: .idle
        ).body

        isOpening = false
        openingError = "Player unavailable"
        _ = TorrentResultRow(
            torrent: torrent,
            isPlayerOpening: Binding(get: { isOpening }, set: { isOpening = $0 }),
            playerOpeningError: Binding(get: { openingError }, set: { openingError = $0 }),
            onPlay: { playCount += 1 },
            onDownload: nil,
            downloadState: .idle
        ).body

        #expect(playCount == 0)
        #expect(downloadCount == 0)
    }

    @Test
    func detailAIAnalysisBuildsResultLoadingErrorAndActionBodies() {
        let verdicts: [AIPersonalizedAnalysis.Verdict] = [
            .strongYes,
            .yes,
            .maybe,
            .no,
            .strongNo,
        ]

        for verdict in verdicts {
            let viewModel = makeDetailViewModel()
            viewModel.aiAnalysis = AIPersonalizedAnalysis(
                personalizedDescription: "This matches your recent high ratings.",
                predictedRating: 8.7,
                verdict: verdict,
                reasons: ["Similar tone", "Strong visuals"]
            )

            _ = DetailAIAnalysis(viewModel: viewModel).body
        }

        let loadingViewModel = makeDetailViewModel()
        loadingViewModel.isLoadingAIAnalysis = true
        _ = DetailAIAnalysis(viewModel: loadingViewModel).body

        let errorViewModel = makeDetailViewModel()
        errorViewModel.aiAnalysisError = "Analysis provider unavailable"
        _ = DetailAIAnalysis(viewModel: errorViewModel).body

        let actionViewModel = makeDetailViewModel()
        actionViewModel.mediaItem = makeMediaItem()
        _ = DetailAIAnalysis(viewModel: actionViewModel).body
    }

    @Test
    func detailRatingSheetBuildsEveryFeedbackScaleBody() {
        for mode in [
            FeedbackScaleMode.likeDislike,
            .oneToTen,
            .oneToHundred,
        ] {
            let viewModel = makeDetailViewModel()
            viewModel.feedbackScaleMode = mode
            viewModel.currentFeedbackValue = switch mode {
            case .likeDislike:
                1
            case .oneToTen:
                8
            case .oneToHundred:
                82
            default:
                50
            }

            var isShowing = true
            var draftFeedbackValue = viewModel.currentFeedbackValue ?? 50
            _ = DetailRatingSheet(
                viewModel: viewModel,
                isShowing: Binding(get: { isShowing }, set: { isShowing = $0 }),
                draftFeedbackValue: Binding(get: { draftFeedbackValue }, set: { draftFeedbackValue = $0 })
            ).body
        }

        let emptyViewModel = makeDetailViewModel()
        emptyViewModel.feedbackScaleMode = .oneToTen
        var isShowing = true
        var draftFeedbackValue = 50.0
        _ = DetailRatingSheet(
            viewModel: emptyViewModel,
            isShowing: Binding(get: { isShowing }, set: { isShowing = $0 }),
            draftFeedbackValue: Binding(get: { draftFeedbackValue }, set: { draftFeedbackValue = $0 })
        ).body
    }

    @Test
    func detailHeroAndSeasonSectionsBuildWithScrollProxy() {
        let viewModel = makeDetailViewModel()
        viewModel.mediaItem = makeMediaItem(type: .series)
        viewModel.mediaLibrary.isInFavorites = true
        viewModel.mediaLibrary.statusMessage = "Saved to Favorites"
        viewModel.seasons = [
            Season(
                id: 1,
                seasonNumber: 1,
                name: "Season 1",
                overview: "The crew starts its journey.",
                posterPath: nil,
                episodeCount: 2,
                airDate: "2024-01-01"
            ),
            Season(
                id: 2,
                seasonNumber: 2,
                name: "Season 2",
                overview: nil,
                posterPath: nil,
                episodeCount: 1,
                airDate: nil
            ),
        ]
        let firstEpisode = Episode(
            id: "series-fixture-s1e1",
            mediaId: "detail-fixture-series",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Pilot",
            overview: "The first hour.",
            airDate: "2024-01-01",
            stillPath: nil,
            runtime: 45
        )
        viewModel.episodes = [
            firstEpisode,
            Episode(
                id: "series-fixture-s1e2",
                mediaId: "detail-fixture-series",
                seasonNumber: 1,
                episodeNumber: 2,
                title: "Signal",
                overview: nil,
                airDate: nil,
                stillPath: "/still.jpg",
                runtime: nil
            ),
        ]
        viewModel.selectedSeason = 1
        viewModel.selectedEpisode = firstEpisode
        viewModel.episodeWatchStates[firstEpisode.id] = WatchHistory(
            id: "series-watch-state",
            mediaId: firstEpisode.mediaId,
            episodeId: firstEpisode.id,
            title: firstEpisode.displayTitle,
            progress: 2700,
            duration: 2700,
            watchedAt: Date(timeIntervalSince1970: 300),
            isCompleted: true
        )

        var didShowRatingSheet = false
        let view = ScrollViewReader { proxy in
            VStack {
                DetailHeroSection(
                    viewModel: viewModel,
                    title: "The Expanse",
                    scrollProxy: proxy,
                    onShowRatingSheet: { didShowRatingSheet = true },
                    tmdbApiKey: "test-key"
                )
                DetailSeasonsSection(
                    viewModel: viewModel,
                    tmdbApiKey: "test-key",
                    scrollProxy: proxy,
                    streamResultsAnchor: "streams"
                )
            }
        }

        _ = view.body
        #if os(macOS)
        let host = NSHostingView(rootView: view.frame(width: 820, height: 780))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 780),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(host.fittingSize.width > 0)
        #endif
        #expect(didShowRatingSheet == false)
    }

    @Test
    func standaloneSharedViewsBuildBodies() {
        _ = VPMenuBackground().body
        _ = LaunchScreen().body
        _ = DownloadsView().body

        #if os(macOS)
        var selectedTab = SidebarTab.downloads
        var openedEnvironmentPicker = false
        var selectedTabs: [SidebarTab] = []
        let view = ZStack {
            VPMenuBackground()
            VPSidebarView(
                selectedTab: Binding(get: { selectedTab }, set: { selectedTab = $0 }),
                opensEnvironmentPicker: true,
                onOpenEnvironmentPicker: { openedEnvironmentPicker = true },
                onTabSelection: { selectedTabs.append($0) },
                activeDownloadCount: 2,
                settingsWarningCount: 1
            )
        }
        let host = NSHostingView(rootView: view.frame(width: 220, height: 520))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 520),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(host.fittingSize.width > 0)
        #expect(openedEnvironmentPicker == false)
        #expect(selectedTabs.isEmpty)
        #endif
    }

    @Test
    func libraryEmptyStateBuildsEachListType() {
        let listTypes: [LibraryEmptyStateCTAPolicy.ListType] = [
            .favorites,
            .watchlist,
            .history,
            .downloads,
        ]
        var actions: [LibraryEmptyStateCTAPolicy.CTAAction] = []

        for listType in listTypes {
            let view = LibraryEmptyStateView(listType: listType) { action in
                actions.append(action)
            }
            _ = view.body
        }

        #expect(actions.isEmpty)
    }

    @Test
    func libraryCSVSheetsBuildInitialBodies() {
        var summaries: [LibraryCSVImportSummary] = []

        _ = LibraryCSVExportSheet().body
        _ = LibraryCSVImportSheet { summary in
            summaries.append(summary)
        }.body
        _ = IMDbCSVImportSheet().body

        #expect(summaries.isEmpty)
    }

    #if os(macOS)
    @Test
    func imdbCSVImportAndPreviewSheetsHostEmptyAndDetectedStates() {
        let appState = AppState(testHooks: .init())
        var emptyHeaders: [String] = []
        var emptyRows: [[String]] = []
        var emptyMappings: [String: String] = [:]
        var emptyAnalyzing = false
        var emptyAISuggestions: [String: String] = [:]
        var emptyAIError: String?

        var headers = ["const", "primaryTitle", "Your Rating", "Date Rated"]
        var rows = [
            ["tt0111161", "The Shawshank Redemption", "10", "2026-04-26"],
            ["tt0068646", "The Godfather", "9", "2026-04-25"],
        ]
        var mappings = [
            "const": "imdbID",
            "primaryTitle": "title",
            "Your Rating": "userRating",
        ]
        var isAnalyzing = true
        var aiSuggestions = [
            "Date Rated": "date",
        ]
        var aiError: String? = "AI mapping unavailable in construction test."

        let views: [AnyView] = [
            AnyView(
                IMDbCSVImportSheet()
                    .environment(appState)
            ),
            AnyView(
                CSVHeaderPreviewSheet(
                    headers: Binding(get: { emptyHeaders }, set: { emptyHeaders = $0 }),
                    firstRows: Binding(get: { emptyRows }, set: { emptyRows = $0 }),
                    detectedMappings: Binding(get: { emptyMappings }, set: { emptyMappings = $0 }),
                    isAnalyzing: Binding(get: { emptyAnalyzing }, set: { emptyAnalyzing = $0 }),
                    aiSuggestedMappings: Binding(get: { emptyAISuggestions }, set: { emptyAISuggestions = $0 }),
                    aiAnalysisError: Binding(get: { emptyAIError }, set: { emptyAIError = $0 })
                )
                .environment(appState)
            ),
            AnyView(
                CSVHeaderPreviewSheet(
                    headers: Binding(get: { headers }, set: { headers = $0 }),
                    firstRows: Binding(get: { rows }, set: { rows = $0 }),
                    detectedMappings: Binding(get: { mappings }, set: { mappings = $0 }),
                    isAnalyzing: Binding(get: { isAnalyzing }, set: { isAnalyzing = $0 }),
                    aiSuggestedMappings: Binding(get: { aiSuggestions }, set: { aiSuggestions = $0 }),
                    aiAnalysisError: Binding(get: { aiError }, set: { aiError = $0 })
                )
                .environment(appState)
            ),
        ]

        for (index, view) in views.enumerated() {
            let host = NSHostingView(rootView: view.frame(width: 700, height: 820))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 820),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            #expect(host.fittingSize.width > 0, "Hosted IMDb CSV sheet \(index) should lay out")
        }

        #expect(headers.count == 4)
        #expect(rows.count == 2)
        #expect(mappings["const"] == "imdbID")
        #expect(aiSuggestions["Date Rated"] == "date")
    }
    #endif

    @Test
    func settingsRowsHeadersAndFeedbackBannersBuildBodies() {
        let statuses = [
            SettingsDestinationStatus(message: "Ready", kind: .positive),
            SettingsDestinationStatus(message: "Needs setup", kind: .warning),
            SettingsDestinationStatus(message: "Optional", kind: .neutral),
        ]

        _ = SettingsDestinationRow(destination: .metadata, status: statuses[0], isRecent: true).body
        _ = SettingsDestinationRow(destination: .debrid, status: statuses[1], isRecent: false).body
        _ = SettingsDestinationRow(destination: .library, status: statuses[2], isRecent: false).body
        _ = SettingsDestinationRow(destination: .testMode, status: nil, isRecent: true).body

        for category in SettingsCategory.allCases {
            _ = SettingsSectionHeader(category: category, configuredCount: 1, totalCount: 3).body
        }

        let success = SettingsInlineNotice.success("Saved")
        let info = SettingsInlineNotice.info("Optional setup")
        let warning = SettingsInlineNotice.warning("Needs attention")

        _ = SettingsNoticeBanner(notice: success).body
        _ = SettingsNoticeBanner(notice: info).body
        _ = SettingsNoticeBanner(notice: warning).body
        _ = SettingsErrorBanner(error: .unknown("Settings failed")).body

        #expect(success.symbolName == "checkmark.circle.fill")
        #expect(info.symbolName == "info.circle.fill")
        #expect(warning.symbolName == "exclamationmark.triangle.fill")
        #expect(success.tone == .success)
        #expect(info.tone == .info)
        #expect(warning.tone == .warning)
    }

    @Test
    func lightweightSettingsDestinationScreensBuildBodies() {
        let appState = AppState(testHooks: .init())

        _ = SettingsView().body
        _ = SetupWizardView().body
        _ = AISettingsView().body
        _ = DebridSettingsView().body
        _ = EnvironmentSettingsView().environment(appState)
        _ = IMDbImportSettingsView().body
        _ = IndexerSettingsView().body
        _ = MetadataSettingsView().body
        _ = SimklSettingsView().body
        _ = SubtitleSettingsView().body
        _ = PlayerSettingsView().body
        _ = ResetDataView().body
        _ = TestModeView().body
        _ = TraktSettingsView().body

        #if os(macOS)
        let environmentHost = NSHostingView(
            rootView: NavigationStack {
                EnvironmentSettingsView()
                    .environment(appState)
            }
            .frame(width: 620, height: 820)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = environmentHost
        environmentHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        #expect(environmentHost.fittingSize.width > 0)

        let hostedSettingsViews: [AnyView] = [
            AnyView(NavigationStack { AISettingsView() }.environment(appState)),
            AnyView(NavigationStack { DebridSettingsView() }.environment(appState)),
            AnyView(NavigationStack { IMDbImportSettingsView() }.environment(appState)),
            AnyView(NavigationStack { IndexerSettingsView() }.environment(appState)),
            AnyView(NavigationStack { MetadataSettingsView() }.environment(appState)),
            AnyView(NavigationStack { PlayerSettingsView() }.environment(appState)),
            AnyView(NavigationStack { ResetDataView() }.environment(appState)),
            AnyView(NavigationStack { SimklSettingsView() }.environment(appState)),
            AnyView(NavigationStack { SubtitleSettingsView() }.environment(appState)),
            AnyView(NavigationStack { TestModeView() }.environment(appState)),
            AnyView(NavigationStack { TraktSettingsView() }.environment(appState)),
        ]

        for (index, view) in hostedSettingsViews.enumerated() {
            let host = NSHostingView(rootView: view.frame(width: 640, height: 820))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 820),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            #expect(host.fittingSize.width > 0, "Hosted settings view \(index) should lay out")
        }
        #endif
    }

    #if os(macOS)
    @Test
    func debridSettingsViewHostsConfiguredSupportedAndUnsupportedProviders() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let database = try DatabaseManager(path: rootDir.appendingPathComponent("debrid-settings.sqlite").path)
        try await database.migrate()
        let appState = AppState(database: database, testHooks: .init())
        let now = Date()
        let configs = [
            DebridConfig(
                id: "real-debrid-row",
                serviceType: .realDebrid,
                apiTokenRef: "legacy-real-token",
                isActive: true,
                priority: 0,
                createdAt: now,
                updatedAt: now
            ),
            DebridConfig(
                id: "premiumize-row",
                serviceType: .premiumize,
                apiTokenRef: "legacy-premiumize-token",
                isActive: false,
                priority: 1,
                createdAt: now,
                updatedAt: now
            ),
            DebridConfig(
                id: "easynews-row",
                serviceType: .easyNews,
                apiTokenRef: "legacy-easynews-token",
                isActive: true,
                priority: 2,
                createdAt: now,
                updatedAt: now
            ),
        ]

        for config in configs {
            try await appState.database.saveDebridConfig(config)
        }

        let host = NSHostingView(
            rootView: NavigationStack {
                DebridSettingsView()
                    .environment(appState)
            }
            .frame(width: 700, height: 860)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 860),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(nanoseconds: 250_000_000)
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.width > 0)
        #expect(DebridSettingsPolicy.supportedConfigs(from: configs).map(\.id) == ["real-debrid-row", "premiumize-row"])
        #expect(DebridSettingsPolicy.unsupportedConfigs(from: configs).map(\.id) == ["easynews-row"])
    }

    @Test
    func indexerSettingsViewHostsConfiguredRowsAndMissingBuiltIns() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let database = try DatabaseManager(path: rootDir.appendingPathComponent("indexer-settings.sqlite").path)
        try await database.migrate()
        let appState = AppState(database: database, testHooks: .init())
        let configs = [
            IndexerConfig(
                id: "torznab-row",
                name: "Custom Torznab",
                indexerType: .torznab,
                baseURL: "https://indexer.example.com",
                apiKey: "torznab-token",
                isActive: true,
                priority: 0,
                providerSubtype: .customTorznab,
                endpointPath: "/api",
                categoryFilter: "2000,5000",
                apiKeyTransport: .query
            ),
            IndexerConfig(
                id: "stremio-row",
                name: "Fixture Stremio",
                indexerType: .stremio,
                baseURL: "https://stremio.example.com/manifest.json",
                apiKey: nil,
                isActive: false,
                priority: 1,
                providerSubtype: .stremioAddon,
                endpointPath: "",
                categoryFilter: nil,
                apiKeyTransport: .query
            ),
            IndexerConfig(
                id: "zilean-row",
                name: "Fixture Zilean",
                indexerType: .zilean,
                baseURL: "https://zilean.example.com",
                apiKey: "zilean-token",
                isActive: true,
                priority: 2,
                providerSubtype: .customTorznab,
                endpointPath: "/api/v1",
                categoryFilter: nil,
                apiKeyTransport: .header
            ),
        ]

        try await appState.database.saveIndexerConfigs(configs)

        let host = NSHostingView(
            rootView: NavigationStack {
                IndexerSettingsView()
                    .environment(appState)
            }
            .frame(width: 760, height: 940)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 940),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(nanoseconds: 250_000_000)
        host.layoutSubtreeIfNeeded()

        let stored = try await appState.database.fetchAllIndexerConfigs().sorted { $0.priority < $1.priority }
        #expect(host.fittingSize.width > 0)
        #expect(stored.map(\.id) == ["torznab-row", "stremio-row", "zilean-row"])
        #expect(IndexerSettingsView.normalizePrioritiesPreservingOrder(configs).map(\.priority) == [0, 1, 2])
        #expect(IndexerDefaultRanking.deletedBuiltIns(from: stored).isEmpty == false)
    }

    @Test
    func resetDataViewHostsEveryConfirmationStep() {
        let appState = AppState(testHooks: .init())
        let states: [(ResetDataStep, String)] = [
            (.warning, ""),
            (.secondConfirmation, ""),
            (.finalConfirmation, ""),
            (.finalConfirmation, ResetDataPolicy.requiredConfirmationPhrase),
        ]

        for (index, state) in states.enumerated() {
            let host = NSHostingView(
                rootView: ResetDataView(
                    initialStep: state.0,
                    initialConfirmationText: state.1
                )
                .environment(appState)
                .frame(width: 560, height: 520)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            #expect(host.fittingSize.width > 0, "Hosted reset step \(index) should lay out")
        }

        #expect(ResetDataStep.allCases == [.warning, .secondConfirmation, .finalConfirmation])
        #expect(ResetDataPolicy.canExecuteReset(confirmationText: ResetDataPolicy.requiredConfirmationPhrase))
        #expect(ResetDataPolicy.canExecuteReset(confirmationText: "reset"))
        #expect(ResetDataPolicy.canExecuteReset(confirmationText: " RESET ", isResetting: true) == false)
    }
    #endif

    @Test
    func testModeScreenMetadataCoversAllVisualQASurfaces() {
        let expected: [(TestScreen, String, String, String)] = [
            (.discover, "Discover", "Hero + sections", "sparkles.tv"),
            (.search, "Search", "Empty search", "magnifyingglass"),
            (.searchResults, "Search + Results", "Filters + results", "line.3.horizontal.decrease.circle"),
            (.detailMovie, "Movie Detail", "Stream list", "film"),
            (.detailSeries, "Series Detail", "Episodes grid", "film.stack"),
            (.library, "Library", "Populated library", "books.vertical"),
            (.downloads, "Downloads", "Active downloads", "arrow.down.circle"),
            (.player, "Player", "Controls + overlays", "play.circle"),
            (.settings, "Settings", "All categories", "gearshape"),
        ]

        #expect(TestScreen.allCases == expected.map(\.0))
        for (screen, title, subtitle, icon) in expected {
            #expect(screen.id == screen.rawValue)
            #expect(screen.title == title)
            #expect(screen.subtitle == subtitle)
            #expect(screen.icon == icon)
        }
    }

    #if os(macOS)
    @Test
    func testModeSheetsHostEveryPreviewSurface() {
        let appState = AppState(testHooks: .init())

        for screen in TestScreen.allCases {
            let host = NSHostingView(
                rootView: TestScreenSheet(screen: screen)
                    .environment(appState)
                    .frame(width: 920, height: 720)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            #expect(host.fittingSize.width > 0, "\(screen.title) preview should lay out")
        }
    }
    #endif
}
