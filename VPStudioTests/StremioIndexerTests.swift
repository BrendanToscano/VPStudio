import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct StremioIndexerTests {
    struct URLCase: Sendable {
        let baseURL: String
        let endpointPath: String
        let mediaType: MediaType
        let season: Int?
        let episode: Int?
        let expectedManifestSuffix: String
        let expectedStreamSuffix: String
    }

    struct PayloadCase: Sendable {
        let payload: String
        let expectedCount: Int
    }

    private static let urlCases: [URLCase] = {
        let templates: [(String, String)] = [
            ("https://addon.example", "/manifest.json"),
            ("https://addon.example/", "manifest.json"),
            ("https://addon.example/base", "/manifest.json"),
            ("https://addon.example/base/", "manifest.json"),
            ("https://addon.example/base", "/custom/manifest.json"),
        ]

        var output: [URLCase] = []
        var index = 0
        while output.count < 60 {
            let pair = templates[index % templates.count]
            let isSeries = index % 2 == 0
            let season = isSeries ? ((index % 3) + 1) : nil
            let episode = isSeries ? ((index % 5) + 1) : nil
            let mediaType: MediaType = isSeries ? .series : .movie
            let imdb = "tt\(1000000 + index)"
            let mediaID = isSeries ? "\(imdb):\(season!):\(episode!)" : imdb
            output.append(
                URLCase(
                    baseURL: pair.0,
                    endpointPath: pair.1,
                    mediaType: mediaType,
                    season: season,
                    episode: episode,
                    expectedManifestSuffix: pair.1.hasPrefix("/") ? pair.1 : "/\(pair.1)",
                    expectedStreamSuffix: "/stream/\(isSeries ? "series" : "movie")/\(mediaID).json"
                )
            )
            index += 1
        }
        return output
    }()

    private static let payloadCases: [PayloadCase] = {
        var values: [PayloadCase] = []
        for index in 0..<50 {
            switch index % 5 {
            case 0:
                values.append(PayloadCase(payload: #"{"streams":[{"title":"A","infoHash":"ABCDEF1234567890","behaviorHints":{"videoSize":1234,"seeders":11,"leechers":2}}]}"#, expectedCount: 1))
            case 1:
                values.append(PayloadCase(payload: #"{"streams":[{"name":"A","url":"magnet:?xt=urn:btih:0123456789ABCDEF0123","behaviorHints":{"videoSize":"1234","seeders":"5","leechers":"1"}}]}"#, expectedCount: 1))
            case 2:
                values.append(PayloadCase(payload: #"{"streams":[{"title":"A","externalUrl":"magnet:?xt=urn:btih:FACE1234FACE1234FACE"}]}"#, expectedCount: 1))
            case 3:
                values.append(PayloadCase(payload: #"{"streams":[{"title":"No Hash"}]}"#, expectedCount: 0))
            default:
                values.append(PayloadCase(payload: #"{"invalid":true}"#, expectedCount: 0))
            }
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(urlCases.prefix(20)), full: urlCases))
    func manifestAndStreamURLComposition(data: URLCase) async throws {
        final class Capture: @unchecked Sendable {
            var requested: [URL] = []
        }
        let capture = Capture()

        let session = URLProtocolHarness.makeSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            capture.requested.append(url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("manifest") {
                return (response, Data(#"{"id":"addon.test"}"#.utf8))
            }
            return (response, Data(#"{"streams":[{"title":"A","infoHash":"ABCDEF1234567890"}]}"#.utf8))
        }

        let indexer = StremioIndexer(name: "Stremio", baseURL: data.baseURL, endpointPath: data.endpointPath, session: session)
        _ = try await indexer.search(
            imdbId: "tt1234567",
            type: data.mediaType,
            season: data.season,
            episode: data.episode
        )

        // P2-016: manifest fetch removed — only stream URL is requested
        #expect(capture.requested.count == 1)
        #expect(capture.requested[0].path.hasSuffix(data.expectedStreamSuffix.replacingOccurrences(of: "tt\\d+", with: "tt1234567", options: .regularExpression)))
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(payloadCases.prefix(20)), full: payloadCases))
    func payloadParsingMatrix(data: PayloadCase) async throws {
        let session = URLProtocolHarness.makeSession { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(data.payload.utf8))
        }

        let indexer = StremioIndexer(name: "Stremio", baseURL: "https://addon.example", endpointPath: "/manifest.json", session: session)
        let results = try await indexer.search(imdbId: "tt1234567", type: .movie, season: nil, episode: nil)
        #expect(results.count == data.expectedCount)
    }

    @Test func searchDoesNotFetchManifest() async throws {
        final class Capture: @unchecked Sendable {
            var requestedPaths: [String] = []
        }
        let capture = Capture()

        let session = URLProtocolHarness.makeSession { request in
            guard let url = request.url else { throw URLError(.badURL) }
            capture.requestedPaths.append(url.path)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"streams":[{"title":"A","infoHash":"ABCDEF1234567890"}]}"#.utf8))
        }

        let indexer = StremioIndexer(name: "Stremio", baseURL: "https://addon.example", endpointPath: "/manifest.json", session: session)
        _ = try await indexer.search(imdbId: "tt9999999", type: .movie, season: nil, episode: nil)

        // No request should hit the manifest endpoint
        #expect(capture.requestedPaths.count == 1)
        #expect(!capture.requestedPaths[0].contains("manifest"))
    }
}
