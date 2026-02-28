import SwiftUI

enum PillPickerAnimationPolicy {
    static let springResponse: Double = 0.35
    static let springDamping: Double = 0.82
    static let pillHeight: CGFloat = 44  // Increased for better Vision Pro touch targets
    static let horizontalPadding: CGFloat = 20  // Increased padding for touch friendliness
}

/// A glass-morphism segmented picker with a sliding indicator.
///
/// Generic over any `Hashable & CustomStringConvertible` selection type.
/// Uses `matchedGeometryEffect` for a smooth animated pill indicator.
struct GlassPillPicker<SelectionType: Hashable & CustomStringConvertible>: View {
    let options: [SelectionType]
    @Binding var selection: SelectionType

    /// Optional accessibility labels for each option
    var accessibilityLabels: [SelectionType: String]?

    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                pillButton(for: option)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
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
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
    }

    private func pillButton(for option: SelectionType) -> some View {
        let isSelected = selection == option
        let label = accessibilityLabels?[option] ?? "Select \(option.description)"
        
        return Button {
            withAnimation(
                .spring(
                    response: PillPickerAnimationPolicy.springResponse,
                    dampingFraction: PillPickerAnimationPolicy.springDamping
                )
            ) {
                selection = option
            }
        } label: {
            Text(option.description)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: PillPickerAnimationPolicy.pillHeight)
                .padding(.horizontal, PillPickerAnimationPolicy.horizontalPadding)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.vpRed)
                            .matchedGeometryEffect(id: "pillIndicator", in: pillNamespace)
                    }
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }
}
