import SwiftUI
import Kingfisher

struct MediaCardView: View {
    let item: MediaPreview
    var userRating: TasteEvent? = nil
    @State private var isHovered = false

    private let cardWidth: CGFloat = 170
    private let cardHeight: CGFloat = 255
    private let radius: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Poster image with Kingfisher for LRU caching
            KFImage(item.posterURL)
                .placeholder {
                    posterPlaceholder
                        .overlay { ProgressView() }
                }
                .retry(maxCount: 2, interval: .seconds(1))
                .cacheOriginalImage()
                .fade(duration: 0.25)
                .scaleFactor(UIScreen.main.scale)
                .resizable()
                .aspectRatio(2 / 3, contentMode: .fill)
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay {
                    // Fallback for failed load
                    posterPlaceholder
                        .opacity(0)
                }
                .shadow(color: .black.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 16 : 6, x: 0, y: isHovered ? 10 : 4)
                .shadow(color: .white.opacity(isHovered ? 0.06 : 0), radius: 20, y: 0)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isHovered ? 0.32 : 0.08),
                                .white.opacity(isHovered ? 0.08 : 0.01),
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
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
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
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        #if os(visionOS)
        .hoverEffect(.lift)
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

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: radius)
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
            .frame(width: cardWidth, height: cardHeight)
            .overlay {
                Image(systemName: "film.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.3))
            }
    }
}
