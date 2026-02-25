import SwiftUI

struct DownloadsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel: DownloadsViewModel?
    @State private var reloadTask: Task<Void, Never>?
    @State private var confirmDeleteMediaId: String?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView("Loading Downloads...")
            }
        }
        .navigationTitle("Downloads")
        .task {
            if viewModel == nil {
                let vm = DownloadsViewModel(appState: appState)
                viewModel = vm
                await vm.load()
            }
        }
        .onDisappear {
            reloadTask?.cancel()
            reloadTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadsDidChange)) { _ in
            guard let vm = viewModel else { return }
            reloadTask?.cancel()
            reloadTask = Task { await vm.load() }
        }
    }

    @ViewBuilder
    private func content(_ vm: DownloadsViewModel) -> some View {
        if vm.isLoading && vm.groups.isEmpty {
            ProgressView("Loading Downloads...")
        } else if vm.groups.isEmpty {
            ContentUnavailableView(
                "No Downloads",
                systemImage: "arrow.down.circle",
                description: Text("Use the Download button on any stream to save content for offline viewing.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(vm.groups) { group in
                        mediaGroupCard(group, vm: vm)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .refreshable {
                await vm.load()
            }
        }

        if let error = vm.errorMessage, !error.isEmpty {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 6)
        }
    }

    private func mediaGroupCard(_ group: DownloadMediaGroup, vm: DownloadsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner header with poster
            HStack(spacing: 16) {
                // Poster thumbnail
                AsyncImage(url: group.posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2 / 3, contentMode: .fill)
                    case .failure:
                        posterPlaceholder
                    case .empty:
                        posterPlaceholder
                            .overlay { ProgressView().controlSize(.small) }
                    @unknown default:
                        posterPlaceholder
                    }
                }
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.mediaTitle.isEmpty ? "Unknown Title" : group.mediaTitle)
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        GlassTag(
                            text: group.mediaType == "series" ? "Series" : "Movie",
                            tintColor: group.mediaType == "series" ? .blue : .purple
                        )
                        Text("\(group.completedCount)/\(group.totalCount) downloaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if group.hasActiveDownloads {
                        GlassProgressBar(
                            progress: group.overallProgress,
                            tint: .blue
                        )
                    }
                }

                Spacer()

                // Delete all button for this media group
                Button(role: .destructive) {
                    confirmDeleteMediaId = group.mediaId
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete all downloads for this title")
                .confirmationDialog(
                    "Delete All Downloads?",
                    isPresented: Binding(
                        get: { confirmDeleteMediaId == group.mediaId },
                        set: { if !$0 { confirmDeleteMediaId = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete All", role: .destructive) {
                        Task { await vm.removeAll(mediaId: group.mediaId) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all downloaded files for \"\(group.mediaTitle)\" from storage.")
                }
            }
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // Individual download rows
            VStack(spacing: 0) {
                ForEach(group.tasks, id: \.id) { task in
                    downloadRow(task, vm: vm, isSeries: group.mediaType == "series")
                    if task.id != group.tasks.last?.id {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    private func downloadRow(_ task: DownloadTask, vm: DownloadsViewModel, isSeries: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isSeries ? task.displayTitle : task.fileName)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    GlassTag(
                        text: task.status.rawValue.capitalized,
                        tintColor: statusColor(for: task.status),
                        weight: .semibold
                    )
                    if task.status == .downloading || task.status == .queued {
                        Text(progressText(for: task))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if task.status == .completed, let bytes = task.totalBytes, bytes > 0 {
                        Text(formatBytes(bytes))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if task.status == .downloading || task.status == .queued || task.status == .resolving {
                    GlassProgressBar(
                        progress: task.progress,
                        tint: statusColor(for: task.status)
                    )
                }

                if let error = task.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                if task.status == .completed {
                    Button {
                        playDownload(task, vm: vm)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.vpRed)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Play")
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }

                if task.status == .downloading || task.status == .queued || task.status == .resolving {
                    Button {
                        Task { await vm.cancel(task) }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Cancel")
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }

                if task.status == .failed || task.status == .cancelled {
                    Button {
                        Task { await vm.retry(task) }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.body)
                            .foregroundStyle(.blue)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Retry")
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }

                Button(role: .destructive) {
                    Task { await vm.remove(task) }
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Delete")
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func playDownload(_ task: DownloadTask, vm: DownloadsViewModel) {
        #if os(macOS)
        vm.playFile(task)
        #else
        guard task.status == .completed, let fileURL = task.destinationURL else { return }
        guard appState.activePlayerSession == nil else { return }
        let stream = StreamInfo(
            streamURL: fileURL,
            quality: .unknown,
            codec: .unknown,
            audio: .unknown,
            source: .unknown,
            hdr: .sdr,
            fileName: task.fileName,
            sizeBytes: task.totalBytes,
            debridService: "local"
        )
        let request = PlayerSessionRequest(
            stream: stream,
            mediaTitle: task.displayTitle,
            mediaId: task.mediaId,
            episodeId: task.episodeId
        )
        appState.activePlayerSession = request
        openWindow(id: "player", value: request)
        #endif
    }

    private func statusColor(for status: DownloadStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .downloading: return .blue
        case .resolving: return .purple
        case .queued: return .secondary
        }
    }

    private func progressText(for task: DownloadTask) -> String {
        let pct = Int((task.progress * 100).rounded())
        if let total = task.totalBytes, total > 0 {
            let written = formatBytes(task.bytesWritten)
            let totalText = formatBytes(total)
            return "\(pct)% \u{2022} \(written) / \(totalText)"
        }
        return "\(pct)%"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private func formatBytes(_ bytes: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: bytes)
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.10, blue: 0.18),
                        Color(red: 0.06, green: 0.05, blue: 0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "film.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.3))
            }
    }
}
