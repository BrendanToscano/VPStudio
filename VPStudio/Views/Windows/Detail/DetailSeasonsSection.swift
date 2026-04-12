import SwiftUI

struct DetailSeasonsSection: View {
    let viewModel: DetailViewModel
    let tmdbApiKey: String
    let scrollProxy: ScrollViewProxy
    let streamResultsAnchor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Season Tabs (Netflix-style horizontal pills) ─────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.seasons, id: \.id) { season in
                        let isSelected = viewModel.selectedSeason == season.seasonNumber
                        Button {
                            Task { await viewModel.loadSeason(season.seasonNumber, apiKey: tmdbApiKey) }
                        } label: {
                            Text("Season \(season.seasonNumber)")
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .medium)
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected ? 
                                        Color.purple.opacity(0.9) :
                                        Color.white.opacity(0.15),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            isSelected ? .purple.opacity(0.5) : .white.opacity(0.1),
                                            lineWidth: 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: viewModel.selectedSeason)
                        #if os(visionOS)
                        .hoverEffect(.lift)
                        #endif
                    }
                }
                .padding(.horizontal, 2)
            }

            // ── Episode Row ────────────────────────────────────────
            if !viewModel.episodes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Season context line
                    if let season = viewModel.seasons.first(where: { $0.seasonNumber == viewModel.selectedSeason }),
                       let overview = season.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Horizontal episode row
                    EpisodeRow(
                        episodes: viewModel.episodes,
                        episodeWatchStates: viewModel.episodeWatchStates,
                        selectedEpisodeID: viewModel.selectedEpisode?.id,
                        onSelectEpisode: { episode in
                            let selectedEpisodeID = episode.id
                            viewModel.selectEpisode(episode)
                            Task {
                                await viewModel.searchTorrents()
                                guard !Task.isCancelled else { return }
                                guard viewModel.selectedEpisode?.id == selectedEpisodeID else { return }
                                await MainActor.run {
                                    withAnimation(.easeInOut(duration: 0.28)) {
                                        scrollProxy.scrollTo(streamResultsAnchor, anchor: .top)
                                    }
                                }
                            }
                        },
                        onToggleWatched: { episode in
                            Task { await viewModel.toggleEpisodeWatched(episode) }
                        }
                    )
                }

                // ── Episode Actions ─────────────────────────────────
                if let episode = viewModel.selectedEpisode {
                    HStack(spacing: 12) {
                        // Mark watched/unwatched
                        let isWatched = viewModel.episodeWatchStates[episode.id]?.isCompleted == true
                        Button {
                            Task { await viewModel.toggleEpisodeWatched(episode) }
                        } label: {
                            Label(
                                isWatched ? "Mark Unwatched" : "Mark Watched",
                                systemImage: isWatched ? "xmark.circle" : "checkmark.circle"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        // Mark entire season watched
                        Button {
                            Task { await viewModel.markSeasonWatched() }
                        } label: {
                            Label("Season Watched", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        // Three-dot menu
                        Menu {
                            Button {
                                Task { await viewModel.markSeasonWatched() }
                            } label: {
                                Label("Mark Season as Watched", systemImage: "checkmark.circle")
                            }
                            Button {
                                Task { await viewModel.markSeasonUnwatched() }
                            } label: {
                                Label("Mark Season as Unwatched", systemImage: "xmark.circle")
                            }
                            Divider()
                            Button {
                                Task { await markRemainingEpisodesWatched(from: episode) }
                            } label: {
                                Label("Mark Rest as Watched", systemImage: "checkmark")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .padding(.top, 8)
                }
            } else if viewModel.isLoading(.seasonEpisodes) {
                HStack {
                    Spacer()
                    ProgressView("Loading episodes...")
                    Spacer()
                }
                .padding(.vertical, 24)
            }
        }
    }

    @MainActor
    private func markRemainingEpisodesWatched(from episode: Episode) async {
        guard let startIndex = viewModel.episodes.firstIndex(where: { $0.id == episode.id }) else {
            return
        }

        for remainingEpisode in viewModel.episodes[startIndex...] {
            guard viewModel.episodeWatchStates[remainingEpisode.id]?.isCompleted != true else { continue }
            await viewModel.toggleEpisodeWatched(remainingEpisode)
        }
    }
}
