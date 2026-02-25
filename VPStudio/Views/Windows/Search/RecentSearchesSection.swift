import SwiftUI

struct RecentSearchesSection: View {
    let searches: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent", systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { onClear() }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(searches, id: \.self) { term in
                        RecentSearchChip(
                            term: term,
                            onSelect: { onSelect(term) },
                            onRemove: { onRemove(term) }
                        )
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: searches)
        }
    }
}

private struct RecentSearchChip: View {
    let term: String
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(term)
                    .font(.subheadline)
                    .lineLimit(1)

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.06), radius: 20, y: 0)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }
}
