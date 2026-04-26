import Foundation
import Testing
@testable import VPStudio

@Suite("MetadataProvider Policies")
struct MetadataProviderPolicyTests {
    @Test
    func discoverFilterDateHelpersUseUTCAndOffsets() {
        let now = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC

        #expect(DiscoverFilters.todayString(now: now) == "2025-01-01")
        #expect(DiscoverFilters.dateString(daysFromNow: 7, now: now) == "2025-01-08")
        #expect(DiscoverFilters.dateString(daysFromNow: -1, now: now) == "2024-12-31")
    }

    @Test(arguments: [
        ("en-US", "en"),
        ("JA-jp", "ja"),
        ("pt", "pt"),
        ("", ""),
    ])
    func iso639LanguageCodeUsesFirstLocaleComponent(locale: String, expected: String) {
        #expect(DiscoverFilters.iso639LanguageCode(from: locale) == expected)
    }

    @Test
    func sortOptionsMapSeriesSpecificTMDBFields() {
        #expect(DiscoverFilters.SortOption.releaseDateDesc.tmdbValue(for: .movie) == "primary_release_date.desc")
        #expect(DiscoverFilters.SortOption.releaseDateDesc.tmdbValue(for: .series) == "first_air_date.desc")
        #expect(DiscoverFilters.SortOption.releaseDateAsc.tmdbValue(for: .series) == "first_air_date.asc")
        #expect(DiscoverFilters.SortOption.titleAsc.tmdbValue(for: .movie) == "title.asc")
        #expect(DiscoverFilters.SortOption.titleAsc.tmdbValue(for: .series) == "name.asc")
        #expect(DiscoverFilters.SortOption.ratingDesc.tmdbValue(for: .series) == "vote_average.desc")
    }

    @Test
    func mediaTypeSearchYearParameterMatchesTMDBAPI() {
        #expect(MediaType.movie.tmdbSearchYearParameterName == "year")
        #expect(MediaType.series.tmdbSearchYearParameterName == "first_air_date_year")
    }

    @Test
    func mediaCategoriesDifferForMovieAndSeries() {
        #expect(MediaCategory.categories(for: .movie) == [.popular, .topRated, .nowPlaying, .upcoming])
        #expect(MediaCategory.categories(for: .series) == [.popular, .topRated, .airingToday, .onTheAir])
        #expect(MediaCategory.nowPlaying.displayName == "Now Playing")
        #expect(MediaCategory.onTheAir.displayName == "On The Air")
    }

    @Test
    func defaultSearchOverloadIgnoresYearAndLanguage() async throws {
        let provider = DefaultSearchOnlyMetadataProvider()

        let result = try await provider.search(
            query: " dune ",
            type: .movie,
            page: 3,
            year: 2021,
            language: "en"
        )

        #expect(result.page == 3)
        #expect(result.totalResults == 1)
        #expect(await provider.recordedQueries == [" dune "])
        #expect(await provider.recordedTypes == [.movie])
        #expect(await provider.recordedPages == [3])
    }
}

private actor DefaultSearchOnlyMetadataProvider: MetadataProvider {
    private(set) var recordedQueries: [String] = []
    private(set) var recordedTypes: [MediaType?] = []
    private(set) var recordedPages: [Int] = []

    func search(query: String, type: MediaType?, page: Int) async throws -> MetadataSearchResult {
        recordedQueries.append(query)
        recordedTypes.append(type)
        recordedPages.append(page)
        return MetadataSearchResult(
            items: [],
            page: page,
            totalPages: 1,
            totalResults: 1
        )
    }

    func getDetail(id: String, type: MediaType) async throws -> MediaItem {
        MediaItem(id: id, type: type, title: "Detail")
    }

    func getTrending(type: MediaType, timeWindow: TrendingWindow, page: Int) async throws -> MetadataSearchResult {
        MetadataSearchResult(items: [], page: page, totalPages: 1, totalResults: 0)
    }

    func getCategory(_ category: MediaCategory, type: MediaType, page: Int) async throws -> MetadataSearchResult {
        MetadataSearchResult(items: [], page: page, totalPages: 1, totalResults: 0)
    }

    func discover(type: MediaType, filters: DiscoverFilters) async throws -> MetadataSearchResult {
        MetadataSearchResult(items: [], page: filters.page, totalPages: 1, totalResults: 0)
    }

    func getGenres(type: MediaType) async throws -> [Genre] { [] }
    func getSeasons(tmdbId: Int) async throws -> [Season] { [] }
    func getEpisodes(tmdbId: Int, season: Int) async throws -> [Episode] { [] }
    func getExternalIds(tmdbId: Int, type: MediaType) async throws -> ExternalIds { ExternalIds() }
}
