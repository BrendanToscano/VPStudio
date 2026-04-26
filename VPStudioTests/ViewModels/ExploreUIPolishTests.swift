import Foundation
import SwiftUI
import Testing
@testable import VPStudio

@Suite("Explore UI Polish - ExplorePhase, GenreCatalog, Language Options")
@MainActor
struct ExploreUIPolishTests {

    private static func waitUntil(
        timeout: Duration = .milliseconds(5000),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("waitUntil timed out after \(timeout)")
                return
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - ExplorePhase Equatable Conformance

    @Test func explorePhaseIdleEqualsIdle() {
        #expect(ExplorePhase.idle == ExplorePhase.idle)
    }

    @Test func explorePhaseSearchingEqualsSearching() {
        #expect(ExplorePhase.searching == ExplorePhase.searching)
    }

    @Test func explorePhaseResultsEqualsResults() {
        #expect(ExplorePhase.results == ExplorePhase.results)
    }

    @Test func explorePhaseEmptyEqualsEmpty() {
        #expect(ExplorePhase.empty == ExplorePhase.empty)
    }

    @Test func explorePhaseErrorEqualsError() {
        #expect(ExplorePhase.error == ExplorePhase.error)
    }

    @Test func explorePhaseErrorNotEqualToIdle() {
        #expect(ExplorePhase.error != ExplorePhase.idle)
    }

    @Test func explorePhaseErrorNotEqualToSearching() {
        #expect(ExplorePhase.error != ExplorePhase.searching)
    }

    @Test func explorePhaseErrorNotEqualToResults() {
        #expect(ExplorePhase.error != ExplorePhase.results)
    }

    @Test func explorePhaseErrorNotEqualToEmpty() {
        #expect(ExplorePhase.error != ExplorePhase.empty)
    }

    @Test func explorePhaseIdleNotEqualToSearching() {
        #expect(ExplorePhase.idle != ExplorePhase.searching)
    }

    @Test func explorePhaseIdleNotEqualToResults() {
        #expect(ExplorePhase.idle != ExplorePhase.results)
    }

    @Test func explorePhaseIdleNotEqualToEmpty() {
        #expect(ExplorePhase.idle != ExplorePhase.empty)
    }

    @Test func explorePhaseSearchingNotEqualToResults() {
        #expect(ExplorePhase.searching != ExplorePhase.results)
    }

    @Test func explorePhaseSearchingNotEqualToEmpty() {
        #expect(ExplorePhase.searching != ExplorePhase.empty)
    }

    @Test func explorePhaseResultsNotEqualToEmpty() {
        #expect(ExplorePhase.results != ExplorePhase.empty)
    }

    // MARK: - ExplorePhase Transitions via ViewModel

    @Test func phaseTransitionsFromIdleToSearchingOnSearch() {
        let viewModel = SearchViewModel()
        viewModel.isSearching = true
        let before = ExplorePhase.idle
        let after = viewModel.explorePhase
        #expect(before != after)
        #expect(after == .searching)
    }

    @Test func phaseTransitionsFromSearchingToResultsWhenResultsArrive() {
        let viewModel = SearchViewModel()
        viewModel.isSearching = false
        viewModel.results = [Fixtures.mediaPreview(id: "r1")]
        #expect(viewModel.explorePhase == .results)
    }

    @Test func phaseTransitionsFromSearchingToEmptyOnNoResults() async throws {
        let viewModel = SearchViewModel(metadataService: StubMetadataProvider())
        viewModel.isSearching = false
        // Use the real submit path so `hasAttemptedTextSearch` is set and the
        // empty state reflects a successful configured search with zero results.
        viewModel.search(queryText: "no matches here")
        try await Self.waitUntil(timeout: .seconds(1)) { viewModel.explorePhase == .empty }
        #expect(viewModel.explorePhase == .empty)
    }

    @Test func phaseIsErrorWhenErrorExistsAndNoResults() {
        let viewModel = SearchViewModel()
        viewModel.error = .network(.transport("Test error"))
        viewModel.results = []
        #expect(viewModel.explorePhase == .error)
    }

    @Test func phaseIsResultsWhenErrorExistsButResultsPresent() {
        let viewModel = SearchViewModel()
        viewModel.error = .network(.transport("Test error"))
        viewModel.results = [Fixtures.mediaPreview(id: "r1")]
        #expect(viewModel.explorePhase == .results)
    }

    @Test func phaseReturnsToIdleAfterClear() {
        let viewModel = SearchViewModel()
        viewModel.query = "test"
        viewModel.results = [Fixtures.mediaPreview(id: "r1")]
        #expect(viewModel.explorePhase == .results)
        viewModel.clear()
        #expect(viewModel.explorePhase == .idle)
    }

    // MARK: - ExploreGenreCatalog

    @Test func catalogHasFourteenCards() {
        #expect(ExploreGenreCatalog.cards.count == 14)
    }

    @Test func catalogCardIdsAreUnique() {
        let ids = ExploreGenreCatalog.cards.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func catalogContainsNewReleasesCard() {
        let newCard = ExploreGenreCatalog.cards.first(where: { $0.id == "new" })
        #expect(newCard != nil)
        #expect(newCard?.isNewReleases == true)
        #expect(newCard?.movieGenreId == -1)
        #expect(newCard?.tvGenreId == -1)
    }

    @Test func catalogNewReleasesIsOnlySpecialCard() {
        let specialCards = ExploreGenreCatalog.cards.filter(\.isNewReleases)
        #expect(specialCards.count == 1)
    }

    @Test func catalogAllNonSpecialCardsHavePositiveGenreIds() {
        let normalCards = ExploreGenreCatalog.cards.filter { !$0.isSpecialCard }
        for card in normalCards {
            #expect(card.movieGenreId > 0, "Card '\(card.id)' has non-positive movieGenreId")
            #expect(card.tvGenreId > 0, "Card '\(card.id)' has non-positive tvGenreId")
        }
    }

    @Test func catalogAllCardsHaveNonEmptyTitles() {
        for card in ExploreGenreCatalog.cards {
            #expect(!card.title.isEmpty, "Card '\(card.id)' has empty title")
        }
    }

    @Test func catalogAllCardsHaveNonEmptySubtitles() {
        for card in ExploreGenreCatalog.cards {
            #expect(!card.subtitle.isEmpty, "Card '\(card.id)' has empty subtitle")
        }
    }

    @Test func catalogAllCardsHaveNonEmptySymbols() {
        for card in ExploreGenreCatalog.cards {
            #expect(!card.symbol.isEmpty, "Card '\(card.id)' has empty symbol")
        }
    }

    @Test func catalogSciFiCardHasCorrectGenreIds() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "scifi" })!
        #expect(card.movieGenreId == 878)
        #expect(card.tvGenreId == 10765)
    }

    @Test func catalogActionCardHasCorrectGenreIds() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "action" })!
        #expect(card.movieGenreId == 28)
        #expect(card.tvGenreId == 10759)
    }

    @Test func catalogDramaCardHasCorrectGenreIds() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "drama" })!
        #expect(card.movieGenreId == 18)
        #expect(card.tvGenreId == 18)
    }

    @Test func catalogContainsAllExpectedIds() {
        let expectedIds: Set<String> = [
            "scifi", "drama", "comedy", "action", "deep", "horror",
            "animation", "mystery", "docs", "fantasy", "chill", "classics", "new", "upcoming"
        ]
        let actualIds = Set(ExploreGenreCatalog.cards.map(\.id))
        #expect(actualIds == expectedIds)
    }

    @Test func genreTilePolicyUsesReferenceSnapshotNames() {
        for card in ExploreGenreCatalog.cards {
            #expect(ExploreGenreTilePolicy.imageName(for: card) == "genre-ref-\(card.id)")
            #expect(ExploreGenreTilePolicy.accessibilityLabel(for: card) == "\(card.title), \(card.subtitle)")
        }
    }

    @Test func genreTilePolicyKeepsScreenshotGeometryStable() {
        #expect(ExploreGenreTilePolicy.columns == 7)
        #expect(ExploreGenreTilePolicy.tileWidth == 128)
        #expect(ExploreGenreTilePolicy.columnSpacing == 16)
        #expect(ExploreGenreTilePolicy.rowSpacing == 15)
        #expect(ExploreGenreTilePolicy.cornerRadius == 17)
        #expect(abs(Double(ExploreGenreTilePolicy.referenceAspectRatio) - (227.0 / 251.0)) < 0.000_001)
        #expect(ExploreGenreTilePolicy.gridColumns().count == ExploreGenreTilePolicy.columns)
    }

    // MARK: - SearchLanguageOption

    @Test func displayNameReturnsLanguageForKnownCode() {
        #expect(SearchLanguageOption.displayName(for: "en-US") == "English")
        #expect(SearchLanguageOption.displayName(for: "ja-JP") == "Japanese")
        #expect(SearchLanguageOption.displayName(for: "ko-KR") == "Korean")
    }

    @Test func displayNameReturnsCodeForUnknownLanguage() {
        #expect(SearchLanguageOption.displayName(for: "xx-XX") == "xx-XX")
    }

    @Test func displayNameReturnsLanguageForNilCode() {
        #expect(SearchLanguageOption.displayName(for: nil) == "Language")
    }

    @Test func summaryNameReturnsAnyForEmptySet() {
        #expect(SearchLanguageOption.summaryName(for: []) == "Any")
    }

    @Test func summaryNameReturnsSingleLanguageName() {
        #expect(SearchLanguageOption.summaryName(for: ["en-US"]) == "English")
    }

    @Test func summaryNameReturnsTwoLanguagesJoined() {
        let result = SearchLanguageOption.summaryName(for: ["en-US", "ja-JP"])
        // Sorted: English, Japanese
        #expect(result == "English, Japanese")
    }

    @Test func summaryNameReturnsCountForThreeOrMore() {
        let result = SearchLanguageOption.summaryName(for: ["en-US", "ja-JP", "ko-KR"])
        #expect(result == "3 languages")
    }

    @Test func commonLanguagesHasNineteenOptions() {
        #expect(SearchLanguageOption.common.count == 19)
    }

    @Test func commonLanguageCodesAreUnique() {
        let codes = SearchLanguageOption.common.map(\.code)
        #expect(Set(codes).count == codes.count)
    }

    @Test func commonLanguageNamesAreNonEmpty() {
        for option in SearchLanguageOption.common {
            #expect(!option.name.isEmpty, "Language option '\(option.code)' has empty name")
        }
    }

    // MARK: - AIMovieRecommendation → MediaPreview Conversion

    @Test func aiRecommendationToMediaPreviewUsesMovieType() {
        let rec = AIMovieRecommendation(title: "Test Movie", year: 2024, type: .movie, reason: "Good", tmdbId: 42)
        let preview = rec.toMediaPreview()
        #expect(preview.type == .movie)
        #expect(preview.title == "Test Movie")
        #expect(preview.year == 2024)
        #expect(preview.tmdbId == 42)
    }

    @Test func aiRecommendationToMediaPreviewUsesSeriesType() {
        let rec = AIMovieRecommendation(title: "Test Show", year: 2023, type: .series, reason: "Great", tmdbId: 99)
        let preview = rec.toMediaPreview()
        #expect(preview.type == .series)
    }

    @Test func aiRecommendationToMediaPreviewWithTmdbIdUsesTypePrefixedId() {
        let rec = AIMovieRecommendation(title: "Dune", year: 2021, type: .movie, reason: "Epic", tmdbId: 438631)
        let preview = rec.toMediaPreview()
        #expect(preview.id == "movie-tmdb-438631")
    }

    @Test func aiRecommendationToMediaPreviewWithoutTmdbIdUsesFallbackId() {
        let rec = AIMovieRecommendation(title: "Unknown Film", year: 2020, type: .movie, reason: "Rare", tmdbId: nil)
        let preview = rec.toMediaPreview()
        #expect(preview.id == "unknown-film-2020-movie")
    }

    @Test func aiRecommendationToMediaPreviewWithNilYearUsesZeroInFallbackId() {
        let rec = AIMovieRecommendation(title: "No Year", year: nil, type: .series, reason: "Old", tmdbId: nil)
        let preview = rec.toMediaPreview()
        #expect(preview.id == "no-year-0-series")
    }

    @Test func aiRecommendationToMediaPreviewHasNilPosterPath() {
        let rec = AIMovieRecommendation(title: "Test", year: 2024, type: .movie, reason: "Good", tmdbId: 1)
        let preview = rec.toMediaPreview()
        #expect(preview.posterPath == nil)
    }

    @Test func aiRecommendationToMediaPreviewHasNilImdbRating() {
        let rec = AIMovieRecommendation(title: "Test", year: 2024, type: .movie, reason: "Good", tmdbId: 1)
        let preview = rec.toMediaPreview()
        #expect(preview.imdbRating == nil)
    }
}
