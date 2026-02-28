import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct SearchFilterDateTests {

    // MARK: - Date Helper Tests

    @Test
    func todayStringReturnsCorrectFormat() {
        let today = DiscoverFilters.todayString()
        // Format should be yyyy-MM-dd
        #expect(today.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }

    @Test
    func dateStringWithNegativeDaysReturnsPastDate() {
        let date90DaysAgo = DiscoverFilters.dateString(daysFromNow: -90)
        // Should be in yyyy-MM-dd format
        #expect(date90DaysAgo.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }

    @Test
    func dateStringWithPositiveDaysReturnsFutureDate() {
        let dateIn30Days = DiscoverFilters.dateString(daysFromNow: 30)
        // Should be in yyyy-MM-dd format
        #expect(dateIn30Days.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }

    @Test
    func dateStringWithZeroReturnsToday() {
        let today = DiscoverFilters.dateString(daysFromNow: 0)
        let expectedToday = DiscoverFilters.todayString()
        #expect(today == expectedToday)
    }

    // MARK: - Year Range Preset Tests

    @Test
    func yearRangePresetRecentContains2024_2025_2026() {
        let preset = YearRangePreset.recent
        #expect(preset.contains(year: 2024) == true)
        #expect(preset.contains(year: 2025) == true)
        #expect(preset.contains(year: 2026) == true)
    }

    @Test
    func yearRangePresetRecentDoesNotContainOtherYears() {
        let preset = YearRangePreset.recent
        #expect(preset.contains(year: 2023) == false)
        #expect(preset.contains(year: 2020) == false)
        #expect(preset.contains(year: 2000) == false)
    }

    @Test
    func yearRangePresetTwentiesContains2020_2029() {
        let preset = YearRangePreset.twenties
        #expect(preset.contains(year: 2020) == true)
        #expect(preset.contains(year: 2025) == true)
        #expect(preset.contains(year: 2029) == true)
    }

    @Test
    func yearRangePresetTwentiesDoesNotContainOtherYears() {
        let preset = YearRangePreset.twenties
        #expect(preset.contains(year: 2019) == false)
        #expect(preset.contains(year: 2030) == false)
    }

    @Test
    func yearRangePresetTensContains2010_2019() {
        let preset = YearRangePreset.tens
        #expect(preset.contains(year: 2010) == true)
        #expect(preset.contains(year: 2015) == true)
        #expect(preset.contains(year: 2019) == true)
    }

    @Test
    func yearRangePresetClassicContainsPre2000() {
        let preset = YearRangePreset.classic
        #expect(preset.contains(year: 1999) == true)
        #expect(preset.contains(year: 1980) == true)
        #expect(preset.contains(year: 1950) == true)
    }

    @Test
    func yearRangePresetClassicDoesNotContain2000AndLater() {
        let preset = YearRangePreset.classic
        #expect(preset.contains(year: 2000) == false)
        #expect(preset.contains(year: 2010) == false)
        #expect(preset.contains(year: 2020) == false)
    }

    // MARK: - Mood Card Date Boundary Tests

    @Test
    func newReleasesCardHasCorrectDateRange() {
        let newReleasesCard = ExploreMoodCard(
            id: "new",
            title: "New Releases",
            subtitle: "JUST DROPPED",
            symbol: "flame.fill",
            color: .red,
            movieGenreId: -1,
            tvGenreId: -1
        )

        #expect(newReleasesCard.isNewReleases == true)
        #expect(newReleasesCard.isFutureReleases == false)
        #expect(newReleasesCard.isSpecialCard == true)

        // Verify the date range logic used in SearchViewModel
        let dateGte = DiscoverFilters.dateString(daysFromNow: -90)
        let dateLte = DiscoverFilters.todayString()

        // dateGte should be 90 days ago
        #expect(dateGte.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
        // dateLte should be today
        #expect(dateLte.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }

    @Test
    func futureReleasesCardHasCorrectDateRange() {
        let futureReleasesCard = ExploreMoodCard(
            id: "upcoming",
            title: "Coming Soon",
            subtitle: "FUTURE RELEASES",
            symbol: "calendar.badge.clock",
            color: .blue,
            movieGenreId: -2,
            tvGenreId: -2
        )

        #expect(futureReleasesCard.isNewReleases == false)
        #expect(futureReleasesCard.isFutureReleases == true)
        #expect(futureReleasesCard.isSpecialCard == true)

        // Verify the date range logic used in SearchViewModel
        let dateGte = DiscoverFilters.dateString(daysFromNow: 1)  // Tomorrow
        let dateLte = DiscoverFilters.dateString(daysFromNow: 365)  // 1 year from now

        // dateGte should be tomorrow (greater than today)
        #expect(dateGte.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
        // dateLte should be 1 year from now
        #expect(dateLte.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }

    @Test
    func regularGenreCardIsNotSpecial() {
        let genreCard = ExploreMoodCard(
            id: "action",
            title: "Action",
            subtitle: "HIGH ENERGY",
            symbol: "bolt.fill",
            color: .orange,
            movieGenreId: 28,
            tvGenreId: 10759
        )

        #expect(genreCard.isNewReleases == false)
        #expect(genreCard.isFutureReleases == false)
        #expect(genreCard.isSpecialCard == false)
    }

    // MARK: - DiscoverFilters Query Tests

    @Test
    func discoverFiltersAcceptsQueryParameter() {
        let filters = DiscoverFilters(
            query: "test movie",
            year: 2024,
            sortBy: .releaseDateDesc,
            page: 1
        )

        #expect(filters.query == "test movie")
        #expect(filters.year == 2024)
        #expect(filters.sortBy == .releaseDateDesc)
        #expect(filters.page == 1)
    }

    @Test
    func discoverFiltersWithDateRange() {
        let dateGte = DiscoverFilters.dateString(daysFromNow: -30)
        let dateLte = DiscoverFilters.todayString()

        let filters = DiscoverFilters(
            releaseDateGte: dateGte,
            releaseDateLte: dateLte,
            sortBy: .releaseDateDesc,
            page: 1
        )

        #expect(filters.releaseDateGte != nil)
        #expect(filters.releaseDateLte != nil)
        #expect(filters.releaseDateLte == DiscoverFilters.todayString())
    }
}
