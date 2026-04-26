import Foundation
import Testing
@testable import VPStudio

@Suite("APIBayIndexer Behavior")
struct APIBayIndexerBehaviorTests {
    @Test func searchByIMDbAppendsEpisodeContextAndFiltersInvalidRows() async throws {
        final class State: @unchecked Sendable {
            var capturedQuery: String?
        }
        let state = State()

        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            state.capturedQuery = components?.queryItems?.first(where: { $0.name == "q" })?.value
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {"id":"0","name":"invalid id","info_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":"100","seeders":"1","leechers":"1"},
                {"id":"2","name":"zero hash","info_hash":"0000000000000000000000000000000000000000","size":"100","seeders":"1","leechers":"1"},
                {"id":"3","name":"Show S01E01","info_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":"100","seeders":"1","leechers":"1"},
                {"id":"4","name":"Show S01E02 1080p WEB-DL","info_hash":"cccccccccccccccccccccccccccccccccccccccc","size":"2000","seeders":"50","leechers":"5"}
            ]
            """
            return (response, Data(body.utf8))
        }

        let indexer = APIBayIndexer(session: session)
        let results = try await indexer.search(imdbId: "tt1234567", type: .series, season: 1, episode: 2)

        #expect(state.capturedQuery == "tt1234567 S01E02")
        #expect(results.map(\.infoHash) == ["cccccccccccccccccccccccccccccccccccccccc"])
        #expect(results.first?.title == "Show S01E02 1080p WEB-DL")
        #expect(results.first?.seeders == 50)
        #expect(results.first?.leechers == 5)
        #expect(results.first?.quality == .hd1080p)
    }

    @Test func searchByQueryUsesEpisodeContextWhenPresent() async throws {
        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {"id":"1","name":"Show S02E03","info_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","size":"1000","seeders":"8","leechers":"2"},
                {"id":"2","name":"Show S02E04","info_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":"1000","seeders":"7","leechers":"1"}
            ]
            """
            return (response, Data(body.utf8))
        }

        let indexer = APIBayIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "Show S02E03", type: .series)

        #expect(results.map(\.infoHash) == ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
    }

    @Test func noResultsSentinelReturnsEmptyList() async throws {
        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"[{"id":"0","name":"No results returned","info_hash":"","size":"0","seeders":"0","leechers":"0"}]"#
            return (response, Data(body.utf8))
        }

        let indexer = APIBayIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "unlikely", type: .movie)

        #expect(results.isEmpty)
    }
}

@Suite("EZTVIndexer Behavior")
struct EZTVIndexerBehaviorTests {
    @Test func searchReturnsEmptyForUnsupportedTypeAndEmptyIMDbID() async throws {
        let indexer = EZTVIndexer(session: URLProtocolHarness.makeSession { request in
            Issue.record("Unexpected EZTV request: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        })

        let movieResults = try await indexer.search(imdbId: "tt1234567", type: .movie, season: nil, episode: nil)
        let emptyIMDbResults = try await indexer.search(imdbId: "tt", type: .series, season: nil, episode: nil)

        #expect(movieResults.isEmpty)
        #expect(emptyIMDbResults.isEmpty)
    }

    @Test func searchByIMDbStripsTTAndFiltersByEpisodeMetadataAndTitle() async throws {
        final class State: @unchecked Sendable {
            var capturedIMDbID: String?
        }
        let state = State()

        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            state.capturedIMDbID = components?.queryItems?.first(where: { $0.name == "imdb_id" })?.value
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"torrents":[
                {"hash":"wrong-season","title":"Show S02E02","season":"2","episode":"2","seeds":1,"peers":1,"size_bytes":"1000"},
                {"hash":"wrong-title","title":"Show Special","season":"1","episode":"2","seeds":1,"peers":1,"size_bytes":"1000"},
                {"hash":"","title":"Missing Hash S01E02","season":"1","episode":"2","seeds":1,"peers":1,"size_bytes":"1000"},
                {"hash":"right-hash","filename":"Show.S01E02.720p.mkv","season":"1","episode":"2","seeds":22,"peers":3,"size_bytes":"12345","magnet_url":"magnet:?xt=urn:btih:right-hash"}
            ]}
            """
            return (response, Data(body.utf8))
        }

        let indexer = EZTVIndexer(session: session)
        let results = try await indexer.search(imdbId: "tt7654321", type: .series, season: 1, episode: 2)

        #expect(state.capturedIMDbID == "7654321")
        #expect(results.map(\.infoHash) == ["right-hash"])
        #expect(results.first?.title == "Show.S01E02.720p.mkv")
        #expect(results.first?.seeders == 22)
        #expect(results.first?.leechers == 3)
        #expect(results.first?.magnetURI == "magnet:?xt=urn:btih:right-hash")
    }

    @Test func searchByQueryContinuesUntilShortPageAndKeepsUnknownFallbackTitle() async throws {
        final class State: @unchecked Sendable {
            var pages: [String] = []
        }
        let state = State()

        let firstPage = (0..<100).map { index in
            #"{"hash":"page1-\#(index)","title":"Show S01E01","season":"1","episode":"1","seeds":1,"peers":0,"size_bytes":"100"}"#
        }.joined(separator: ",")

        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let page = components?.queryItems?.first(where: { $0.name == "page" })?.value ?? "missing"
            state.pages.append(page)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if page == "1" {
                let body = #"{"torrents":["# + firstPage + #"]}"#
                return (response, Data(body.utf8))
            }
            let body = #"{"torrents":[{"hash":"page2","season":"1","episode":"1","seeds":9,"peers":2,"size_bytes":"bad"}]}"#
            return (response, Data(body.utf8))
        }

        let indexer = EZTVIndexer(session: session)
        let results = try await indexer.searchByQuery(query: "Show", type: .series)

        #expect(state.pages == ["1", "2"])
        #expect(results.count == 101)
        #expect(results.last?.infoHash == "page2")
        #expect(results.last?.title == "Unknown")
        #expect(results.last?.sizeBytes == 0)
    }

    @Test func searchByQueryReturnsEmptyForMovieWithoutNetwork() async throws {
        let indexer = EZTVIndexer(session: URLProtocolHarness.makeSession { request in
            Issue.record("Unexpected EZTV request: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        })

        let results = try await indexer.searchByQuery(query: "Show S01E01", type: .movie)

        #expect(results.isEmpty)
    }
}

@Suite("ZileanIndexer Behavior")
struct ZileanIndexerBehaviorTests {
    @Test func searchByIMDbUsesConfiguredEndpointAndAllowsUntokenizedEpisodeTitles() async throws {
        final class State: @unchecked Sendable {
            var capturedPath: String?
            var queryItems: [URLQueryItem] = []
        }
        let state = State()

        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            state.capturedPath = url.path
            state.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {"info_hash":"untokenized","raw_title":"Complete Season Pack","size":3000},
                {"info_hash":"episode-match","raw_title":"Show S01E02 1080p","size":2000},
                {"info_hash":"wrong-episode","raw_title":"Show S01E03 1080p","size":4000},
                {"info_hash":"","raw_title":"Missing Hash","size":1000},
                {"raw_title":"Nil Hash","size":1000}
            ]
            """
            return (response, Data(body.utf8))
        }

        let indexer = ZileanIndexer(baseURL: "https://zilean.example", endpointPath: "/custom", session: session)
        let results = try await indexer.search(imdbId: "tt1234567", type: .series, season: 1, episode: 2)

        #expect(state.capturedPath == "/custom/dmm/filtered")
        #expect(state.queryItems.first(where: { $0.name == "imdbId" })?.value == "tt1234567")
        #expect(state.queryItems.first(where: { $0.name == "season" })?.value == "1")
        #expect(state.queryItems.first(where: { $0.name == "episode" })?.value == "2")
        #expect(results.map(\.infoHash) == ["untokenized", "episode-match"])
        #expect(results.first?.title == "Complete Season Pack")
        #expect(results.first?.sizeBytes == 3000)
        #expect(results.allSatisfy { $0.indexerName == "Zilean" })
    }

    @Test func searchByQueryRequiresEpisodeTokensWhenQueryContainsEpisodeContext() async throws {
        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            [
                {"info_hash":"season-pack","raw_title":"Complete Season Pack","size":3000},
                {"info_hash":"episode-match","raw_title":"Show S02E04 720p","size":2000},
                {"info_hash":"wrong-episode","raw_title":"Show S02E05 720p","size":2000}
            ]
            """
            return (response, Data(body.utf8))
        }

        let indexer = ZileanIndexer(baseURL: "https://zilean.example", session: session)
        let results = try await indexer.searchByQuery(query: "Show S02E04", type: .series)

        #expect(results.map(\.infoHash) == ["episode-match"])
    }

    @Test func missingTitleAndSizeUseSafeDefaults() async throws {
        let session = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"[{"info_hash":"hash-with-defaults"}]"#.utf8))
        }

        let indexer = ZileanIndexer(baseURL: "https://zilean.example", session: session)
        let results = try await indexer.searchByQuery(query: "Movie", type: .movie)

        #expect(results.count == 1)
        #expect(results.first?.title == "Unknown")
        #expect(results.first?.sizeBytes == 0)
    }

    @Test func invalidBaseURLsAndNonSuccessResponsesThrow() async {
        let httpIndexer = ZileanIndexer(baseURL: "http://zilean.example", session: URLProtocolHarness.makeSession { request in
            Issue.record("Unexpected request for unsupported URL: \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        })

        await #expect(throws: URLError.self) {
            _ = try await httpIndexer.searchByQuery(query: "Movie", type: .movie)
        }

        let failingSession = URLProtocolHarness.makeSession { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let failingIndexer = ZileanIndexer(baseURL: "https://zilean.example", session: failingSession)

        await #expect(throws: URLError.self) {
            _ = try await failingIndexer.searchByQuery(query: "Movie", type: .movie)
        }
    }
}
