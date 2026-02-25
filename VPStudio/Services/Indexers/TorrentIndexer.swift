import Foundation

protocol TorrentIndexer: Sendable {
    nonisolated var name: String { get }
    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult]
    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult]
}

enum IndexerManagerError: LocalizedError {
    case allIndexersFailed(String)

    var errorDescription: String? {
        switch self {
        case .allIndexersFailed(let details):
            return "All indexers failed: \(details)"
        }
    }
}

actor IndexerManager {
    private let database: DatabaseManager
    private var indexers: [any TorrentIndexer] = []
    private(set) var lastSearchErrors: [(indexer: String, error: String)] = []

    init(database: DatabaseManager) {
        self.database = database
    }

    func initialize() async throws {
        let fetchedConfigs = try await database.fetchAllIndexerConfigs().sorted { $0.priority < $1.priority }
        let hydratedConfigs = Self.hydratedConfigs(from: fetchedConfigs)
        if hydratedConfigs != fetchedConfigs {
            try await database.saveIndexerConfigs(hydratedConfigs)
        }

        let activeConfigs = hydratedConfigs.filter(\.isActive)
        indexers = activeConfigs.compactMap { IndexerFactory.create(from: $0) }

        #if DEBUG
        print("[IndexerManager] Fetched \(fetchedConfigs.count) configs, hydrated to \(hydratedConfigs.count), active: \(activeConfigs.count), created: \(indexers.count)")
        for config in activeConfigs {
            let created = IndexerFactory.create(from: config) != nil
            print("[IndexerManager]   \(config.name) (\(config.indexerType.rawValue)) baseURL=\(config.baseURL ?? "nil") created=\(created)")
        }
        #endif
    }

    func search(imdbId: String, type: MediaType, season: Int? = nil, episode: Int? = nil) async throws -> [TorrentResult] {
        var deduped = try await runConcurrentSearch { indexer in
            try await indexer.search(imdbId: imdbId, type: type, season: season, episode: episode)
        }
        if type == .series, let season, let episode {
            deduped = deduped.filter { EpisodeTokenMatcher.matches(title: $0.title, season: season, episode: episode) }
        }
        return deduped
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        var deduped = try await runConcurrentSearch { indexer in
            try await indexer.searchByQuery(query: query, type: type)
        }
        if type == .series, let context = EpisodeTokenMatcher.context(fromQuery: query) {
            deduped = deduped.filter {
                EpisodeTokenMatcher.matches(title: $0.title, season: context.season, episode: context.episode)
            }
        }
        return deduped
    }

    private func runConcurrentSearch(
        _ fetch: @escaping @Sendable (any TorrentIndexer) async throws -> [TorrentResult]
    ) async throws -> [TorrentResult] {
        var allResults: [TorrentResult] = []
        var errors: [(indexer: String, error: String)] = []

        await withTaskGroup(of: ([TorrentResult], String?).self) { group in
            for indexer in indexers {
                group.addTask { [indexer] in
                    #if DEBUG
                    print("[IndexerManager] >>> Dispatching \(indexer.name)")
                    #endif
                    do {
                        let results = try await fetch(indexer)
                        #if DEBUG
                        print("[IndexerManager] <<< \(indexer.name) returned \(results.count) results")
                        #endif
                        return (results, nil)
                    } catch {
                        #if DEBUG
                        print("[IndexerManager] <<< \(indexer.name) ERROR: \(error)")
                        #endif
                        return ([], "\(indexer.name): \(error.localizedDescription)")
                    }
                }
            }
            for await (results, errorMessage) in group {
                allResults.append(contentsOf: results)
                if let errorMessage {
                    let parts = errorMessage.split(separator: ": ", maxSplits: 1)
                    errors.append((indexer: String(parts.first ?? ""), error: String(parts.last ?? "")))
                }
            }
        }

        lastSearchErrors = errors

        #if DEBUG
        if !errors.isEmpty {
            for e in errors { print("[IndexerManager] \(e.indexer) FAILED: \(e.error)") }
        }
        print("[IndexerManager] Search complete: \(allResults.count) results from \(indexers.count) indexers, \(errors.count) errors")
        #endif

        if allResults.isEmpty, let firstError = errors.first {
            throw IndexerManagerError.allIndexersFailed("\(firstError.indexer): \(firstError.error)")
        }

        return Self.deduplicateAndSort(allResults)
    }

    func configuredIndexerNames() -> [String] {
        indexers.map(\.name)
    }

    nonisolated static func deduplicateAndSort(_ results: [TorrentResult]) -> [TorrentResult] {
        var seen: [String: TorrentResult] = [:]
        for result in results {
            if let existing = seen[result.infoHash] {
                if result.seeders > existing.seeders {
                    seen[result.infoHash] = result
                }
            } else {
                seen[result.infoHash] = result
            }
        }

        return Array(seen.values).sorted { lhs, rhs in
            if lhs.isCached != rhs.isCached { return lhs.isCached }
            if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
            return lhs.seeders > rhs.seeders
        }
    }

    private static func defaultBuiltInIndexers() -> [any TorrentIndexer] {
        IndexerDefaultRanking.defaultConfigs().compactMap { config in
            IndexerFactory.create(from: config)
        }
    }

    private static func hydratedConfigs(from configs: [IndexerConfig]) -> [IndexerConfig] {
        guard !configs.isEmpty else {
            return IndexerDefaultRanking.defaultConfigs()
        }

        // Canonicalize legacy built-in definitions (e.g. old torznab-format
        // configs that should now be stremio) but do NOT force-add missing
        // built-ins back — if the user deleted one, it stays deleted.
        return IndexerDefaultRanking.canonicalizingKnownDefaults(in: configs)
    }
}

enum IndexerFactory {
    static func create(from config: IndexerConfig) -> (any TorrentIndexer)? {
        switch config.indexerType {
        case .apiBay:
            return APIBayIndexer(baseURL: config.baseURL)
        case .yts:
            return YTSIndexer()
        case .eztv:
            return EZTVIndexer()
        case .jackett, .prowlarr, .torznab:
            guard let url = config.baseURL else { return nil }
            return TorznabIndexer(
                name: config.name,
                baseURL: url,
                endpointPath: config.endpointPath,
                apiKey: config.apiKey,
                categoryFilter: config.categoryFilter,
                apiKeyTransport: config.apiKeyTransport
            )
        case .zilean:
            guard let url = config.baseURL else { return nil }
            return ZileanIndexer(baseURL: url)
        case .stremio:
            guard let url = config.baseURL else { return nil }
            return StremioIndexer(
                name: config.name,
                baseURL: url,
                endpointPath: config.endpointPath
            )
        }
    }
}
