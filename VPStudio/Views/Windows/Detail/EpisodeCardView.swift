import SwiftUI

// MARK: - Episode Card View

/// A thumbnail-based episode card matching the streaming-app UX:
/// horizontal scrollable row, still frame as background, watch-state overlay,
/// and progress bar for in-progress episodes.
struct EpisodeCardView: View {
    let episode: Episode
    let watchState: WatchHistory?
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleWatched: () -> Void

    // Card dimensions
    private let cardWidth: CGFloat = 220
    private let cardHeight: CGFloat = 160
    private let cornerRadius: CGFloat = 12

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                // ── Thumbnail ──────────────────────────────────────
                ZStack(alignment: .bottomLeading) {
                    thumbnailImage
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .overlay(thumbnailOverlay)
                        .overlay(alignment: .bottom) {
                            progressBar
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                    // Checkmark badge (top-right when completed)
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

                    // Selected ring
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.tint, lineWidth: 2)
                    }
                }

                // ── Info ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.shortLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    if let title = episode.title, !title.isEmpty {
                        Text(title)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                    }

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                .frame(width: cardWidth, alignment: .leading)
                .padding(.top, 6)
            }
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    // MARK: - Thumbnail Image

    @ViewBuilder
    private var thumbnailImage: some View {
        if let url = episode.stillURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackThumbnail
                case .empty:
                    ZStack {
                        fallbackThumbnail
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                @unknown default:
                    fallbackThumbnail
                }
            }
        } else {
            fallbackThumbnail
        }
    }

    private var fallbackThumbnail: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Thumbnail Overlay (watched dim + info chip)

    @ViewBuilder
    private var thumbnailOverlay: some View {
        // Dim completed episodes slightly
        if isCompleted {
            Rectangle()
                .fill(.black.opacity(0.35))
        }

        // Info chip bottom-left
        HStack(spacing: 4) {
            Text(episode.shortLabel)
                .font(.caption2)
                .fontWeight(.semibold)

            if let runtime = episode.runtime, runtime > 0 {
                Text("·")
                Text("\(runtime)m")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // MARK: - Progress Bar

    @ViewBuilder
    private var progressBar: some View {
        if isCompleted {
            // Solid progress bar (no GeometryReader — avoids layout thrashing in ScrollView)
            Rectangle()
                .fill(.green)
                .frame(height: 3)
        } else if let progress = progressPercent, progress > 0 {
            // Partial progress bar (uses scaleEffect instead of GeometryReader)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 3)
                Rectangle()
                    .fill(.blue)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: progress, y: 1, anchor: .leading)
                    .frame(height: 3)
            }
            .frame(height: 3)
        }
    }

    // MARK: - Computed State

    private var isCompleted: Bool {
        watchState?.isCompleted == true
    }

    private var progressPercent: Double? {
        guard !isCompleted else { return nil }
        let p = watchState?.progressPercent ?? 0
        return p > 0 ? p : nil
    }
}

// MARK: - Episode Row (horizontal scroll container)

/// A horizontal scrollable row of episode cards, similar to Apple TV+'s episode browser.
struct EpisodeRow: View {
    let episodes: [Episode]
    let episodeWatchStates: [String: WatchHistory]
    let selectedEpisodeID: String?
    let onSelectEpisode: (Episode) -> Void
    let onToggleWatched: (Episode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(episodes) { episode in
                    EpisodeCardView(
                        episode: episode,
                        watchState: episodeWatchStates[episode.id],
                        isSelected: selectedEpisodeID == episode.id,
                        onSelect: { onSelectEpisode(episode) },
                        onToggleWatched: { onToggleWatched(episode) }
                    )
                    .id(episode.id)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: rowHeight)
    }

    private var rowHeight: CGFloat {
        // Card (image + info) height
        160 + 56
    }
}
