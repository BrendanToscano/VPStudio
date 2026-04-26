import SwiftUI

enum ExploreGenreTilePolicy {
    static let columns = 7
    static let tileWidth: CGFloat = 128
    static let columnSpacing: CGFloat = 16
    static let rowSpacing: CGFloat = 15
    static let cornerRadius: CGFloat = 17
    static let referenceAspectRatio: CGFloat = 227.0 / 251.0

    static func imageName(for card: ExploreMoodCard) -> String {
        "genre-ref-\(card.id)"
    }

    static func accessibilityLabel(for card: ExploreMoodCard) -> String {
        "\(card.title), \(card.subtitle)"
    }

    static func gridColumns() -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(tileWidth), spacing: columnSpacing, alignment: .top),
            count: columns
        )
    }
}

struct ExploreGenreGrid: View {
    let cards: [ExploreMoodCard]
    let onSelect: (ExploreMoodCard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Browse by Genre & Mood")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            LazyVGrid(
                columns: ExploreGenreTilePolicy.gridColumns(),
                alignment: .leading,
                spacing: ExploreGenreTilePolicy.rowSpacing
            ) {
                ForEach(cards) { card in
                    ExploreGenreTile(card: card) {
                        onSelect(card)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExploreGenreTile: View {
    let card: ExploreMoodCard
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            Image(ExploreGenreTilePolicy.imageName(for: card))
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .contrast(0.94)
                .saturation(1.01)
                .brightness(0.01)
                .scaledToFill()
                .aspectRatio(ExploreGenreTilePolicy.referenceAspectRatio, contentMode: .fit)
                .clipShape(tileShape)
                .overlay {
                    tileShape
                        .inset(by: 0.6)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white.opacity(0.16), location: 0.0),
                                    .init(color: .white.opacity(0.05), location: 0.18),
                                    .init(color: .clear, location: 0.42),
                                    .init(color: .clear, location: 0.78),
                                    .init(color: .black.opacity(0.05), location: 1.0),
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.45
                        )
                        .blendMode(.screen)
                }
                .shadow(color: .black.opacity(0.012), radius: 0.35, y: 0.15)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ExploreGenreTilePolicy.accessibilityLabel(for: card)))
        #if os(visionOS)
        .hoverEffect(.lift)
        #else
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isHovered = hovering
            }
        }
        #endif
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ExploreGenreTilePolicy.cornerRadius, style: .continuous)
    }
}
