import SwiftUI

struct ExploreGenreGrid: View {
    let cards: [ExploreMoodCard]
    let onSelect: (ExploreMoodCard) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Browse by Genre & Mood", systemImage: "sparkle.magnifyingglass")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(cards) { card in
                    Button { onSelect(card) } label: {
                        ExploreMoodCardView(card: card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Browse \(card.title): \(card.subtitle)")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }
}

struct ExploreMoodCardView: View {
    let card: ExploreMoodCard
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: card.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [card.color, card.color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: card.color.opacity(0.4), radius: 6, y: 2)

            Text(card.title)
                .font(.subheadline)
                .fontWeight(.bold)

            Text(card.subtitle)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [card.color.opacity(0.15), card.color.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassStroke(cornerRadius: 16)
        .glassShadow()
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }
}
