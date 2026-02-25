import Foundation
import Testing
@testable import VPStudio

@Suite("Torrent Indexer Factory")
struct TorrentIndexerFactoryTests {
    struct CaseData: Sendable {
        let config: IndexerConfig
        let shouldCreate: Bool
    }

    private static let cases: [CaseData] = {
        var values: [CaseData] = []
        let types: [IndexerConfig.IndexerType] = [.apiBay, .yts, .eztv, .torznab, .jackett, .prowlarr, .zilean, .stremio]
        for index in 0..<40 {
            let type = types[index % types.count]
            let needsURL = type == .torznab || type == .jackett || type == .prowlarr || type == .zilean || type == .stremio
            let includeURL = index % 2 == 0
            values.append(
                CaseData(
                    config: IndexerConfig(
                        id: "cfg-\(index)",
                        name: "Idx-\(index)",
                        indexerType: type,
                        baseURL: includeURL ? "https://indexer-\(index).example" : nil,
                        apiKey: "k",
                        isActive: true,
                        priority: index
                    ),
                    shouldCreate: needsURL ? includeURL : true
                )
            )
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(12)), full: cases))
    func factoryCreationMatrix(data: CaseData) {
        let created = IndexerFactory.create(from: data.config)
        #expect((created != nil) == data.shouldCreate)
    }
}
