import Foundation
import Testing
@testable import VPStudio

private struct FixedTorrentIndexer: TorrentIndexer {
    let name: String
    var imdbResults: [TorrentResult] = []
    var queryResults: [TorrentResult] = []
    var searchError: Error?
    var queryError: Error?

    func search(imdbId: String, type: MediaType, season: Int?, episode: Int?) async throws -> [TorrentResult] {
        if let searchError { throw searchError }
        return imdbResults
    }

    func searchByQuery(query: String, type: MediaType) async throws -> [TorrentResult] {
        if let queryError { throw queryError }
        return queryResults
    }
}

@Suite("Indexer Manager Dedup And Sort")
struct IndexerManagerDedupAndSortTests {
    struct CaseData: Sendable {
        let lhs: TorrentResult
        let rhs: TorrentResult
        let expectedFirstHash: String
    }

    private static let cases: [CaseData] = {
        var values: [CaseData] = []
        for idx in 0..<72 {
            let hash = "hash-\(idx / 3)"
            let first = Fixtures.torrent(
                hash: hash,
                title: "Title A \(idx)",
                quality: idx % 2 == 0 ? .uhd4k : .hd1080p,
                seeders: 5 + idx,
                cached: idx % 4 == 0
            )
            let second = Fixtures.torrent(
                hash: idx % 3 == 0 ? hash : "hash-\(idx)-alt",
                title: "Title B \(idx)",
                quality: idx % 2 == 0 ? .hd1080p : .uhd4k,
                seeders: 10 + idx,
                cached: idx % 5 == 0
            )

            let expected = (idx % 3 == 0)
                ? (second.seeders > first.seeders ? second.infoHash : first.infoHash)
                : (second.isCached == first.isCached
                    ? (second.quality > first.quality ? second.infoHash : first.infoHash)
                    : (second.isCached ? second.infoHash : first.infoHash))

            values.append(CaseData(lhs: first, rhs: second, expectedFirstHash: expected))
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(20)), full: cases))
    func deduplicateAndSortMatrix(data: CaseData) {
        let ranked = IndexerManager.deduplicateAndSort([data.lhs, data.rhs])
        #expect(!ranked.isEmpty)

        if data.lhs.infoHash == data.rhs.infoHash {
            #expect(ranked.count == 1)
            #expect(ranked[0].seeders == max(data.lhs.seeders, data.rhs.seeders))
        } else {
            #expect(ranked.count == 2)
            for index in 1..<ranked.count {
                let previous = ranked[index - 1]
                let current = ranked[index]
                let ordered: Bool
                if previous.isCached != current.isCached {
                    ordered = previous.isCached
                } else if previous.quality != current.quality {
                    ordered = previous.quality > current.quality
                } else {
                    ordered = previous.seeders >= current.seeders
                }
                #expect(ordered)
            }
        }

        #expect(ranked.first?.infoHash == data.expectedFirstHash)
    }

    @Test
    func sortsBySeederCountWhenCacheAndQualityMatch() {
        let weaker = Fixtures.torrent(
            hash: "weaker",
            title: "Same Quality A",
            quality: .hd1080p,
            seeders: 12,
            cached: false
        )
        let stronger = Fixtures.torrent(
            hash: "stronger",
            title: "Same Quality B",
            quality: .hd1080p,
            seeders: 48,
            cached: false
        )

        let ranked = IndexerManager.deduplicateAndSort([weaker, stronger])

        #expect(ranked.map(\.infoHash) == ["stronger", "weaker"])
    }
}

@Suite("Indexer Manager Search")
struct IndexerManagerSearchTests {
    @Test
    func imdbSeriesSearchFiltersEpisodeTokensAndKeepsUntokenizedResults() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-manager-imdb-search.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let matching = Fixtures.torrent(hash: "hash-match", title: "Show S01E02 1080p", seeders: 30)
        let seasonPack = Fixtures.torrent(hash: "hash-pack", title: "Show Season 1 Pack", seeders: 20)
        let wrongEpisode = Fixtures.torrent(hash: "hash-wrong", title: "Show S01E03 1080p", seeders: 40)
        let manager = IndexerManager(
            database: database,
            indexers: [
                FixedTorrentIndexer(name: "Fixed", imdbResults: [wrongEpisode, seasonPack, matching])
            ],
            hasInitialized: true
        )

        let results = try await manager.search(imdbId: "tt1234567", type: .series, season: 1, episode: 2)

        #expect(results.map(\.infoHash) == ["hash-match", "hash-pack"])
        #expect(await manager.lastSearchErrors.isEmpty)
    }

    @Test
    func querySearchReturnsResultsWhenOneIndexerFailsAndRecordsSanitizedError() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-manager-query-partial.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }
        struct TokenError: LocalizedError {
            var errorDescription: String? {
                "failed https://indexer.example/api?apikey=abcdef1234567890abcdef"
            }
        }
        let result = Fixtures.torrent(hash: "hash-result", title: "Movie 1080p", seeders: 5)
        let manager = IndexerManager(
            database: database,
            indexers: [
                FixedTorrentIndexer(name: "Broken", queryError: TokenError()),
                FixedTorrentIndexer(name: "Working", queryResults: [result]),
            ],
            hasInitialized: true
        )

        let results = try await manager.searchByQuery(query: "Movie", type: .movie)
        let errors = await manager.lastSearchErrors

        #expect(results.map(\.infoHash) == ["hash-result"])
        #expect(errors.count == 1)
        #expect(errors.first?.indexer == "Broken")
        #expect(errors.first?.error.contains("abcdef1234567890abcdef") == false)
        #expect(errors.first?.error.contains("apikey=REDACTED") == true)
    }

    @Test
    func querySeriesSearchFiltersByEpisodeContext() async throws {
        let (database, rootDir) = try await makeDatabase(named: "indexer-manager-query-series.sqlite")
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let matching = Fixtures.torrent(hash: "hash-match", title: "Show S02E04 1080p", seeders: 4)
        let untokenized = Fixtures.torrent(hash: "hash-pack", title: "Show Season Pack", seeders: 20)
        let wrong = Fixtures.torrent(hash: "hash-wrong", title: "Show S02E05 1080p", seeders: 50)
        let manager = IndexerManager(
            database: database,
            indexers: [
                FixedTorrentIndexer(name: "Fixed", queryResults: [wrong, untokenized, matching])
            ],
            hasInitialized: true
        )

        let results = try await manager.searchByQuery(query: "Show S02E04", type: .series)

        #expect(results.map(\.infoHash) == ["hash-match"])
    }

    private func makeDatabase(named fileName: String) async throws -> (DatabaseManager, URL) {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        let dbURL = rootDir.appendingPathComponent(fileName)
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, rootDir)
    }
}

@Suite("Indexer Log Sanitizer")
struct IndexerLogSanitizerTests {
    @Test
    func redactsSensitiveQueryItemsUserInfoAndFragments() {
        let url = URL(string: "https://user:password@indexer.example/path/movie.mkv?apikey=secret-key&query=dune&token=abcdef1234567890abcdef#frag")!

        let redacted = IndexerLogSanitizer.redactedURL(url)

        #expect(redacted.contains("user") == false)
        #expect(redacted.contains("password") == false)
        #expect(redacted.contains("secret-key") == false)
        #expect(redacted.contains("abcdef1234567890abcdef") == false)
        #expect(redacted.contains("apikey=REDACTED"))
        #expect(redacted.contains("token=REDACTED"))
        #expect(redacted.contains("query=dune"))
        #expect(redacted.contains("#frag") == false)
    }

    @Test
    func redactsTokenLikePathSegmentsButKeepsNormalPathSegments() {
        let url = URL(string: "https://indexer.example/api/abcdef1234567890abcdef/results/movie.mkv")!

        let redacted = IndexerLogSanitizer.redactedURL(url)

        #expect(redacted.contains("abcdef1234567890abcdef") == false)
        #expect(redacted.contains("/api/REDACTED/results/movie.mkv"))
    }

    @Test
    func redactedURLStringHandlesNilInvalidAndPlainSensitiveValues() {
        #expect(IndexerLogSanitizer.redactedURLString(nil) == "nil")
        #expect(IndexerLogSanitizer.redactedURLString("") == "nil")
        #expect(IndexerLogSanitizer.redactedURLString("not a url") == "not%20a%20url")
        #expect(IndexerLogSanitizer.redactedURLString("abcdef1234567890abcdef") == "REDACTED")
        #expect(IndexerLogSanitizer.redactedURLString("http://[::1") == "http://[::1")
        #expect(IndexerLogSanitizer.redactedURLString("abcdefghijklmnopqrstuvwxyz") == "REDACTED")
    }

    @Test
    func redactsEmbeddedHTTPAndMagnetURLsFromErrorMessages() {
        struct SampleError: LocalizedError {
            var errorDescription: String? {
                "failed https://indexer.example/api?apikey=abcdef1234567890abcdef and magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&token=abcdef1234567890abcdef&dn=Movie"
            }
        }

        let redacted = IndexerLogSanitizer.redactedErrorMessage(SampleError())

        #expect(redacted.contains("abcdef1234567890abcdef") == false)
        #expect(redacted.contains("0123456789abcdef0123456789abcdef01234567"))
        #expect(redacted.contains("apikey=REDACTED"))
        #expect(redacted.contains("token=REDACTED"))
    }

    @Test
    func managerErrorDescriptionIncludesSanitizedFailureDetails() {
        let error = IndexerManagerError.allIndexersFailed("Indexer: Network error")

        #expect(error.errorDescription == "All indexers failed: Indexer: Network error")
    }

    @Test
    func parseErrorDescriptionNamesIndexerAndReason() {
        let error = IndexerParseError.invalidPayload(indexer: "Sample", reason: "missing torrents")

        #expect(error.errorDescription == "Sample returned an invalid response: missing torrents")
    }
}
