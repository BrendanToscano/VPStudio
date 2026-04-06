import SwiftUI
import Combine

private enum SeriesDetailQAScrollDebug {
    static let coordinateSpace = "series-detail-scroll-space"

    static func log(_ message: @autoclosure () -> String) {
        guard QARuntimeOptions.scrollDebug else { return }
        print("[VPStudio QA Scroll] \(message())")
    }
}

private struct SeriesDetailTopOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum SeriesPrimaryPlayPolicy {
    static let noStreamsMessage = "No streams found for this episode. Try another episode or result."

    static func isBusy(
        isLocalPlayLoading: Bool,
        isPlayerOpening: Bool,
        isLoadingSeasonEpisodes: Bool
    ) -> Bool {
        isLocalPlayLoading || isPlayerOpening || isLoadingSeasonEpisodes
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
    @State private var lastLoggedTopOffset: CGFloat?

    private var isPrimaryPlayBusy: Bool {
        SeriesPrimaryPlayPolicy.isBusy(
            isLocalPlayLoading: isPlayButtonLoading,
            isPlayerOpening: isPlayerOpening,
            isLoadingSeasonEpisodes: viewModel.isLoading(.seasonEpisodes)
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
                qaScrollTopMarker
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

                    // Current episode info
                    currentEpisodeRow

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
        .coordinateSpace(name: SeriesDetailQAScrollDebug.coordinateSpace)
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
        .onPreferenceChange(SeriesDetailTopOffsetPreferenceKey.self) { topOffset in
            guard QARuntimeOptions.scrollDebug else { return }
            let rounded = (topOffset * 10).rounded() / 10
            if let lastLoggedTopOffset, abs(lastLoggedTopOffset - rounded) < 4 {
                return
            }
            lastLoggedTopOffset = rounded
            SeriesDetailQAScrollDebug.log("topOffset=\(rounded)")
        }
    }
    
    // MARK: - Subviews

    private var qaScrollTopMarker: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: SeriesDetailTopOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(SeriesDetailQAScrollDebug.coordinateSpace)).minY
                )
        }
        .frame(height: 0)
    }
    
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
                
                Spacer()
                
                // Utility icons
                HStack(spacing: 12) {
                    ShareLink(item: shareItem) {
                        utilityGlyph(name: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.toggleWatchlist() }
                    } label: {
                        utilityGlyph(name: viewModel.isInWatchlist ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.plain)

                    Button(action: onCast) {
                        utilityGlyph(name: "airplayvideo")
                    }
                    .buttonStyle(.plain)

                    Button(action: onShowRatingSheet) {
                        utilityGlyph(name: viewModel.currentFeedbackValue != nil ? "star.fill" : "star")
                    }
                    .buttonStyle(.plain)
                    
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
                let seasonCount = viewModel.seasons.count
                Text("\(seasonCount) Season\(seasonCount > 1 ? "s" : "")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let runtime = viewModel.mediaItem?.runtime, runtime > 0 {
                Text("\(runtime) min")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            
            if let rating = viewModel.mediaItem?.imdbRating, rating > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f IMDb", rating))
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
        }
    }
    
    private var playButtonRow: some View {
        Button {
            guard !isPrimaryPlayBusy else { return }
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
                    Text("Play")
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
        .disabled(isPrimaryPlayBusy)
    }
    
    @ViewBuilder
    private var currentEpisodeRow: some View {
        if let episode = viewModel.selectedEpisode ?? viewModel.episodes.first {
            HStack(spacing: 8) {
                Text("S\(viewModel.selectedSeason):E\(episode.episodeNumber)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.9))
                
                if let episodeTitle = episode.title, !episodeTitle.isEmpty {
                    Text(episodeTitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                if let runtime = episode.runtime, runtime > 0 {
                    Text("• \(runtime)m")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.top, 8)
        } else if mediaType == .series, viewModel.isLoading(.seasonEpisodes) {
            Text(SeriesSeasonLoadingPresentationPolicy.loadingTitle(for: viewModel.selectedSeason))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 8)
        }
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
        
        return VStack(alignment: .leading, spacing: 8) {
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
                Text(episode.title ?? "Episode \(episode.episodeNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if let runtime = episode.runtime, runtime > 0 {
                    Text("\(runtime)m")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 240, alignment: .leading)
        }
        .onTapGesture {
            viewModel.selectEpisode(episode)
            Task {
                await viewModel.searchTorrents()
            }
        }
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
