import SwiftUI

struct RecentSearchesSection: View {
    let searches: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                Text("Recent")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button("Clear All") {
                    onClear()
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.08), lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(searches, id: \.self) { term in
                        RecentSearchChip(
                            term: term,
                            onSelect: { onSelect(term) },
                            onRemove: { onRemove(term) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentSearchChip: View {
    let term: String
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                Text(term)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.26))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.085))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.06), lineWidth: 0.75)
                }
        }
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }
}
