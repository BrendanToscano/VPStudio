import SwiftUI

// MARK: - Test Mode View

/// A visual QA launcher that displays every major VPStudio screen with
/// injected mock data, requiring no API keys or real credentials.
struct TestModeView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedScreen: TestScreen?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                screensGrid
            }
            .padding(24)
        }
        .navigationTitle("Test Mode")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $selectedScreen) { screen in
            TestScreenSheet(screen: screen)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Visual QA")
                    .font(.headline)
                Spacer()
                Text("No API keys required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.15), in: Capsule())
            }

            Text("Tap any screen to launch a live test version with realistic mock data. Use this to verify UI/UX without credentials or network access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Screens Grid

    private var screensGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(TestScreen.allCases) { screen in
                TestScreenTile(screen: screen) {
                    selectedScreen = screen
                }
            }
        }
    }
}

// MARK: - Screen Tile

private struct TestScreenTile: View {
    let screen: TestScreen
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(screen.color.opacity(0.15))
                        .frame(height: 80)

                    Image(systemName: screen.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(screen.color)
                }

                VStack(spacing: 2) {
                    Text(screen.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(screen.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(screen.title), \(screen.subtitle)")
        .accessibilityHint("Opens the \(screen.title) preview screen.")
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }
}

// MARK: - Test Screen Definitions

enum TestScreen: String, CaseIterable, Identifiable {
    case discover
    case search
    case searchResults
    case detailMovie
    case detailSeries
    case library
    case downloads
    case player
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "Discover"
        case .search: return "Search"
        case .searchResults: return "Search + Results"
        case .detailMovie: return "Movie Detail"
        case .detailSeries: return "Series Detail"
        case .library: return "Library"
        case .downloads: return "Downloads"
        case .player: return "Player"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .discover: return "Hero + sections"
        case .search: return "Empty search"
        case .searchResults: return "Filters + results"
        case .detailMovie: return "Stream list"
        case .detailSeries: return "Episodes grid"
        case .library: return "Populated library"
        case .downloads: return "Active downloads"
        case .player: return "Controls + overlays"
        case .settings: return "All categories"
        }
    }

    var icon: String {
        switch self {
        case .discover: return "sparkles.tv"
        case .search: return "magnifyingglass"
        case .searchResults: return "line.3.horizontal.decrease.circle"
        case .detailMovie: return "film"
        case .detailSeries: return "film.stack"
        case .library: return "books.vertical"
        case .downloads: return "arrow.down.circle"
        case .player: return "play.circle"
        case .settings: return "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .discover: return .purple
        case .search: return .blue
        case .searchResults: return .cyan
        case .detailMovie: return .orange
        case .detailSeries: return .pink
        case .library: return .green
        case .downloads: return .mint
        case .player: return .red
        case .settings: return .gray
        }
    }
}

// MARK: - Test Screen Sheet

struct TestScreenSheet: View {
    let screen: TestScreen
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            screenContent
                .navigationTitle(screen.title)
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch screen {
        case .discover:
            TestDiscoverView()
        case .search:
            TestSearchView()
        case .searchResults:
            TestSearchResultsView()
        case .detailMovie:
            TestDetailMovieView()
        case .detailSeries:
            TestDetailSeriesView()
        case .library:
            TestLibraryView()
        case .downloads:
            TestDownloadsView()
        case .player:
            TestPlayerView()
        case .settings:
            TestSettingsView()
        }
    }
}

// MARK: - Discover Test

private struct TestDiscoverView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.indigo.opacity(0.8), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 300)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Featured")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Dune: Part Two")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                        HStack {
                            Text("2024 · 8.8 ★")
                            Text("·")
                            Text("Sci-Fi")
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(20)
                }

                // Section: Trending
                discoverSection("Trending Now") {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { i in
                            VStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3 + Double(i) * 0.1))
                                    .frame(width: 120, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(["Oppenheimer", "Poor Things", "The Bear", "Shrinking"][i])
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                // Section: New Releases
                discoverSection("New Releases") {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { i in
                            VStack {
                                Rectangle()
                                    .fill(Color.blue.opacity(0.3 + Double(i) * 0.1))
                                    .frame(width: 120, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(["Rebel Ridge", "A Quiet Place", "Fallout", "Presumed Innocent"][i])
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                // Section: Your Watchlist
                discoverSection("Your Watchlist") {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { i in
                            VStack {
                                Rectangle()
                                    .fill(Color.green.opacity(0.3 + Double(i) * 0.1))
                                    .frame(width: 120, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(["Killers", "The Holdovers", "Anatomy", "Ad Astra"][i])
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func discoverSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

// MARK: - Search Test

private struct TestSearchView: View {
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Movies, shows, people...", text: $query)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Search for movies and TV shows")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Find streams, explore cast, and more")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }
}

// MARK: - Search Results Test

private struct TestSearchResultsView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Movies", "TV", "Anime", "2024", "8.0+ ★", "HD"], id: \.self) { filter in
                        Text(filter)
                            .font(.caption)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(filter == "Movies" ? AnyShapeStyle(.tint) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    }
                    Image(systemName: "slider.horizontal.3")
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        HStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(["Dune: Part Two", "Dune", "Dune Prophecy", "Messiah: Dune", "Dune: Part Three", "Dune (1984)"][i])
                                    .font(.subheadline)
                                Text(["2024 · Sci-Fi", "2021 · Sci-Fi", "2024 · Sci-Fi", "1971 · Sci-Fi", "2030 · Sci-Fi", "1984 · Sci-Fi"][i])
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(["8.8", "8.0", "7.1", "7.8", "—", "6.5"][i])
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Detail Movie Test

private struct TestDetailMovieView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.indigo.opacity(0.9), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 300)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("DUNE: PART TWO")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        HStack(spacing: 12) {
                            Text("2024")
                            Text("166 min")
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text("8.8 IMDb")
                            }
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))

                        Text("Science Fiction · Adventure · Drama")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        Text("Denis Villeneuve")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(20)
                }

                VStack(alignment: .leading, spacing: 16) {
                    // Synopsis
                    Text("Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen while on a warpath of revenge against the conspirators who destroyed his family.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)

                    // Genres
                    HStack(spacing: 6) {
                        ForEach(["Sci-Fi", "Adventure", "Drama"], id: \.self) { g in
                            Text(g)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }

                    // Streams section
                    Text("Available Streams")
                        .font(.headline)

                    ForEach(0..<3, id: \.self) { i in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(["Dune.Part.Two.2024.2160p.WEB", "Dune Part Two 2024 1080p WEB-DL", "Dune.Part.Two.2024.720p.WEB"][i])
                                    .font(.subheadline)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(["2160p · HDR · Dolby Vision", "1080p · DDP 5.1", "720p · x264"][i])
                                        .font(.caption2)
                                    Text("·")
                                    Text(["342 seeders", "1204 seeders", "567 seeders"][i])
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("8.5 GB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Detail Series Test

private struct TestDetailSeriesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.indigo.opacity(0.9), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(height: 300)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SHRINKING")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        HStack(spacing: 12) {
                            Text("2023")
                            Text("35 min")
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text("8.1 IMDb")
                            }
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))

                        Text("Comedy · Drama")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        Text("Jason Segel · Harrison Ford")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(20)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("A therapist starts breaking the rules with his patients after a tragedy changes everything.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)

                    // Seasons tabs
                    HStack(spacing: 8) {
                        ForEach(["Season 1 · 10 eps", "Season 2 · 10 eps", "Season 3 · 9 eps"], id: \.self) { s in
                            Text(s)
                                .font(.caption)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(s.contains("3") ? AnyShapeStyle(.tint) : AnyShapeStyle(.ultraThinMaterial), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Episodes row
                    Text("Episodes")
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<6, id: \.self) { i in
                                VStack(alignment: .leading, spacing: 4) {
                                    ZStack(alignment: .bottomLeading) {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3 + Double(i) * 0.08))
                                            .frame(width: 180, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                        HStack(spacing: 4) {
                                            Text("S03E0\(i+1)")
                                                .font(.caption2.weight(.semibold))
                                            Text("·")
                                            Text("\([35, 34, 36, 37, 35, 38][i])m")
                                                .font(.caption2)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(6)
                                    }

                                    Text(["Fanatics", "The Ghosts", "The Medal", "The River", "The Bowl", "The High Price"][i])
                                        .font(.caption2)
                                        .lineLimit(1)

                                    if i == 0 {
                                        Text("3/6 watched")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 180)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Library Test

private struct TestLibraryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Library")
                    .font(.title2.bold())

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 14) {
                    ForEach(0..<6, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack(alignment: .bottomLeading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3 + Double(i) * 0.08))
                                    .aspectRatio(2/3, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                if i % 3 == 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .padding(6)
                                }
                            }

                            Text(["Oppenheimer", "Poor Things", "The Bear", "Killers", "Slow Horses", "The Holdovers"][i])
                                .font(.caption2)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Downloads Test

private struct TestDownloadsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Downloads")
                        .font(.title2.bold())
                    Spacer()
                    Text("2 active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                ForEach(0..<2, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(["Dune.Part.Two.2024.2160p", "Shrinking.S03E01.1080p"][i])
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(["73% · 6.2 GB of 8.5 GB", "Completed · 1.9 GB"][i])
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            if i == 0 {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .frame(height: 4)
                                Capsule()
                                    .fill(i == 0 ? .blue : .green)
                                    .frame(width: geo.size.width * CGFloat(i == 0 ? 0.73 : 1.0), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Player Test

private struct TestPlayerView: View {
    @State private var isShowingControls = true

    var body: some View {
        ZStack {
            // Video area
            Rectangle()
                .fill(.black)

            VStack {
                Spacer()

                // Controls overlay
                if isShowingControls {
                    VStack(spacing: 16) {
                        // Top bar
                        HStack {
                            Image(systemName: "chevron.left")
                            Spacer()
                            Text("Dune: Part Two")
                                .font(.caption)
                            Spacer()
                            Image(systemName: "airplayaudio")
                        }
                        .foregroundStyle(.white)

                        Spacer()

                        // Center play/pause
                        HStack(spacing: 60) {
                            Image(systemName: "backward.fill")
                                .font(.title)
                            Image(systemName: "play.fill")
                                .font(.largeTitle)
                            Image(systemName: "forward.fill")
                                .font(.title)
                        }
                        .foregroundStyle(.white)

                        Spacer()

                        // Scrubber
                        VStack(spacing: 4) {
                            Slider(value: .constant(0.35), in: 0...1)
                                .tint(.white)
                                .accessibilityLabel("Playback position")
                                .accessibilityValue("35 percent")
                                .accessibilityHint("Preview-only playback progress in test mode.")
                            HStack {
                                Text("58:21")
                                Spacer()
                                Text("2:46:00")
                            }
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                        }

                        // Bottom bar
                        HStack {
                            Image(systemName: "speaker.fill")
                            Slider(value: .constant(0.7), in: 0...1)
                                .frame(width: 80)
                                .tint(.white)
                                .accessibilityLabel("Volume")
                                .accessibilityValue("70 percent")
                                .accessibilityHint("Preview-only volume level in test mode.")

                            Spacer()

                            HStack(spacing: 20) {
                                Image(systemName: "captions.bubble")
                                Image(systemName: "pip.enter")
                                Image(systemName: "gear")
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingControls.toggle()
            }
        }
    }
}

// MARK: - Settings Test

private struct TestSettingsView: View {
    private let categories = [
        ("Connect", "link", "Accounts, providers, and API keys", ["Streaming Providers", "Search Providers", "TMDB API", "AI Recommendations", "Trakt", "Simkl", "IMDb Import"]),
        ("Watch", "play.circle", "Playback, quality, and subtitles", ["Playback", "Subtitles"]),
        ("Discover", "sparkles", "Environments and browsing", ["Environments"]),
        ("Library", "books.vertical", "Downloads and local content", ["Library", "Downloads"]),
        ("About", "info.circle", "App info, health, and data", ["Reset All Data"]),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(categories, id: \.0) { category in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: category.1)
                                .font(.caption)
                            Text(category.0)
                                .font(.headline)
                        }
                        .foregroundStyle(.secondary)

                        VStack(spacing: 4) {
                            ForEach(category.3, id: \.self) { item in
                                HStack {
                                    Text(item)
                                        .font(.subheadline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}
