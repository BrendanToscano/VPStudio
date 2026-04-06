import SwiftUI

/// Wrapping horizontal layout that flows children onto the next line when width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let intrinsicWidth = subviews.enumerated().reduce(CGFloat(0)) { partial, element in
            let size = element.element.sizeThatFits(.unspecified)
            let spacingWidth = element.offset == 0 ? CGFloat(0) : spacing
            return partial + spacingWidth + size.width
        }
        let maxWidth = max(proposal.width ?? intrinsicWidth, 0)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var requiredWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                requiredWidth = max(requiredWidth, x - spacing)
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        requiredWidth = max(requiredWidth, x - spacing)
        let resolvedWidth = proposal.width ?? requiredWidth
        return CGSize(width: resolvedWidth, height: y + rowHeight)
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

// MARK: - Artwork & State Surfaces

enum ArtworkFallbackStyle {
    private static let palettes: [[Color]] = [
        [Color(red: 0.16, green: 0.22, blue: 0.52), Color(red: 0.44, green: 0.18, blue: 0.63)],
        [Color(red: 0.10, green: 0.36, blue: 0.42), Color(red: 0.18, green: 0.63, blue: 0.52)],
        [Color(red: 0.42, green: 0.16, blue: 0.28), Color(red: 0.82, green: 0.33, blue: 0.29)],
        [Color(red: 0.35, green: 0.25, blue: 0.08), Color(red: 0.86, green: 0.63, blue: 0.22)],
        [Color(red: 0.12, green: 0.20, blue: 0.38), Color(red: 0.26, green: 0.48, blue: 0.80)],
        [Color(red: 0.16, green: 0.14, blue: 0.18), Color(red: 0.35, green: 0.33, blue: 0.42)],
    ]
    private static let fillerWords: Set<String> = ["a", "an", "and", "at", "by", "for", "from", "in", "of", "on", "the", "to"]

    static func initials(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "VP" }

        let tokens = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.uppercased() }
            .filter { !fillerWords.contains($0.lowercased()) }

        if tokens.count >= 2 {
            return String((tokens[0].prefix(1) + tokens[1].prefix(1)).prefix(2))
        }

        if let first = tokens.first {
            return String(first.prefix(2))
        }

        let letters = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(letters).prefix(2)).uppercased()
    }

    static func palette(for title: String, type: MediaType?) -> [Color] {
        let hash = title.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let index = abs(hash % palettes.count)
        var palette = palettes[index]

        switch type {
        case .movie:
            palette[0] = palette[0].opacity(0.95)
            palette[1] = palette[1].opacity(0.95)
        case .series:
            palette[0] = Color(red: 0.10, green: 0.23, blue: 0.48)
            palette[1] = Color(red: 0.31, green: 0.61, blue: 0.93)
        case nil:
            break
        }

        return palette
    }

    static func metadata(for type: MediaType?, year: Int?) -> String {
        let label = type?.displayName.uppercased() ?? "FEATURE"
        if let year {
            return "\(label) • \(year)"
        }
        return label
    }

    static func accentSymbol(for type: MediaType?) -> String {
        switch type {
        case .series:
            return "tv.fill"
        case .movie, nil:
            return "film.stack.fill"
        }
    }
}

struct ArtworkFallbackPosterView: View {
    let title: String
    var type: MediaType? = nil
    var year: Int? = nil
    var backdropURL: URL? = nil
    var compact: Bool = false

    private var palette: [Color] {
        ArtworkFallbackStyle.palette(for: title, type: type)
    }

    private var initials: String {
        ArtworkFallbackStyle.initials(for: title)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: compact ? 12 : 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette[0], palette[1]],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let backdropURL {
                AsyncImage(url: backdropURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(0.42)
                            .overlay {
                                LinearGradient(
                                    colors: [.black.opacity(0.08), .black.opacity(0.38)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                    }
                }
                .allowsHitTesting(false)
            }

            Circle()
                .fill(.white.opacity(compact ? 0.12 : 0.16))
                .frame(width: compact ? 84 : 136, height: compact ? 84 : 136)
                .blur(radius: compact ? 4 : 8)
                .offset(x: compact ? 28 : 56, y: compact ? -20 : -48)

            Capsule()
                .fill(.white.opacity(0.10))
                .frame(width: compact ? 84 : 190, height: compact ? 18 : 28)
                .blur(radius: compact ? 12 : 20)
                .rotationEffect(.degrees(-26))
                .offset(x: compact ? 18 : 42, y: compact ? -8 : -30)

            LinearGradient(
                colors: [.clear, .black.opacity(compact ? 0.46 : 0.62)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                HStack(alignment: .top) {
                    if !compact {
                        GlassTag(
                            text: ArtworkFallbackStyle.metadata(for: type, year: year),
                            tintColor: .white.opacity(0.22),
                            symbol: ArtworkFallbackStyle.accentSymbol(for: type),
                            weight: .semibold
                        )
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: compact ? 8 : 12) {
                    Text(initials)
                        .font(.system(size: compact ? 24 : 46, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                        .shadow(color: .black.opacity(0.24), radius: 8, y: 2)

                    if !compact {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("Artwork fallback")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .padding(compact ? 10 : 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 12 : 20, style: .continuous)
                .strokeBorder(.white.opacity(compact ? 0.12 : 0.14), lineWidth: 1)
        }
    }
}

struct CinematicStateCard<Content: View>: View {
    var accent: Color = .accentColor
    var artworkName: String? = nil
    var minHeight: CGFloat = 220
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)

            if let artworkName {
                Image(artworkName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .opacity(0.28)
                    .clipped()
                    .allowsHitTesting(false)
            }

            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 18)
                .offset(x: 70, y: 50)

            LinearGradient(
                colors: [.black.opacity(0.06), .black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.30),
                            accent.opacity(0.18),
                            .white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            content()
                .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .glassShadow()
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
