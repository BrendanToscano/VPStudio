import Foundation
import Testing
@testable import VPStudio

private actor HydratorMetadataProvider: MetadataProvider {
    private let detailPayloadByID: [String: MediaItem]
    private let failingDetailIDs: Set<String>
    private let searchPayload: MetadataSearchResult
    private let detailDelayNanoseconds: UInt64

    private var detailCallIDs: [String] = []
    private var searchQueries: [String] = []

    init(
        detailPayloadByID: [String: MediaItem],
        failingDetailIDs: Set<String> = [],
        searchPayload: MetadataSearchResult = MetadataSearchResult(items: [], page: 1, totalPages: 1, totalResults: 0),
        detailDelayNanoseconds: UInt64 = 0
    ) {
        self.detailPayloadByID = detailPayloadByID
        self.failingDetailIDs = failingDetailIDs
        self.searchPayload = searchPayload
        self.detailDelayNanoseconds = detailDelayNanoseconds
    }

    func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
        searchQueries.append(query)
        return searchPayload
    }

    func search(query: String, type: MediaType?, page: Int, year: Int?, language: String?) async throws -> MetadataSearchResult {
        searchQueries.append(query)
        return searchPayload
    }

    func getDetail(id: String, type: MediaType) async throws -> MediaItem {
        detailCallIDs.append(id)

        if detailDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: detailDelayNanoseconds)
        }

        if failingDetailIDs.contains(id) {
            throw TMDBError.notFound(id)
        }

        guard let payload = detailPayloadByID[id] else {
            throw TMDBError.notFound(id)
        }
        return payload
    }

    func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult {
        MetadataSearchResult(items: [], page: 1, totalPages: 1, totalResults: 0)
    }

    func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult {
        MetadataSearchResult(items: [], page: 1, totalPages: 1, totalResults: 0)
    }

    func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult {
        MetadataSearchResult(items: [], page: 1, totalPages: 1, totalResults: 0)
    }

    func getGenres(type: MediaType) async throws -> [Genre] { [] }
    func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
    func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds {
        ExternalIds(imdbId: nil, tvdbId: nil)
    }

    func recordedDetailCalls() -> [String] { detailCallIDs }
    func recordedSearchQueries() -> [String] { searchQueries }
}

@Suite("Library Metadata Hydrator")
struct LibraryMetadataHydratorTests {
    @Test
    func hydrateUsesTmdbIdAndPreservesOriginalMediaIdentifier() async throws {
        let provider = HydratorMetadataProvider(
            detailPayloadByID: [
                "123": MediaItem(
                    id: "tt1160419",
                    type: .movie,
                    title: "Dune",
                    year: 2021,
                    posterPath: "/dune.jpg",
                    backdropPath: "/dune-bg.jpg",
                    overview: "A duke's son leads desert warriors.",
                    genres: ["Science Fiction"],
                    imdbRating: 8.1,
                    runtime: 155,
                    status: "Released",
                    tmdbId: 123,
                    lastFetched: Date()
                ),
            ]
        )

        let hydrator = LibraryMetadataHydrator(
            metadataServiceFactory: { _ in provider }
        )

        let existing = MediaItem(
            id: "tt1160419",
            type: .movie,
            title: "Dune",
            year: 2021,
            posterPath: nil,
            backdropPath: nil,
            overview: nil,
            genres: [],
            imdbRating: nil,
            runtime: nil,
            status: nil,
            tmdbId: 123,
            lastFetched: nil
        )

        let hydrated = await hydrator.hydrate(
            mediaID: "tt1160419",
            existingItem: existing,
            apiKey: "tmdb-key"
        )

        let result = try #require(hydrated)
        #expect(result.id == "tt1160419")
        #expect(result.title == "Dune")
        #expect(result.posterPath == "/dune.jpg")
        #expect(result.tmdbId == 123)

        let detailCalls = await provider.recordedDetailCalls()
        #expect(detailCalls == ["123"])
    }

    @Test
    func hydrateFallsBackToTitleSearchWhenDirectLookupFails() async throws {
        let searchPreview = MediaPreview(
            id: "movie-tmdb-777",
            type: .movie,
            title: "Recovered Title",
            year: 2024,
            posterPath: "/recovered.jpg",
            backdropPath: nil,
            imdbRating: 7.8,
            tmdbId: 777
        )

        let provider = HydratorMetadataProvider(
            detailPayloadByID: [
                "777": MediaItem(
                    id: "tmdb-777",
                    type: .movie,
                    title: "Recovered Title",
                    year: 2024,
                    posterPath: "/recovered.jpg",
                    backdropPath: "/recovered-bg.jpg",
                    overview: "Recovered from search fallback.",
                    genres: ["Drama"],
                    imdbRating: 7.8,
                    runtime: 118,
                    status: "Released",
                    tmdbId: 777,
                    lastFetched: Date()
                ),
            ],
            failingDetailIDs: ["tt-fallback"],
            searchPayload: MetadataSearchResult(items: [searchPreview], page: 1, totalPages: 1, totalResults: 1)
        )

        let hydrator = LibraryMetadataHydrator(
            metadataServiceFactory: { _ in provider }
        )

        let existing = MediaItem(
            id: "tt-fallback",
            type: .movie,
            title: "Recovered Title",
            year: 2024,
            posterPath: nil,
            backdropPath: nil,
            overview: nil,
            genres: [],
            imdbRating: nil,
            runtime: nil,
            status: nil,
            tmdbId: nil,
            lastFetched: nil
        )

        let hydrated = await hydrator.hydrate(
            mediaID: "tt-fallback",
            existingItem: existing,
            apiKey: "tmdb-key"
        )

        let result = try #require(hydrated)
        #expect(result.id == "tt-fallback")
        #expect(result.posterPath == "/recovered.jpg")
        #expect(result.tmdbId == 777)

        let detailCalls = await provider.recordedDetailCalls()
        #expect(detailCalls == ["tt-fallback", "777"])
        let searchQueries = await provider.recordedSearchQueries()
        #expect(searchQueries == ["Recovered Title"])
    }

    @Test
    func hydrateDeduplicatesInflightRequestsForSameMediaId() async {
        let provider = HydratorMetadataProvider(
            detailPayloadByID: [
                "321": MediaItem(
                    id: "tmdb-321",
                    type: .movie,
                    title: "Inflight",
                    year: 2020,
                    posterPath: "/inflight.jpg",
                    backdropPath: nil,
                    overview: nil,
                    genres: [],
                    imdbRating: nil,
                    runtime: nil,
                    status: nil,
                    tmdbId: 321,
                    lastFetched: Date()
                ),
            ],
            detailDelayNanoseconds: 150_000_000
        )

        let hydrator = LibraryMetadataHydrator(
            metadataServiceFactory: { _ in provider }
        )

        let existing = MediaItem(
            id: "tt-inflight",
            type: .movie,
            title: "Inflight",
            year: 2020,
            posterPath: nil,
            backdropPath: nil,
            overview: nil,
            genres: [],
            imdbRating: nil,
            runtime: nil,
            status: nil,
            tmdbId: 321,
            lastFetched: nil
        )

        async let first = hydrator.hydrate(mediaID: "tt-inflight", existingItem: existing, apiKey: "tmdb-key")
        async let second = hydrator.hydrate(mediaID: "tt-inflight", existingItem: existing, apiKey: "tmdb-key")

        let firstResult = await first
        let secondResult = await second

        #expect(firstResult != nil)
        #expect(secondResult != nil)

        let detailCalls = await provider.recordedDetailCalls()
        #expect(detailCalls == ["321"])
    }

    @Test
    func hydrateSkipsImmediateRepeatRequestsAfterSuccess() async {
        let provider = HydratorMetadataProvider(
            detailPayloadByID: [
                "555": MediaItem(
                    id: "tmdb-555",
                    type: .movie,
                    title: "Cooldown",
                    year: 2022,
                    posterPath: "/cooldown.jpg",
                    backdropPath: nil,
                    overview: nil,
                    genres: [],
                    imdbRating: nil,
                    runtime: nil,
                    status: nil,
                    tmdbId: 555,
                    lastFetched: Date()
                ),
            ]
        )

        let hydrator = LibraryMetadataHydrator(
            configuration: .init(successCooldown: 60, failureCooldown: 1),
            metadataServiceFactory: { _ in provider }
        )

        let existing = MediaItem(
            id: "tt-cooldown",
            type: .movie,
            title: "Cooldown",
            year: 2022,
            posterPath: nil,
            backdropPath: nil,
            overview: nil,
            genres: [],
            imdbRating: nil,
            runtime: nil,
            status: nil,
            tmdbId: 555,
            lastFetched: nil
        )

        let first = await hydrator.hydrate(mediaID: "tt-cooldown", existingItem: existing, apiKey: "tmdb-key")
        let second = await hydrator.hydrate(mediaID: "tt-cooldown", existingItem: existing, apiKey: "tmdb-key")

        #expect(first != nil)
        #expect(second == nil)

        let detailCalls = await provider.recordedDetailCalls()
        #expect(detailCalls == ["555"])
    }
}
