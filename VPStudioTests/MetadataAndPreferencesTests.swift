import Testing
import Foundation
@testable import VPStudio

// MARK: - DiscoverFilters Tests

@Suite("DiscoverFilters")
struct DiscoverFiltersTests {

    @Test func defaultValues() {
        let filters = DiscoverFilters()
        #expect(filters.genreId == nil)
        #expect(filters.year == nil)
        #expect(filters.minRating == nil)
        #expect(filters.sortBy == .popularityDesc)
        #expect(filters.page == 1)
    }

    @Test func customValues() {
        let filters = DiscoverFilters(genreId: 28, year: 2025, minRating: 7.0, sortBy: .ratingDesc, page: 3, language: "en-US")
        #expect(filters.genreId == 28)
        #expect(filters.year == 2025)
        #expect(filters.minRating == 7.0)
        #expect(filters.sortBy == .ratingDesc)
        #expect(filters.page == 3)
        #expect(filters.language == "en-US")
    }
}

@Suite("DiscoverFilters.SortOption")
struct SortOptionTests {

    @Test func allCasesExist() {
        #expect(DiscoverFilters.SortOption.allCases.count == 7)
    }

    @Test func rawValuesAreCorrect() {
        #expect(DiscoverFilters.SortOption.popularityDesc.rawValue == "popularity.desc")
        #expect(DiscoverFilters.SortOption.popularityAsc.rawValue == "popularity.asc")
        #expect(DiscoverFilters.SortOption.ratingDesc.rawValue == "vote_average.desc")
        #expect(DiscoverFilters.SortOption.ratingAsc.rawValue == "vote_average.asc")
        #expect(DiscoverFilters.SortOption.releaseDateDesc.rawValue == "primary_release_date.desc")
        #expect(DiscoverFilters.SortOption.releaseDateAsc.rawValue == "primary_release_date.asc")
        #expect(DiscoverFilters.SortOption.titleAsc.rawValue == "title.asc")
    }

    @Test func displayNamesAreHumanReadable() {
        #expect(DiscoverFilters.SortOption.popularityDesc.displayName == "Most Popular")
        #expect(DiscoverFilters.SortOption.popularityAsc.displayName == "Least Popular")
        #expect(DiscoverFilters.SortOption.ratingDesc.displayName == "Highest Rated")
        #expect(DiscoverFilters.SortOption.ratingAsc.displayName == "Lowest Rated")
        #expect(DiscoverFilters.SortOption.releaseDateDesc.displayName == "Newest")
        #expect(DiscoverFilters.SortOption.releaseDateAsc.displayName == "Oldest")
        #expect(DiscoverFilters.SortOption.titleAsc.displayName == "Title A-Z")
    }

    @Test func allCasesHaveNonEmptyDisplayNames() {
        for option in DiscoverFilters.SortOption.allCases {
            #expect(!option.displayName.isEmpty)
        }
    }
}

// MARK: - Genre Tests

@Suite("Genre")
struct GenreTests {

    @Test func identifiableById() {
        let genre = Genre(id: 28, name: "Action")
        #expect(genre.id == 28)
    }

    @Test func equatableByIdAndName() {
        let a = Genre(id: 28, name: "Action")
        let b = Genre(id: 28, name: "Action")
        let c = Genre(id: 35, name: "Comedy")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func codableRoundTrip() throws {
        let original = Genre(id: 12, name: "Adventure")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Genre.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - MediaCategory Tests

@Suite("MediaCategory")
struct MediaCategoryTests {

    @Test func allCasesExist() {
        #expect(MediaCategory.allCases.count == 6)
    }

    @Test func displayNamesAreCorrect() {
        #expect(MediaCategory.popular.displayName == "Popular")
        #expect(MediaCategory.topRated.displayName == "Top Rated")
        #expect(MediaCategory.nowPlaying.displayName == "Now Playing")
        #expect(MediaCategory.upcoming.displayName == "Upcoming")
        #expect(MediaCategory.airingToday.displayName == "Airing Today")
        #expect(MediaCategory.onTheAir.displayName == "On The Air")
    }

    @Test func rawValuesAreCorrect() {
        #expect(MediaCategory.popular.rawValue == "popular")
        #expect(MediaCategory.topRated.rawValue == "top_rated")
        #expect(MediaCategory.nowPlaying.rawValue == "now_playing")
        #expect(MediaCategory.upcoming.rawValue == "upcoming")
        #expect(MediaCategory.airingToday.rawValue == "airing_today")
        #expect(MediaCategory.onTheAir.rawValue == "on_the_air")
    }

    @Test func movieCategoriesAreCorrect() {
        let categories = MediaCategory.categories(for: .movie)
        #expect(categories.count == 4)
        #expect(categories.contains(.popular))
        #expect(categories.contains(.topRated))
        #expect(categories.contains(.nowPlaying))
        #expect(categories.contains(.upcoming))
        #expect(!categories.contains(.airingToday))
        #expect(!categories.contains(.onTheAir))
    }

    @Test func seriesCategoriesAreCorrect() {
        let categories = MediaCategory.categories(for: .series)
        #expect(categories.count == 4)
        #expect(categories.contains(.popular))
        #expect(categories.contains(.topRated))
        #expect(categories.contains(.airingToday))
        #expect(categories.contains(.onTheAir))
        #expect(!categories.contains(.nowPlaying))
        #expect(!categories.contains(.upcoming))
    }

    @Test func movieAndSeriesCategoriesOverlap() {
        let movieCats = MediaCategory.categories(for: .movie)
        let seriesCats = MediaCategory.categories(for: .series)
        let shared = Set(movieCats).intersection(Set(seriesCats))
        #expect(shared.contains(.popular))
        #expect(shared.contains(.topRated))
        #expect(shared.count == 2)
    }
}

// MARK: - TrendingWindow Tests

@Suite("TrendingWindow")
struct TrendingWindowTests {

    @Test func rawValues() {
        #expect(TrendingWindow.day.rawValue == "day")
        #expect(TrendingWindow.week.rawValue == "week")
    }
}

// MARK: - ExternalIds Tests

@Suite("ExternalIds")
struct ExternalIdsTests {

    @Test func codableRoundTrip() throws {
        let original = ExternalIds(imdbId: "tt1234567", tvdbId: 42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExternalIds.self, from: data)
        #expect(decoded.imdbId == "tt1234567")
        #expect(decoded.tvdbId == 42)
    }

    @Test func decodesFromSnakeCaseJSON() throws {
        let json = """
        {"imdb_id":"tt9999999","tvdb_id":100}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(ExternalIds.self, from: Data(json.utf8))
        #expect(decoded.imdbId == "tt9999999")
        #expect(decoded.tvdbId == 100)
    }

    @Test func optionalFieldsDecodeAsNil() throws {
        let json = """
        {}
        """
        let decoded = try JSONDecoder().decode(ExternalIds.self, from: Data(json.utf8))
        #expect(decoded.imdbId == nil)
        #expect(decoded.tvdbId == nil)
    }
}

// MARK: - MetadataSearchResult Tests

@Suite("MetadataSearchResult")
struct MetadataSearchResultTests {

    @Test func storesAllFields() {
        let result = MetadataSearchResult(
            items: [MediaPreview(id: "1", type: .movie, title: "Test")],
            page: 2,
            totalPages: 10,
            totalResults: 100
        )
        #expect(result.items.count == 1)
        #expect(result.page == 2)
        #expect(result.totalPages == 10)
        #expect(result.totalResults == 100)
    }
}

// MARK: - PlayerSessionRequest Tests

@Suite("PlayerSessionRequest")
struct PlayerSessionRequestTests {

    @Test func storesAllFields() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/video.mkv")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "video.mkv",
            sizeBytes: 1_000_000, debridService: "rd"
        )
        let request = PlayerSessionRequest(
            stream: stream,
            availableStreams: [stream],
            mediaTitle: "Test Movie",
            mediaId: "movie-1",
            episodeId: "ep-1"
        )
        #expect(request.mediaTitle == "Test Movie")
        #expect(request.mediaId == "movie-1")
        #expect(request.episodeId == "ep-1")
        #expect(request.availableStreams.count == 1)
    }

    @Test func defaultAvailableStreamsIsEmpty() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/video.mkv")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "video.mkv",
            sizeBytes: nil, debridService: "rd"
        )
        let request = PlayerSessionRequest(
            stream: stream,
            mediaTitle: "Test",
            mediaId: "m1"
        )
        #expect(request.availableStreams.isEmpty)
        #expect(request.episodeId == nil)
    }

    @Test func hashableConformance() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/video.mkv")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "video.mkv",
            sizeBytes: nil, debridService: "rd"
        )
        let a = PlayerSessionRequest(
            id: UUID(),
            stream: stream,
            mediaTitle: "Movie",
            mediaId: "m1"
        )
        let b = PlayerSessionRequest(
            id: a.id,
            stream: stream,
            mediaTitle: "Movie",
            mediaId: "m1"
        )
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func codableRoundTrip() throws {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/video.mkv")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "video.mkv",
            sizeBytes: 500, debridService: "rd"
        )
        let original = PlayerSessionRequest(
            stream: stream,
            mediaTitle: "Test Movie",
            mediaId: "movie-1",
            episodeId: "ep-1"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlayerSessionRequest.self, from: data)
        #expect(decoded.mediaTitle == "Test Movie")
        #expect(decoded.mediaId == "movie-1")
        #expect(decoded.episodeId == "ep-1")
    }

    @Test func identifiableById() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "a.mkv",
            sizeBytes: nil, debridService: "rd"
        )
        let id = UUID()
        let request = PlayerSessionRequest(
            id: id,
            stream: stream,
            mediaTitle: "M",
            mediaId: "1"
        )
        #expect(request.id == id)
    }
}

// MARK: - Subtitle Model Additional Tests

@Suite("Subtitle - Additional")
struct SubtitleAdditionalTests {

    @Test func downloadURLIsNilForInvalidURL() {
        let sub = Subtitle(id: "1", language: "en", fileName: "a.srt", url: "not a url\n\n", format: .srt)
        #expect(sub.downloadURL == nil)
    }

    @Test func displayNameHandlesMultiByteLanguage() {
        let sub = Subtitle(id: "1", language: "日本語", fileName: "a.srt", url: "https://x.com/a.srt", format: .srt)
        #expect(sub.displayName == "日本語")
    }

    @Test func subtitleFormatParseHandlesUppercase() {
        #expect(SubtitleFormat.parse(from: "Movie.SRT") == .srt)
        #expect(SubtitleFormat.parse(from: "Movie.VTT") == .vtt)
        #expect(SubtitleFormat.parse(from: "Movie.ASS") == .ass)
        #expect(SubtitleFormat.parse(from: "Movie.SSA") == .ssa)
    }

    @Test func subtitleFormatParseMixedCase() {
        #expect(SubtitleFormat.parse(from: "movie.Srt") == .srt)
        #expect(SubtitleFormat.parse(from: "movie.WebVTT") == .vtt)
    }
}
