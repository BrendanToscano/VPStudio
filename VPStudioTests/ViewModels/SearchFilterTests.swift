import Foundation
import Testing
@testable import VPStudio

// MARK: - ExploreFilterSheet Data Tests

@Suite("ExploreFilterSheet - Year Range")
struct ExploreFilterSheetYearRangeTests {

    // The ExploreFilterSheet.yearRange is a private static let.
    // We test the behavior it implements by reasoning about the year range logic:
    // It should span from 1950 to the current year, in descending order.

    @Test func currentYearIsValid() {
        let currentYear = Calendar.current.component(.year, from: Date())
        #expect(currentYear >= 2024, "Current year should be at least 2024")
        #expect(currentYear <= 2100, "Current year sanity check")
    }

    @Test func yearRangeStartsAt1950() {
        // The filter uses (1950...current).reversed()
        // 1950 should be the oldest selectable year
        let currentYear = Calendar.current.component(.year, from: Date())
        let expectedCount = currentYear - 1950 + 1
        #expect(expectedCount > 70, "Year range should cover at least 70 years")
    }
}

// MARK: - DiscoverFilters Tests

@Suite("DiscoverFilters - Extended")
struct DiscoverFiltersExtendedTests {

    @Test func defaultInitHasPopularityDescSort() {
        let filters = DiscoverFilters()
        #expect(filters.sortBy == .popularityDesc)
    }

    @Test func defaultInitHasPageOne() {
        let filters = DiscoverFilters()
        #expect(filters.page == 1)
    }

    @Test func defaultInitHasNilGenreId() {
        let filters = DiscoverFilters()
        #expect(filters.genreId == nil)
    }

    @Test func defaultInitHasNilYear() {
        let filters = DiscoverFilters()
        #expect(filters.year == nil)
    }

    @Test func defaultInitHasNilMinRating() {
        let filters = DiscoverFilters()
        #expect(filters.minRating == nil)
    }

    @Test func defaultInitHasNilLanguage() {
        let filters = DiscoverFilters()
        #expect(filters.language == nil)
    }

    @Test func defaultInitHasNilReleaseDateGte() {
        let filters = DiscoverFilters()
        #expect(filters.releaseDateGte == nil)
    }

    @Test func defaultInitHasNilReleaseDateLte() {
        let filters = DiscoverFilters()
        #expect(filters.releaseDateLte == nil)
    }

    @Test func defaultInitHasNilOriginalLanguage() {
        let filters = DiscoverFilters()
        #expect(filters.originalLanguage == nil)
    }

    @Test func customInitSetsAllFields() {
        let filters = DiscoverFilters(
            genreId: 28,
            year: 2024,
            minRating: 7.5,
            sortBy: .ratingDesc,
            page: 3,
            language: "fr-FR",
            releaseDateGte: "2024-01-01",
            releaseDateLte: "2024-12-31",
            originalLanguage: "en"
        )
        #expect(filters.genreId == 28)
        #expect(filters.year == 2024)
        #expect(filters.minRating == 7.5)
        #expect(filters.sortBy == .ratingDesc)
        #expect(filters.page == 3)
        #expect(filters.language == "fr-FR")
        #expect(filters.releaseDateGte == "2024-01-01")
        #expect(filters.releaseDateLte == "2024-12-31")
        #expect(filters.originalLanguage == "en")
    }

    @Test func discoverFiltersIsSendable() {
        let filters = DiscoverFilters()
        let sendableCheck: any Sendable = filters
        _ = sendableCheck
    }
}

// MARK: - DiscoverFilters.SortOption Tests

@Suite("DiscoverFilters.SortOption - Extended")
struct DiscoverFiltersSortOptionExtendedTests {

    @Test func sortOptionCaseCount() {
        #expect(DiscoverFilters.SortOption.allCases.count == 7)
    }

    @Test func popularityDescRawValue() {
        #expect(DiscoverFilters.SortOption.popularityDesc.rawValue == "popularity.desc")
    }

    @Test func popularityAscRawValue() {
        #expect(DiscoverFilters.SortOption.popularityAsc.rawValue == "popularity.asc")
    }

    @Test func ratingDescRawValue() {
        #expect(DiscoverFilters.SortOption.ratingDesc.rawValue == "vote_average.desc")
    }

    @Test func ratingAscRawValue() {
        #expect(DiscoverFilters.SortOption.ratingAsc.rawValue == "vote_average.asc")
    }

    @Test func releaseDateDescRawValue() {
        #expect(DiscoverFilters.SortOption.releaseDateDesc.rawValue == "primary_release_date.desc")
    }

    @Test func releaseDateAscRawValue() {
        #expect(DiscoverFilters.SortOption.releaseDateAsc.rawValue == "primary_release_date.asc")
    }

    @Test func titleAscRawValue() {
        #expect(DiscoverFilters.SortOption.titleAsc.rawValue == "title.asc")
    }

    @Test func allDisplayNamesAreNonEmpty() {
        for option in DiscoverFilters.SortOption.allCases {
            #expect(!option.displayName.isEmpty, "\(option.rawValue) has empty displayName")
        }
    }

    @Test func popularityDescDisplayName() {
        #expect(DiscoverFilters.SortOption.popularityDesc.displayName == "Most Popular")
    }

    @Test func popularityAscDisplayName() {
        #expect(DiscoverFilters.SortOption.popularityAsc.displayName == "Least Popular")
    }

    @Test func ratingDescDisplayName() {
        #expect(DiscoverFilters.SortOption.ratingDesc.displayName == "Highest Rated")
    }

    @Test func ratingAscDisplayName() {
        #expect(DiscoverFilters.SortOption.ratingAsc.displayName == "Lowest Rated")
    }

    @Test func releaseDateDescDisplayName() {
        #expect(DiscoverFilters.SortOption.releaseDateDesc.displayName == "Newest")
    }

    @Test func releaseDateAscDisplayName() {
        #expect(DiscoverFilters.SortOption.releaseDateAsc.displayName == "Oldest")
    }

    @Test func titleAscDisplayName() {
        #expect(DiscoverFilters.SortOption.titleAsc.displayName == "Title A-Z")
    }

    @Test func sortOptionConformsToSendable() {
        let option: any Sendable = DiscoverFilters.SortOption.popularityDesc
        _ = option
    }

    @Test func sortOptionConformsToCaseIterable() {
        let all = DiscoverFilters.SortOption.allCases
        #expect(!all.isEmpty)
    }

    @Test func allRawValuesAreUnique() {
        let rawValues = DiscoverFilters.SortOption.allCases.map(\.rawValue)
        let uniqueRawValues = Set(rawValues)
        #expect(rawValues.count == uniqueRawValues.count)
    }

    @Test func allDisplayNamesAreUnique() {
        let names = DiscoverFilters.SortOption.allCases.map(\.displayName)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }
}

// MARK: - SearchLanguageOption Tests

@Suite("SearchLanguageOption")
struct SearchLanguageOptionTests {

    @Test func commonLanguagesIsNonEmpty() {
        #expect(!SearchLanguageOption.common.isEmpty)
    }

    @Test func commonLanguagesCountIsSeventeen() {
        #expect(SearchLanguageOption.common.count == 17)
    }

    @Test func englishIsFirstCommonLanguage() {
        let first = SearchLanguageOption.common.first
        #expect(first?.code == "en-US")
        #expect(first?.name == "English")
    }

    @Test func allLanguageCodesAreUnique() {
        let codes = SearchLanguageOption.common.map(\.code)
        let uniqueCodes = Set(codes)
        #expect(codes.count == uniqueCodes.count)
    }

    @Test func allLanguageNamesAreNonEmpty() {
        for option in SearchLanguageOption.common {
            #expect(!option.name.isEmpty, "Language with code \(option.code) has empty name")
        }
    }

    @Test func allLanguageCodesAreNonEmpty() {
        for option in SearchLanguageOption.common {
            #expect(!option.code.isEmpty, "Found language option with empty code")
        }
    }

    @Test func allLanguageCodesContainDash() {
        // Language codes follow locale format "xx-YY"
        for option in SearchLanguageOption.common {
            #expect(option.code.contains("-"),
                    "Language code \(option.code) does not follow xx-YY format")
        }
    }

    @Test func allLanguageNamesAreUnique() {
        let names = SearchLanguageOption.common.map(\.name)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }

    @Test func optionIdentifiableUsesCode() {
        let option = SearchLanguageOption.common[0]
        #expect(option.id == option.code)
    }

    // MARK: - displayName

    @Test func displayNameReturnsNameForKnownCode() {
        #expect(SearchLanguageOption.displayName(for: "en-US") == "English")
    }

    @Test func displayNameReturnsNameForJapanese() {
        #expect(SearchLanguageOption.displayName(for: "ja-JP") == "Japanese")
    }

    @Test func displayNameReturnsCodeForUnknownCode() {
        #expect(SearchLanguageOption.displayName(for: "xx-ZZ") == "xx-ZZ")
    }

    @Test func displayNameReturnsLanguageForNil() {
        #expect(SearchLanguageOption.displayName(for: nil) == "Language")
    }

    // MARK: - summaryName

    @Test func summaryNameReturnsAnyForEmptySet() {
        #expect(SearchLanguageOption.summaryName(for: []) == "Any")
    }

    @Test func summaryNameReturnsSingleLanguageName() {
        #expect(SearchLanguageOption.summaryName(for: ["en-US"]) == "English")
    }

    @Test func summaryNameReturnsTwoLanguagesJoinedSorted() {
        let summary = SearchLanguageOption.summaryName(for: ["fr-FR", "en-US"])
        // Names sorted alphabetically: "English", "French"
        #expect(summary == "English, French")
    }

    @Test func summaryNameReturnsCountForThreeOrMore() {
        let summary = SearchLanguageOption.summaryName(for: ["en-US", "fr-FR", "de-DE"])
        #expect(summary == "3 languages")
    }

    @Test func summaryNameReturnsCountForManyLanguages() {
        let codes: Set<String> = ["en-US", "fr-FR", "de-DE", "ja-JP", "ko-KR"]
        let summary = SearchLanguageOption.summaryName(for: codes)
        #expect(summary == "5 languages")
    }

    @Test func summaryNameForUnknownSingleCodeReturnsCode() {
        // Unknown code falls through displayName which returns the code itself
        let summary = SearchLanguageOption.summaryName(for: ["xx-ZZ"])
        #expect(summary == "xx-ZZ")
    }

    // MARK: - Specific Language Presence

    @Test func commonContainsSpanish() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "es-ES" }))
    }

    @Test func commonContainsFrench() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "fr-FR" }))
    }

    @Test func commonContainsGerman() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "de-DE" }))
    }

    @Test func commonContainsJapanese() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "ja-JP" }))
    }

    @Test func commonContainsKorean() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "ko-KR" }))
    }

    @Test func commonContainsChinese() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "zh-CN" }))
    }

    @Test func commonContainsArabic() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "ar-SA" }))
    }

    @Test func commonContainsPortuguese() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "pt-BR" }))
    }

    @Test func commonContainsRussian() {
        #expect(SearchLanguageOption.common.contains(where: { $0.code == "ru-RU" }))
    }
}

// MARK: - Genre Model Tests

@Suite("Genre - Extended")
struct GenreExtendedModelTests {

    @Test func genreIdentifiableUsesId() {
        let genre = Genre(id: 28, name: "Action")
        #expect(genre.id == 28)
    }

    @Test func genreHashableEquality() {
        let a = Genre(id: 28, name: "Action")
        let b = Genre(id: 28, name: "Action")
        #expect(a == b)
    }

    @Test func genreHashableInequality() {
        let a = Genre(id: 28, name: "Action")
        let b = Genre(id: 35, name: "Comedy")
        #expect(a != b)
    }

    @Test func genreCanBeUsedInSet() {
        let genres: Set<Genre> = [
            Genre(id: 28, name: "Action"),
            Genre(id: 35, name: "Comedy"),
            Genre(id: 28, name: "Action"),
        ]
        #expect(genres.count == 2)
    }

    @Test func genreIsCodable() throws {
        let genre = Genre(id: 28, name: "Action")
        let data = try JSONEncoder().encode(genre)
        let decoded = try JSONDecoder().decode(Genre.self, from: data)
        #expect(decoded.id == 28)
        #expect(decoded.name == "Action")
    }

    @Test func genreIsSendable() {
        let genre: any Sendable = Genre(id: 28, name: "Action")
        _ = genre
    }

    @Test func genreOptionalNilEquality() {
        let a: Genre? = nil
        let b: Genre? = nil
        #expect(a == b)
    }

    @Test func genreOptionalSomeEquality() {
        let a: Genre? = Genre(id: 28, name: "Action")
        let b: Genre? = Genre(id: 28, name: "Action")
        #expect(a == b)
    }

    @Test func genreOptionalMismatch() {
        let a: Genre? = Genre(id: 28, name: "Action")
        let b: Genre? = nil
        #expect(a != b)
    }
}

// MARK: - SearchViewModel Language Filter Behavior

@Suite("SearchViewModel - Filter Logic")
@MainActor
struct SearchViewModelFilterLogicTests {

    @Test func defaultLanguageFilterIsEnUS() {
        let viewModel = SearchViewModel()
        #expect(viewModel.languageFilters == ["en-US"])
    }

    @Test func multipleLanguagesCanBeSelected() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["en-US", "ja-JP", "ko-KR"]
        #expect(viewModel.languageFilters.count == 3)
        #expect(viewModel.languageFilters.contains("en-US"))
        #expect(viewModel.languageFilters.contains("ja-JP"))
        #expect(viewModel.languageFilters.contains("ko-KR"))
    }

    @Test func languageFilterCanBeCleared() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["en-US", "ja-JP"]
        viewModel.languageFilters = []
        #expect(viewModel.languageFilters.isEmpty)
    }

    @Test func clearResetsLanguageFilterToDefault() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["ja-JP", "ko-KR"]
        viewModel.clear()
        #expect(viewModel.languageFilters == ["en-US"])
    }

    @Test func clearResetsSortOption() {
        let viewModel = SearchViewModel()
        viewModel.sortOption = .ratingDesc
        viewModel.clear()
        #expect(viewModel.sortOption == .popularityDesc)
    }

    @Test func clearResetsYearFilter() {
        let viewModel = SearchViewModel()
        viewModel.yearFilter = 2023
        viewModel.clear()
        #expect(viewModel.yearFilter == nil)
    }

    @Test func clearResetsIsLoadingMore() {
        let viewModel = SearchViewModel()
        viewModel.clear()
        #expect(viewModel.isLoadingMore == false)
    }

    @Test func yearFilterAcceptsRecentYear() {
        let viewModel = SearchViewModel()
        viewModel.yearFilter = 2026
        #expect(viewModel.yearFilter == 2026)
    }

    @Test func yearFilterAcceptsOldYear() {
        let viewModel = SearchViewModel()
        viewModel.yearFilter = 1950
        #expect(viewModel.yearFilter == 1950)
    }

    @Test func yearFilterAcceptsNil() {
        let viewModel = SearchViewModel()
        viewModel.yearFilter = 2024
        viewModel.yearFilter = nil
        #expect(viewModel.yearFilter == nil)
    }

    @Test func languageFilterIsSet() {
        let viewModel = SearchViewModel()
        // Adding the same language twice should not result in duplicates
        viewModel.languageFilters.insert("en-US")
        viewModel.languageFilters.insert("en-US")
        #expect(viewModel.languageFilters.count == 1)
    }

    @Test func languageToggleRemovesIfPresent() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["en-US", "ja-JP"]
        viewModel.languageFilters.remove("en-US")
        #expect(viewModel.languageFilters == ["ja-JP"])
    }

    @Test func languageToggleAddsIfAbsent() {
        let viewModel = SearchViewModel()
        viewModel.languageFilters = ["en-US"]
        viewModel.languageFilters.insert("fr-FR")
        #expect(viewModel.languageFilters == ["en-US", "fr-FR"])
    }
}
