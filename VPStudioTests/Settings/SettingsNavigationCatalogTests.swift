import Testing
@testable import VPStudio

struct SettingsNavigationCatalogTests {
    @Test
    func categoryMetadataCoversEverySection() {
        let expected: [(SettingsCategory, String, String)] = [
            (.connect, "Connect", "Accounts, providers, and API keys"),
            (.watch, "Watch", "Playback, quality, and subtitles"),
            (.discover, "Discover", "Environments and browsing"),
            (.library, "Library", "Downloads and local content"),
            (.about, "About", "App info, health, and data"),
        ]

        #expect(SettingsCategory.allCases == expected.map(\.0))
        for (category, title, subtitle) in expected {
            #expect(category.id == category.rawValue)
            #expect(category.title == title)
            #expect(category.subtitle == subtitle)
        }
    }

    @Test
    func destinationMetadataCoversEveryDestination() {
        let expected: [(SettingsDestination, String, String, SettingsCategory, String)] = [
            (.debrid, "Streaming Providers (Debrid)", "cloud", .connect, "realdebrid"),
            (.indexers, "Search Providers", "magnifyingglass.circle", .connect, "torznab"),
            (.metadata, "Movie & TV Metadata (TMDB)", "film", .connect, "tmdb"),
            (.ai, "AI Recommendations", "brain", .connect, "openai"),
            (.trakt, "Trakt", "arrow.triangle.2.circlepath", .connect, "watch history"),
            (.simkl, "Simkl", "arrow.triangle.2.circlepath.circle", .connect, "cleanup-only"),
            (.imdbImport, "IMDb Import", "film.stack", .connect, "csv"),
            (.player, "Playback", "play.circle", .watch, "hdr"),
            (.subtitles, "Subtitles", "captions.bubble", .watch, "opensubtitles"),
            (.environments, "Environments", "mountain.2", .discover, "immersive"),
            (.library, "Library", "books.vertical", .library, "collection"),
            (.downloads, "Downloads", "arrow.down.circle", .library, "offline"),
            (.resetData, "Reset All Data", "trash", .about, "factory reset"),
            (.testMode, "Test Mode", "flame", .about, "qa"),
        ]

        #expect(SettingsDestination.allCases == expected.map(\.0))
        for (destination, title, icon, category, token) in expected {
            #expect(destination.id == destination.rawValue)
            #expect(destination.title == title)
            #expect(destination.icon == icon)
            #expect(destination.category == category)
            #expect(destination.summary.isEmpty == false)
            #expect(destination.searchTokens.contains(token))
        }
    }

    @Test
    func emptyQueryReturnsAllDestinationsGroupedByCategory() {
        let groups = SettingsNavigationCatalog.groups(matching: "")
        let flattened = groups.flatMap(\.destinations)

        #expect(groups.count == SettingsCategory.allCases.count)
        #expect(groups.map(\.id) == groups.map(\.category))
        #expect(flattened.count == SettingsNavigationCatalog.orderedDestinations.count)
        #expect(Set(flattened.map(\.rawValue)).count == SettingsNavigationCatalog.orderedDestinations.count)
    }

    @Test
    func tmdbQueryFindsOnlyMetadataDestination() {
        let groups = SettingsNavigationCatalog.groups(matching: "tmdb")
        let flattened = groups.flatMap(\.destinations)

        #expect(flattened == [.metadata])
    }

    @Test
    func queryByProviderTokenMatchesRelevantDestination() {
        let groups = SettingsNavigationCatalog.groups(matching: "realdebrid")
        let flattened = groups.flatMap(\.destinations)

        #expect(flattened == [.debrid])
    }

    @Test
    func imdbCsvImportQueryFindsImportDestination() {
        let groups = SettingsNavigationCatalog.groups(matching: "imdb csv import")
        let flattened = groups.flatMap(\.destinations)

        #expect(flattened == [.imdbImport])
    }

    @Test
    func simklCleanupSurfaceDoesNotMatchSyncQueries() {
        let flattened = SettingsNavigationCatalog.groups(matching: "simkl watchlist").flatMap(\.destinations)

        #expect(flattened.isEmpty)
    }

    @Test
    func simklDestinationSummaryHighlightsCleanupOnlyAvailability() {
        let summary = SettingsDestination.simkl.summary

        #expect(summary.contains("cleanup-only"))
        #expect(summary.contains("unavailable"))
    }

    @Test
    func multiTokenQueryRequiresAllTerms() {
        let matched = SettingsNavigationCatalog.groups(matching: "ai openai").flatMap(\.destinations)
        let unmatched = SettingsNavigationCatalog.groups(matching: "ai bananas").flatMap(\.destinations)

        #expect(matched.contains(.ai))
        #expect(unmatched.isEmpty)
    }

    @Test
    func destinationLookupHandlesValidAndInvalidValues() {
        #expect(SettingsNavigationCatalog.destination(from: "trakt") == .trakt)
        #expect(SettingsNavigationCatalog.destination(from: "missing") == nil)
        #expect(SettingsNavigationCatalog.destination(from: nil) == nil)
        #expect(SettingsNavigationCatalog.destination(from: "") == nil)
    }

    // MARK: - Essential Destinations

    @Test
    func essentialDestinationsContainsOnlyServicesThatRequireSetup() {
        let essential = SettingsNavigationCatalog.essentialDestinations
        let expectedEssential: Set<SettingsDestination> = [.debrid, .indexers, .metadata, .ai, .trakt]

        #expect(Set(essential) == expectedEssential)
    }

    @Test
    func essentialDestinationsExcludesPreferenceOnlyItems() {
        let essential = SettingsNavigationCatalog.essentialDestinations

        #expect(!essential.contains(.player))
        #expect(!essential.contains(.subtitles))
        #expect(!essential.contains(.environments))
    }

    @Test
    func essentialDestinationsCountIsFive() {
        #expect(SettingsNavigationCatalog.essentialDestinations.count == 5)
    }

    @Test
    func isEssentialMatchesExpectedValues() {
        // Essential: require explicit setup
        #expect(SettingsDestination.debrid.isEssential == true)
        #expect(SettingsDestination.indexers.isEssential == true)
        #expect(SettingsDestination.metadata.isEssential == true)
        #expect(SettingsDestination.ai.isEssential == true)
        #expect(SettingsDestination.trakt.isEssential == true)
        #expect(SettingsDestination.simkl.isEssential == false)

        // Non-essential: work with defaults
        #expect(SettingsDestination.player.isEssential == false)
        #expect(SettingsDestination.subtitles.isEssential == false)
        #expect(SettingsDestination.environments.isEssential == false)
    }

    @Test
    func essentialDestinationsIsSubsetOfOrderedDestinations() {
        let essential = Set(SettingsNavigationCatalog.essentialDestinations)
        let ordered = Set(SettingsNavigationCatalog.orderedDestinations)

        #expect(essential.isSubset(of: ordered))
    }

    @Test
    func totalDestinationsCountIsSumOfEssentialAndNonEssential() {
        let essentialCount = SettingsNavigationCatalog.essentialDestinations.count
        let nonEssentialCount = SettingsNavigationCatalog.orderedDestinations.filter { !$0.isEssential }.count

        #expect(essentialCount + nonEssentialCount == SettingsNavigationCatalog.orderedDestinations.count)
    }
}
