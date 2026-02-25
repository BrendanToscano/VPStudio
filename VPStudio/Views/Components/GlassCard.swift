import SwiftUI

/// Wrapping horizontal layout that flows children onto the next line when width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A stylized pill tag for genres, quality labels, and metadata badges.
///
/// Renders with ultra-thin glass material and a hairline specular stroke.
/// Pass a `tintColor` to tint the background and label for quality-coded badges.
struct GlassTag: View {
    let text: String
    var tintColor: Color?
    var symbol: String?
    var weight: Font.Weight = .medium

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.caption)
                .fontWeight(weight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tagBackground, in: Capsule())
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
        .foregroundStyle(tintColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }

    private var tagBackground: AnyShapeStyle {
        if let tintColor {
            AnyShapeStyle(tintColor.opacity(0.18))
        } else {
            AnyShapeStyle(.ultraThinMaterial)
        }
    }
}

/// A spatial-aware button with hover effects for visionOS.
///
/// Renders with a custom glass background instead of the native bordered style,
/// giving it a more immersive, spatial character.
struct SpatialButton: View {
    let title: String
    let icon: String
    var tint: Color?
    let action: () -> Void

    init(title: String, icon: String, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(buttonBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    private var buttonBackground: AnyShapeStyle {
        if let tint {
            AnyShapeStyle(tint.opacity(0.22))
        } else {
            AnyShapeStyle(.regularMaterial)
        }
    }
}

/// A circular icon-only glass button for compact actions (play, delete, etc.).
///
/// Uses ultra-thin material with specular stroke and dual-layer shadows.
struct GlassIconButton: View {
    let icon: String
    var tint: Color?
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint ?? .white)
                .frame(width: size, height: size)
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
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }
}

/// A capsule progress bar with glass-morphism styling.
///
/// Displays a filled track over a translucent background with specular stroke.
struct GlassProgressBar: View {
    let progress: Double
    var tint: Color = .white
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

// MARK: - Design Tokens

/// The signature neon red/pink gradient used throughout the cinematic UI.
extension LinearGradient {
    static let vpAccent = LinearGradient(
        colors: [Color(red: 1.0, green: 0.16, blue: 0.33), Color(red: 1.0, green: 0.35, blue: 0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    static let vpRed = Color(red: 1.0, green: 0.16, blue: 0.33)
    static let vpRedLight = Color(red: 1.0, green: 0.35, blue: 0.35)
}

// MARK: - Paste Button

/// A clipboard paste button for use next to SecureField / TextField inputs.
struct PasteFieldButton: View {
    let onPaste: (String) -> Void

    var body: some View {
        Button {
            #if os(macOS)
            if let string = NSPasteboard.general.string(forType: .string) {
                onPaste(string.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            #else
            if let string = UIPasteboard.general.string {
                onPaste(string.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            #endif
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }
}

// MARK: - Reusable Glass View Extensions

extension View {
    /// Standard glass morphism specular stroke overlay.
    func glassStroke(cornerRadius: CGFloat = 16, lineWidth: CGFloat = 1) -> some View {
        self.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth
                )
        }
    }

    /// Standard dual-layer glass shadow.
    func glassShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
            .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
    }

    /// Combined glass card treatment (material background + stroke + shadow).
    func glassCard(cornerRadius: CGFloat = 16, material: Material = .ultraThinMaterial) -> some View {
        self
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassStroke(cornerRadius: cornerRadius)
            .glassShadow()
    }
}
