import SwiftUI
import os

private enum SeriesDetailQAScrollDebug {
    private static let logger = Logger(subsystem: "com.vpstudio", category: "series-detail-scroll")

    static func log(_ message: @autoclosure () -> String) {
        guard QARuntimeOptions.scrollDebug else { return }
        let renderedMessage = message()
        logger.debug("\(renderedMessage, privacy: .public)")
    }
}

enum SeriesPrimaryPlayPolicy {
    static let noStreamsMessage = "No streams found for this episode. Try another episode or result."
    static let selectEpisodeLabel = "Select Episode"

    static func isBusy(
        isLocalPlayLoading: Bool,
        isPlayerOpening: Bool,
        isLoadingSeasonEpisodes: Bool
    ) -> Bool {
        isLocalPlayLoading || isPlayerOpening || isLoadingSeasonEpisodes
    }

    static func isEnabled(
        mediaType: MediaType,
        hasSelectedEpisode: Bool,
        isBusy: Bool
    ) -> Bool {
        guard !isBusy else { return false }
        return mediaType != .series || hasSelectedEpisode
    }

    static func title(
        mediaType: MediaType,
        hasSelectedEpisode: Bool
    ) -> String {
        mediaType == .series && !hasSelectedEpisode ? selectEpisodeLabel : "Play"
    }

    static func accessibilityHint(
        mediaType: MediaType,
        hasSelectedEpisode: Bool
    ) -> String {
        if mediaType == .series && !hasSelectedEpisode {
            return "Choose an episode before loading streams."
        }
        return "Searches for streams if needed and opens the first available result."
    }
}

enum SeriesDetailScrollPolicy {
    static func shouldShowTorrentsSection(
        mediaType: MediaType,
        hasSelectedEpisode: Bool,
        isLoadingTorrentSearch: Bool,
        didSearch: Bool,
        hasTorrentResults: Bool
    ) -> Bool {
        if mediaType == .series {
            return hasSelectedEpisode || isLoadingTorrentSearch || didSearch || hasTorrentResults
        }

        return isLoadingTorrentSearch || didSearch || hasTorrentResults
    }

    static func shouldScrollToResults(
        tappedEpisodeID: String,
        currentSelectedEpisodeID: String?,
        isTaskCancelled: Bool
    ) -> Bool {
        // Auto-scrolling to the bottom streams block on episode selection
        // proved visually unstable in the live series detail route.
        let _ = tappedEpisodeID
        let _ = currentSelectedEpisodeID
        let _ = isTaskCancelled
        return false
    }
}

enum SeriesSeasonLoadingPresentationPolicy {
    static func shouldShowEpisodesSection(
        hasSeasons: Bool,
        episodeCount: Int,
        isLoadingSeasonEpisodes: Bool
    ) -> Bool {
        hasSeasons && (episodeCount > 0 || isLoadingSeasonEpisodes)
    }

    static func loadingTitle(for seasonNumber: Int) -> String {
        "Loading Season \(seasonNumber)…"
    }

    static func loadingMessage(for seasonNumber: Int) -> String {
        "Updating episode choices for Season \(seasonNumber) while keeping your place on the page."
    }
}

enum SeriesDetailPresentationPolicy {
    static func seasonCountText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) Season\(count == 1 ? "" : "s")"
    }

    static func runtimeText(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        return "\(minutes) min"
    }

    static func imdbRatingText(_ rating: Double?) -> String? {
        guard let rating, rating > 0 else { return nil }
        return String(format: "%.1f IMDb", rating)
    }

    static func episodeContextText(season: Int, episodeNumber: Int) -> String {
        "S\(season):E\(episodeNumber)"
    }

    static func episodeRuntimeText(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        return "• \(minutes)m"
    }

    static func episodeTitle(_ title: String?, episodeNumber: Int) -> String {
        guard let title, !title.isEmpty else { return "Episode \(episodeNumber)" }
        return title
    }

    static func episodeAccessibilityLabel(episodeNumber: Int, title: String?) -> String {
        "Episode \(episodeNumber), \(title ?? "Untitled")"
    }

    static func episodeAccessibilityValue(isWatched: Bool, isSelected: Bool) -> String {
        switch (isWatched, isSelected) {
        case (true, true):
            return "Watched, selected"
        case (true, false):
            return "Watched"
        case (false, true):
            return "Selected"
        case (false, false):
            return "Not watched"
        }
    }

    static func episodeWatchLabel(isWatched: Bool) -> String {
        isWatched ? "Watched" : "Not watched"
    }

    static func episodeWatchActionTitle(isWatched: Bool) -> String {
        isWatched ? "Mark Episode as Unwatched" : "Mark Episode as Watched"
    }

    static func watchStatusIcon(for state: DetailWatchStatusState) -> String {
        switch state {
        case .watched:
            return "checkmark.circle.fill"
        case .inProgress:
            return "play.circle.fill"
        case .notWatched:
            return "circle"
        case .selectionRequired:
            return "rectangle.and.hand.point.up.left.fill"
        }
    }

    static func selectedEpisodeWatchState(hasSelectedEpisode: Bool, isSelectedEpisodeCompleted: Bool) -> DetailWatchStatusState {
        guard hasSelectedEpisode else { return .selectionRequired }
        return isSelectedEpisodeCompleted ? .watched : .notWatched
    }

    static func seriesWatchProgressLabel(watchedCount: Int, seasonEpisodeCounts: [Int]) -> String {
        let totalCount = max(seasonEpisodeCounts.reduce(0, +), watchedCount)
        guard totalCount > 0 else { return "Series Actions" }
        return "\(watchedCount)/\(totalCount) watched"
    }
}

/// A series‑detail layout matching the reference screenshot exactly:
/// – Back arrow top-left, share/list/cast icons top-right
/// – Hero image with gradient overlay
/// – Title "SHRINKING" large and bold
/// – Metadata row: year, season count, IMDb rating, favorite heart
/// – Large white play button
/// – Current episode info: "S3:E4 The Final Chapter • 35m"
/// – Synopsis paragraph
/// – Season tabs as circular numbers (1, 2, 3) with selected state
/// – Horizontal episode grid with thumbnails, progress bars, checkmarks
struct SeriesDetailLayout: View {
    let viewModel: DetailViewModel
    let title: String
    let tmdbApiKey: String
    let mediaType: MediaType
    let streamResultsAnchor: String
    let shareItem: String
    @Binding var isPlayerOpening: Bool
    @Binding var playerOpeningError: String?
    let onPlayTorrent: (TorrentResult) -> Void
    let onCast: () -> Void
    let onShowRatingSheet: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isPlayButtonLoading = false

    private var isPrimaryPlayBusy: Bool {
        SeriesPrimaryPlayPolicy.isBusy(
            isLocalPlayLoading: isPlayButtonLoading,
            isPlayerOpening: isPlayerOpening,
            isLoadingSeasonEpisodes: viewModel.isLoading(.seasonEpisodes)
        )
    }

    private var isPrimaryPlayEnabled: Bool {
        SeriesPrimaryPlayPolicy.isEnabled(
            mediaType: mediaType,
            hasSelectedEpisode: viewModel.selectedEpisode != nil,
            isBusy: isPrimaryPlayBusy
        )
    }

    private var shouldShowTorrentsSection: Bool {
        SeriesDetailScrollPolicy.shouldShowTorrentsSection(
            mediaType: mediaType,
            hasSelectedEpisode: viewModel.selectedEpisode != nil,
            isLoadingTorrentSearch: viewModel.isLoading(.torrentSearch),
            didSearch: viewModel.torrentSearch.didSearch,
            hasTorrentResults: !viewModel.torrentSearch.results.isEmpty
        )
    }

    private var shouldShowEpisodesSection: Bool {
        SeriesSeasonLoadingPresentationPolicy.shouldShowEpisodesSection(
            hasSeasons: !viewModel.seasons.isEmpty,
            episodeCount: viewModel.episodes.count,
            isLoadingSeasonEpisodes: viewModel.isLoading(.seasonEpisodes)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Hero Image
                heroImage
                    .frame(height: 380)
                    .clipped()
                    .overlay(heroOverlay)

                // MARK: - Main Content
                VStack(alignment: .leading, spacing: 20) {
                    // Title & Navigation
                    titleAndNavRow

                    // Metadata row
                    metadataRow

                    // Play button
                    playButtonRow

                    if mediaType != .series {
                        watchStateRow
                    }

                    // Current episode info
                    currentEpisodeRow

                    if mediaType == .series {
                        seriesTrackingRow
                    }

                    // Synopsis
                    if let overview = viewModel.mediaItem?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(4)
                            .padding(.top, 4)
                    }

                    // AI Analysis
                    DetailAIAnalysis(viewModel: viewModel)
                        .padding(.top, 16)

                    if let genres = viewModel.mediaItem?.genres, !genres.isEmpty {
                        genrePills(genres)
                    }

                    if let status = viewModel.libraryStatusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    // Seasons
                    if !viewModel.seasons.isEmpty {
                        seasonsSection
                    }

                    // Episodes
                    if shouldShowEpisodesSection {
                        episodesSection()
                    }

                    // Torrents
                    if shouldShowTorrentsSection {
                        torrentsSection
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
        }
        .background(Color.black)
        .foregroundStyle(.white)
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            SeriesDetailQAScrollDebug.log(
                "appear title=\(title) mediaType=\(mediaType.rawValue) selectedEpisode=\(viewModel.selectedEpisode?.id ?? "nil") didSearch=\(viewModel.torrentSearch.didSearch) results=\(viewModel.torrentSearch.results.count)"
            )
        }
        .onChange(of: viewModel.selectedEpisode?.id) { _, newValue in
            SeriesDetailQAScrollDebug.log("selectedEpisode=\(newValue ?? "nil")")
        }
        .onChange(of: viewModel.torrentSearch.results.count) { _, newValue in
            SeriesDetailQAScrollDebug.log("torrentResults=\(newValue)")
        }
        .onChange(of: viewModel.torrentSearch.didSearch) { _, newValue in
            SeriesDetailQAScrollDebug.log("didSearch=\(newValue)")
        }
        .onChange(of: viewModel.loadingPhase?.rawValue ?? "none") { _, newValue in
            SeriesDetailQAScrollDebug.log("loadingPhase=\(newValue)")
        }
    }
    
    // MARK: - Subviews
    
    private var heroImage: some View {
        Group {
            if let backdropURL = viewModel.mediaItem?.backdropURL {
                AsyncImage(url: backdropURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.gray.opacity(0.3), .gray.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.gray.opacity(0.3), .gray.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }
    
    private var heroOverlay: some View {
        ZStack(alignment: .top) {
            // Gradient fade
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.7), location: 0.0),
                    .init(color: .black.opacity(0.3), location: 0.3),
                    .init(color: .clear, location: 0.6),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            
            // Top bar
            HStack {
                // Back button
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityHint("Returns to the previous screen.")
                
                Spacer()
                
                // Utility icons
                HStack(spacing: 12) {
                    ShareLink(item: shareItem) {
                        utilityGlyph(name: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share title")
                    .accessibilityHint("Opens the share sheet for this title.")

                    Button {
                        Task { await viewModel.toggleWatchlist() }
                    } label: {
                        utilityGlyph(name: viewModel.isInWatchlist ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.isInWatchlist ? "Remove from Watchlist" : "Add to Watchlist")
                    .accessibilityHint("Toggles this title in your watchlist.")

                    Button(action: onCast) {
                        utilityGlyph(name: "airplayvideo")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cast")
                    .accessibilityHint("Opens playback destination options.")

                    Button(action: onShowRatingSheet) {
                        utilityGlyph(name: viewModel.currentFeedbackValue != nil ? "star.fill" : "star")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.currentFeedbackValue != nil ? "Edit rating" : "Rate title")
                    .accessibilityHint("Opens rating controls for this title.")
                    
                    // AI button
                    Button {
                        Task { await viewModel.fetchAIAnalysis() }
                    } label: {
                        Image(systemName: "brain")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .background(Color.purple.opacity(0.8), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Analyze with AI")
                    .accessibilityHint("Requests an AI summary for this title.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var titleAndNavRow: some View {
        HStack(alignment: .top) {
            Text(title.uppercased())
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundStyle(.white)
            
            Spacer()
        }
    }
    
    private var metadataRow: some View {
        HStack(spacing: 16) {
            if let year = viewModel.mediaItem?.year {
                Text(String(year))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            
            if !viewModel.seasons.isEmpty {
                Text(SeriesDetailPresentationPolicy.seasonCountText(viewModel.seasons.count) ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let runtimeText = SeriesDetailPresentationPolicy.runtimeText(minutes: viewModel.mediaItem?.runtime) {
                Text(runtimeText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            
            if let ratingText = SeriesDetailPresentationPolicy.imdbRatingText(viewModel.mediaItem?.imdbRating) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(ratingText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            
            // Favorite button
            Button {
                Task { await viewModel.toggleFavorites() }
            } label: {
                Image(systemName: viewModel.mediaLibrary.isInFavorites ? "heart.fill" : "heart")
                    .font(.system(size: 18))
                    .foregroundStyle(viewModel.mediaLibrary.isInFavorites ? .red : .white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.mediaLibrary.isInFavorites ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityHint("Toggles this title in your Favorites list.")
        }
    }
    
    private var playButtonRow: some View {
        Button {
            guard isPrimaryPlayEnabled else { return }
            playerOpeningError = nil
            isPlayButtonLoading = true
            Task {
                defer { isPlayButtonLoading = false }

                // Ensure we have torrents for the selected episode
                if viewModel.torrentSearch.results.isEmpty {
                    await viewModel.searchTorrents()
                }

                guard let torrent = viewModel.torrentSearch.results.first else {
                    playerOpeningError = SeriesPrimaryPlayPolicy.noStreamsMessage
                    return
                }

                onPlayTorrent(torrent)
            }
        } label: {
            HStack(spacing: 12) {
                if isPrimaryPlayBusy {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                    Text(
                        SeriesPrimaryPlayPolicy.title(
                            mediaType: mediaType,
                            hasSelectedEpisode: viewModel.selectedEpisode != nil
                        )
                    )
                        .font(.headline)
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .disabled(!isPrimaryPlayEnabled)
        .accessibilityHint(
            SeriesPrimaryPlayPolicy.accessibilityHint(
                mediaType: mediaType,
                hasSelectedEpisode: viewModel.selectedEpisode != nil
            )
        )
    }

    private var watchStateRow: some View {
        let state = viewModel.currentWatchStatusState
        let actionTitle = state.isWatched ? "Mark Unwatched" : "Mark Watched"

        return Button {
            Task { await viewModel.toggleCurrentWatchState() }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: watchStatusIcon(for: state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(watchStatusColor(for: state))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch Status")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))

                        Text(state.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }

                Spacer()

                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(actionTitle)
        .accessibilityHint("Updates the watched state for this title.")
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private var currentEpisodeRow: some View {
        if let episode = viewModel.selectedEpisode {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 8) {
                    Text(SeriesDetailPresentationPolicy.episodeContextText(
                        season: viewModel.selectedSeason,
                        episodeNumber: episode.episodeNumber
                    ))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.9))

                    if let episodeTitle = episode.title, !episodeTitle.isEmpty {
                        Text(episodeTitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if let runtimeText = SeriesDetailPresentationPolicy.episodeRuntimeText(minutes: episode.runtime) {
                        Text(runtimeText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                if mediaType == .series {
                    watchStatusBadge(for: selectedEpisodeWatchState)
                }
            }
            .padding(.top, 8)
        } else if mediaType == .series, !viewModel.episodes.isEmpty {
            Text("Select an episode to load streams and update watched state.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 8)
        } else if mediaType == .series, viewModel.isLoading(.seasonEpisodes) {
            Text(SeriesSeasonLoadingPresentationPolicy.loadingTitle(for: viewModel.selectedSeason))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 8)
            }
    }

    private var seriesTrackingRow: some View {
        HStack(alignment: .center, spacing: 12) {
            if viewModel.selectedEpisode != nil {
                Label("Press and hold an episode for watch options.", systemImage: "hand.point.up.left.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                Label("Select an episode, then press and hold it for watched options.", systemImage: "hand.point.up.left.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            Menu {
                if viewModel.selectedEpisode != nil {
                    Section("Episode") {
                        Button {
                            Task { await viewModel.toggleCurrentWatchState() }
                        } label: {
                            Label(
                                SeriesDetailPresentationPolicy.episodeWatchActionTitle(
                                    isWatched: selectedEpisodeWatchState.isWatched
                                ),
                                systemImage: selectedEpisodeWatchState.isWatched ? "xmark.circle" : "checkmark.circle"
                            )
                        }
                    }
                }

                Section("Series") {
                    Button {
                        Task { await viewModel.markSeriesWatched() }
                    } label: {
                        Label("Mark Series as Watched", systemImage: "checkmark.circle.fill")
                    }

                    Button(role: .destructive) {
                        Task { await viewModel.markSeriesUnwatched() }
                    } label: {
                        Label("Mark Series as Unwatched", systemImage: "xmark.circle")
                    }
                }

                Section("Season") {
                    Button {
                        Task { await viewModel.markSeasonWatched() }
                    } label: {
                        Label("Mark Season as Watched", systemImage: "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        Task { await viewModel.markSeasonUnwatched() }
                    } label: {
                        Label("Mark Season as Unwatched", systemImage: "xmark.circle")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                    Text(seriesWatchProgressLabel)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Series watch actions")
            .accessibilityHint("Opens episode, season, and series watched options.")
        }
        .padding(.top, 4)
    }
    
    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text("Seasons")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                if viewModel.isLoading(.seasonEpisodes) {
                    InlineLoadingStatusView(title: SeriesSeasonLoadingPresentationPolicy.loadingTitle(for: viewModel.selectedSeason))
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.seasons, id: \.id) { season in
                        seasonTab(season: season)
                    }
                }
            }
            .allowsHitTesting(!viewModel.isLoading(.seasonEpisodes))
        }
        .padding(.top, 24)
    }
    
    private func seasonTab(season: Season) -> some View {
        let isSelected = viewModel.selectedSeason == season.seasonNumber
        
        return Button {
            Task {
                await viewModel.loadSeason(season.seasonNumber, apiKey: tmdbApiKey)
            }
        } label: {
            Text("\(season.seasonNumber)")
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.15)),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading(.seasonEpisodes))
        .animation(.spring(response: 0.3), value: viewModel.selectedSeason)
    }
    
    private func episodesSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text("Episodes")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                if viewModel.isLoading(.seasonEpisodes) {
                    InlineLoadingStatusView(title: "Refreshing episode list…")
                }
            }

            if viewModel.isLoading(.seasonEpisodes) && viewModel.episodes.isEmpty {
                seasonLoadingEpisodePlaceholders

                Text(SeriesSeasonLoadingPresentationPolicy.loadingMessage(for: viewModel.selectedSeason))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(viewModel.episodes) { episode in
                            episodeCard(episode: episode)
                        }
                    }
                }
                .allowsHitTesting(!viewModel.isLoading(.seasonEpisodes))
            }
        }
        .padding(.top, 16)
    }
    
    private func episodeCard(episode: Episode) -> some View {
        let isSelected = viewModel.selectedEpisode?.id == episode.id
        let watchState = viewModel.episodeWatchStates[episode.id]
        let isWatched = watchState?.isCompleted == true
        let progress = watchState?.progress ?? 0
        
        return Button {
            viewModel.selectEpisode(episode)
            Task {
                await viewModel.searchTorrents()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
            // Thumbnail container
                ZStack(alignment: .bottomLeading) {
                // Thumbnail
                    if let stillURL = episode.stillURL {
                        AsyncImage(url: stillURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(16/9, contentMode: .fill)
                            default:
                                Rectangle()
                                    .fill(.gray.opacity(0.3))
                            }
                        }
                        .frame(width: 240, height: 135)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Rectangle()
                            .fill(.gray.opacity(0.3))
                            .frame(width: 240, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                
                    // Progress bar (uses scaleEffect instead of GeometryReader to avoid layout thrashing)
                    if progress > 0 && progress < 1 {
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.tint.opacity(0.3))
                                .frame(height: 3)
                            Rectangle()
                                .fill(.tint)
                                .frame(maxWidth: .infinity)
                                .scaleEffect(x: progress, y: 1, anchor: .leading)
                                .frame(height: 3)
                        }
                        .frame(height: 3)
                    }
                
                    // Watched badge (checkmark)
                    if isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                
                    // Episode number badge
                    Text("\(episode.episodeNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(8)
                }
                .frame(width: 240, height: 135)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                )
            
                // Episode info
                VStack(alignment: .leading, spacing: 4) {
                    Text(SeriesDetailPresentationPolicy.episodeTitle(
                        episode.title,
                        episodeNumber: episode.episodeNumber
                    ))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                
                    if let runtime = episode.runtime, runtime > 0 {
                        Text("\(runtime)m")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                            .font(.caption2.weight(.semibold))
                        Text(SeriesDetailPresentationPolicy.episodeWatchLabel(isWatched: isWatched))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(isWatched ? .green : .white.opacity(0.62))
                }
                .frame(width: 240, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await viewModel.toggleEpisodeWatched(episode) }
            } label: {
                Label(
                    SeriesDetailPresentationPolicy.episodeWatchActionTitle(isWatched: isWatched),
                    systemImage: isWatched ? "xmark.circle" : "checkmark.circle"
                )
            }
        }
        .accessibilityLabel(SeriesDetailPresentationPolicy.episodeAccessibilityLabel(
            episodeNumber: episode.episodeNumber,
            title: episode.title
        ))
        .accessibilityValue(SeriesDetailPresentationPolicy.episodeAccessibilityValue(
            isWatched: isWatched,
            isSelected: isSelected
        ))
        .accessibilityHint("Opens this episode and refreshes available streams. Press and hold for watched options.")
    }
    
    private var seasonLoadingEpisodePlaceholders: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(width: 240, height: 135, cornerRadius: 8)
                        SkeletonBlock(width: 180, height: 16, cornerRadius: 6)
                        SkeletonBlock(width: 72, height: 12, cornerRadius: 6)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func utilityGlyph(name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18))
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
    }

    private func watchStatusIcon(for state: DetailWatchStatusState) -> String {
        SeriesDetailPresentationPolicy.watchStatusIcon(for: state)
    }

    private func watchStatusColor(for state: DetailWatchStatusState) -> Color {
        switch state {
        case .watched:
            return .green
        case .inProgress:
            return .yellow
        case .notWatched:
            return .white.opacity(0.65)
        case .selectionRequired:
            return .white.opacity(0.75)
        }
    }

    private var selectedEpisodeWatchState: DetailWatchStatusState {
        guard let selectedEpisode = viewModel.selectedEpisode else {
            return SeriesDetailPresentationPolicy.selectedEpisodeWatchState(
                hasSelectedEpisode: false,
                isSelectedEpisodeCompleted: false
            )
        }
        return SeriesDetailPresentationPolicy.selectedEpisodeWatchState(
            hasSelectedEpisode: true,
            isSelectedEpisodeCompleted: viewModel.episodeWatchStates[selectedEpisode.id]?.isCompleted == true
        )
    }

    private var seriesWatchProgressLabel: String {
        SeriesDetailPresentationPolicy.seriesWatchProgressLabel(
            watchedCount: viewModel.episodeWatchStates.count,
            seasonEpisodeCounts: viewModel.seasons.map(\.episodeCount)
        )
    }

    private func watchStatusBadge(for state: DetailWatchStatusState) -> some View {
        HStack(spacing: 6) {
            Image(systemName: watchStatusIcon(for: state))
                .font(.caption.weight(.semibold))
            Text(state.label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(watchStatusColor(for: state))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private func genrePills(_ genres: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(genres.prefix(4)), id: \.self) { genre in
                    Text(genre)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
        }
    }
    
    private var torrentsSection: some View {
        DetailTorrentsSection(
            viewModel: viewModel,
            mediaType: mediaType,
            streamResultsAnchor: streamResultsAnchor,
            isPlayerOpening: $isPlayerOpening,
            playerOpeningError: $playerOpeningError,
            onPlayTorrent: onPlayTorrent
        )
        .padding(.top, 32)
    }
}
