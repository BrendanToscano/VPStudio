import Foundation
import Testing
@testable import VPStudio

@Suite("Indexer Connectivity URL Builder")
struct IndexerConnectivityBuilderMatrixTests {
    struct CaseData: Sendable {
        let config: IndexerConfig
        let expectedPathSuffix: String
        let expectHeaderKey: Bool
    }

    private static let cases: [CaseData] = {
        var values: [CaseData] = []
        for index in 0..<30 {
            switch index % 3 {
            case 0:
                values.append(
                    CaseData(
                        config: Fixtures.indexerConfig(
                            id: "jackett-\(index)",
                            name: "Jackett",
                            type: .jackett,
                            baseURL: "https://jackett.example",
                            apiKey: "k-\(index)",
                            endpointPath: "/api/v2.0/indexers/all/results/torznab/api",
                            transport: .query
                        ),
                        expectedPathSuffix: "/api/v2.0/indexers/all/results/torznab/api",
                        expectHeaderKey: false
                    )
                )
            case 1:
                values.append(
                    CaseData(
                        config: Fixtures.indexerConfig(
                            id: "prowlarr-\(index)",
                            name: "Prowlarr",
                            type: .prowlarr,
                            baseURL: "https://prowlarr.example/base",
                            apiKey: "k-\(index)",
                            endpointPath: "/api/v1/search",
                            transport: .header
                        ),
                        expectedPathSuffix: "/base/api/v1/search",
                        expectHeaderKey: true
                    )
                )
            default:
                values.append(
                    CaseData(
                        config: Fixtures.indexerConfig(
                            id: "stremio-\(index)",
                            name: "Stremio",
                            type: .stremio,
                            baseURL: "https://stremio.example",
                            apiKey: nil,
                            endpointPath: "/manifest.json",
                            transport: .query
                        ),
                        expectedPathSuffix: "/manifest.json",
                        expectHeaderKey: false
                    )
                )
            }
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(10)), full: cases))
    func makeRequestMatrix(data: CaseData) throws {
        let request = try IndexerConnectivityTester.makeRequest(for: data.config)
        guard let url = request.url else {
            Issue.record("Expected request URL")
            return
        }
        #expect(url.path.hasSuffix(data.expectedPathSuffix))
        if data.expectHeaderKey {
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == data.config.apiKey)
        } else {
            #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
        }
    }
}
