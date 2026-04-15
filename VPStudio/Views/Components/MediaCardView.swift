import SwiftUI

struct MediaCardView: View {
    enum InteractionMode: Equatable {
        case fullyAnimated
        case systemHoverOnly

        func allowsCustomHoverChrome(onVisionOS: Bool) -> Bool {
            !onVisionOS || self == .fullyAnimated
        }
    }

    let item: MediaPreview
    var userRating: TasteEvent? = nil
    var interactionMode: InteractionMode = .fullyAnimated
    @State private var isHovered = false

    private let cardWidth: CGFloat = 170
    private let cardHeight: CGFloat = 255
    private let radius: CGFloat = 20

    nonisolated static func shouldShowPosterLoadingIndicator(for item: MediaPreview) -> Bool {
        item.posterURL != nil
    }

    var body: some View {
        let hoverChromeEnabled = interactionMode.allowsCustomHoverChrome(onVisionOS: Self.isVisionOS)
        let hoverActive = hoverChromeEnabled && isHovered

        return VStack(alignment: .leading, spacing: 10) {
            // Poster image
            posterArtwork
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: radius))
            .shadow(color: .black.opacity(hoverActive ? 0.35 : 0.15), radius: hoverActive ? 16 : 6, x: 0, y: hoverActive ? 10 : 4)
            .shadow(color: .white.opacity(hoverActive ? 0.06 : 0), radius: 20, y: 0)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(hoverActive ? 0.32 : 0.08),
                                .white.opacity(hoverActive ? 0.08 : 0.01),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(.black.opacity(0.3))
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .offset(x: 1.5)
                        }
                }
                .opacity(hoverActive ? 1 : 0)
                .animation(hoverChromeEnabled ? .easeInOut(duration: 0.15) : nil, value: hoverActive)
            }

            // Metadata below the poster
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    if let year = item.year {
                        Text(item.type.displayName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                        Text("\u{2022}")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.3))
                        Text(String(year))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if let rating = item.imdbRating, rating > 0 {
                        Text("\u{2022}")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.3))
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    if let event = userRating, let value = event.feedbackValue {
                        let scale = (event.feedbackScale ?? .oneToTen).canonicalMode
                        let normalized = scale.normalizedValue(value)
                        let isPositive = normalized >= 0.555
                        Text("\u{2022}")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.3))
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(isPositive ? .green : .red)
                            Text(userRatingLabel(scale: scale, value: value))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(isPositive ? .green : .red)
                        }
                    }
                }
            }
            .frame(width: cardWidth, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .scaleEffect(hoverActive ? 1.04 : 1.0)
        .modifier(MediaCardInteractionModifier(hoverChromeEnabled: hoverChromeEnabled, isHovered: $isHovered))
    }

    private static var isVisionOS: Bool {
        #if os(visionOS)
        true
        #else
        false
        #endif
    }

    private func userRatingLabel(scale: FeedbackScaleMode, value: Double) -> String {
        let clamped = scale.clamp(value)
        switch scale.canonicalMode {
        case .likeDislike:
            return clamped >= 0.5 ? "Liked" : "Disliked"
        default:
            return "\(Int(clamped))"
        }
    }

    @ViewBuilder
    private var posterArtwork: some View {
        if let posterURL = item.posterURL {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                case .failure:
                    posterPlaceholder
                case .empty:
                    if Self.shouldShowPosterLoadingIndicator(for: item) {
                        posterPlaceholder
                            .overlay { ProgressView() }
                    } else {
                        posterPlaceholder
                    }
                @unknown default:
                    posterPlaceholder
                }
            }
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        ArtworkFallbackPosterView(
            title: item.title,
            type: item.type,
            year: item.year,
            backdropURL: item.backdropURL
        )
        .frame(width: cardWidth, height: cardHeight)
    }
}

private struct MediaCardInteractionModifier: ViewModifier {
    let hoverChromeEnabled: Bool
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        #if os(visionOS)
        if hoverChromeEnabled {
            content
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isHovered = hovering
                    }
                }
                .hoverEffect(.lift)
        } else {
            content
                .hoverEffect(.lift)
        }
        #else
        content
            .onHover { hovering in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isHovered = hovering
                }
            }
        #endif
    }
}
