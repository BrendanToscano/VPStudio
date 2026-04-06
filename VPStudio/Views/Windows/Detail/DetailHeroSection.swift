import SwiftUI

struct DetailHeroSection: View {
    let viewModel: DetailViewModel
    let title: String
    let scrollProxy: ScrollViewProxy
    let onShowRatingSheet: () -> Void
    let tmdbApiKey: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image
            backdropImage
                .frame(height: 280)
                .clipped()

            // Gradient overlay
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.2), location: 0.4),
                    .init(color: .black.opacity(0.75), location: 0.8),
                    .init(color: .black.opacity(0.95), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)
            .frame(maxHeight: .infinity, alignment: .bottom)

            // Banner content
            VStack(alignment: .leading, spacing: 8) {
                // Title + utility cluster row
                HStack(alignment: .top) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer()

                    // Top-right: Share, List, Cast, AI
                    HStack(spacing: 4) {
                        utilityButton(icon: "square.and.arrow.up", label: "Share") {}
                        utilityButton(icon: "list.bullet", label: "List") {}
                        utilityButton(icon: "airplayvideo", label: "Cast") {}

                        // AI — "Would I Like This?" pill button
                        Button {
                            Task { await viewModel.fetchAIAnalysis() }
                        } label: {
                            Label("Would I Like This?", systemImage: "brain")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.8), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        #if os(visionOS)
                        .hoverEffect(.lift)
                        #endif
                    }
                }

                // Metadata row
                HStack(spacing: 10) {
                    if let year = viewModel.mediaItem?.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let runtime = viewModel.mediaItem?.runtime, runtime > 0 {
                        Text("\(runtime) min")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if let rating = viewModel.mediaItem?.imdbRating, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f IMDb", rating))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    // Inline favorite
                    Button {
                        Task { await viewModel.toggleFavorites() }
                    } label: {
                        Image(systemName: viewModel.mediaLibrary.isInFavorites ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(viewModel.mediaLibrary.isInFavorites ? .red : .white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }

                // Synopsis
                if let overview = viewModel.mediaItem?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                }

                // Genre pills
                genrePills

                // Status message
                if let status = viewModel.mediaLibrary.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
            
            // Season tabs (positioned at bottom of hero gradient)
            if !viewModel.seasons.isEmpty {
                VStack(spacing: 0) {
                    // Gradient fade from hero to content
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black.opacity(0.3), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 20)
                    
                    // Season tabs
                    seasonTabs
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
        }
    }
    
    @ViewBuilder
    private var seasonTabs: some View {
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
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var backdropImage: some View {
        if let url = viewModel.mediaItem?.backdropURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .transition(.opacity)
                default:
                    Rectangle().fill(.quaternary)
                }
            }
            .animation(.easeIn(duration: 0.5), value: url)
        } else {
            Rectangle().fill(.quaternary)
        }
    }

    @ViewBuilder
    private var genrePills: some View {
        if let genres = viewModel.mediaItem?.genres, !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<min(genres.count, 4), id: \.self) { i in
                        Text(genres[i])
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    /// A pill-shaped utility icon button in the top-right cluster.
    private func utilityButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }
}
