import SwiftUI

struct DetailTorrentsSection: View {
    let viewModel: DetailViewModel
    let mediaType: MediaType
    let streamResultsAnchor: String
    @Binding var isPlayerOpening: Bool
    @Binding var playerOpeningError: String?
    let onPlayTorrent: (TorrentResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Streams")
                    .font(.headline)
                Spacer()
                if viewModel.isLoading(.torrentSearch) {
                    InlineLoadingStatusView(title: "Searching\u{2026}")
                }
            }

            if mediaType == .series, let selectedEpisode = viewModel.selectedEpisode {
                Text("Selected episode: \(selectedEpisode.shortLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.torrentSearch.results.isEmpty && !viewModel.isLoading(.torrentSearch) {
                if viewModel.requiresFreshEpisodeSearch, let selectedEpisode = viewModel.selectedEpisode {
                    ContentUnavailableView(
                        "Episode Changed",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Selected \(selectedEpisode.displayTitle). Run a new search for this episode.")
                    )
                } else if viewModel.torrentSearch.didSearch {
                    ContentUnavailableView(
                        "No Streams Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different episode, season, or search again.")
                    )
                } else if mediaType == .series, viewModel.selectedEpisode == nil {
                    ContentUnavailableView(
                        "Select an Episode",
                        systemImage: "rectangle.stack.badge.play",
                        description: Text("Tap an episode above to automatically search for streams.")
                    )
                } else {
                    let description =
                        if mediaType == .series {
                            "Tap Play or select an episode above to search for available streams."
                        } else {
                            "Tap Play to search for available streams."
                        }
                    ContentUnavailableView(
                        "No Streams Found",
                        systemImage: "magnifyingglass",
                        description: Text(description)
                    )
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.torrentSearch.results) { torrent in
                        TorrentResultRow(
                            torrent: torrent,
                            isPlayerOpening: $isPlayerOpening,
                            playerOpeningError: $playerOpeningError,
                            onPlay: {
                                onPlayTorrent(torrent)
                            },
                            onDownload: {
                                Task { await viewModel.queueDownload(torrent: torrent) }
                            },
                            downloadState: viewModel.downloadState(for: torrent)
                        )
                    }
                }

                if viewModel.canLoadMoreTorrents {
                    let shownCount = viewModel.torrentSearch.results.count
                    let totalCount = shownCount + viewModel.remainingTorrentCount

                    HStack(spacing: 12) {
                        Text("Showing \(shownCount) of \(totalCount) streams")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            viewModel.loadMoreTorrentResults()
                        } label: {
                            Label("Load \(viewModel.nextTorrentBatchCount) More", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPlayerOpening)
                        .accessibilityHint("Loads more stream results for the current search.")
                    }
                }
            }

            if let error = viewModel.error {
                AppErrorInlineView(error: error)
            }

            if viewModel.isLoading(.streamResolution) || viewModel.isLoading(.downloadQueue) {
                InlineLoadingStatusView(
                    title: viewModel.loadingPhase == .downloadQueue ? "Queueing download..." : "Resolving stream..."
                )
            }
        }
        .id(streamResultsAnchor)
    }
}

struct TorrentResultRow: View {
    let torrent: TorrentResult
    @Binding var isPlayerOpening: Bool
    @Binding var playerOpeningError: String?
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
                if isPlayerOpening {
                    // Row-level feedback: player is launching
                    VStack(alignment: .leading, spacing: 4) {
                        if let error = playerOpeningError {
                            // Error state — show message and retry
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Button {
                                playerOpeningError = nil
                                onPlay()
                            } label: {
                                Text("Try Again")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.blue)
                            }
                        } else {
                            // Loading state
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Opening player...")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    downloadButton

                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Play")
                    .accessibilityLabel("Play \(torrent.title)")
                    .accessibilityHint("Opens this stream in the player.")
                }
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
                .disabled(isPlayerOpening)
                .help("Download")
                .accessibilityLabel("Download \(torrent.title)")
                .accessibilityHint("Queues this stream for offline playback.")
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
                .accessibilityLabel("Retry download for \(torrent.title)")
                .accessibilityHint("Attempts this download again.")
            }
        }
    }

    private var qualityColor: Color {
        switch torrent.quality {
        case .uhd4k:
            return .purple
        case .hd1080p:
            return .blue
        case .hd720p:
            return .green
        default:
            return .secondary
        }
    }

    private var hdrColor: Color {
        switch torrent.hdr {
        case .dolbyVision:
            return .purple
        case .hdr10Plus:
            return .orange
        case .hdr10:
            return .yellow
        case .hlg:
            return .mint
        case .sdr:
            return .secondary
        }
    }

    private var hdrSymbol: String {
        torrent.hdr == .dolbyVision ? "sparkles" : "sun.max.fill"
    }

    private var audioColor: Color {
        torrent.audio.spatialAudioHint ? .cyan : .secondary
    }
}
