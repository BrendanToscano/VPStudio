import Testing
@testable import VPStudio

struct SettingsNavigationCatalogTests {
    @Test
    func emptyQueryReturnsAllDestinationsGroupedByCategory() {
        let groups = SettingsNavigationCatalog.groups(matching: "")
        let flattened = groups.flatMap(\.destinations)

        #expect(groups.count == SettingsCategory.allCases.count)
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
    func imdbCsvImportQueryFindsAIDestination() {
        let groups = SettingsNavigationCatalog.groups(matching: "imdb csv import")
        let flattened = groups.flatMap(\.destinations)

        #expect(flattened == [.ai])
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
        let expectedEssential: Set<SettingsDestination> = [.debrid, .indexers, .metadata, .ai, .trakt, .simkl]

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
    func essentialDestinationsCountIsSix() {
        #expect(SettingsNavigationCatalog.essentialDestinations.count == 6)
    }

    @Test
    func isEssentialMatchesExpectedValues() {
        // Essential: require explicit setup
        #expect(SettingsDestination.debrid.isEssential == true)
        #expect(SettingsDestination.indexers.isEssential == true)
        #expect(SettingsDestination.metadata.isEssential == true)
        #expect(SettingsDestination.ai.isEssential == true)
        #expect(SettingsDestination.trakt.isEssential == true)
        #expect(SettingsDestination.simkl.isEssential == true)

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
