import SwiftUI

/// A glass-morphism empty state card for library tabs.
///
/// Displays a large icon, title, description, and an optional CTA button.
/// Delegates all content and action logic to `LibraryEmptyStateCTAPolicy`.
struct LibraryEmptyStateView: View {
    let listType: LibraryEmptyStateCTAPolicy.ListType
    var onCTAAction: ((LibraryEmptyStateCTAPolicy.CTAAction) -> Void)?

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: LibraryEmptyStateCTAPolicy.icon(for: listType))
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }

            Text(LibraryEmptyStateCTAPolicy.title(for: listType))
                .font(.headline)

            Text(LibraryEmptyStateCTAPolicy.description(for: listType))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            let action = LibraryEmptyStateCTAPolicy.ctaAction(for: listType)
            if action != .none {
                SpatialButton(
                    title: LibraryEmptyStateCTAPolicy.ctaLabel(for: listType),
                    icon: ctaIcon(for: action),
                    tint: .vpRed
                ) {
                    onCTAAction?(action)
                }
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
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
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private func ctaIcon(for action: LibraryEmptyStateCTAPolicy.CTAAction) -> String {
        switch action {
        case .switchToDiscover:
            return "sparkles"
        case .openSettings:
            return "gearshape"
        case .none:
            return "circle"
        }
    }
}
