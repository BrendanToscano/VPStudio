import re

def update_file(path, replacements):
    with open(path, 'r') as f:
        content = f.read()
    
    for old, new in replacements:
        if old not in content:
            print(f"Warning: Could not find '{old}' in {path}")
        content = content.replace(old, new)
        
    with open(path, 'w') as f:
        f.write(content)

# 1. Update RecentSearchesSection.swift
recent_old = """        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text("Recent")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))

                Spacer(minLength: 12)

                Button("Clear All") {
                    onClear()
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
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
                .padding(.trailing, 24)
            }
        }"""
recent_new = """        HStack(alignment: .center, spacing: 12) {
            Text("Recent")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(searches, id: \.self) { term in
                        RecentSearchChip(
                            term: term,
                            onSelect: { onSelect(term) },
                            onRemove: { onRemove(term) }
                        )
                    }
                }
            }

            Spacer()

            Button("Clear All") {
                onClear()
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.40))
            .buttonStyle(.plain)
            #if os(visionOS)
            .hoverEffect(.highlight)
            #endif
        }"""
update_file("VPStudio/Views/Windows/Search/RecentSearchesSection.swift", [(recent_old, recent_new)])


# 2. Update SearchView.swift
search_old1 = """    private var searchBarSection: some View {
        centeredStage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Explore")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.98))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 8) {
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

                        HStack(spacing: 8) {
                            askAIButton
                            filterUtilityButton
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }"""
search_new1 = """    private var searchBarSection: some View {
        centeredStage {
            VStack(alignment: .leading, spacing: 16) {
                Text("Explore")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(alignment: .center, spacing: 12) {
                    SearchQueryBar(
                        viewModel: viewModel,
                        seedQuery: searchDraft,
                        suppressNextDraftDebounce: $suppressNextSearchDraftDebounce,
                        placeholder: "Search titles, cast, or keywords",
                        onSubmit: { text in submitSearch(queryText: text) },
                        onClear: {
                            searchDraft = ""
                            viewModel.clear()
                        }
                    )
                    .frame(maxWidth: 400) // Slim search pill

                    Spacer()

                    HStack(spacing: 12) {
                        askAIButton
                        filterUtilityButton
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }"""

search_old2 = """    private var typeFilterSection: some View {
        HStack(spacing: 4) {
            typeFilterButton(title: "All", type: nil)
            typeFilterButton(title: "Movies", type: .movie)
            typeFilterButton(title: "TV Shows", type: .series)
        }
        .padding(3)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.11))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.12), lineWidth: 0.8)
                }
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }"""
search_new2 = """    private var typeFilterSection: some View {
        HStack(spacing: 4) {
            typeFilterButton(title: "All", type: nil)
            typeFilterButton(title: "Movies", type: .movie)
            typeFilterButton(title: "TV Shows", type: .series)
        }
        .padding(4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.16), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }"""

search_old3 = """                        RecentSearchesSection(
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
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ExploreGenreGrid(
                        cards: ExploreGenreCatalog.cards,
                        onSelect: { card in
                            viewModel.selectMoodCard(card)
                        }
                    )
                }
                .padding(.horizontal, 26)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
        }
    }"""
search_new3 = """                        RecentSearchesSection(
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
                        .padding(.bottom, 8)
                    }

                    ExploreGenreGrid(
                        cards: ExploreGenreCatalog.cards,
                        onSelect: { card in
                            viewModel.selectMoodCard(card)
                        }
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }"""
update_file("VPStudio/Views/Windows/Search/SearchView.swift", [(search_old1, search_new1), (search_old2, search_new2), (search_old3, search_new3)])


# 3. Update ExploreGenreGrid.swift
grid_old1 = """    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 92), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse by Genre & Mood")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {"""
grid_new1 = """    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browse by Genre & Mood")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {"""

grid_old2 = """            .frame(height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.20), radius: 10, y: 6)
            .shadow(color: card.color.opacity(0.20), radius: 12, y: 6)"""
grid_new2 = """            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            .shadow(color: card.color.opacity(0.25), radius: 16, y: 8)"""

grid_old3 = """    private var tileTint: some View {
        ZStack {
            LinearGradient(
                colors: [
                    card.color.opacity(0.12),
                    .clear,
                    .black.opacity(0.36),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    .white.opacity(0.18),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            Circle()
                .fill(card.color.opacity(0.28))
                .frame(width: 56, height: 56)
                .blur(radius: 20)
                .offset(x: -18, y: -20)

            Ellipse()
                .fill(.white.opacity(0.18))
                .frame(width: 72, height: 24)
                .blur(radius: 14)
                .rotationEffect(.degrees(-14))
                .offset(x: -8, y: -18)
        }
        .allowsHitTesting(false)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: card.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.64))
                    .padding(.top, 9)
                    .padding(.trailing, 9)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(card.subtitle)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .tracking(0.8)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 9)
        }
    }"""
grid_new3 = """    private var tileTint: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.2),
                    .black.opacity(0.7),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    .white.opacity(0.25),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .allowsHitTesting(false)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: card.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(card.subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }"""
update_file("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", [(grid_old1, grid_new1), (grid_old2, grid_new2), (grid_old3, grid_new3)])
