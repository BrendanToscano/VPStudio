import Foundation

enum IndexerDefaultRanking {
    struct Definition: Sendable, Equatable {
        let id: String
        let name: String
        let type: IndexerConfig.IndexerType
        let baseURL: String?
        let endpointPath: String
        let providerSubtype: IndexerConfig.ProviderSubtype
        let apiKeyTransport: IndexerConfig.APIKeyTransport
        let activeByDefault: Bool

        func makeConfig(priority: Int, isActive: Bool? = nil) -> IndexerConfig {
            IndexerConfig(
                id: id,
                name: name,
                indexerType: type,
                baseURL: baseURL,
                apiKey: nil,
                isActive: isActive ?? activeByDefault,
                priority: priority,
                providerSubtype: providerSubtype,
                endpointPath: endpointPath,
                categoryFilter: nil,
                apiKeyTransport: apiKeyTransport
            )
        }

        func canonicalized(from config: IndexerConfig) -> IndexerConfig {
            var canonical = makeConfig(priority: config.priority)
            canonical.isActive = config.isActive
            return canonical
        }

        func matches(_ config: IndexerConfig) -> Bool {
            config.id == id
                || (config.indexerType == type
                    && config.baseURL == baseURL
                    && config.endpointPath == endpointPath)
        }
    }

    // Ranked best -> worst by a blended score of search speed, catalog breadth,
    // and provider trustworthiness/consistency for default out-of-box usage.
    nonisolated static let rankedDefinitions: [Definition] = [
        Definition(
            id: "builtin-torrentio",
            name: "Stremio Torrentio",
            type: .stremio,
            baseURL: "https://torrentio.strem.fun",
            endpointPath: "/manifest.json",
            providerSubtype: .stremioAddon,
            apiKeyTransport: .query,
            activeByDefault: true
        ),
        Definition(
            id: "builtin-yts",
            name: "YTS",
            type: .yts,
            baseURL: nil,
            endpointPath: "",
            providerSubtype: .builtIn,
            apiKeyTransport: .query,
            activeByDefault: true
        ),
        Definition(
            id: "builtin-apibay",
            name: "APiBay",
            type: .apiBay,
            baseURL: nil,
            endpointPath: "",
            providerSubtype: .builtIn,
            apiKeyTransport: .query,
            activeByDefault: true
        ),
        Definition(
            id: "builtin-eztv",
            name: "EZTV",
            type: .eztv,
            baseURL: nil,
            endpointPath: "",
            providerSubtype: .builtIn,
            apiKeyTransport: .query,
            activeByDefault: false
        ),
        Definition(
            id: "builtin-torrentgalaxy",
            name: "TorrentGalaxy",
            type: .stremio,
            baseURL: "https://torrentio.strem.fun/providers=torrentgalaxy",
            endpointPath: "/manifest.json",
            providerSubtype: .stremioAddon,
            apiKeyTransport: .query,
            activeByDefault: false
        ),
    ]

    nonisolated static func defaultConfigs() -> [IndexerConfig] {
        rankedDefinitions.enumerated().map { index, definition in
            definition.makeConfig(priority: index)
        }
    }

    nonisolated static func canonicalizingKnownDefaults(in input: [IndexerConfig]) -> [IndexerConfig] {
        input.map { config in
            guard let definition = rankedDefinitions.first(where: { $0.id == config.id }) else {
                return config
            }
            return definition.canonicalized(from: config)
        }
    }

    nonisolated static func addingMissingDefaults(to input: [IndexerConfig]) -> [IndexerConfig] {
        var output = input
        for definition in rankedDefinitions {
            if output.contains(where: definition.matches) {
                continue
            }
            output.append(definition.makeConfig(priority: output.count))
        }
        return normalizePriorities(output)
    }

    nonisolated static func normalizePriorities(_ input: [IndexerConfig]) -> [IndexerConfig] {
        input.enumerated().map { offset, config in
            var copy = config
            copy.priority = offset
            return copy
        }
    }

    nonisolated static func prioritizeKnownDefaults(in input: [IndexerConfig]) -> [IndexerConfig] {
        var remaining = input
        var ordered: [IndexerConfig] = []
        ordered.reserveCapacity(input.count)

        for definition in rankedDefinitions {
            if let index = remaining.firstIndex(where: definition.matches) {
                ordered.append(remaining.remove(at: index))
            }
        }

        ordered.append(contentsOf: remaining)
        return normalizePriorities(ordered)
    }

    nonisolated static func isKnownDefaultConfig(_ config: IndexerConfig) -> Bool {
        rankedDefinitions.contains(where: { $0.matches(config) })
    }

    /// Returns built-in definitions that are not present in the given config list.
    nonisolated static func deletedBuiltIns(from existing: [IndexerConfig]) -> [Definition] {
        rankedDefinitions.filter { definition in
            !existing.contains(where: definition.matches)
        }
    }
}
