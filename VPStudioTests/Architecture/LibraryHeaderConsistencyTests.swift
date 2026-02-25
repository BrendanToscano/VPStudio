import Foundation
import Testing
@testable import VPStudio

@Suite("Library Header Consistency")
struct LibraryHeaderConsistencyTests {
    @Test func favoritesLabelIsFavorites() {
        #expect(UserLibraryEntry.ListType.favorites.displayName == "Favorites")
    }

    @Test func topTabOrderIsWatchlistFavoritesHistory() {
        #expect(UserLibraryEntry.ListType.libraryTopTabs == [.watchlist, .favorites, .history])
        let titles = UserLibraryEntry.ListType.libraryTopTabs.map(\.displayName)
        #expect(titles == ["Watchlist", "Favorites", "History"])
    }
}
