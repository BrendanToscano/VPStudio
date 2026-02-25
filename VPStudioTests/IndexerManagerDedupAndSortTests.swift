import Foundation
import Testing
@testable import VPStudio

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
}
