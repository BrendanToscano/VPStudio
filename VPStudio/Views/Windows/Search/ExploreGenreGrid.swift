import SwiftUI

struct ExploreGenreGrid: View {
    let cards: [ExploreMoodCard]
    let onSelect: (ExploreMoodCard) -> Void

    private let referenceTileSize = CGSize(width: 227, height: 251)
    private let referenceGridArtboardSize = CGSize(width: 1812, height: 570)
    /// Bias the visible crop toward the literal illustrated tile bodies themselves.
    /// The user called out thumbnail personality/artwork first, so keep the shared
    /// outer haze trimmed back and let the per-card faces dominate the lane.
    private let referenceGridPresentationRect = CGRect(x: 17, y: 17, width: 1792, height: 556)
    private let displayTileWidth: CGFloat = 128

    private let referenceTileRects: [CGRect] = [
        CGRect(x: 17, y: 17, width: 227, height: 251),
        CGRect(x: 275, y: 17, width: 227, height: 251),
        CGRect(x: 533, y: 17, width: 227, height: 251),
        CGRect(x: 791, y: 17, width: 227, height: 251),
        CGRect(x: 1_049, y: 17, width: 227, height: 251),
        CGRect(x: 1_307, y: 17, width: 227, height: 251),
        CGRect(x: 1_565, y: 17, width: 227, height: 251),
        CGRect(x: 17, y: 305, width: 227, height: 251),
        CGRect(x: 275, y: 305, width: 227, height: 251),
        CGRect(x: 533, y: 305, width: 227, height: 251),
        CGRect(x: 791, y: 305, width: 227, height: 251),
        CGRect(x: 1_049, y: 305, width: 227, height: 251),
        CGRect(x: 1_307, y: 305, width: 227, height: 251),
        CGRect(x: 1_565, y: 305, width: 227, height: 251),
    ]

    private var artboardScale: CGFloat {
        displayTileWidth / referenceTileSize.width
    }

    private var displayedArtboardSize: CGSize {
        CGSize(
            width: referenceGridPresentationRect.width * artboardScale,
            height: referenceGridPresentationRect.height * artboardScale
        )
    }

    private func displayedTileRect(for rect: CGRect, presentationRect: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - presentationRect.minX) * artboardScale,
            y: (rect.minY - presentationRect.minY) * artboardScale,
            width: rect.width * artboardScale,
            height: rect.height * artboardScale
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Browse by Genre & Mood")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            // Use the per-tile renderer directly.
            // The stitched reference-artboard path was useful for screenshot-parity
            // experiments, but it softens and contaminates imported icon artwork with
            // context/restore layers. The desktop icons should render as sharp, literal
            // tile faces instead of being composited through that proxy stack.
            fallbackGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var referenceTileAssetGrid: some View {
        let presentationRect = referenceGridPresentationRect
        let displayedTileRects = referenceTileRects.map {
            displayedTileRect(for: $0, presentationRect: presentationRect)
        }

        return ZStack(alignment: .topLeading) {
            referenceGridGutterWash(
                presentationRect: presentationRect,
                displayedTileRects: displayedTileRects
            )
            // Keep the screenshot-matched context only around the embedded tile
            // cluster so the page background can breathe at the lane edges, then
            // restore the literal card faces on top to keep the swirls / icon
            // feel / per-card personality anchored to the reference art.
            referenceGridContextEmbeddedField(displayedTileRects: displayedTileRects)
            referenceGridLiteralTileBodyRestore(
                presentationRect: presentationRect,
                displayedTileRects: displayedTileRects
            )
            referenceGridLiteralTileCorePop(
                presentationRect: presentationRect,
                displayedTileRects: displayedTileRects
            )

            ForEach(Array(zip(cards.indices, cards)), id: \.1.id) { index, card in
                let displayedRect = displayedTileRects[index]
                let tileCornerRadius = 22 * artboardScale

                Button {
                    onSelect(card)
                } label: {
                    RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                        .frame(width: displayedRect.width, height: displayedRect.height)
                }
                .buttonStyle(.plain)
                .frame(width: displayedRect.width, height: displayedRect.height)
                .position(x: displayedRect.midX, y: displayedRect.midY)
                .accessibilityLabel(Text("\(card.title), \(card.subtitle)"))
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif
            }
        }
        .frame(
            width: displayedArtboardSize.width,
            height: displayedArtboardSize.height,
            alignment: .topLeading
        )
        .clipped()
    }

    private func referenceGridContextEmbeddedField(displayedTileRects: [CGRect]) -> some View {
        // `genre-ref-grid-context` already has the right between-card field from
        // the reference screenshot, but showing the full crop reads like a boxed
        // dark lane. Keep it concentrated around the tile cluster so the cards
        // stay embedded while the lane still leans on the screenshot-matched art
        // instead of rebuilding the field into a cleaner synthetic strip.
        Image("genre-ref-grid-context")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(
                width: displayedArtboardSize.width,
                height: displayedArtboardSize.height,
                alignment: .topLeading
            )
            .mask(referenceGridEmbeddedLaneMask(displayedTileRects: displayedTileRects))
            .opacity(0.72)
            .allowsHitTesting(false)
    }

    private func referenceGridLiteralWhisper(presentationRect: CGRect) -> some View {
        let artboardWidth = referenceGridArtboardSize.width * artboardScale
        let artboardHeight = referenceGridArtboardSize.height * artboardScale

        return Image("genre-ref-grid")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(width: artboardWidth, height: artboardHeight)
            .offset(
                x: -presentationRect.minX * artboardScale,
                y: -presentationRect.minY * artboardScale
            )
            .frame(
                width: displayedArtboardSize.width,
                height: displayedArtboardSize.height,
                alignment: .topLeading
            )
            // Keep this tiny: enough to restore a touch of literal tile texture,
            // not enough to reintroduce the darker boxed lane the user disliked.
            .opacity(0.08)
            .allowsHitTesting(false)
    }

    private func referenceGridLiteralTileFieldVisible(
        presentationRect: CGRect,
        displayedTileRects: [CGRect]
    ) -> some View {
        let artboardWidth = referenceGridArtboardSize.width * artboardScale
        let artboardHeight = referenceGridArtboardSize.height * artboardScale

        return Image("genre-ref-grid")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(width: artboardWidth, height: artboardHeight)
            .offset(
                x: -presentationRect.minX * artboardScale,
                y: -presentationRect.minY * artboardScale
            )
            .frame(
                width: displayedArtboardSize.width,
                height: displayedArtboardSize.height,
                alignment: .topLeading
            )
            .mask(referenceGridTileFieldMask(displayedTileRects: displayedTileRects))
            .allowsHitTesting(false)
    }

    private func referenceGridLiteralTileBodyRestore(
        presentationRect: CGRect,
        displayedTileRects: [CGRect]
    ) -> some View {
        referenceGridLiteralTileFieldVisible(
            presentationRect: presentationRect,
            displayedTileRects: displayedTileRects
        )
        .saturation(1.06)
        .contrast(1.05)
        .brightness(0.012)
        .opacity(0.42)
    }

    private func referenceGridLiteralTileCorePop(
        presentationRect: CGRect,
        displayedTileRects: [CGRect]
    ) -> some View {
        referenceGridLiteralTileFieldVisible(
            presentationRect: presentationRect,
            displayedTileRects: displayedTileRects
        )
        .mask(referenceGridTileCoreMask(displayedTileRects: displayedTileRects))
        .saturation(1.12)
        .contrast(1.08)
        .brightness(0.018)
        .opacity(0.18)
    }

    private func referenceGridEmbeddedLaneMask(displayedTileRects: [CGRect]) -> some View {
        let tileCornerRadius = 22 * artboardScale
        // Keep the screenshot-context support close to the tiles so the lane
        // feels embedded, but avoid rebuilding the broad dark slab the user
        // called out in the blocked captures.
        let lanePad = max(10.0, displayTileWidth * 0.086)
        let laneBlur = max(4.8, displayTileWidth * 0.039)

        return ZStack {
            ForEach(Array(displayedTileRects.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(
                    cornerRadius: tileCornerRadius + (lanePad * 0.34),
                    style: .continuous
                )
                .fill(.white)
                .frame(
                    width: rect.width + (lanePad * 2),
                    height: rect.height + (lanePad * 2)
                )
                .position(x: rect.midX, y: rect.midY)
                .blur(radius: laneBlur)
            }
        }
        .compositingGroup()
    }

    private func referenceGridTileFieldMask(displayedTileRects: [CGRect]) -> some View {
        let tileCornerRadius = 22 * artboardScale
        // Keep the literal reference art focused on the illustrated tile cores so
        // the darker outer shell from `genre-ref-grid` does not read like a clean
        // boxed card wrapped around each thumbnail.
        let tileCoreInset = max(3.0, displayTileWidth * 0.030)
        let tileFieldPad = max(0.8, displayTileWidth * 0.006)
        let tileFieldBlur = max(1.8, displayTileWidth * 0.014)

        return ZStack {
            ForEach(Array(displayedTileRects.enumerated()), id: \.offset) { _, rect in
                let cornerRadius = max(0, tileCornerRadius - (tileCoreInset * 0.40) + (tileFieldPad * 0.12))
                let width = max(1, rect.width - (tileCoreInset * 2) + (tileFieldPad * 2))
                let height = max(1, rect.height - (tileCoreInset * 2) + (tileFieldPad * 2))

                referenceGridMaskTile(
                    rect: rect,
                    cornerRadius: cornerRadius,
                    width: width,
                    height: height,
                    blurRadius: tileFieldBlur
                )
            }
        }
        .compositingGroup()
    }

    private func referenceGridTileCoreMask(displayedTileRects: [CGRect]) -> some View {
        let tileCornerRadius = 22 * artboardScale
        // Tight extra pop for the illustrated card interiors only — enough to pull
        // the swirls / icon feel / per-card color treatment forward without letting
        // the darker literal grid shell reclaim the lane edges.
        let tileCoreInset = max(6.6, displayTileWidth * 0.052)
        let tileCorePad = max(0.4, displayTileWidth * 0.003)
        let tileCoreBlur = max(1.3, displayTileWidth * 0.010)

        return ZStack {
            ForEach(Array(displayedTileRects.enumerated()), id: \.offset) { _, rect in
                let cornerRadius = max(0, tileCornerRadius - (tileCoreInset * 0.56) + (tileCorePad * 0.10))
                let width = max(1, rect.width - (tileCoreInset * 2) + (tileCorePad * 2))
                let height = max(1, rect.height - (tileCoreInset * 2) + (tileCorePad * 2))

                referenceGridMaskTile(
                    rect: rect,
                    cornerRadius: cornerRadius,
                    width: width,
                    height: height,
                    blurRadius: tileCoreBlur
                )
            }
        }
        .compositingGroup()
    }

    private func referenceGridMaskTile(
        rect: CGRect,
        cornerRadius: CGFloat,
        width: CGFloat,
        height: CGFloat,
        blurRadius: CGFloat
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.white)
            .frame(width: width, height: height)
            .position(x: rect.midX, y: rect.midY)
            .blur(radius: blurRadius)
    }

    private func referenceGridGutterWash(
        presentationRect: CGRect,
        displayedTileRects: [CGRect]
    ) -> some View {
        let artboardWidth = referenceGridArtboardSize.width * artboardScale
        let artboardHeight = referenceGridArtboardSize.height * artboardScale
        let broadBlur = max(8.0, displayTileWidth * 0.11)
        let tightBlur = max(4.0, displayTileWidth * 0.052)

        return ZStack {
            Image("genre-ref-grid")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(width: artboardWidth, height: artboardHeight)
                .saturation(1.14)
                .contrast(1.01)
                .brightness(0.024)
                .scaleEffect(1.010)
                .blur(radius: broadBlur)
                .opacity(0.10)
                .blendMode(.screen)

            Image("genre-ref-grid")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(width: artboardWidth, height: artboardHeight)
                .saturation(1.08)
                .contrast(1.00)
                .brightness(0.014)
                .scaleEffect(1.004)
                .blur(radius: tightBlur)
                .opacity(0.14)
                .blendMode(.screen)
        }
        .offset(
            x: -presentationRect.minX * artboardScale,
            y: -presentationRect.minY * artboardScale
        )
        .frame(
            width: displayedArtboardSize.width,
            height: displayedArtboardSize.height,
            alignment: .topLeading
        )
        .mask(referenceGridGutterMask(displayedTileRects: displayedTileRects))
        .allowsHitTesting(false)
    }

    private func referenceGridGutterMask(displayedTileRects: [CGRect]) -> some View {
        // Let the matched reference-page context sit slightly closer to each tile's
        // outer spill so the lane feels less like isolated clean cards on a slab
        // and more like the embedded illustrated field from the screenshot.
        let tilePunchInset = max(1.2, displayTileWidth * 0.014)
        let tilePunchBlur = max(4.0, displayTileWidth * 0.042)
        let tileCornerRadius = 22 * artboardScale

        return ZStack {
            Rectangle()
                .fill(.white)

            ForEach(Array(displayedTileRects.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(
                    cornerRadius: max(0, tileCornerRadius - (tilePunchInset * 0.32)),
                    style: .continuous
                )
                .fill(.black)
                .frame(
                    width: rect.width + (tilePunchInset * 2),
                    height: rect.height + (tilePunchInset * 2)
                )
                .position(x: rect.midX, y: rect.midY)
                .blur(radius: tilePunchBlur)
                .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }

    private func referenceGridContextUnderlay(displayedTileRects: [CGRect]) -> some View {
        let blurRadius = max(2.6, displayTileWidth * 0.022)

        return ZStack {
            Image("genre-ref-grid-context")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(
                    width: displayedArtboardSize.width,
                    height: displayedArtboardSize.height
                )
                .saturation(1.07)
                .contrast(1.02)
                .brightness(0.012)
                .scaleEffect(1.004)
                .blur(radius: blurRadius)
                .opacity(0.48)
                .blendMode(.screen)

            Image("genre-ref-grid-context")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(
                    width: displayedArtboardSize.width,
                    height: displayedArtboardSize.height
                )
                .saturation(1.05)
                .contrast(1.02)
                .brightness(0.008)
                .opacity(0.78)
        }
        .mask(referenceGridGutterMask(displayedTileRects: displayedTileRects))
        .allowsHitTesting(false)
    }

    private func referenceGridLiteralVisible(presentationRect: CGRect) -> some View {
        let artboardWidth = referenceGridArtboardSize.width * artboardScale
        let artboardHeight = referenceGridArtboardSize.height * artboardScale

        return Image("genre-ref-grid")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(width: artboardWidth, height: artboardHeight)
            .offset(
                x: -presentationRect.minX * artboardScale,
                y: -presentationRect.minY * artboardScale
            )
            .frame(
                width: displayedArtboardSize.width,
                height: displayedArtboardSize.height,
                alignment: .topLeading
            )
            .allowsHitTesting(false)
    }

    private func referenceTilePresentation(
        id: String,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        let faceInset = max(0.55, width * 0.0048)
        let faceWidth = max(1, width - (faceInset * 2))
        let faceHeight = max(1, height - (faceInset * 2))
        let faceShape = RoundedRectangle(
            cornerRadius: max(0, cornerRadius - (faceInset * 0.48)),
            style: .continuous
        )

        return ZStack {
            referenceTileAtmosphere(
                id: id,
                width: width,
                height: height,
                cornerRadius: cornerRadius
            )

            referenceTileFace(
                id: id,
                width: faceWidth,
                height: faceHeight,
                shape: faceShape
            )
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func referenceTileAtmosphere(
        id: String,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        let glowWidth = width * 1.14
        let glowHeight = height * 1.12
        let glowBlur = max(4.0, width * 0.062)
        let glowShape = RoundedRectangle(
            cornerRadius: cornerRadius * 1.08,
            style: .continuous
        )

        return Image("genre-ref-\(id)")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(width: glowWidth, height: glowHeight)
            .saturation(1.08)
            .contrast(1.02)
            .brightness(0.03)
            .blur(radius: glowBlur)
            .opacity(0.28)
            .blendMode(.screen)
            .mask(
                glowShape
                    .fill(.white)
                    .frame(width: glowWidth, height: glowHeight)
                    .blur(radius: glowBlur * 0.62)
            )
            .allowsHitTesting(false)
    }

    private func referenceTileFace(
        id: String,
        width: CGFloat,
        height: CGFloat,
        shape: RoundedRectangle
    ) -> some View {
        Image("genre-ref-\(id)")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(width: width * 1.02, height: height * 1.02)
            .clipShape(shape)
            .frame(width: width, height: height)
            .contentShape(shape)
    }

    private var fallbackGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(128), spacing: 16, alignment: .top), count: 7)

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 15) {
            ForEach(cards) { card in
                ExploreGenreTile(card: card) {
                    onSelect(card)
                }
            }
        }
    }
}

private struct ExploreGenreTile: View {
    let card: ExploreMoodCard
    let onSelect: () -> Void
    @State private var isHovered = false

    private let cornerRadius: CGFloat = 17.0

    private struct Palette {
        let top: Color
        let mid: Color
        let bottom: Color
        let bloom: Color
        let rim: Color
        let artTint: Color
    }

    private struct TextureStyle {
        let scale: CGFloat
        let xOffset: CGFloat
        let yOffset: CGFloat
        let rotation: Double
        let textureOpacity: Double
        let colorOpacity: Double
        let glowOpacity: Double
        let glowBlur: CGFloat
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                if usesReferenceTileSnapshot {
                    referenceTileBackground
                } else {
                    tileBackground

                    tileContent
                        .padding(.horizontal, 9)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(usesReferenceTileSnapshot ? (227.0 / 251.0) : (80.0 / 84.0), contentMode: .fit)
            .clipShape(tileShape)
            .overlay {
                if usesReferenceTileSnapshot {
                    referenceTileSurfaceTreatment
                } else {
                    tileShape
                        .strokeBorder(.white.opacity(0.045), lineWidth: 0.55)

                    tileShape
                        .inset(by: 1)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white.opacity(0.34), location: 0.0),
                                    .init(color: palette.bloom.opacity(0.28), location: 0.08),
                                    .init(color: .white.opacity(0.10), location: 0.20),
                                    .init(color: .clear, location: 0.36),
                                    .init(color: .black.opacity(0.09), location: 0.76),
                                    .init(color: .black.opacity(0.18), location: 1.0),
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.95
                        )
                }
            }
            .shadow(color: .black.opacity(usesReferenceTileSnapshot ? 0.012 : 0.40), radius: usesReferenceTileSnapshot ? 0.35 : 18, y: usesReferenceTileSnapshot ? 0.15 : 12)
            .shadow(color: palette.bloom.opacity(usesReferenceTileSnapshot ? 0.0 : 0.10), radius: usesReferenceTileSnapshot ? 0 : 16, y: usesReferenceTileSnapshot ? 0 : 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(card.title), \(card.subtitle)"))
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
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var usesReferenceTileSnapshot: Bool {
        true
    }

    private var referenceTileImageName: String {
        "genre-ref-\(card.id)"
    }

    private var referenceTileBackground: some View {
        GeometryReader { proxy in
            let size = proxy.size

            Image(referenceTileImageName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .contrast(0.94)
                .saturation(1.01)
                .brightness(0.01)
                .scaledToFill()
                .frame(width: size.width, height: size.height, alignment: .center)
                .clipped()
                .compositingGroup()
        }
    }

    private var referenceTileSurfaceTreatment: some View {
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

    private var tileContent: some View {
        VStack(spacing: 6) {
            tileIcon

            VStack(spacing: 2) {
                Text(card.title)
                    .font(.system(size: 14.2, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.34), radius: 5, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(card.subtitle)
                    .font(.system(size: 7.0, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private var tileIcon: some View {
        ZStack {
            Circle()
                .fill(palette.bloom.opacity(0.15))
                .frame(width: 24, height: 24)
                .blur(radius: 8)

            tileSymbol
                .foregroundStyle(.black.opacity(0.26))
                .blur(radius: 0.9)
                .offset(y: 1.4)

            tileSymbol
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.99),
                            .white.opacity(0.88),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: palette.bloom.opacity(0.28), radius: 9, y: 0)
                .shadow(color: .black.opacity(0.36), radius: 8, y: 2)
                .overlay {
                    tileSymbol
                        .foregroundStyle(.white.opacity(0.18))
                        .blur(radius: 0.4)
                        .offset(y: -0.8)
                        .blendMode(.screen)
                }
        }
        .frame(height: 26)
    }

    @ViewBuilder
    private var tileSymbol: some View {
        switch card.id {
        case "scifi":
            RocketGlyph()
                .frame(width: 24, height: 24)
        case "animation":
            PlanetGlyph()
                .frame(width: 24, height: 24)
        default:
            Image(systemName: card.symbol)
                .font(.system(size: 22, weight: .bold))
                .frame(width: 24, height: 24)
        }
    }

    private var artworkFadeMask: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .white, location: 0.0),
                .init(color: .white.opacity(0.96), location: 0.24),
                .init(color: .white.opacity(0.84), location: 0.44),
                .init(color: .white.opacity(0.42), location: 0.66),
                .init(color: .clear, location: 0.86),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var prefersWindowOnlyArtwork: Bool {
        switch card.id {
        case "scifi", "drama", "fantasy", "animation", "classics", "new", "upcoming":
            return true
        default:
            return false
        }
    }

    private var usesSyntheticArtworkOnly: Bool {
        switch card.id {
        case "classics", "upcoming":
            return true
        default:
            return false
        }
    }

    private var speckleSeed: Int {
        card.id.unicodeScalars.reduce(5_381) { (($0 << 5) &+ $0) &+ Int($1.value) }
    }

    @ViewBuilder
    private var tileBackground: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                tileShape
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.top,
                                palette.mid,
                                palette.bottom,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let artName = card.artImageName, !prefersWindowOnlyArtwork, !usesSyntheticArtworkOnly {
                    artworkCore(
                        artName: artName,
                        size: size,
                        scale: textureStyle.scale * 1.10,
                        xOffset: textureStyle.xOffset,
                        yOffset: textureStyle.yOffset - 6,
                        rotation: textureStyle.rotation,
                        saturation: 0.10,
                        contrast: 1.74,
                        brightness: -0.36,
                        tint: palette.bottom,
                        opacity: textureStyle.textureOpacity * 0.74,
                        blur: 0.9,
                        blendMode: .multiply
                    )
                    .mask(artworkFadeMask)
                }

                if let artName = card.artImageName, !prefersWindowOnlyArtwork, !usesSyntheticArtworkOnly {
                    artworkCore(
                        artName: artName,
                        size: size,
                        scale: textureStyle.scale * 1.02,
                        xOffset: textureStyle.xOffset * 0.9,
                        yOffset: textureStyle.yOffset - 2,
                        rotation: textureStyle.rotation,
                        saturation: 1.10,
                        contrast: 1.16,
                        brightness: -0.08,
                        tint: palette.artTint,
                        opacity: textureStyle.colorOpacity * 0.16,
                        blur: 0.8,
                        blendMode: .softLight
                    )
                    .mask(artworkFadeMask)
                }

                if let artName = card.artImageName, prefersWindowOnlyArtwork, !usesSyntheticArtworkOnly {
                    artworkCore(
                        artName: artName,
                        size: size,
                        scale: textureStyle.scale * 1.68,
                        xOffset: textureStyle.xOffset * 1.6,
                        yOffset: textureStyle.yOffset - 34,
                        rotation: textureStyle.rotation,
                        saturation: 0.04,
                        contrast: 1.40,
                        brightness: -0.26,
                        tint: palette.bottom,
                        opacity: textureStyle.textureOpacity * 0.24,
                        blur: 5.2,
                        blendMode: .multiply
                    )
                    .mask(artworkFadeMask)
                }

                tileArtworkWindows(size: size)

                tileAccentArtwork(size: size)

                TileSpeckleTexture(
                    seed: speckleSeed,
                    color: palette.rim,
                    opacity: textureStyle.textureOpacity * 0.08
                )
                .blendMode(.screen)
                .mask(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.74),
                            .white.opacity(0.20),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                tileShape
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.10), location: 0.0),
                                .init(color: palette.bloom.opacity(0.12), location: 0.06),
                                .init(color: .clear, location: 0.18),
                                .init(color: .clear, location: 0.52),
                                .init(color: .black.opacity(0.10), location: 0.76),
                                .init(color: .black.opacity(0.22), location: 1.0),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                tileShape
                    .fill(
                        RadialGradient(
                            colors: [
                                .clear,
                                .clear,
                                .black.opacity(0.14),
                            ],
                            center: .center,
                            startRadius: 18,
                            endRadius: 94
                        )
                    )
            }
            .frame(width: size.width, height: size.height)
            .clipShape(tileShape)
        }
    }

    @ViewBuilder
    private func tileArtworkWindows(size: CGSize) -> some View {
        if let artName = card.artImageName, !usesSyntheticArtworkOnly {
            switch card.id {
        case "scifi":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 2.36,
                imageXOffset: 58,
                imageYOffset: -112,
                imageRotation: -6,
                tint: palette.artTint,
                opacity: 0.78,
                width: size.width * 0.96,
                height: size.height * 0.56,
                x: size.width * 0.04,
                y: -size.height * 0.30,
                rotation: -10,
                maskBlur: 4.6
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 2.08,
                imageXOffset: 22,
                imageYOffset: -94,
                imageRotation: -14,
                tint: palette.bloom,
                opacity: 0.42,
                width: size.width * 0.42,
                height: size.height * 0.28,
                x: -size.width * 0.16,
                y: -size.height * 0.18,
                rotation: -20,
                maskBlur: 3.6
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.54,
                imageXOffset: 74,
                imageYOffset: -80,
                imageRotation: -22,
                tint: palette.rim,
                opacity: 0.30,
                width: size.width * 0.72,
                height: size.height * 0.10,
                x: size.width * 0.10,
                y: -size.height * 0.04,
                rotation: -30,
                maskBlur: 2.6
            )
        case "drama":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.96,
                imageXOffset: 56,
                imageYOffset: -20,
                imageRotation: 2,
                tint: palette.artTint,
                opacity: 0.82,
                width: size.width * 0.66,
                height: size.height * 0.48,
                x: size.width * 0.22,
                y: -size.height * 0.18,
                rotation: 12,
                maskBlur: 4.5
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.88,
                imageXOffset: -58,
                imageYOffset: -16,
                imageRotation: -4,
                tint: palette.bloom,
                opacity: 0.52,
                width: size.width * 0.58,
                height: size.height * 0.42,
                x: -size.width * 0.22,
                y: -size.height * 0.18,
                rotation: -12,
                maskBlur: 4.0
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.40,
                imageXOffset: 24,
                imageYOffset: -12,
                imageRotation: -10,
                tint: palette.rim,
                opacity: 0.34,
                width: size.width * 0.90,
                height: size.height * 0.12,
                x: size.width * 0.04,
                y: 0,
                rotation: 22,
                maskBlur: 3.2
            )
        case "comedy":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.08,
                imageXOffset: 10,
                imageYOffset: -10,
                tint: palette.artTint,
                opacity: 0.74,
                width: size.width * 0.78,
                height: size.height * 0.56,
                x: size.width * 0.08,
                y: -size.height * 0.14,
                rotation: 6,
                maskBlur: 4.0
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.02,
                imageXOffset: -10,
                imageYOffset: -2,
                imageRotation: -8,
                tint: palette.bloom,
                opacity: 0.34,
                width: size.width * 0.88,
                height: size.height * 0.16,
                x: -size.width * 0.08,
                y: size.height * 0.06,
                rotation: -10,
                maskBlur: 3.5
            )
        case "action":
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.10,
                imageXOffset: 10,
                imageYOffset: -10,
                imageRotation: -8,
                tint: palette.bloom,
                opacity: 0.62,
                width: size.width * 1.02,
                height: size.height * 0.18,
                x: size.width * 0.04,
                y: -size.height * 0.02,
                rotation: -38,
                maskBlur: 3.0
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.04,
                imageXOffset: 20,
                imageYOffset: -16,
                imageRotation: -6,
                tint: palette.artTint,
                opacity: 0.52,
                width: size.width * 0.44,
                height: size.height * 0.36,
                x: size.width * 0.22,
                y: -size.height * 0.18,
                rotation: 6,
                maskBlur: 3.5
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 0.96,
                imageXOffset: -8,
                imageYOffset: 8,
                imageRotation: 6,
                tint: palette.rim,
                opacity: 0.34,
                width: size.width * 0.72,
                height: size.height * 0.12,
                x: -size.width * 0.18,
                y: size.height * 0.16,
                rotation: -22,
                maskBlur: 3.0
            )
        case "deep":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.12,
                imageXOffset: -8,
                imageYOffset: -10,
                tint: palette.artTint,
                opacity: 0.66,
                width: size.width * 0.84,
                height: size.height * 0.58,
                x: -size.width * 0.04,
                y: -size.height * 0.12,
                rotation: -8,
                maskBlur: 4.5
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.00,
                imageXOffset: 10,
                imageYOffset: -2,
                imageRotation: -12,
                tint: palette.bloom,
                opacity: 0.30,
                width: size.width * 0.92,
                height: size.height * 0.14,
                x: size.width * 0.06,
                y: size.height * 0.02,
                rotation: 18,
                maskBlur: 3.5
            )
        case "horror":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.04,
                imageXOffset: -12,
                imageYOffset: -18,
                tint: palette.artTint,
                opacity: 0.48,
                width: size.width * 0.52,
                height: size.height * 0.40,
                x: -size.width * 0.10,
                y: -size.height * 0.22,
                rotation: 0,
                maskBlur: 3.5
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.02,
                imageXOffset: 18,
                imageYOffset: -6,
                imageRotation: 10,
                tint: palette.bloom,
                opacity: 0.22,
                width: size.width * 0.54,
                height: size.height * 0.14,
                x: size.width * 0.18,
                y: -size.height * 0.04,
                rotation: -64,
                maskBlur: 3.0
            )
        case "animation":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.62,
                imageXOffset: 62,
                imageYOffset: -56,
                imageRotation: 8,
                tint: palette.artTint,
                opacity: 0.76,
                width: size.width * 0.90,
                height: size.height * 0.46,
                x: size.width * 0.08,
                y: -size.height * 0.26,
                rotation: -6,
                maskBlur: 3.6
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.48,
                imageXOffset: 94,
                imageYOffset: -28,
                imageRotation: 12,
                tint: palette.bloom,
                opacity: 0.40,
                width: size.width * 0.34,
                height: size.height * 0.24,
                x: size.width * 0.26,
                y: -size.height * 0.12,
                rotation: 0,
                maskBlur: 2.8
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.26,
                imageXOffset: 16,
                imageYOffset: 18,
                imageRotation: 8,
                tint: palette.rim,
                opacity: 0.28,
                width: size.width * 0.82,
                height: size.height * 0.12,
                x: size.width * 0.04,
                y: size.height * 0.14,
                rotation: 18,
                maskBlur: 3.2
            )
        case "mystery":
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.10,
                imageXOffset: -18,
                tint: palette.artTint,
                opacity: 0.48,
                width: size.width * 1.00,
                height: size.height * 0.24,
                x: -size.width * 0.16,
                y: size.height * 0.08,
                rotation: -82,
                maskBlur: 3.0
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.02,
                imageXOffset: 18,
                imageYOffset: -18,
                tint: palette.bloom,
                opacity: 0.40,
                width: size.width * 0.40,
                height: size.height * 0.32,
                x: size.width * 0.18,
                y: -size.height * 0.18,
                rotation: 0,
                maskBlur: 3.5
            )
        case "docs":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.06,
                imageXOffset: 10,
                imageYOffset: -8,
                tint: palette.artTint,
                opacity: 0.56,
                width: size.width * 0.58,
                height: size.height * 0.44,
                x: size.width * 0.10,
                y: -size.height * 0.12,
                rotation: 0,
                maskBlur: 4.0
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.02,
                imageXOffset: -6,
                imageYOffset: 6,
                imageRotation: -10,
                tint: palette.bloom,
                opacity: 0.32,
                width: size.width * 0.82,
                height: size.height * 0.14,
                x: size.width * 0.06,
                y: size.height * 0.18,
                rotation: 20,
                maskBlur: 3.5
            )
        case "fantasy":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.92,
                imageXOffset: 20,
                imageYOffset: -56,
                imageRotation: 2,
                tint: palette.artTint,
                opacity: 0.82,
                width: size.width * 0.92,
                height: size.height * 0.58,
                x: size.width * 0.08,
                y: -size.height * 0.26,
                rotation: 6,
                maskBlur: 4.8
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.26,
                imageXOffset: -18,
                imageYOffset: -22,
                imageRotation: -6,
                tint: palette.bloom,
                opacity: 0.40,
                width: size.width * 0.84,
                height: size.height * 0.12,
                x: size.width * 0.06,
                y: -size.height * 0.06,
                rotation: 18,
                maskBlur: 3.4
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.56,
                imageXOffset: -48,
                imageYOffset: -28,
                tint: palette.rim,
                opacity: 0.28,
                width: size.width * 0.38,
                height: size.height * 0.28,
                x: -size.width * 0.24,
                y: -size.height * 0.18,
                rotation: -18,
                maskBlur: 3.2
            )
        case "chill":
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.06,
                imageYOffset: 12,
                tint: palette.artTint,
                opacity: 0.64,
                width: size.width * 1.02,
                height: size.height * 0.24,
                x: size.width * 0.04,
                y: size.height * 0.10,
                rotation: 0,
                maskBlur: 3.5
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.00,
                imageXOffset: -16,
                imageYOffset: -18,
                tint: palette.bloom,
                opacity: 0.42,
                width: size.width * 0.44,
                height: size.height * 0.36,
                x: -size.width * 0.20,
                y: -size.height * 0.18,
                rotation: 0,
                maskBlur: 3.5
            )
        case "classics":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 2.10,
                imageXOffset: -48,
                imageYOffset: -44,
                imageRotation: -4,
                tint: palette.artTint,
                opacity: 0.56,
                width: size.width * 0.54,
                height: size.height * 0.36,
                x: -size.width * 0.20,
                y: -size.height * 0.24,
                rotation: -10,
                maskBlur: 3.8
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.78,
                imageXOffset: 38,
                imageYOffset: -12,
                imageRotation: 2,
                tint: palette.bloom,
                opacity: 0.22,
                width: size.width * 0.78,
                height: size.height * 0.14,
                x: size.width * 0.14,
                y: size.height * 0.08,
                rotation: 14,
                maskBlur: 3.0
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.60,
                imageXOffset: -24,
                imageYOffset: 8,
                tint: palette.rim,
                opacity: 0.18,
                width: size.width * 0.48,
                height: size.height * 0.36,
                x: size.width * 0.06,
                y: size.height * 0.14,
                rotation: 10,
                maskBlur: 3.2
            )
        case "new":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.94,
                imageXOffset: -24,
                imageYOffset: -56,
                imageRotation: -2,
                tint: palette.artTint,
                opacity: 0.82,
                width: size.width * 0.90,
                height: size.height * 0.58,
                x: -size.width * 0.04,
                y: -size.height * 0.24,
                rotation: -6,
                maskBlur: 4.8
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.32,
                imageXOffset: 42,
                imageYOffset: -22,
                imageRotation: -14,
                tint: palette.bloom,
                opacity: 0.46,
                width: size.width * 0.94,
                height: size.height * 0.14,
                x: size.width * 0.10,
                y: -size.height * 0.02,
                rotation: -24,
                maskBlur: 3.2
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.54,
                imageXOffset: 34,
                imageYOffset: -18,
                tint: palette.rim,
                opacity: 0.30,
                width: size.width * 0.34,
                height: size.height * 0.24,
                x: size.width * 0.24,
                y: -size.height * 0.18,
                rotation: 0,
                maskBlur: 3.0
            )
        case "upcoming":
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 2.02,
                imageXOffset: -64,
                imageYOffset: -24,
                imageRotation: 0,
                tint: palette.artTint,
                opacity: 0.82,
                width: size.width * 0.88,
                height: size.height * 0.54,
                x: -size.width * 0.08,
                y: -size.height * 0.18,
                rotation: -6,
                maskBlur: 4.4
            )
            accentArtworkRibbon(
                artName: artName,
                size: size,
                scaleMultiplier: 1.54,
                imageXOffset: -58,
                imageYOffset: 8,
                imageRotation: -4,
                tint: palette.bloom,
                opacity: 0.34,
                width: size.width * 0.94,
                height: size.height * 0.24,
                x: -size.width * 0.04,
                y: size.height * 0.04,
                rotation: 8,
                maskBlur: 3.8
            )
            accentArtworkBlob(
                artName: artName,
                size: size,
                scaleMultiplier: 1.72,
                imageXOffset: 58,
                imageYOffset: -36,
                tint: palette.rim,
                opacity: 0.24,
                width: size.width * 0.30,
                height: size.height * 0.22,
                x: size.width * 0.24,
                y: -size.height * 0.22,
                rotation: 0,
                maskBlur: 2.8
            )
        default:
            accentArtworkBlob(
                artName: artName,
                size: size,
                tint: palette.artTint,
                opacity: 0.48,
                width: size.width * 0.64,
                height: size.height * 0.42,
                x: 0,
                y: -size.height * 0.12,
                rotation: textureStyle.rotation,
                maskBlur: 3.5
            )
        }
        }
    }

    @ViewBuilder
    private func tileAccentArtwork(size: CGSize) -> some View {
        switch card.id {
        case "scifi":
            accentHalo(
                color: palette.bloom,
                width: size.width * 0.42,
                height: size.height * 0.24,
                lineWidth: size.width * 0.06,
                x: -size.width * 0.12,
                y: -size.height * 0.16,
                rotation: -22,
                opacity: 0.28,
                blur: 5
            )
            accentRibbon(
                colors: [.clear, palette.bloom.opacity(0.98), palette.rim.opacity(0.66), .clear],
                width: size.width * 0.92,
                height: size.height * 0.12,
                x: -size.width * 0.02,
                y: -size.height * 0.02,
                rotation: -38,
                blur: 6
            )
            accentRibbon(
                colors: [palette.top.opacity(0.76), .clear],
                width: size.width * 0.68,
                height: size.height * 0.12,
                x: size.width * 0.16,
                y: size.height * 0.22,
                rotation: 26,
                blur: 8
            )
            accentBlob(
                color: palette.rim,
                width: size.width * 0.50,
                height: size.height * 0.40,
                x: -size.width * 0.24,
                y: -size.height * 0.22,
                rotation: -10,
                opacity: 0.30,
                blur: 14
            )
            accentBlob(
                color: .white,
                width: size.width * 0.14,
                height: size.height * 0.14,
                x: size.width * 0.24,
                y: -size.height * 0.24,
                rotation: 0,
                opacity: 0.12,
                blur: 7
            )
            accentBlob(
                color: .black,
                width: size.width * 0.62,
                height: size.height * 0.56,
                x: size.width * 0.24,
                y: -size.height * 0.04,
                rotation: 14,
                opacity: 0.24,
                blur: 18,
                blendMode: .multiply
            )
        case "drama":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.60,
                height: size.height * 0.52,
                x: -size.width * 0.14,
                y: -size.height * 0.18,
                rotation: -18,
                opacity: 0.38,
                blur: 16
            )
            accentRibbon(
                colors: [palette.rim.opacity(0.80), palette.bloom.opacity(0.34), .clear],
                width: size.width * 0.80,
                height: size.height * 0.12,
                x: size.width * 0.04,
                y: size.height * 0.02,
                rotation: 26,
                blur: 7
            )
            accentRibbon(
                colors: [palette.top.opacity(0.44), .clear],
                width: size.width * 0.56,
                height: size.height * 0.10,
                x: -size.width * 0.18,
                y: size.height * 0.20,
                rotation: -34,
                blur: 9
            )
            accentBlob(
                color: .black,
                width: size.width * 0.58,
                height: size.height * 0.52,
                x: size.width * 0.20,
                y: size.height * 0.08,
                rotation: 10,
                opacity: 0.22,
                blur: 16,
                blendMode: .multiply
            )
        case "comedy":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.62,
                height: size.height * 0.56,
                x: -size.width * 0.04,
                y: -size.height * 0.02,
                rotation: -10,
                opacity: 0.44,
                blur: 18
            )
            accentBlob(
                color: palette.rim,
                width: size.width * 0.60,
                height: size.height * 0.50,
                x: size.width * 0.22,
                y: size.height * 0.18,
                rotation: 18,
                opacity: 0.24,
                blur: 22
            )
            accentRibbon(
                colors: [palette.top.opacity(0.46), .clear],
                width: size.width * 0.70,
                height: size.height * 0.14,
                x: -size.width * 0.16,
                y: -size.height * 0.18,
                rotation: -12,
                blur: 12
            )
        case "action":
            accentRibbon(
                colors: [.clear, palette.bloom.opacity(0.98), palette.rim.opacity(0.72), .clear],
                width: size.width * 0.98,
                height: size.height * 0.10,
                x: size.width * 0.04,
                y: -size.height * 0.02,
                rotation: -36,
                blur: 5
            )
            accentRibbon(
                colors: [palette.top.opacity(0.76), .clear],
                width: size.width * 0.74,
                height: size.height * 0.12,
                x: -size.width * 0.14,
                y: size.height * 0.20,
                rotation: -24,
                blur: 7
            )
            accentBlob(
                color: palette.rim,
                width: size.width * 0.50,
                height: size.height * 0.40,
                x: -size.width * 0.20,
                y: -size.height * 0.22,
                rotation: -12,
                opacity: 0.24,
                blur: 14
            )
            accentBlob(
                color: .black,
                width: size.width * 0.58,
                height: size.height * 0.56,
                x: size.width * 0.22,
                y: size.height * 0.16,
                rotation: 10,
                opacity: 0.28,
                blur: 18,
                blendMode: .multiply
            )
        case "deep":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.58,
                height: size.height * 0.52,
                x: -size.width * 0.08,
                y: -size.height * 0.02,
                rotation: -10,
                opacity: 0.34,
                blur: 18
            )
            accentBlob(
                color: palette.rim,
                width: size.width * 0.64,
                height: size.height * 0.54,
                x: size.width * 0.18,
                y: -size.height * 0.08,
                rotation: 18,
                opacity: 0.18,
                blur: 24
            )
            accentBlob(
                color: .black,
                width: size.width * 0.60,
                height: size.height * 0.56,
                x: size.width * 0.22,
                y: -size.height * 0.06,
                rotation: 0,
                opacity: 0.22,
                blur: 18,
                blendMode: .multiply
            )
        case "horror":
            accentRibbon(
                colors: [palette.bloom.opacity(0.62), .clear],
                width: size.width * 0.68,
                height: size.height * 0.12,
                x: -size.width * 0.10,
                y: size.height * 0.14,
                rotation: -78,
                blur: 8
            )
            accentBlob(
                color: palette.rim,
                width: size.width * 0.44,
                height: size.height * 0.56,
                x: -size.width * 0.20,
                y: -size.height * 0.14,
                rotation: 0,
                opacity: 0.20,
                blur: 16
            )
        case "animation":
            accentHalo(
                color: palette.bloom,
                width: size.width * 0.44,
                height: size.height * 0.24,
                lineWidth: size.width * 0.05,
                x: size.width * 0.10,
                y: -size.height * 0.10,
                rotation: -18,
                opacity: 0.30,
                blur: 5
            )
            accentBlob(
                color: palette.rim,
                width: size.width * 0.54,
                height: size.height * 0.46,
                x: -size.width * 0.18,
                y: -size.height * 0.22,
                rotation: 0,
                opacity: 0.30,
                blur: 14
            )
            accentRibbon(
                colors: [palette.top.opacity(0.80), .clear],
                width: size.width * 0.78,
                height: size.height * 0.12,
                x: size.width * 0.04,
                y: size.height * 0.22,
                rotation: 22,
                blur: 8
            )
            accentBlob(
                color: .white,
                width: size.width * 0.16,
                height: size.height * 0.16,
                x: size.width * 0.24,
                y: -size.height * 0.22,
                rotation: 0,
                opacity: 0.18,
                blur: 8
            )
            accentBlob(
                color: .white,
                width: size.width * 0.08,
                height: size.height * 0.08,
                x: -size.width * 0.04,
                y: -size.height * 0.28,
                rotation: 0,
                opacity: 0.12,
                blur: 5
            )
            accentBlob(
                color: .black,
                width: size.width * 0.54,
                height: size.height * 0.44,
                x: -size.width * 0.18,
                y: size.height * 0.20,
                rotation: 10,
                opacity: 0.14,
                blur: 14,
                blendMode: .multiply
            )
        case "mystery":
            accentRibbon(
                colors: [palette.bloom.opacity(0.84), palette.rim.opacity(0.34), .clear],
                width: size.width * 0.88,
                height: size.height * 0.16,
                x: -size.width * 0.16,
                y: size.height * 0.18,
                rotation: -22,
                blur: 12
            )
            accentBlob(
                color: palette.top,
                width: size.width * 0.62,
                height: size.height * 0.54,
                x: size.width * 0.18,
                y: -size.height * 0.18,
                rotation: 8,
                opacity: 0.22,
                blur: 20
            )
            accentBlob(
                color: .black,
                width: size.width * 0.60,
                height: size.height * 0.50,
                x: size.width * 0.18,
                y: -size.height * 0.14,
                rotation: 10,
                opacity: 0.22,
                blur: 18,
                blendMode: .multiply
            )
        case "docs":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.54,
                height: size.height * 0.46,
                x: -size.width * 0.12,
                y: -size.height * 0.04,
                rotation: -10,
                opacity: 0.26,
                blur: 18
            )
            accentRibbon(
                colors: [palette.rim.opacity(0.48), .clear],
                width: size.width * 0.72,
                height: size.height * 0.16,
                x: size.width * 0.12,
                y: size.height * 0.16,
                rotation: 18,
                blur: 12
            )
        case "fantasy":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.56,
                height: size.height * 0.44,
                x: -size.width * 0.16,
                y: -size.height * 0.18,
                rotation: -12,
                opacity: 0.28,
                blur: 16
            )
            accentRibbon(
                colors: [palette.rim.opacity(0.64), palette.top.opacity(0.30), .clear],
                width: size.width * 0.82,
                height: size.height * 0.12,
                x: size.width * 0.08,
                y: size.height * 0.06,
                rotation: 26,
                blur: 8
            )
            accentBlob(
                color: palette.top,
                width: size.width * 0.58,
                height: size.height * 0.46,
                x: size.width * 0.18,
                y: size.height * 0.16,
                rotation: 16,
                opacity: 0.24,
                blur: 18
            )
            accentBlob(
                color: .black,
                width: size.width * 0.56,
                height: size.height * 0.48,
                x: size.width * 0.06,
                y: -size.height * 0.22,
                rotation: 0,
                opacity: 0.20,
                blur: 16,
                blendMode: .multiply
            )
        case "chill":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.50,
                height: size.height * 0.42,
                x: -size.width * 0.16,
                y: size.height * 0.14,
                rotation: -10,
                opacity: 0.22,
                blur: 18
            )
            accentRibbon(
                colors: [palette.rim.opacity(0.42), .clear],
                width: size.width * 0.72,
                height: size.height * 0.14,
                x: size.width * 0.10,
                y: -size.height * 0.16,
                rotation: 14,
                blur: 10
            )
            accentRibbon(
                colors: [palette.top.opacity(0.28), .clear],
                width: size.width * 0.56,
                height: size.height * 0.10,
                x: -size.width * 0.18,
                y: -size.height * 0.02,
                rotation: -32,
                blur: 8
            )
        case "classics":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.66,
                height: size.height * 0.50,
                x: -size.width * 0.12,
                y: -size.height * 0.18,
                rotation: -10,
                opacity: 0.22,
                blur: 18
            )
            accentHalo(
                color: .white,
                width: size.width * 0.44,
                height: size.height * 0.22,
                lineWidth: size.width * 0.05,
                x: -size.width * 0.06,
                y: -size.height * 0.16,
                rotation: -20,
                opacity: 0.14,
                blur: 4
            )
            accentRibbon(
                colors: [.clear, palette.rim.opacity(0.72), palette.top.opacity(0.26), .clear],
                width: size.width * 0.92,
                height: size.height * 0.10,
                x: size.width * 0.02,
                y: -size.height * 0.04,
                rotation: -22,
                blur: 7
            )
            accentBlob(
                color: .white,
                width: size.width * 0.18,
                height: size.height * 0.18,
                x: size.width * 0.10,
                y: -size.height * 0.12,
                rotation: 0,
                opacity: 0.12,
                blur: 8
            )
            accentBlob(
                color: palette.top,
                width: size.width * 0.58,
                height: size.height * 0.46,
                x: size.width * 0.20,
                y: size.height * 0.16,
                rotation: 16,
                opacity: 0.22,
                blur: 18
            )
            accentBlob(
                color: .black,
                width: size.width * 0.58,
                height: size.height * 0.52,
                x: size.width * 0.22,
                y: size.height * 0.06,
                rotation: 10,
                opacity: 0.22,
                blur: 18,
                blendMode: .multiply
            )
        case "new":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.56,
                height: size.height * 0.46,
                x: -size.width * 0.02,
                y: size.height * 0.14,
                rotation: 0,
                opacity: 0.34,
                blur: 16
            )
            accentRibbon(
                colors: [.clear, palette.rim.opacity(0.78), palette.top.opacity(0.26), .clear],
                width: size.width * 0.84,
                height: size.height * 0.10,
                x: size.width * 0.06,
                y: -size.height * 0.04,
                rotation: -24,
                blur: 6
            )
            accentBlob(
                color: palette.rim,
                width: size.width * 0.54,
                height: size.height * 0.44,
                x: -size.width * 0.18,
                y: -size.height * 0.18,
                rotation: 0,
                opacity: 0.18,
                blur: 14
            )
            accentBlob(
                color: .black,
                width: size.width * 0.52,
                height: size.height * 0.48,
                x: size.width * 0.20,
                y: size.height * 0.18,
                rotation: 12,
                opacity: 0.22,
                blur: 16,
                blendMode: .multiply
            )
        case "upcoming":
            accentBlob(
                color: palette.bloom,
                width: size.width * 0.48,
                height: size.height * 0.40,
                x: size.width * 0.18,
                y: -size.height * 0.20,
                rotation: 0,
                opacity: 0.24,
                blur: 14
            )
            accentRibbon(
                colors: [.clear, .white.opacity(0.28), .clear],
                width: size.width * 0.10,
                height: size.height * 0.66,
                x: size.width * 0.22,
                y: 0,
                rotation: 0,
                blur: 8
            )
            accentRibbon(
                colors: [.clear, palette.rim.opacity(0.22), .clear],
                width: size.width * 0.08,
                height: size.height * 0.58,
                x: -size.width * 0.20,
                y: -size.height * 0.02,
                rotation: 0,
                blur: 8
            )
            accentRibbon(
                colors: [palette.rim.opacity(0.54), .clear],
                width: size.width * 0.80,
                height: size.height * 0.12,
                x: -size.width * 0.04,
                y: size.height * 0.18,
                rotation: 16,
                blur: 8
            )
            accentRibbon(
                colors: [palette.top.opacity(0.30), .clear],
                width: size.width * 0.58,
                height: size.height * 0.10,
                x: size.width * 0.18,
                y: -size.height * 0.02,
                rotation: -24,
                blur: 8
            )
        default:
            accentRibbon(
                colors: [palette.bloom.opacity(0.62), palette.rim.opacity(0.24), .clear],
                width: size.width * 0.76,
                height: size.height * 0.16,
                x: -size.width * 0.08,
                y: size.height * 0.12,
                rotation: textureStyle.rotation - 12,
                blur: 10
            )
            accentBlob(
                color: palette.rim,
                width: size.width * 0.50,
                height: size.height * 0.50,
                x: size.width * 0.14,
                y: -size.height * 0.12,
                rotation: 0,
                opacity: 0.18,
                blur: 16
            )
        }
    }

    private func artworkCore(
        artName: String,
        size: CGSize,
        scale: CGFloat,
        xOffset: CGFloat,
        yOffset: CGFloat,
        rotation: Double,
        saturation: Double,
        contrast: Double,
        brightness: Double,
        tint: Color,
        opacity: Double,
        blur: CGFloat,
        blendMode: BlendMode
    ) -> some View {
        Image(artName)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .saturation(saturation)
            .contrast(contrast)
            .brightness(brightness)
            .colorMultiply(tint)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .offset(x: xOffset, y: yOffset)
            .blur(radius: blur)
            .opacity(opacity)
            .blendMode(blendMode)
    }

    private func accentArtworkBlob(
        artName: String,
        size: CGSize,
        scaleMultiplier: CGFloat = 1.0,
        imageXOffset: CGFloat = 0,
        imageYOffset: CGFloat = 0,
        imageRotation: Double = 0,
        saturation: Double = 1.18,
        contrast: Double = 1.20,
        brightness: Double = 0.04,
        tint: Color,
        opacity: Double,
        blur: CGFloat = 0.8,
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat,
        rotation: Double = 0,
        maskBlur: CGFloat = 4.0,
        blendMode: BlendMode = .screen
    ) -> some View {
        artworkCore(
            artName: artName,
            size: size,
            scale: textureStyle.scale * scaleMultiplier,
            xOffset: textureStyle.xOffset + imageXOffset,
            yOffset: textureStyle.yOffset + imageYOffset,
            rotation: textureStyle.rotation + imageRotation,
            saturation: saturation,
            contrast: contrast,
            brightness: brightness,
            tint: tint,
            opacity: opacity,
            blur: blur,
            blendMode: blendMode
        )
        .mask(
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white,
                            .white.opacity(0.94),
                            .white.opacity(0.52),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.56
                    )
                )
                .frame(width: width, height: height)
                .rotationEffect(.degrees(rotation))
                .offset(x: x, y: y)
                .blur(radius: maskBlur)
        )
    }

    private func accentArtworkRibbon(
        artName: String,
        size: CGSize,
        scaleMultiplier: CGFloat = 1.0,
        imageXOffset: CGFloat = 0,
        imageYOffset: CGFloat = 0,
        imageRotation: Double = 0,
        saturation: Double = 1.18,
        contrast: Double = 1.20,
        brightness: Double = 0.04,
        tint: Color,
        opacity: Double,
        blur: CGFloat = 0.7,
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat,
        rotation: Double,
        maskBlur: CGFloat = 3.0,
        blendMode: BlendMode = .screen
    ) -> some View {
        artworkCore(
            artName: artName,
            size: size,
            scale: textureStyle.scale * scaleMultiplier,
            xOffset: textureStyle.xOffset + imageXOffset,
            yOffset: textureStyle.yOffset + imageYOffset,
            rotation: textureStyle.rotation + imageRotation,
            saturation: saturation,
            contrast: contrast,
            brightness: brightness,
            tint: tint,
            opacity: opacity,
            blur: blur,
            blendMode: blendMode
        )
        .mask(
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.84),
                            .white,
                            .white.opacity(0.74),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: height)
                .rotationEffect(.degrees(rotation))
                .offset(x: x, y: y)
                .blur(radius: maskBlur)
        )
    }

    private func accentBlob(
        color: Color,
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat,
        rotation: Double,
        opacity: Double,
        blur: CGFloat,
        blendMode: BlendMode = .screen
    ) -> some View {
        Ellipse()
            .fill(color.opacity(opacity))
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
            .blur(radius: blur)
            .blendMode(blendMode)
    }

    private func accentRibbon(
        colors: [Color],
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat,
        rotation: Double,
        blur: CGFloat,
        blendMode: BlendMode = .screen
    ) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
            .blur(radius: blur)
            .blendMode(blendMode)
    }

    private func accentHalo(
        color: Color,
        width: CGFloat,
        height: CGFloat,
        lineWidth: CGFloat,
        x: CGFloat,
        y: CGFloat,
        rotation: Double,
        opacity: Double,
        blur: CGFloat,
        blendMode: BlendMode = .screen
    ) -> some View {
        Ellipse()
            .strokeBorder(color.opacity(opacity), lineWidth: lineWidth)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
            .blur(radius: blur)
            .blendMode(blendMode)
    }

    private var textureStyle: TextureStyle {
        switch card.id {
        case "scifi":
            return TextureStyle(scale: 1.54, xOffset: -8, yOffset: -6, rotation: -14, textureOpacity: 0.60, colorOpacity: 0.46, glowOpacity: 0.22, glowBlur: 5.5)
        case "drama":
            return TextureStyle(scale: 1.58, xOffset: 9, yOffset: -4, rotation: -6, textureOpacity: 0.56, colorOpacity: 0.44, glowOpacity: 0.24, glowBlur: 5.5)
        case "comedy":
            return TextureStyle(scale: 1.56, xOffset: -5, yOffset: -2, rotation: -8, textureOpacity: 0.50, colorOpacity: 0.36, glowOpacity: 0.20, glowBlur: 6)
        case "action":
            return TextureStyle(scale: 1.62, xOffset: 7, yOffset: -6, rotation: -12, textureOpacity: 0.60, colorOpacity: 0.44, glowOpacity: 0.22, glowBlur: 4.5)
        case "deep":
            return TextureStyle(scale: 1.52, xOffset: 0, yOffset: 0, rotation: 0, textureOpacity: 0.58, colorOpacity: 0.40, glowOpacity: 0.24, glowBlur: 6)
        case "horror":
            return TextureStyle(scale: 1.50, xOffset: 12, yOffset: -7, rotation: 0, textureOpacity: 0.48, colorOpacity: 0.30, glowOpacity: 0.18, glowBlur: 5)
        case "animation":
            return TextureStyle(scale: 1.56, xOffset: 6, yOffset: -3, rotation: -2, textureOpacity: 0.56, colorOpacity: 0.44, glowOpacity: 0.24, glowBlur: 5.5)
        case "mystery":
            return TextureStyle(scale: 1.60, xOffset: -9, yOffset: 3, rotation: -6, textureOpacity: 0.50, colorOpacity: 0.36, glowOpacity: 0.21, glowBlur: 6)
        case "docs":
            return TextureStyle(scale: 1.56, xOffset: 6, yOffset: 2, rotation: 0, textureOpacity: 0.52, colorOpacity: 0.36, glowOpacity: 0.21, glowBlur: 6)
        case "fantasy":
            return TextureStyle(scale: 1.58, xOffset: -5, yOffset: -4, rotation: -8, textureOpacity: 0.56, colorOpacity: 0.42, glowOpacity: 0.24, glowBlur: 5.5)
        case "chill":
            return TextureStyle(scale: 1.52, xOffset: 4, yOffset: 5, rotation: 2, textureOpacity: 0.50, colorOpacity: 0.38, glowOpacity: 0.22, glowBlur: 6.5)
        case "classics":
            return TextureStyle(scale: 1.56, xOffset: 9, yOffset: 1, rotation: 0, textureOpacity: 0.60, colorOpacity: 0.34, glowOpacity: 0.20, glowBlur: 5)
        case "new":
            return TextureStyle(scale: 1.62, xOffset: 4, yOffset: -4, rotation: -6, textureOpacity: 0.56, colorOpacity: 0.40, glowOpacity: 0.24, glowBlur: 4.5)
        case "upcoming":
            return TextureStyle(scale: 1.50, xOffset: -2, yOffset: 2, rotation: -2, textureOpacity: 0.52, colorOpacity: 0.36, glowOpacity: 0.20, glowBlur: 5)
        default:
            return TextureStyle(scale: 1.56, xOffset: 0, yOffset: 0, rotation: 0, textureOpacity: 0.50, colorOpacity: 0.36, glowOpacity: 0.20, glowBlur: 6)
        }
    }

    private var palette: Palette {
        switch card.id {
        case "scifi":
            return Palette(
                top: Color(red: 0.18, green: 0.84, blue: 1.0),
                mid: Color(red: 0.22, green: 0.24, blue: 0.94),
                bottom: Color(red: 0.05, green: 0.07, blue: 0.28),
                bloom: Color(red: 0.54, green: 0.94, blue: 1.0),
                rim: Color(red: 0.78, green: 0.50, blue: 1.0),
                artTint: Color(red: 0.72, green: 0.92, blue: 1.0)
            )
        case "drama":
            return Palette(
                top: Color(red: 0.98, green: 0.38, blue: 0.78),
                mid: Color(red: 0.82, green: 0.12, blue: 0.56),
                bottom: Color(red: 0.24, green: 0.06, blue: 0.19),
                bloom: Color(red: 1.0, green: 0.56, blue: 0.86),
                rim: Color(red: 1.0, green: 0.42, blue: 0.74),
                artTint: Color(red: 0.98, green: 0.60, blue: 0.84)
            )
        case "comedy":
            return Palette(
                top: Color(red: 1.0, green: 0.91, blue: 0.36),
                mid: Color(red: 1.0, green: 0.70, blue: 0.20),
                bottom: Color(red: 0.62, green: 0.28, blue: 0.08),
                bloom: Color(red: 1.0, green: 0.95, blue: 0.52),
                rim: Color(red: 1.0, green: 0.75, blue: 0.30),
                artTint: Color(red: 1.0, green: 0.85, blue: 0.44)
            )
        case "action":
            return Palette(
                top: Color(red: 1.0, green: 0.48, blue: 0.22),
                mid: Color(red: 0.96, green: 0.16, blue: 0.10),
                bottom: Color(red: 0.30, green: 0.04, blue: 0.06),
                bloom: Color(red: 1.0, green: 0.78, blue: 0.34),
                rim: Color(red: 1.0, green: 0.52, blue: 0.20),
                artTint: Color(red: 1.0, green: 0.66, blue: 0.28)
            )
        case "deep":
            return Palette(
                top: Color(red: 0.66, green: 0.38, blue: 1.0),
                mid: Color(red: 0.36, green: 0.14, blue: 0.72),
                bottom: Color(red: 0.12, green: 0.06, blue: 0.28),
                bloom: Color(red: 0.88, green: 0.56, blue: 1.0),
                rim: Color(red: 0.50, green: 0.34, blue: 1.0),
                artTint: Color(red: 0.78, green: 0.52, blue: 1.0)
            )
        case "horror":
            return Palette(
                top: Color(red: 0.54, green: 0.08, blue: 0.12),
                mid: Color(red: 0.22, green: 0.03, blue: 0.07),
                bottom: Color(red: 0.06, green: 0.01, blue: 0.03),
                bloom: Color(red: 1.0, green: 0.34, blue: 0.30),
                rim: Color(red: 0.82, green: 0.14, blue: 0.20),
                artTint: Color(red: 0.86, green: 0.20, blue: 0.20)
            )
        case "animation":
            return Palette(
                top: Color(red: 0.62, green: 0.98, blue: 1.0),
                mid: Color(red: 0.34, green: 0.78, blue: 0.96),
                bottom: Color(red: 0.10, green: 0.36, blue: 0.50),
                bloom: Color(red: 0.96, green: 1.0, blue: 1.0),
                rim: Color(red: 0.76, green: 0.94, blue: 1.0),
                artTint: Color(red: 0.86, green: 0.98, blue: 1.0)
            )
        case "mystery":
            return Palette(
                top: Color(red: 0.08, green: 0.58, blue: 0.54),
                mid: Color(red: 0.05, green: 0.28, blue: 0.28),
                bottom: Color(red: 0.03, green: 0.10, blue: 0.12),
                bloom: Color(red: 0.28, green: 0.98, blue: 0.96),
                rim: Color(red: 0.12, green: 0.78, blue: 0.76),
                artTint: Color(red: 0.24, green: 0.84, blue: 0.80)
            )
        case "docs":
            return Palette(
                top: Color(red: 0.54, green: 0.66, blue: 0.20),
                mid: Color(red: 0.30, green: 0.42, blue: 0.14),
                bottom: Color(red: 0.12, green: 0.18, blue: 0.10),
                bloom: Color(red: 0.84, green: 0.94, blue: 0.38),
                rim: Color(red: 0.60, green: 0.82, blue: 0.28),
                artTint: Color(red: 0.78, green: 0.90, blue: 0.44)
            )
        case "fantasy":
            return Palette(
                top: Color(red: 0.52, green: 0.82, blue: 1.0),
                mid: Color(red: 0.48, green: 0.28, blue: 0.96),
                bottom: Color(red: 0.14, green: 0.08, blue: 0.34),
                bloom: Color(red: 0.96, green: 0.64, blue: 1.0),
                rim: Color(red: 0.76, green: 0.82, blue: 1.0),
                artTint: Color(red: 0.86, green: 0.86, blue: 1.0)
            )
        case "chill":
            return Palette(
                top: Color(red: 0.70, green: 1.0, blue: 0.84),
                mid: Color(red: 0.40, green: 0.86, blue: 0.68),
                bottom: Color(red: 0.10, green: 0.28, blue: 0.20),
                bloom: Color(red: 0.92, green: 1.0, blue: 0.94),
                rim: Color(red: 0.64, green: 0.96, blue: 0.82),
                artTint: Color(red: 0.82, green: 1.0, blue: 0.90)
            )
        case "classics":
            return Palette(
                top: Color(red: 0.28, green: 0.38, blue: 0.52),
                mid: Color(red: 0.16, green: 0.22, blue: 0.32),
                bottom: Color(red: 0.09, green: 0.13, blue: 0.18),
                bloom: Color(red: 0.70, green: 0.82, blue: 0.94),
                rim: Color(red: 0.46, green: 0.58, blue: 0.76),
                artTint: Color(red: 0.66, green: 0.78, blue: 0.90)
            )
        case "new":
            return Palette(
                top: Color(red: 1.0, green: 0.32, blue: 0.16),
                mid: Color(red: 0.84, green: 0.06, blue: 0.08),
                bottom: Color(red: 0.22, green: 0.03, blue: 0.04),
                bloom: Color(red: 1.0, green: 0.78, blue: 0.32),
                rim: Color(red: 1.0, green: 0.48, blue: 0.18),
                artTint: Color(red: 1.0, green: 0.62, blue: 0.24)
            )
        case "upcoming":
            return Palette(
                top: Color(red: 0.72, green: 0.84, blue: 1.0),
                mid: Color(red: 0.40, green: 0.60, blue: 0.82),
                bottom: Color(red: 0.18, green: 0.28, blue: 0.40),
                bloom: Color(red: 0.92, green: 0.96, blue: 1.0),
                rim: Color(red: 0.74, green: 0.86, blue: 1.0),
                artTint: Color(red: 0.82, green: 0.90, blue: 1.0)
            )
        default:
            return Palette(
                top: card.color.opacity(0.92),
                mid: card.color.opacity(0.66),
                bottom: card.color.opacity(0.34),
                bloom: card.color,
                rim: .white.opacity(0.4),
                artTint: card.color
            )
        }
    }
}

private struct TileSpeckleTexture: View {
    let seed: Int
    let color: Color
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            for index in 0..<42 {
                let x = sample(index, salt: 11) * size.width
                let y = sample(index, salt: 23) * size.height
                let diameter = 0.8 + sample(index, salt: 37) * 2.2
                let alpha = opacity * (0.10 + sample(index, salt: 51) * 0.42)
                let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(alpha))
                )
            }

            for index in 0..<7 {
                let x = sample(index, salt: 79) * size.width
                let y = sample(index, salt: 97) * size.height
                let width = 9 + sample(index, salt: 131) * 18
                let height = 3 + sample(index, salt: 149) * 6
                let rect = CGRect(x: x, y: y, width: width, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: height / 2),
                    with: .color(color.opacity(opacity * 0.05))
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func sample(_ index: Int, salt: Int) -> CGFloat {
        let value = sin(Double(seed &* 97 &+ index &* 31 &+ salt) * 12.9898) * 43_758.5453
        return CGFloat(value - floor(value))
    }
}

private struct RocketGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .frame(width: size * 0.22, height: size * 0.46)
                    .offset(x: -size * 0.01, y: -size * 0.02)

                TriangleShape()
                    .frame(width: size * 0.18, height: size * 0.18)
                    .offset(x: -size * 0.01, y: -size * 0.32)

                TriangleShape()
                    .frame(width: size * 0.13, height: size * 0.16)
                    .rotationEffect(.degrees(42))
                    .offset(x: -size * 0.14, y: size * 0.02)

                TriangleShape()
                    .frame(width: size * 0.13, height: size * 0.16)
                    .rotationEffect(.degrees(-42))
                    .offset(x: size * 0.12, y: size * 0.10)

                TriangleShape()
                    .frame(width: size * 0.11, height: size * 0.14)
                    .scaleEffect(x: 1, y: -1)
                    .offset(x: -size * 0.01, y: size * 0.28)
            }
            .rotationEffect(.degrees(-34))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PlanetGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle()
                    .strokeBorder(lineWidth: size * 0.11)
                    .frame(width: size * 0.44, height: size * 0.44)
                    .offset(x: -size * 0.01, y: size * 0.01)

                Ellipse()
                    .strokeBorder(lineWidth: size * 0.10)
                    .frame(width: size * 0.74, height: size * 0.24)
                    .rotationEffect(.degrees(-18))
                    .offset(y: size * 0.03)

                Circle()
                    .frame(width: size * 0.10, height: size * 0.10)
                    .offset(x: size * 0.27, y: -size * 0.18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
