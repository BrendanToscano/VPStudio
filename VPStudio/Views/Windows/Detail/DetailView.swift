import Combine
import SwiftUI

struct DetailView: View {
    let preview: MediaPreview
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
    @State private var streamResolutionTask: Task<Void, Never>?
    @State private var showActiveSessionToast = false
    @State private var activeSessionToastTask: Task<Void, Never>?
    private let streamResultsAnchor = "detail-stream-results-anchor"

    var body: some View {
        Group {
            if let vm = viewModel {
                detailContent(vm)
                    .transition(.opacity)
            } else {
                DetailSkeletonView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel != nil)
        .task(id: previewTaskIdentity) {
            await reloadDetailForLatestTMDBKey()
        }
        .onDisappear {
            viewModel?.cancelInFlightWork()
            tmdbReloadTask?.cancel()
            tmdbReloadTask = nil
            libraryReloadTask?.cancel()
            libraryReloadTask = nil
            feedbackReloadTask?.cancel()
            feedbackReloadTask = nil
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
        .onReceive(NotificationCenter.default.publisher(for: .tasteProfileDidChange)) { _ in
            guard let vm = viewModel else { return }
            feedbackReloadTask?.cancel()
            feedbackReloadTask = Task { await vm.reloadFeedbackState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadsDidChange)) { _ in
            guard let vm = viewModel else { return }
            Task { await vm.refreshDownloadStates() }
        }
        .sheet(isPresented: $isShowingRatingSheet) {
            if let vm = viewModel {
                feedbackSheet(vm)
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

        // Auto-search streams once metadata loads.
        // For movies, search immediately. For series, search once the first episode is selected.
        if vm.mediaItem != nil, vm.selectedEpisode != nil || preview.type == .movie {
            await vm.searchTorrents()
        }
    }

    @ViewBuilder
    private func detailContent(_ vm: DetailViewModel) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero backdrop
                    heroSection(vm, scrollProxy: scrollProxy)

                    VStack(alignment: .leading, spacing: 24) {
                        // Metadata row
                        metadataRow(vm)

                        // Overview
                        if let overview = vm.mediaItem?.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        // AI Personalized Analysis
                        aiAnalysisSection(vm)

                        // Genres
                        if let genres = vm.mediaItem?.genres, !genres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(genres, id: \.self) { genre in
                                        GlassTag(text: genre)
                                    }
                                }
                            }
                        }

                        // Seasons picker for TV
                        if preview.type == .series, !vm.seasons.isEmpty {
                            seasonsSection(vm, scrollProxy: scrollProxy)
                        }

                        // Torrent results
                        torrentsSection(vm)
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(preview.title)
        .overlay {
            if vm.isLoading(.detail) || vm.isLoading(.seasonEpisodes) {
                LoadingOverlay(
                    title: vm.isLoading(.seasonEpisodes) ? "Loading Episodes" : "Loading Details",
                    message: "Fetching metadata and availability."
                )
            }
        }
        .appErrorAlert(
            "Detail Error",
            error: Binding(
                get: { vm.error },
                set: { vm.error = $0 }
            ),
            onRetry: {
                Task { await vm.searchTorrents() }
            }
        )
        .overlay(alignment: .top) {
            if showActiveSessionToast {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.caption.weight(.semibold))
                    Text("A video is already playing")
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
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showActiveSessionToast)
    }

    @ViewBuilder
    private func heroSection(_ vm: DetailViewModel, scrollProxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = vm.mediaItem?.backdropURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .frame(height: 400)
                            .clipped()
                            .transition(.opacity)
                    default:
                        Rectangle()
                            .fill(.quaternary)
                            .frame(height: 400)
                    }
                }
                .animation(.easeIn(duration: 0.5), value: url)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 400)
            }

            // Cinematic 4-stop gradient fade
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
            .frame(height: 280)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                Text(preview.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 16) {
                    Button {
                        Task { await vm.toggleWatchlist() }
                    } label: {
                        Label(
                            vm.mediaLibrary.isInWatchlist ? "In Watchlist" : "Add to Watchlist",
                            systemImage: vm.mediaLibrary.isInWatchlist ? "checkmark" : "plus"
                        )
                    }
                    .buttonStyle(.bordered)
                    #if os(visionOS)
                    .hoverEffect(.lift)
                    #endif

                    Button {
                        Task { await vm.toggleFavorites() }
                    } label: {
                        Label(
                            vm.mediaLibrary.isInFavorites ? "In Favorites" : "Add to Favorites",
                            systemImage: vm.mediaLibrary.isInFavorites ? "heart.fill" : "heart"
                        )
                    }
                    .buttonStyle(.bordered)
                    #if os(visionOS)
                    .hoverEffect(.lift)
                    #endif

                    Button {
                        prepareFeedbackDraft(vm)
                        isShowingRatingSheet = true
                    } label: {
                        Label(vm.currentFeedbackSummary ?? "Rate", systemImage: "star.leadinghalf.filled")
                    }
                    .buttonStyle(.bordered)
                    #if os(visionOS)
                    .hoverEffect(.lift)
                    #endif

                    libraryFoldersMenu(vm)
                }

                if let status = vm.mediaLibrary.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(24)
        }
    }

    private func libraryFoldersMenu(_ vm: DetailViewModel) -> some View {
        Menu {
            Section("Watchlist") {
                if vm.mediaLibrary.isInWatchlist {
                    Button("Remove from Watchlist", systemImage: "minus.circle") {
                        Task { await vm.removeFromLibrary(listType: .watchlist) }
                    }
                }

                if vm.mediaLibrary.watchlistFolders.isEmpty {
                    Button("No folders available") {}
                        .disabled(true)
                } else {
                    ForEach(vm.mediaLibrary.watchlistFolders, id: \.id) { folder in
                        Button(folderMenuLabel(folderName: folder.name, isInList: vm.mediaLibrary.isInWatchlist)) {
                            Task {
                                await vm.addOrMoveToLibrary(
                                    listType: .watchlist,
                                    folderId: folder.id,
                                    folderName: folder.name
                                )
                            }
                        }
                    }
                }
            }

            Section("Favorites") {
                if vm.mediaLibrary.isInFavorites {
                    Button("Remove from Favorites", systemImage: "minus.circle") {
                        Task { await vm.removeFromLibrary(listType: .favorites) }
                    }
                }

                if vm.mediaLibrary.favoriteFolders.isEmpty {
                    Button("No folders available") {}
                        .disabled(true)
                } else {
                    ForEach(vm.mediaLibrary.favoriteFolders, id: \.id) { folder in
                        Button(folderMenuLabel(folderName: folder.name, isInList: vm.mediaLibrary.isInFavorites)) {
                            Task {
                                await vm.addOrMoveToLibrary(
                                    listType: .favorites,
                                    folderId: folder.id,
                                    folderName: folder.name
                                )
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Folders", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.bordered)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    private func folderMenuLabel(folderName: String, isInList: Bool) -> String {
        let verb = isInList ? "Move to" : "Add to"
        return "\(verb) \(folderName)"
    }

    private func prepareFeedbackDraft(_ vm: DetailViewModel) {
        if let current = vm.currentFeedbackValue {
            draftFeedbackValue = vm.feedbackScaleMode.clamp(current)
        } else {
            draftFeedbackValue = vm.feedbackScaleMode.maximumValue
        }
    }

    private func feedbackSheet(_ vm: DetailViewModel) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.feedbackScaleMode == .likeDislike {
                    likeDislikeFeedback(vm)
                } else if vm.feedbackScaleMode == .oneToTen {
                    numberedCircleRating(vm)
                } else {
                    hundredPointRating(vm)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .navigationTitle("Rate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingRatingSheet = false
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 240)
    }

    @ViewBuilder
    private func likeDislikeFeedback(_ vm: DetailViewModel) -> some View {
        VStack(spacing: 20) {
            Text("How do you feel about this?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                likeDislikeButton(
                    icon: "hand.thumbsdown.fill",
                    label: "Dislike",
                    isSelected: vm.currentFeedbackValue == 0,
                    tint: .red
                ) {
                    Task {
                        if vm.currentFeedbackValue == 0 {
                            await vm.clearFeedback()
                        } else {
                            await vm.submitFeedback(value: 0)
                        }
                        isShowingRatingSheet = false
                    }
                }

                likeDislikeButton(
                    icon: "hand.thumbsup.fill",
                    label: "Like",
                    isSelected: vm.currentFeedbackValue == 1,
                    tint: .green
                ) {
                    Task {
                        if vm.currentFeedbackValue == 1 {
                            await vm.clearFeedback()
                        } else {
                            await vm.submitFeedback(value: 1)
                        }
                        isShowingRatingSheet = false
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func likeDislikeButton(
        icon: String,
        label: String,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(isSelected ? tint : .secondary)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? tint : .secondary)
            }
            .frame(width: 90, height: 90)
            .background(
                isSelected ? AnyShapeStyle(tint.opacity(0.18)) : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(tint.opacity(0.5))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.07), radius: 20, y: 0)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    @ViewBuilder
    private func numberedCircleRating(_ vm: DetailViewModel) -> some View {
        let selectedValue = vm.currentFeedbackValue.map { Int($0) }

        VStack(spacing: 20) {
            // Prominent selected value display
            VStack(spacing: 4) {
                if let selected = selectedValue {
                    Text("\(selected)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(ratingGradientColor(for: selected))
                        .contentTransition(.numericText(value: Double(selected)))
                    Text("out of 10")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap to rate")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 68)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedValue)

            // Rating circles row
            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { value in
                    ratingCircle(
                        value: value,
                        isSelected: selectedValue != nil && value <= selectedValue!,
                        isExactSelection: selectedValue == value
                    ) {
                        if selectedValue == value {
                            Task { await vm.clearFeedback() }
                        } else {
                            Task { await vm.submitFeedback(value: Double(value)) }
                        }
                    }
                }
            }

            // Clear button when a rating exists
            if selectedValue != nil {
                Button {
                    Task { await vm.clearFeedback() }
                } label: {
                    Label("Clear Rating", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selectedValue)
    }

    @ViewBuilder
    private func ratingCircle(
        value: Int,
        isSelected: Bool,
        isExactSelection: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? AnyShapeStyle(ratingGradientColor(for: value).opacity(0.85))
                            : AnyShapeStyle(.ultraThinMaterial)
                    )

                Circle()
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(ratingGradientColor(for: value))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ),
                        lineWidth: isExactSelection ? 2 : 0.5
                    )

                Text("\(value)")
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .frame(width: 34, height: 34)
            .frame(minWidth: 44, minHeight: 44) // visionOS eye-tracking minimum
            .contentShape(Circle())
            .scaleEffect(isExactSelection ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .shadow(
            color: isSelected ? ratingGradientColor(for: value).opacity(0.3) : .clear,
            radius: isSelected ? 6 : 0,
            y: 2
        )
        .shadow(color: .black.opacity(isSelected ? 0.12 : 0.06), radius: 4, y: 2)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    private func ratingGradientColor(for value: Int) -> Color {
        // Red(1) -> Orange(3-4) -> Yellow(5-6) -> YellowGreen(7-8) -> Green(9-10)
        let t = Double(value - 1) / 9.0
        if t < 0.25 {
            // Red to Orange
            let localT = t / 0.25
            return Color(
                red: 1.0,
                green: 0.2 + 0.45 * localT,
                blue: 0.15 * (1.0 - localT)
            )
        } else if t < 0.5 {
            // Orange to Yellow
            let localT = (t - 0.25) / 0.25
            return Color(
                red: 1.0 - 0.05 * localT,
                green: 0.65 + 0.2 * localT,
                blue: 0.0 + 0.05 * localT
            )
        } else if t < 0.75 {
            // Yellow to Yellow-Green
            let localT = (t - 0.5) / 0.25
            return Color(
                red: 0.95 - 0.45 * localT,
                green: 0.85 - 0.05 * localT,
                blue: 0.05 + 0.1 * localT
            )
        } else {
            // Yellow-Green to Green
            let localT = (t - 0.75) / 0.25
            return Color(
                red: 0.5 - 0.25 * localT,
                green: 0.8 - 0.05 * localT,
                blue: 0.15 + 0.2 * localT
            )
        }
    }

    @ViewBuilder
    private func hundredPointRating(_ vm: DetailViewModel) -> some View {
        VStack(spacing: 20) {
            // Prominent value display
            VStack(spacing: 4) {
                Text("\(Int(draftFeedbackValue))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: draftFeedbackValue))
                Text("out of 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: Int(draftFeedbackValue))

            // Glass-backed slider track
            VStack(spacing: 12) {
                Slider(
                    value: $draftFeedbackValue,
                    in: 1...100,
                    step: 1
                ) {
                    Text("Rating")
                } onEditingChanged: { isEditing in
                    if !isEditing {
                        Task {
                            await vm.submitFeedback(value: draftFeedbackValue)
                        }
                    }
                }
                .tint(hundredPointColor(for: draftFeedbackValue))

                // Scale labels
                HStack {
                    Text("1")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("50")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("100")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)

            // Clear button
            if vm.currentFeedbackValue != nil {
                Button {
                    Task {
                        await vm.clearFeedback()
                        isShowingRatingSheet = false
                    }
                } label: {
                    Label("Clear Rating", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hundredPointColor(for value: Double) -> Color {
        let t = (value - 1.0) / 99.0
        if t < 0.33 {
            return .red
        } else if t < 0.66 {
            return .yellow
        } else {
            return .green
        }
    }

    @ViewBuilder
    private func metadataRow(_ vm: DetailViewModel) -> some View {
        HStack(spacing: 16) {
            if let year = vm.mediaItem?.year {
                Label(String(year), systemImage: "calendar")
                    .font(.subheadline)
            }
            if let rating = vm.mediaItem?.imdbRating, rating > 0 {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            }
            if let runtime = vm.mediaItem?.runtimeString, !runtime.isEmpty {
                Label(runtime, systemImage: "clock")
                    .font(.subheadline)
            }
            if let status = vm.mediaItem?.status {
                GlassTag(text: status)
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func aiAnalysisSection(_ vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let analysis = vm.aiAnalysis {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: analysis.verdict.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(verdictColor(analysis.verdict))
                        Text(analysis.verdict.label)
                            .font(.headline)
                            .foregroundStyle(verdictColor(analysis.verdict))
                        Spacer()
                        Text(String(format: "%.0f/10", analysis.predictedRating))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                vm.aiAnalysis = nil
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

                    Text(analysis.personalizedDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if !analysis.reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(analysis.reasons, id: \.self) { reason in
                                Label(reason, systemImage: "circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(BulletLabelStyle())
                            }
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if vm.isLoadingAIAnalysis {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing based on your taste profile\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            } else if let aiError = vm.aiAnalysisError {
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
                .transition(.opacity)
            } else if vm.mediaItem != nil {
                Button {
                    Task { await vm.fetchAIAnalysis() }
                } label: {
                    Label("Would I Like This?", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vm.aiAnalysis != nil)
        .animation(.easeInOut(duration: 0.2), value: vm.isLoadingAIAnalysis)
    }

    private func verdictColor(_ verdict: AIPersonalizedAnalysis.Verdict) -> Color {
        switch verdict {
        case .strongYes, .yes: return .green
        case .maybe: return .yellow
        case .no: return .orange
        case .strongNo: return .red
        }
    }

    @ViewBuilder
    private func seasonsSection(_ vm: DetailViewModel, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.seasons, id: \.id) { season in
                        let isSelected = vm.selectedSeason == season.seasonNumber
                        Button {
                            Task { await vm.loadSeason(season.seasonNumber, apiKey: tmdbApiKey) }
                        } label: {
                            Text(season.name)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.ultraThinMaterial),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            isSelected
                                                ? .white.opacity(0.25)
                                                : .white.opacity(0.10),
                                            lineWidth: 0.5
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: vm.selectedSeason)
                        #if os(visionOS)
                        .hoverEffect(.highlight)
                        #endif
                    }
                }
            }

            if !vm.episodes.isEmpty {
                HStack {
                    Text("Episodes")
                        .font(.headline)

                    Spacer()

                    // Season watched progress
                    let watchedCount = vm.episodes.filter { vm.episodeWatchStates[$0.id]?.isCompleted == true }.count
                    if watchedCount > 0 {
                        Text("\(watchedCount)/\(vm.episodes.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Menu {
                        Button {
                            Task { await vm.markSeasonWatched() }
                        } label: {
                            Label("Mark Season as Watched", systemImage: "checkmark.circle")
                        }
                        Button {
                            Task { await vm.markSeasonUnwatched() }
                        } label: {
                            Label("Mark Season as Unwatched", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }

                ForEach(vm.episodes) { episode in
                    Button {
                        let selectedEpisodeID = episode.id
                        vm.selectEpisode(episode)
                        Task {
                            await vm.searchTorrents()
                            guard !Task.isCancelled else { return }
                            guard vm.selectedEpisode?.id == selectedEpisodeID else { return }
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    scrollProxy.scrollTo(streamResultsAnchor, anchor: .top)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            // Watched indicator
                            let watchState = vm.episodeWatchStates[episode.id]
                            let isWatched = watchState?.isCompleted == true

                            Button {
                                Task { await vm.toggleEpisodeWatched(episode) }
                            } label: {
                                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isWatched ? .green : .white.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            #if os(visionOS)
                            .hoverEffect(.highlight)
                            #endif

                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.displayTitle)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(isWatched ? .secondary : .primary)
                                if let overview = episode.overview {
                                    Text(overview)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if let runtime = episode.runtime {
                                Text("\(runtime)m")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            if vm.selectedEpisode?.id == episode.id {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            vm.selectedEpisode?.id == episode.id
                                ? AnyShapeStyle(.tint.opacity(0.15))
                                : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay {
                            if vm.selectedEpisode?.id == episode.id {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.tint.opacity(0.35), lineWidth: 0.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: vm.selectedEpisode?.id)
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private func torrentsSection(_ vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Streams")
                    .font(.headline)
                Spacer()
                if vm.isLoading(.torrentSearch) {
                    InlineLoadingStatusView(title: "Searching\u{2026}")
                }
            }

            if preview.type == .series, let selectedEpisode = vm.selectedEpisode {
                Text("Selected episode: \(selectedEpisode.shortLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if vm.torrentSearch.results.isEmpty && !vm.isLoading(.torrentSearch) {
                if vm.requiresFreshEpisodeSearch, let selectedEpisode = vm.selectedEpisode {
                    ContentUnavailableView(
                        "Episode Changed",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Selected \(selectedEpisode.displayTitle). Run a new search for this episode.")
                    )
                } else if vm.torrentSearch.didSearch {
                    ContentUnavailableView(
                        "No Streams Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different episode, season, or search again.")
                    )
                } else if preview.type == .series, vm.selectedEpisode != nil {
                    ContentUnavailableView(
                        "Select an Episode",
                        systemImage: "rectangle.stack.badge.play",
                        description: Text("Tap an episode above to automatically search for streams.")
                    )
                } else {
                    ContentUnavailableView(
                        "No Streams Found",
                        systemImage: "magnifyingglass",
                        description: Text("Tap 'Find Streams' to search for available streams")
                    )
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(vm.torrentSearch.results) { torrent in
                        TorrentResultRow(
                            torrent: torrent,
                            onPlay: {
                                guard appState.activePlayerSession == nil else {
                                    showActiveSessionToast(for: appState.activePlayerSession)
                                    return
                                }
                                streamResolutionTask?.cancel()
                                streamResolutionTask = Task {
                                    if let stream = await vm.resolveStream(torrent: torrent) {
                                        guard !Task.isCancelled else { return }
                                        let request = vm.makePlayerSessionRequest(stream: stream, preview: preview)
                                        if await launchWithPreferredPlayer(for: request.stream.streamURL) {
                                            return
                                        }
                                        guard !Task.isCancelled else { return }

                                        await MainActor.run {
                                            appState.activePlayerSession = request
                                            openWindow(id: "player", value: request)
                                        }
                                    }
                                }
                            },
                            onDownload: {
                                Task { await vm.queueDownload(torrent: torrent) }
                            },
                            downloadState: vm.downloadState(for: torrent)
                        )
                    }
                }

                if vm.canLoadMoreTorrents {
                    let shownCount = vm.torrentSearch.results.count
                    let totalCount = shownCount + vm.remainingTorrentCount

                    HStack(spacing: 12) {
                        Text("Showing \(shownCount) of \(totalCount) streams")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            vm.loadMoreTorrentResults()
                        } label: {
                            Label("Load \(vm.nextTorrentBatchCount) More", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let error = vm.error {
                AppErrorInlineView(error: error)
            }

            if vm.isLoading(.streamResolution) || vm.isLoading(.downloadQueue) {
                InlineLoadingStatusView(
                    title: vm.loadingPhase == .downloadQueue ? "Queueing download..." : "Resolving stream..."
                )
            }
        }
        .id(streamResultsAnchor)
    }

}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .font(.system(size: 4))
                .foregroundStyle(.tertiary)
            configuration.title
        }
    }
}

struct TorrentResultRow: View {
    let torrent: TorrentResult
    let onPlay: () -> Void
    let onDownload: (() -> Void)?
    var downloadState: DownloadButtonState = .idle

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(torrent.title)
                    .font(.subheadline)
                    .lineLimit(2)

                FlowLayout(spacing: 6) {
                    if torrent.isCached {
                        GlassTag(text: "Cached", tintColor: .green, symbol: "bolt.fill", weight: .semibold)
                    }
                    if torrent.quality != .unknown {
                        GlassTag(text: torrent.quality.rawValue, tintColor: qualityColor, weight: .bold)
                    }
                    if torrent.hdr != .sdr {
                        GlassTag(text: torrent.hdr.rawValue, tintColor: hdrColor, symbol: hdrSymbol)
                    }
                    if torrent.audio != .unknown {
                        GlassTag(text: torrent.audio.rawValue, tintColor: audioColor, symbol: "hifispeaker.fill")
                    }
                    if torrent.codec != .unknown {
                        GlassTag(text: torrent.codec.rawValue)
                    }
                    if torrent.source != .unknown {
                        GlassTag(text: torrent.source.rawValue)
                    }
                }

                HStack(spacing: 8) {
                    if torrent.seeders > 0 {
                        Label("\(torrent.seeders)", systemImage: "arrow.up")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Text(torrent.indexerName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                downloadButton

                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)
                .help("Play")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch downloadState {
        case .idle:
            if let onDownload {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .help("Download")
            }
        case .resolving:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Resolving")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        case .downloading:
            Label("Downloading", systemImage: "arrow.down.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
        case .completed:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        case .failed:
            if let onDownload {
                Button(action: onDownload) {
                    Label("Retry", systemImage: "arrow.clockwise.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Retry download")
            }
        }
    }

    private var qualityColor: Color {
        switch torrent.quality {
        case .uhd4k: return .purple
        case .hd1080p: return .blue
        case .hd720p: return .green
        default: return .secondary
        }
    }

    private var hdrColor: Color {
        switch torrent.hdr {
        case .dolbyVision: return .purple
        case .hdr10Plus: return .orange
        case .hdr10: return .yellow
        case .hlg: return .mint
        case .sdr: return .secondary
        }
    }

    private var hdrSymbol: String {
        torrent.hdr == .dolbyVision ? "sparkles" : "sun.max.fill"
    }

    private var audioColor: Color {
        torrent.audio.spatialAudioHint ? .cyan : .secondary
    }
}

private extension DetailView {
    var previewTaskIdentity: String {
        "\(preview.type.rawValue)-\(preview.id)-\(preview.tmdbId.map(String.init) ?? "none")"
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
