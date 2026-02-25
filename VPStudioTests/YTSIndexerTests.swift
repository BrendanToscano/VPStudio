import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct YTSIndexerTests {
    @Test
    func searchByQueryFallsBackToSecondaryHostWhenPrimaryFails() async throws {
        final class RequestState: @unchecked Sendable {
            var requestedHosts: [String] = []
        }
        let state = RequestState()

        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            state.requestedHosts.append(url.host ?? "")

            if url.host == "yts.torrentbay.st" {
                throw URLError(.cannotFindHost)
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {"data":{"movies":[{"title":"The Matrix","title_long":"The Matrix (1999)","year":1999,"torrents":[{"hash":"ABCDEF123456","quality":"1080p","type":"bluray","size_bytes":1234567890,"seeds":120,"peers":4}]}]}}
            """
            return (response, Data(payload.utf8))
        }

        let indexer = YTSIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "The Matrix", type: .movie)

        #expect(state.requestedHosts.prefix(2) == ["yts.torrentbay.st", "yts.mx"])
        #expect(results.count == 1)
        #expect(results.first?.infoHash == "abcdef123456")
        #expect(results.first?.indexerName == "YTS")
    }

    @Test
    func searchByQueryFallsThroughWhenPrimaryReturnsEmptyMovies() async throws {
        final class RequestState: @unchecked Sendable {
            var requestedHosts: [String] = []
        }
        let state = RequestState()

        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            state.requestedHosts.append(url.host ?? "")

            if url.host == "yts.torrentbay.st" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let emptyPayload = """
                {"status":"ok","data":{"movie_count":0}}
                """
                return (response, Data(emptyPayload.utf8))
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {"data":{"movies":[{"title":"Dune","title_long":"Dune (2021)","year":2021,"torrents":[{"hash":"DEADBEEF","quality":"2160p","type":"web","size_bytes":5000000000,"seeds":200,"peers":10}]}]}}
            """
            return (response, Data(payload.utf8))
        }

        let indexer = YTSIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "Dune", type: .movie)

        #expect(state.requestedHosts.prefix(2) == ["yts.torrentbay.st", "yts.mx"])
        #expect(results.count == 1)
        #expect(results.first?.infoHash == "deadbeef")
    }

    @Test
    func searchByQueryThrowsWhenAllHostsFail() async {
        final class RequestState: @unchecked Sendable {
            var requestCount: Int = 0
        }
        let state = RequestState()

        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            state.requestCount += 1
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let indexer = YTSIndexer(session: session)

        do {
            _ = try await indexer.searchByQuery(query: "Dune", type: .movie)
            Issue.record("Expected URLError.badServerResponse")
        } catch let error as URLError {
            #expect(error.code == .badServerResponse)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(state.requestCount == 3)
    }

    @Test
    func nilQualityAndTypeProducesValidResult() async throws {
        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {"data":{"movies":[{"title":"Test Movie","title_long":"Test Movie (2024)","year":2024,"torrents":[{"hash":"ABC123","quality":null,"type":null,"size_bytes":500000000,"seeds":50,"peers":5}]}]}}
            """
            return (response, Data(payload.utf8))
        }

        let indexer = YTSIndexer(session: session)
        let results = try await indexer.search(imdbId: "tt0000001", type: .movie, season: nil, episode: nil)

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.infoHash == "abc123")
        #expect(!result.title.contains("[]"))
        #expect(result.title == "Test Movie (2024)")
    }

    @Test
    func emptyStringQualityAndTypeProducesValidResult() async throws {
        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {"data":{"movies":[{"title":"Test Movie","title_long":"Test Movie (2024)","year":2024,"torrents":[{"hash":"DEF456","quality":"","type":"","size_bytes":500000000,"seeds":50,"peers":5}]}]}}
            """
            return (response, Data(payload.utf8))
        }

        let indexer = YTSIndexer(session: session)
        let results = try await indexer.search(imdbId: "tt0000002", type: .movie, season: nil, episode: nil)

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.infoHash == "def456")
        #expect(!result.title.contains("[]"))
        #expect(result.title == "Test Movie (2024)")
    }

    @Test
    func searchReturnsNoResultsForSeriesWithoutNetworkRequest() async throws {
        final class RequestState: @unchecked Sendable {
            var requestCount: Int = 0
        }
        let state = RequestState()

        let session = URLProtocolHarness.makeSession { request in
            _ = try #require(request.url)
            state.requestCount += 1
            throw URLError(.badURL)
        }

        let indexer = YTSIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "Any Show", type: .series)

        #expect(results.isEmpty)
        #expect(state.requestCount == 0)
    }
}
