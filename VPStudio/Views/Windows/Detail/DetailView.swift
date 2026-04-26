import Combine
import SwiftUI

enum DetailInitialAction: String, Hashable, Sendable {
    case none
    case resumePlayback
}

enum DetailAutoSearchPolicy {
    static func shouldAutoSearch(
        previewType: MediaType,
        hasMediaItem: Bool,
        hasSelectedEpisode: Bool,
        hasExplicitEpisodeContext: Bool
    ) -> Bool {
        guard hasMediaItem else { return false }
        if previewType == .movie {
            return true
        }

        // Series detail can hydrate a lot of late-arriving content on first open
        // (episode context, stream results, cache enrichment). Requiring an
        // explicit follow-up action keeps the initial scroll container stable.
        let _ = hasSelectedEpisode
        let _ = hasExplicitEpisodeContext
        return false
    }
}

enum DetailInitialRenderPolicy {
    static func shouldShowContent(
        hasViewModel: Bool,
        isPreparingInitialPresentation: Bool
    ) -> Bool {
        hasViewModel && !isPreparingInitialPresentation
    }
}

enum DetailRefreshLoadingPresentationPolicy {
    static let refreshTitle = "Refreshing Details"

    static func shouldShowBlockingOverlay(
        isLoadingDetail: Bool,
        isLoadingSeasonEpisodes: Bool,
        hasMediaItem: Bool
    ) -> Bool {
        let _ = isLoadingSeasonEpisodes
        return isLoadingDetail && !hasMediaItem
    }

    static func shouldShowRefreshIndicator(
        isLoadingDetail: Bool,
        isLoadingSeasonEpisodes: Bool,
        hasMediaItem: Bool
    ) -> Bool {
        isLoadingDetail && hasMediaItem && !isLoadingSeasonEpisodes
    }
}

enum DetailPresentationPolicy {
    static let activeSessionToastText = "A video is already playing"

    static func yearText(_ year: Int?) -> String? {
        year.map(String.init)
    }

    static func imdbRatingText(_ rating: Double?) -> String? {
        guard let rating, rating > 0 else { return nil }
        return String(format: "%.1f", rating)
    }

    static func runtimeText(_ runtimeString: String?) -> String? {
        guard let runtimeString, !runtimeString.isEmpty else { return nil }
        return runtimeString
    }

    static func feedbackDraftValue(currentValue: Double?, scaleMode: FeedbackScaleMode) -> Double {
        if let currentValue {
            return scaleMode.clamp(currentValue)
        }
        return scaleMode.maximumValue
    }

    static func shareItem(
        previewID: String,
        previewTitle: String,
        previewType: MediaType,
        previewTMDBID: Int?,
        mediaTitle: String?,
        mediaTMDBID: Int?
    ) -> String {
        let baseTitle = mediaTitle ?? previewTitle
        if previewID.hasPrefix("tt") {
            return "\(baseTitle)\nhttps://www.imdb.com/title/\(previewID)/"
        }
        if let tmdbId = mediaTMDBID ?? previewTMDBID {
            let path = previewType == .movie ? "movie" : "tv"
            return "\(baseTitle)\nhttps://www.themoviedb.org/\(path)/\(tmdbId)"
        }
        return baseTitle
    }
}

struct DetailView: View {
    let preview: MediaPreview
    let initialAction: DetailInitialAction
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @State private var viewModel: DetailViewModel?
    @State private var tmdbApiKey = ""
    @State private var isShowingRatingSheet = false
    @State private var draftFeedbackValue: Double = 1
    @State private var tmdbReloadTask: Task<Void, Never>?
    @State private var libraryReloadTask: Task<Void, Never>?
    @State private var feedbackReloadTask: Task<Void, Never>?
    @State private var downloadsReloadTask: Task<Void, Never>?
    @State private var streamResolutionTask: Task<Void, Never>?
    @State private var showActiveSessionToast = false
    @State private var activeSessionToastTask: Task<Void, Never>?
    @State private var didRunQAActions = false
    /// True from the moment a play button is clicked until the player window has taken over.
    /// Used to disable all play buttons and prevent double-taps during player launch.
    @State private var isPlayerOpening = false
    /// Error message to show when player fails to open.
    @State private var playerOpeningError: String?
    @State private var isPreparingInitialPresentation = true
    @State private var hasHandledInitialAction = false
    private let streamResultsAnchor = "detail-stream-results-anchor"

    init(preview: MediaPreview, initialAction: DetailInitialAction = .none) {
        self.preview = preview
        self.initialAction = initialAction
    }

    private var shouldShowDetailContent: Bool {
        return DetailInitialRenderPolicy.shouldShowContent(
            hasViewModel: viewModel != nil,
            isPreparingInitialPresentation: isPreparingInitialPresentation
        )
    }

    var body: some View {
        Group {
            if let vm = viewModel, shouldShowDetailContent {
                detailContent(vm)
                    .transition(.opacity)
            } else {
                DetailSkeletonView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: shouldShowDetailContent)
        .task(id: previewTaskIdentity) {
            isPreparingInitialPresentation = true
            didRunQAActions = false
            hasHandledInitialAction = false
            await reloadDetailForLatestTMDBKey()
            guard !Task.isCancelled else { return }
            isPreparingInitialPresentation = false
        }
        .onDisappear {
            viewModel?.cancelInFlightWork()
            tmdbReloadTask?.cancel()
            tmdbReloadTask = nil
            libraryReloadTask?.cancel()
            libraryReloadTask = nil
            feedbackReloadTask?.cancel()
            feedbackReloadTask = nil
            downloadsReloadTask?.cancel()
            downloadsReloadTask = nil
            streamResolutionTask?.cancel()
            streamResolutionTask = nil
            activeSessionToastTask?.cancel()
            activeSessionToastTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .tmdbApiKeyDidChange)) { _ in
            tmdbReloadTask?.cancel()
            tmdbReloadTask = Task { await reloadDetailForLatestTMDBKey() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in
            guard let vm = viewModel else { return }
            libraryReloadTask?.cancel()
            libraryReloadTask = Task { await vm.reloadLibraryState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            guard let vm = viewModel else { return }
            libraryReloadTask?.cancel()
            libraryReloadTask = Task { await vm.reloadLibraryState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tasteProfileDidChange)) { _ in
            guard let vm = viewModel else { return }
            feedbackReloadTask?.cancel()
            feedbackReloadTask = Task { await vm.reloadFeedbackState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadsDidChange)) { _ in
            guard let vm = viewModel else { return }
            downloadsReloadTask?.cancel()
            downloadsReloadTask = Task { await vm.refreshDownloadStates() }
        }
        .sheet(isPresented: $isShowingRatingSheet) {
            if let vm = viewModel {
                DetailRatingSheet(
                    viewModel: vm,
                    isShowing: $isShowingRatingSheet,
                    draftFeedbackValue: $draftFeedbackValue
                )
            }
        }
    }

    @MainActor
    private func reloadDetailForLatestTMDBKey() async {
        let key = (try? await appState.settingsManager.getString(key: SettingsKeys.tmdbApiKey)) ?? ""
        tmdbApiKey = key

        let vm: DetailViewModel
        if let existingViewModel = viewModel {
            vm = existingViewModel
        } else {
            let created = DetailViewModel(appState: appState)
            viewModel = created
            vm = created
        }

        vm.setPreviewContext(preview)
        await vm.loadDetail(preview: preview, apiKey: key)

        // Auto-search streams once metadata loads for movies only.
        // Series wait for an explicit follow-up action such as Play or episode tap.
        if DetailAutoSearchPolicy.shouldAutoSearch(
            previewType: preview.type,
            hasMediaItem: vm.mediaItem != nil,
            hasSelectedEpisode: vm.selectedEpisode != nil,
            hasExplicitEpisodeContext: preview.episodeId != nil || preview.episodeNumber != nil
        ) {
            await vm.searchTorrents()
        }

        if !QARuntimeOptions.isEnabled {
            await runInitialActionIfNeeded(vm)
        }

        await runQAActionsIfNeeded(vm)
    }

    @ViewBuilder
    private func detailContent(_ vm: DetailViewModel) -> some View {
        SeriesDetailLayout(
            viewModel: vm,
            title: preview.title,
            tmdbApiKey: tmdbApiKey,
            mediaType: preview.type,
            streamResultsAnchor: streamResultsAnchor,
            shareItem: detailShareItem(vm),
            isPlayerOpening: $isPlayerOpening,
            playerOpeningError: $playerOpeningError,
            onPlayTorrent: { torrent in
                playTorrent(torrent, vm: vm)
            },
            onCast: {
                castBestAvailable(vm)
            },
            onShowRatingSheet: {
                prepareFeedbackDraft(vm)
                isShowingRatingSheet = true
            }
        )
        // Force a fresh detail scroll container per preview so a newly opened
        // show does not inherit the prior title's vertical offset.
        .id(previewTaskIdentity)
        .navigationTitle(preview.title)
        .overlay {
            if DetailRefreshLoadingPresentationPolicy.shouldShowBlockingOverlay(
                isLoadingDetail: vm.isLoading(.detail),
                isLoadingSeasonEpisodes: vm.isLoading(.seasonEpisodes),
                hasMediaItem: vm.mediaItem != nil
            ) {
                LoadingOverlay(
                    title: vm.isLoading(.seasonEpisodes) ? "Loading Episodes" : "Loading Details",
                    message: "Fetching metadata and availability."
                )
            } else {
                EmptyView()
            }
        }
        .overlay(alignment: .top) {
            if DetailRefreshLoadingPresentationPolicy.shouldShowRefreshIndicator(
                isLoadingDetail: vm.isLoading(.detail),
                isLoadingSeasonEpisodes: vm.isLoading(.seasonEpisodes),
                hasMediaItem: vm.mediaItem != nil
            ) {
                InlineLoadingStatusView(title: DetailRefreshLoadingPresentationPolicy.refreshTitle)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                EmptyView()
            }
        }
        .appErrorAlert(
            "Detail Error",
            error: Binding(
                get: { vm.error },
                set: { vm.error = $0 }
            ),
            onRetry: {
                Task { await vm.retryLastFailedOperation(apiKey: tmdbApiKey) }
            }
        )
        .overlay(alignment: .top) {
            if showActiveSessionToast {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.caption.weight(.semibold))
                    Text(DetailPresentationPolicy.activeSessionToastText)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showActiveSessionToast)
    }

    @ViewBuilder
    private func metadataRow(_ vm: DetailViewModel) -> some View {
        HStack(spacing: 16) {
            if let year = vm.mediaItem?.year {
                Label(DetailPresentationPolicy.yearText(year) ?? "", systemImage: "calendar")
                    .font(.subheadline)
            }
            if let rating = DetailPresentationPolicy.imdbRatingText(vm.mediaItem?.imdbRating) {
                Label(rating, systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            }
            if let runtime = DetailPresentationPolicy.runtimeText(vm.mediaItem?.runtimeString) {
                Label(runtime, systemImage: "clock")
                    .font(.subheadline)
            }
            if let status = vm.mediaItem?.status {
                GlassTag(text: status)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func prepareFeedbackDraft(_ vm: DetailViewModel) {
        draftFeedbackValue = DetailPresentationPolicy.feedbackDraftValue(
            currentValue: vm.currentFeedbackValue,
            scaleMode: vm.feedbackScaleMode
        )
    }

    private func detailShareItem(_ vm: DetailViewModel) -> String {
        DetailPresentationPolicy.shareItem(
            previewID: preview.id,
            previewTitle: preview.title,
            previewType: preview.type,
            previewTMDBID: preview.tmdbId,
            mediaTitle: vm.mediaItem?.title,
            mediaTMDBID: vm.mediaItem?.tmdbId
        )
    }

    private func castBestAvailable(_ vm: DetailViewModel) {
        guard appState.activePlayerSession == nil else {
            showActiveSessionToast(for: appState.activePlayerSession)
            return
        }

        isPlayerOpening = true
        playerOpeningError = nil

        streamResolutionTask?.cancel()
        streamResolutionTask = Task {
            defer { isPlayerOpening = false }

            if vm.torrentSearch.results.isEmpty {
                await vm.searchTorrents()
            }

            guard let torrent = vm.torrentSearch.results.first else {
                playerOpeningError = "No streams available to cast right now."
                return
            }

            if let stream = await vm.resolveStream(torrent: torrent) {
                await openPlayer(for: stream, vm: vm)
            } else {
                playerOpeningError = "Could not open stream for casting."
            }
        }
    }

    private func playTorrent(_ torrent: TorrentResult, vm: DetailViewModel) {
        guard appState.activePlayerSession == nil else {
            showActiveSessionToast(for: appState.activePlayerSession)
            return
        }

        // Immediately disable all play buttons and clear any previous error
        isPlayerOpening = true
        playerOpeningError = nil

        streamResolutionTask?.cancel()
        streamResolutionTask = Task {
            defer { isPlayerOpening = false }
            if let stream = await vm.resolveStream(torrent: torrent) {
                await openPlayer(for: stream, vm: vm)
            } else {
                // Stream resolution returned nil — show error in the row
                playerOpeningError = "Could not open stream. Please try another result."
            }
        }
    }
}

private extension DetailView {
    var previewTaskIdentity: String {
        [
            preview.type.rawValue,
            preview.id,
            preview.tmdbId.map(String.init) ?? "none",
            preview.episodeId ?? "none",
            preview.seasonNumber.map(String.init) ?? "none",
            preview.episodeNumber.map(String.init) ?? "none",
            initialAction.rawValue
        ].joined(separator: "-")
    }

    @MainActor
    func runInitialActionIfNeeded(_ vm: DetailViewModel) async {
        guard !hasHandledInitialAction else { return }
        hasHandledInitialAction = true

        guard initialAction == .resumePlayback else { return }
        guard vm.mediaItem != nil else { return }

        if preview.type == .series, vm.selectedEpisode == nil {
            playerOpeningError = "Pick an episode to continue watching."
            return
        }

        guard appState.activePlayerSession == nil else {
            showActiveSessionToast(for: appState.activePlayerSession)
            return
        }

        isPlayerOpening = true
        playerOpeningError = nil
        defer { isPlayerOpening = false }

        if vm.torrentSearch.results.isEmpty {
            await vm.searchTorrents()
        }

        guard let torrent = vm.torrentSearch.results.first else {
            playerOpeningError = "No streams are available to resume right now."
            return
        }

        if let stream = await vm.resolveStream(torrent: torrent) {
            await openPlayer(for: stream, vm: vm)
        } else {
            playerOpeningError = "Could not resume playback right now."
        }
    }

    @MainActor
    func runQAActionsIfNeeded(_ vm: DetailViewModel) async {
        guard QARuntimeOptions.isEnabled else { return }
        guard !didRunQAActions else { return }
        guard vm.mediaItem != nil else { return }
        didRunQAActions = true

        if preview.type == .series {
            if let season = QARuntimeOptions.selectedSeason, season != vm.selectedSeason {
                await vm.loadSeason(season, apiKey: tmdbApiKey)
            }

            if let episodeNumber = QARuntimeOptions.selectedEpisode,
               let episode = vm.episodes.first(where: { $0.episodeNumber == episodeNumber }) {
                vm.selectEpisode(episode)
                await vm.searchTorrents()
            }
        }

        if QARuntimeOptions.autoAddWatchlist, !vm.isInWatchlist {
            await vm.toggleWatchlist()
        }
        if QARuntimeOptions.autoAddFavorites, !vm.isInFavorites {
            await vm.toggleFavorites()
        }
        if QARuntimeOptions.autoRemoveWatchlist, vm.isInWatchlist {
            await vm.removeFromLibrary(listType: .watchlist)
        }
        if QARuntimeOptions.autoRemoveFavorites, vm.isInFavorites {
            await vm.removeFromLibrary(listType: .favorites)
        }

        if let syntheticTorrent = QARuntimeOptions.syntheticTorrent {
            vm.torrents = [syntheticTorrent]
            vm.didSearch = true

            if QARuntimeOptions.autoPlaySyntheticTorrent,
               let stream = await vm.resolveStream(torrent: syntheticTorrent) {
                await openPlayer(for: stream, vm: vm)
            }
            return
        }

        guard let sampleStreams = makeQASampleStreams(using: vm),
              let sampleStream = sampleStreams.first else { return }

        if QARuntimeOptions.autoQueueSampleDownload {
            await queueQASampleDownload(sampleStream, vm: vm)
        }

        if QARuntimeOptions.autoPlaySample {
            await openPlayer(for: sampleStream, availableStreams: sampleStreams, vm: vm)
        }
    }

    func makeQASampleStreams(using vm: DetailViewModel) -> [StreamInfo]? {
        let sampleURLs = QARuntimeOptions.sampleURLs
        guard !sampleURLs.isEmpty else { return nil }
        let mediaTitle = vm.mediaItem?.title ?? preview.title
        let fileName: String
        if preview.type == .series,
           let selectedEpisode = vm.selectedEpisode {
            fileName = "\(mediaTitle)-S\(String(format: "%02d", selectedEpisode.seasonNumber))E\(String(format: "%02d", selectedEpisode.episodeNumber)).mp4"
        } else {
            fileName = "\(mediaTitle).mp4"
        }

        return sampleURLs.map { sampleURL in
            StreamInfo(
                streamURL: sampleURL,
                quality: .hd720p,
                codec: .h264,
                audio: .aac,
                source: .webDL,
                hdr: .sdr,
                fileName: fileName,
                sizeBytes: nil,
                debridService: "qa-sample"
            )
        }
    }

    @MainActor
    func queueQASampleDownload(_ stream: StreamInfo, vm: DetailViewModel) async {
        guard let item = vm.mediaItem else { return }
        _ = try? await appState.downloadManager.enqueueDownload(
            stream: stream,
            mediaId: item.id,
            episodeId: preview.type == .series ? vm.selectedEpisode?.id : nil,
            mediaTitle: item.title,
            mediaType: item.type.rawValue,
            posterPath: item.posterPath,
            seasonNumber: preview.type == .series ? vm.selectedEpisode?.seasonNumber : nil,
            episodeNumber: preview.type == .series ? vm.selectedEpisode?.episodeNumber : nil,
            episodeTitle: preview.type == .series ? vm.selectedEpisode?.title : nil
        )
        NotificationCenter.default.post(name: .downloadsDidChange, object: nil)
    }

    func openPlayer(
        for stream: StreamInfo,
        availableStreams: [StreamInfo]? = nil,
        vm: DetailViewModel
    ) async {
        guard appState.activePlayerSession == nil else {
            showActiveSessionToast(for: appState.activePlayerSession)
            return
        }

        guard !Task.isCancelled else { return }
        let request = vm.makePlayerSessionRequest(
            stream: stream,
            preview: preview,
            availableStreams: availableStreams
        )
        if await launchWithPreferredPlayer(for: request.stream.streamURL) {
            return
        }
        guard !Task.isCancelled else { return }

        await MainActor.run {
            appState.activePlayerSession = request
            openWindow(id: "player", value: request)
        }
    }

    @MainActor
    func launchWithPreferredPlayer(for streamURL: URL) async -> Bool {
        let preference = await ExternalPlayerSettings.loadPreference(from: appState.settingsManager)
        guard let launchURL = ExternalPlayerRouting.launchURL(for: streamURL, preference: preference) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            openURL(launchURL) { accepted in
                continuation.resume(returning: accepted)
            }
        }
    }

    func showActiveSessionToast(for session: PlayerSessionRequest?) {
        activeSessionToastTask?.cancel()
        showActiveSessionToast = true
        activeSessionToastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            showActiveSessionToast = false
        }
    }

}
