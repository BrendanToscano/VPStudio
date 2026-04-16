import re

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write("""import SwiftUI

struct ExploreGenreGrid: View {
    let cards: [ExploreMoodCard]
    let onSelect: (ExploreMoodCard) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Browse by Genre & Mood")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 16) {
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
            ZStack {
                tileArtwork
                Color.black.opacity(0.15)
                tileContent
            }
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
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

    private var tileArtwork: some View {
        Group {
            if let artName = card.artImageName {
                Image(artName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [card.color.opacity(0.8), card.color.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .saturation(1.3)
    }

    private var tileContent: some View {
        VStack(spacing: 12) {
            Image(systemName: card.symbol)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

            VStack(spacing: 4) {
                Text(card.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .lineLimit(1)

                Text(card.subtitle.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .tracking(1.2)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .lineLimit(1)
            }
        }
        .padding(8)
    }
}
""")

with open("VPStudio/Views/Windows/Search/RecentSearchesSection.swift", "w") as f:
    f.write("""import SwiftUI

struct RecentSearchesSection: View {
    let searches: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                Text("Recent")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button("Clear All") {
                    onClear()
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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
        HStack(spacing: 8) {
            Button(action: onSelect) {
                Text(term)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
        }
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }
}
""")

import sys
with open("VPStudio/Views/Windows/Search/SearchView.swift", "r") as f:
    sv = f.read()

# 1. Update maxWidth
sv = re.sub(r'private let contentMaxWidth: CGFloat = 980', r'private let contentMaxWidth: CGFloat = 1360', sv)

# 2. Update searchBarSection
search_bar = """    private var searchBarSection: some View {
        centeredStage {
            VStack(alignment: .leading, spacing: 16) {
                Text("Explore")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(alignment: .center, spacing: 16) {
                    SearchQueryBar(
                        viewModel: viewModel,
                        seedQuery: searchDraft,
                        suppressNextDraftDebounce: $suppressNextSearchDraftDebounce,
                        placeholder: "Movies, TV shows, and more...",
                        onSubmit: { text in submitSearch(queryText: text) },
                        onClear: {
                            searchDraft = ""
                            viewModel.clear()
                        }
                    )
                    .frame(maxWidth: .infinity)

                    askAIButton

                    filterUtilityButton
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }"""
sv = re.sub(r'private var searchBarSection: some View \{.*?(?=\n    private var searchHeroCompanionPanel: some View)', search_bar + "\n\n", sv, flags=re.DOTALL)

# 3. Update askAIButton
ai_btn = """    private var askAIButton: some View {
        Button {
            guard aiButtonEnabled else { return }
            viewModel.fetchAIRecommendations(aiManager: appState.aiAssistantManager)
        } label: {
            HStack(spacing: 8) {
                if viewModel.isLoadingAI {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .medium))
                }

                Text(viewModel.isLoadingAI ? "Curating" : "Curate For Me")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                            .shadow(color: .white.opacity(0.5), radius: 4, y: 0)
                    }
            }
        }
        .buttonStyle(.plain)
        .opacity(aiButtonEnabled ? 1.0 : 0.5)
        .allowsHitTesting(aiButtonEnabled)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }"""
sv = re.sub(r'private var askAIButton: some View \{.*?(?=\n    private var filterUtilityButton: some View)', ai_btn + "\n\n", sv, flags=re.DOTALL)

# 4. Update filterUtilityButton
filter_btn = """    private var filterUtilityButton: some View {
        Button {
            isShowingFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            }
                    }

                if viewModel.activeFilterCount > 0 {
                    Text("\(viewModel.activeFilterCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red, in: Capsule())
                        .offset(x: 5, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }"""
sv = re.sub(r'private var filterUtilityButton: some View \{.*?(?=\n    private var curationBanner: some View)', filter_btn + "\n\n", sv, flags=re.DOTALL)

# 5. Update typeFilterSection and typeFilterButton
type_filter = """    private var typeFilterSection: some View {
        HStack(spacing: 0) {
            typeFilterButton(title: "All", type: nil)
            typeFilterButton(title: "Movies", type: .movie)
            typeFilterButton(title: "TV Shows", type: .series)
        }
        .padding(4)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }

    private func typeFilterButton(title: String, type: MediaType?) -> some View {
        let isSelected = viewModel.selectedType == type

        return Button {
            setSelectedType(type)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.black.opacity(0.9) : .white.opacity(0.7))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(red: 0.3, green: 0.9, blue: 0.95))
                            .shadow(color: Color(red: 0.3, green: 0.9, blue: 0.95).opacity(0.5), radius: 8, y: 0)
                    }
                }
        }
        .buttonStyle(.plain)
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }"""
sv = re.sub(r'private var typeFilterSection: some View \{.*?(?=\n    private func setSelectedType\(_ type: MediaType\?\))', type_filter + "\n\n", sv, flags=re.DOTALL)

# 6. Update SearchQueryBar styling
bar_body = """    var body: some View {
        HStack(spacing: 12) {
            leadingIndicator
            draftField

            if showsClearButton {
                clearButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSearching)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .contentShape(Capsule())
        .onTapGesture {
            isSearchFieldFocused = true
        }
        .animation(.easeInOut(duration: 0.18), value: showsClearButton)
    }"""
sv = re.sub(r'    var body: some View \{\n        HStack\(spacing: 10\).*?(?=\n\}\n\n// MARK: - Search Results Grid)', bar_body, sv, flags=re.DOTALL)

# 7. Update exploreIdleContent padding to match image spacing
idle_content = """    private var exploreIdleContent: some View {
        ScrollView {
            centeredStage {
                VStack(alignment: .leading, spacing: 32) {
                    if !viewModel.recentSearches.isEmpty {
                        RecentSearchesSection(
                            searches: viewModel.recentSearches,
                            onSelect: { term in
                                submitSearch(queryText: term)
                            },
                            onRemove: { term in
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    viewModel.removeRecentSearch(term)
                                }
                                viewModel.saveRecentSearches(to: appState.settingsManager)
                            },
                            onClear: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    viewModel.clearRecentSearches()
                                }
                                viewModel.saveRecentSearches(to: appState.settingsManager)
                            }
                        )
                        .transition(.opacity)
                    }

                    ExploreGenreGrid(
                        cards: ExploreGenreCatalog.cards,
                        onSelect: { card in
                            viewModel.selectMoodCard(card)
                        }
                    )
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
    }"""
sv = re.sub(r'    private var exploreIdleContent: some View \{.*?(?=\n    // MARK: - Error Content)', idle_content + "\n\n", sv, flags=re.DOTALL)

# 8. Update atmospheric background to be brighter/more colorful
bg = """                atmosphericGlow(color: atmosphericBlue, width: size.width * 0.45, height: size.height * 0.55)
                    .offset(x: -size.width * 0.2, y: -size.height * 0.1)

                atmosphericGlow(color: atmosphericPink, width: size.width * 0.35, height: size.height * 0.45)
                    .offset(x: -size.width * 0.05, y: -size.height * 0.1)

                atmosphericGlow(color: atmosphericGreen, width: size.width * 0.35, height: size.height * 0.45)
                    .offset(x: size.width * 0.1, y: -size.height * 0.1)

                atmosphericGlow(color: atmosphericPink, width: size.width * 0.35, height: size.height * 0.45)
                    .offset(x: size.width * 0.15, y: size.height * 0.1)

                atmosphericGlow(color: atmosphericGreen, width: size.width * 0.35, height: size.height * 0.45)
                    .offset(x: size.width * 0.3, y: size.height * 0.1)

                atmosphericGlow(color: atmosphericGold, width: size.width * 0.3, height: size.height * 0.35)
                    .offset(x: size.width * 0.4, y: size.height * 0.2)"""
sv = re.sub(r'                atmosphericGlow\(color: atmosphericBlue, width: size.width \* 0.28.*?(?=\n                Rectangle\(\))', bg + "\n", sv, flags=re.DOTALL)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "w") as f:
    f.write(sv)

