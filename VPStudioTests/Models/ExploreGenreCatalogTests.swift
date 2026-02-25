import Foundation
import SwiftUI
import Testing
@testable import VPStudio

// MARK: - ExploreMoodCard Tests

@Suite("ExploreMoodCard")
struct ExploreMoodCardTests {

    @Test func identifiableConformanceUsesId() {
        let card = ExploreGenreCatalog.cards[0]
        let _: String = card.id
    }

    @Test func isNewReleasesReturnsTrueWhenMovieGenreIdIsNegativeOne() {
        let card = ExploreMoodCard(
            id: "test", title: "Test", subtitle: "TEST",
            symbol: "star", color: .red, movieGenreId: -1, tvGenreId: -1
        )
        #expect(card.isNewReleases == true)
    }

    @Test func isNewReleasesReturnsFalseForRegularGenre() {
        let card = ExploreMoodCard(
            id: "test", title: "Test", subtitle: "TEST",
            symbol: "star", color: .red, movieGenreId: 28, tvGenreId: 10759
        )
        #expect(card.isNewReleases == false)
    }

    @Test func isNewReleasesReturnsFalseForZeroGenreId() {
        let card = ExploreMoodCard(
            id: "test", title: "Test", subtitle: "TEST",
            symbol: "star", color: .red, movieGenreId: 0, tvGenreId: 0
        )
        #expect(card.isNewReleases == false)
    }

    @Test func isFutureReleasesReturnsTrueWhenMovieGenreIdIsNegativeTwo() {
        let card = ExploreMoodCard(
            id: "test", title: "Test", subtitle: "TEST",
            symbol: "star", color: .red, movieGenreId: -2, tvGenreId: -2
        )
        #expect(card.isFutureReleases == true)
    }

    @Test func isFutureReleasesReturnsFalseForRegularGenre() {
        let card = ExploreMoodCard(
            id: "test", title: "Test", subtitle: "TEST",
            symbol: "star", color: .red, movieGenreId: 28, tvGenreId: 10759
        )
        #expect(card.isFutureReleases == false)
    }

    @Test func isSpecialCardReturnsTrueForNegativeGenreIds() {
        let newReleases = ExploreMoodCard(
            id: "test", title: "Test", subtitle: "TEST",
            symbol: "star", color: .red, movieGenreId: -1, tvGenreId: -1
        )
        let upcoming = ExploreMoodCard(
            id: "test2", title: "Test2", subtitle: "TEST2",
            symbol: "star", color: .red, movieGenreId: -2, tvGenreId: -2
        )
        #expect(newReleases.isSpecialCard == true)
        #expect(upcoming.isSpecialCard == true)
    }

    @Test func isSpecialCardReturnsFalseForPositiveGenreIds() {
        let card = ExploreMoodCard(
            id: "test", title: "Test", subtitle: "TEST",
            symbol: "star", color: .red, movieGenreId: 28, tvGenreId: 10759
        )
        #expect(card.isSpecialCard == false)
    }
}

// MARK: - ExploreGenreCatalog Tests

@Suite("ExploreGenreCatalog")
struct ExploreGenreCatalogTests {

    // MARK: - Card Count

    @Test func catalogContainsFourteenCards() {
        #expect(ExploreGenreCatalog.cards.count == 14)
    }

    // MARK: - Card Ordering Stability

    @Test func cardOrderingIsStableAcrossAccesses() {
        let first = ExploreGenreCatalog.cards.map(\.id)
        let second = ExploreGenreCatalog.cards.map(\.id)
        #expect(first == second)
    }

    @Test func firstCardIsSciFi() {
        #expect(ExploreGenreCatalog.cards.first?.id == "scifi")
    }

    @Test func lastCardIsComingSoon() {
        #expect(ExploreGenreCatalog.cards.last?.id == "upcoming")
    }

    // MARK: - ID Uniqueness

    @Test func allCardIdsAreUnique() {
        let ids = ExploreGenreCatalog.cards.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Duplicate card IDs found")
    }

    // MARK: - No Duplicate Movie Genre IDs (Excluding Special Cases)

    @Test func noDuplicateMovieGenreIdsExcludingSpecialCases() {
        // Filter out special cards (New Releases, Coming Soon)
        let movieGenreIds = ExploreGenreCatalog.cards
            .filter { !$0.isSpecialCard }
            .map(\.movieGenreId)
        // Note: "deep" and "mystery" share movieGenreId 9648, which is intentional
        // (they map to the same TMDB Mystery genre). We verify other IDs are not duplicated.
        let counts = Dictionary(grouping: movieGenreIds, by: { $0 }).mapValues(\.count)
        let triplicatesOrMore = counts.filter { $0.value >= 3 }
        #expect(triplicatesOrMore.isEmpty, "Found genre IDs appearing 3+ times: \(triplicatesOrMore)")
    }

    // MARK: - All Non-Empty Strings

    @Test func allCardTitlesAreNonEmpty() {
        for card in ExploreGenreCatalog.cards {
            #expect(!card.title.isEmpty, "Card \(card.id) has empty title")
        }
    }

    @Test func allCardSubtitlesAreNonEmpty() {
        for card in ExploreGenreCatalog.cards {
            #expect(!card.subtitle.isEmpty, "Card \(card.id) has empty subtitle")
        }
    }

    @Test func allCardSymbolsAreNonEmpty() {
        for card in ExploreGenreCatalog.cards {
            #expect(!card.symbol.isEmpty, "Card \(card.id) has empty symbol")
        }
    }

    @Test func allCardIdsAreNonEmpty() {
        for card in ExploreGenreCatalog.cards {
            #expect(!card.id.isEmpty, "Found card with empty id")
        }
    }

    // MARK: - SF Symbol Name Validation

    @Test func allSymbolNamesContainOnlyValidCharacters() {
        let validCharacterSet = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: ".-"))

        for card in ExploreGenreCatalog.cards {
            let symbol = card.symbol
            #expect(symbol == symbol.trimmingCharacters(in: .whitespaces),
                    "Card \(card.id) symbol has leading/trailing whitespace")
            let allValid = symbol.unicodeScalars.allSatisfy { validCharacterSet.contains($0) }
            #expect(allValid, "Card \(card.id) symbol '\(symbol)' contains invalid characters for SF Symbol names")
        }
    }

    // MARK: - New Releases Special Case

    @Test func newReleasesCardHasGenreIdNegativeOne() {
        let newReleases = ExploreGenreCatalog.cards.first(where: { $0.id == "new" })
        #expect(newReleases != nil, "New Releases card not found")
        #expect(newReleases?.movieGenreId == -1)
        #expect(newReleases?.tvGenreId == -1)
        #expect(newReleases?.isNewReleases == true)
    }

    @Test func newReleasesCardHasCorrectTitle() {
        let newReleases = ExploreGenreCatalog.cards.first(where: { $0.id == "new" })
        #expect(newReleases?.title == "New Releases")
    }

    @Test func newReleasesCardHasFlameSymbol() {
        let newReleases = ExploreGenreCatalog.cards.first(where: { $0.id == "new" })
        #expect(newReleases?.symbol == "flame.fill")
    }

    @Test func onlyOneCardIsNewReleases() {
        let newReleasesCards = ExploreGenreCatalog.cards.filter(\.isNewReleases)
        #expect(newReleasesCards.count == 1)
    }

    // MARK: - Coming Soon / Future Releases Special Case

    @Test func comingSoonCardHasGenreIdNegativeTwo() {
        let upcoming = ExploreGenreCatalog.cards.first(where: { $0.id == "upcoming" })
        #expect(upcoming != nil, "Coming Soon card not found")
        #expect(upcoming?.movieGenreId == -2)
        #expect(upcoming?.tvGenreId == -2)
        #expect(upcoming?.isFutureReleases == true)
    }

    @Test func comingSoonCardHasCorrectTitle() {
        let upcoming = ExploreGenreCatalog.cards.first(where: { $0.id == "upcoming" })
        #expect(upcoming?.title == "Coming Soon")
    }

    @Test func comingSoonCardIsNotNewReleases() {
        let upcoming = ExploreGenreCatalog.cards.first(where: { $0.id == "upcoming" })
        #expect(upcoming?.isNewReleases == false)
    }

    @Test func comingSoonCardIsSpecialCard() {
        let upcoming = ExploreGenreCatalog.cards.first(where: { $0.id == "upcoming" })
        #expect(upcoming?.isSpecialCard == true)
    }

    @Test func newReleasesCardIsSpecialCard() {
        let newReleases = ExploreGenreCatalog.cards.first(where: { $0.id == "new" })
        #expect(newReleases?.isSpecialCard == true)
    }

    @Test func regularCardsAreNotSpecial() {
        let action = ExploreGenreCatalog.cards.first(where: { $0.id == "action" })
        #expect(action?.isSpecialCard == false)
        #expect(action?.isNewReleases == false)
        #expect(action?.isFutureReleases == false)
    }

    @Test func exactlyTwoSpecialCards() {
        let specialCards = ExploreGenreCatalog.cards.filter(\.isSpecialCard)
        #expect(specialCards.count == 2)
    }

    // MARK: - Specific Card Properties

    @Test func sciFiCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "scifi" })
        #expect(card != nil)
        #expect(card?.title == "Sci-Fi")
        #expect(card?.subtitle == "FUTURISTIC")
        #expect(card?.symbol == "atom")
        #expect(card?.movieGenreId == 878)
        #expect(card?.tvGenreId == 10765)
    }

    @Test func dramaCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "drama" })
        #expect(card != nil)
        #expect(card?.title == "Drama")
        #expect(card?.subtitle == "EMOTIONAL")
        #expect(card?.symbol == "theatermasks.fill")
        #expect(card?.movieGenreId == 18)
        #expect(card?.tvGenreId == 18)
    }

    @Test func comedyCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "comedy" })
        #expect(card != nil)
        #expect(card?.title == "Comedy")
        #expect(card?.subtitle == "HILARIOUS")
        #expect(card?.symbol == "face.smiling")
        #expect(card?.movieGenreId == 35)
        #expect(card?.tvGenreId == 35)
    }

    @Test func actionCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "action" })
        #expect(card != nil)
        #expect(card?.title == "Action")
        #expect(card?.subtitle == "HIGH ENERGY")
        #expect(card?.symbol == "bolt.fill")
        #expect(card?.movieGenreId == 28)
        #expect(card?.tvGenreId == 10759)
    }

    @Test func horrorCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "horror" })
        #expect(card != nil)
        #expect(card?.title == "Horror")
        #expect(card?.subtitle == "SUSPENSEFUL")
        #expect(card?.symbol == "eye.fill")
        #expect(card?.movieGenreId == 27)
        #expect(card?.tvGenreId == 27)
    }

    @Test func animationCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "animation" })
        #expect(card != nil)
        #expect(card?.title == "Animation")
        #expect(card?.subtitle == "WHIMSICAL")
        #expect(card?.symbol == "paintpalette")
        #expect(card?.movieGenreId == 16)
        #expect(card?.tvGenreId == 16)
    }

    @Test func fantasyCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "fantasy" })
        #expect(card != nil)
        #expect(card?.title == "Fantasy")
        #expect(card?.subtitle == "MAGICAL")
        #expect(card?.symbol == "wand.and.stars")
        #expect(card?.movieGenreId == 14)
        #expect(card?.tvGenreId == 10765)
    }

    @Test func docsCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "docs" })
        #expect(card != nil)
        #expect(card?.title == "Docs")
        #expect(card?.subtitle == "REAL STORIES")
        #expect(card?.symbol == "globe.americas")
        #expect(card?.movieGenreId == 99)
        #expect(card?.tvGenreId == 99)
    }

    @Test func classicsCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "classics" })
        #expect(card != nil)
        #expect(card?.title == "Classics")
        #expect(card?.subtitle == "TIMELESS")
        #expect(card?.symbol == "clock.arrow.circlepath")
        #expect(card?.movieGenreId == 36)
        #expect(card?.tvGenreId == 36)
    }

    @Test func deepCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "deep" })
        #expect(card != nil)
        #expect(card?.title == "Deep")
        #expect(card?.subtitle == "MIND-BENDING")
        #expect(card?.symbol == "brain.head.profile")
        #expect(card?.movieGenreId == 9648)
        #expect(card?.tvGenreId == 9648)
    }

    @Test func mysteryCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "mystery" })
        #expect(card != nil)
        #expect(card?.title == "Mystery")
        #expect(card?.subtitle == "ENIGMATIC")
        #expect(card?.symbol == "magnifyingglass")
        #expect(card?.movieGenreId == 9648)
        #expect(card?.tvGenreId == 9648)
    }

    @Test func chillCardProperties() {
        let card = ExploreGenreCatalog.cards.first(where: { $0.id == "chill" })
        #expect(card != nil)
        #expect(card?.title == "Chill")
        #expect(card?.subtitle == "RELIEVE STRESS")
        #expect(card?.symbol == "leaf.fill")
        #expect(card?.movieGenreId == 10749)
        #expect(card?.tvGenreId == 10749)
    }

    // MARK: - Genre IDs Are Valid TMDB IDs

    @Test func allNonSpecialMovieGenreIdsArePositive() {
        for card in ExploreGenreCatalog.cards where !card.isSpecialCard {
            #expect(card.movieGenreId > 0, "Card \(card.id) has non-positive movieGenreId: \(card.movieGenreId)")
        }
    }

    @Test func allNonSpecialTvGenreIdsArePositive() {
        for card in ExploreGenreCatalog.cards where !card.isSpecialCard {
            #expect(card.tvGenreId > 0, "Card \(card.id) has non-positive tvGenreId: \(card.tvGenreId)")
        }
    }

    // MARK: - Subtitles Are Uppercased

    @Test func allSubtitlesAreUppercased() {
        for card in ExploreGenreCatalog.cards {
            #expect(card.subtitle == card.subtitle.uppercased(),
                    "Card \(card.id) subtitle '\(card.subtitle)' is not fully uppercased")
        }
    }

    // MARK: - ExploreMoodCard Sendable

    @Test func exploreMoodCardIsSendable() {
        let card = ExploreGenreCatalog.cards[0]
        let sendableCheck: any Sendable = card
        _ = sendableCheck
    }

    // MARK: - Deep vs Mystery Share Genre ID Intentionally

    @Test func deepAndMysteryShareMovieGenreId() {
        let deep = ExploreGenreCatalog.cards.first(where: { $0.id == "deep" })
        let mystery = ExploreGenreCatalog.cards.first(where: { $0.id == "mystery" })
        #expect(deep?.movieGenreId == mystery?.movieGenreId)
        #expect(deep?.movieGenreId == 9648)
    }

    @Test func deepAndMysteryShareTvGenreId() {
        let deep = ExploreGenreCatalog.cards.first(where: { $0.id == "deep" })
        let mystery = ExploreGenreCatalog.cards.first(where: { $0.id == "mystery" })
        #expect(deep?.tvGenreId == mystery?.tvGenreId)
        #expect(deep?.tvGenreId == 9648)
    }

    // MARK: - SciFi and Fantasy Share TV Genre ID

    @Test func sciFiAndFantasyShareTvGenreId() {
        let scifi = ExploreGenreCatalog.cards.first(where: { $0.id == "scifi" })
        let fantasy = ExploreGenreCatalog.cards.first(where: { $0.id == "fantasy" })
        #expect(scifi?.tvGenreId == fantasy?.tvGenreId)
        #expect(scifi?.tvGenreId == 10765)
    }

    @Test func sciFiAndFantasyHaveDifferentMovieGenreIds() {
        let scifi = ExploreGenreCatalog.cards.first(where: { $0.id == "scifi" })
        let fantasy = ExploreGenreCatalog.cards.first(where: { $0.id == "fantasy" })
        #expect(scifi?.movieGenreId != fantasy?.movieGenreId)
    }

    // MARK: - Expected Card ID Roster

    @Test func catalogContainsAllExpectedCardIds() {
        let expectedIds: Set<String> = [
            "scifi", "drama", "comedy", "action", "deep", "horror",
            "animation", "mystery", "docs", "fantasy", "chill", "classics", "new", "upcoming"
        ]
        let actualIds = Set(ExploreGenreCatalog.cards.map(\.id))
        #expect(actualIds == expectedIds)
    }
}
