import Testing
@testable import VPStudio

@Suite("Indexer Default Ranking")
struct IndexerDefaultRankingTests {
    @Test
    func defaultConfigsAreOrderedBestToWorst() {
        let configs = IndexerDefaultRanking.defaultConfigs()

        #expect(configs.map(\.id) == [
            "builtin-torrentio",
            "builtin-yts",
            "builtin-apibay",
            "builtin-eztv",
            "builtin-torrentgalaxy",
        ])
        #expect(configs.map(\.name) == [
            "Stremio Torrentio",
            "YTS",
            "APiBay",
            "EZTV",
            "TorrentGalaxy",
        ])

        let defaultTorrentGalaxy = configs.first(where: { $0.id == "builtin-torrentgalaxy" })
        #expect(defaultTorrentGalaxy?.indexerType == .stremio)
        #expect(defaultTorrentGalaxy?.baseURL == "https://torrentio.strem.fun/providers=torrentgalaxy")
        #expect(defaultTorrentGalaxy?.endpointPath == "/manifest.json")
    }

    @Test
    func defaultConfigsHaveCorrectActiveStatesAndSequentialPriorities() {
        let configs = IndexerDefaultRanking.defaultConfigs()

        let activeIDs = configs.filter(\.isActive).map(\.id)
        #expect(activeIDs == ["builtin-torrentio", "builtin-yts", "builtin-apibay"])

        let inactiveIDs = configs.filter { !$0.isActive }.map(\.id)
        #expect(inactiveIDs == ["builtin-eztv", "builtin-torrentgalaxy"])

        #expect(configs.map(\.priority) == Array(0..<configs.count))
    }

    @Test
    func addingMissingDefaultsAvoidsDuplicatesForEquivalentConfigs() {
        let custom = IndexerConfig(
            id: "custom-jackett",
            name: "Custom Jackett",
            indexerType: .jackett,
            baseURL: "https://jackett.example",
            apiKey: "key",
            isActive: true,
            priority: 9
        )
        let existingTorrentGalaxy = IndexerConfig(
            id: "builtin-torrentgalaxy",
            name: "TorrentGalaxy Legacy",
            indexerType: .torznab,
            baseURL: "https://torrentgalaxy.to",
            apiKey: nil,
            isActive: true,
            priority: 99,
            providerSubtype: .customTorznab,
            endpointPath: "/api",
            categoryFilter: nil,
            apiKeyTransport: .query
        )

        let merged = IndexerDefaultRanking.addingMissingDefaults(to: [custom, existingTorrentGalaxy])

        #expect(merged.map(\.priority) == Array(0..<merged.count))
        #expect(merged.first?.id == "custom-jackett")
        #expect(merged.dropFirst().contains(where: { $0.id == "builtin-torrentio" }))
        #expect(merged.filter { $0.id == "builtin-torrentgalaxy" }.count == 1)
        #expect(merged.contains(where: { $0.id == "builtin-yts" }))
        #expect(merged.contains(where: { $0.id == "builtin-eztv" }))
        #expect(merged.contains(where: { $0.id == "builtin-apibay" }))
    }

    @Test
    func canonicalizingKnownDefaultsRewritesLegacyBuiltInDefinitionsByID() {
        let legacyEZTV = IndexerConfig(
            id: "builtin-eztv",
            name: "EZTV Legacy",
            indexerType: .torznab,
            baseURL: "https://eztv.re",
            apiKey: nil,
            isActive: false,
            priority: 3,
            providerSubtype: .customTorznab,
            endpointPath: "/api",
            categoryFilter: nil,
            apiKeyTransport: .query
        )
        let custom = IndexerConfig(
            id: "custom",
            name: "Custom",
            indexerType: .torznab,
            baseURL: "https://custom.example",
            apiKey: "abc",
            isActive: true,
            priority: 0
        )

        let output = IndexerDefaultRanking.canonicalizingKnownDefaults(in: [custom, legacyEZTV])
        let rewrittenEZTV = output.first(where: { $0.id == "builtin-eztv" })
        let unchangedCustom = output.first(where: { $0.id == "custom" })

        #expect(rewrittenEZTV?.indexerType == .eztv)
        #expect(rewrittenEZTV?.baseURL == nil)
        #expect(rewrittenEZTV?.endpointPath == "")
        #expect(rewrittenEZTV?.providerSubtype == .builtIn)
        #expect(rewrittenEZTV?.isActive == false)
        #expect(rewrittenEZTV?.priority == 3)

        #expect(unchangedCustom == custom)
    }

    @Test
    func prioritizeKnownDefaultsReordersBuiltInsToCanonicalRanking() {
        let apibay = IndexerConfig(
            id: "legacy-apibay",
            name: "APiBay",
            indexerType: .apiBay,
            baseURL: nil,
            apiKey: nil,
            isActive: true,
            priority: 0
        )
        let yts = IndexerConfig(
            id: "legacy-yts",
            name: "YTS",
            indexerType: .yts,
            baseURL: nil,
            apiKey: nil,
            isActive: true,
            priority: 1
        )
        let reordered = IndexerDefaultRanking.prioritizeKnownDefaults(in: [apibay, yts])

        #expect(reordered.map(\.name) == ["YTS", "APiBay"])
        #expect(reordered.map(\.priority) == [0, 1])
    }

    @Test
    func deletedBuiltInsReturnsDefinitionsNotInExistingConfigs() {
        let torrentioConfig = IndexerDefaultRanking.rankedDefinitions[0].makeConfig(priority: 0)
        let ytsConfig = IndexerDefaultRanking.rankedDefinitions[1].makeConfig(priority: 1)

        let missing = IndexerDefaultRanking.deletedBuiltIns(from: [torrentioConfig, ytsConfig])

        #expect(missing.map(\.id) == ["builtin-apibay", "builtin-eztv", "builtin-torrentgalaxy"])
    }

    @Test
    func deletedBuiltInsReturnsAllWhenNoConfigsExist() {
        let missing = IndexerDefaultRanking.deletedBuiltIns(from: [])
        #expect(missing.count == 5)
        #expect(missing.map(\.id) == IndexerDefaultRanking.rankedDefinitions.map(\.id))
    }

    @Test
    func deletedBuiltInsReturnsEmptyWhenAllPresent() {
        let allConfigs = IndexerDefaultRanking.defaultConfigs()
        let missing = IndexerDefaultRanking.deletedBuiltIns(from: allConfigs)
        #expect(missing.isEmpty)
    }
}
