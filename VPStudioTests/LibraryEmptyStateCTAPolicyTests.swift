import Testing
@testable import VPStudio

@Suite("Library Empty State CTA Policy")
struct LibraryEmptyStateCTAPolicyTests {
    @Test
    func eachListTypeHasNonEmptyTitle() {
        let types: [LibraryEmptyStateCTAPolicy.ListType] = [.favorites, .watchlist, .history, .downloads]
        for type in types {
            #expect(!LibraryEmptyStateCTAPolicy.title(for: type).isEmpty, "Title for \(type) should not be empty")
        }
    }

    @Test
    func eachListTypeHasNonEmptyDescription() {
        let types: [LibraryEmptyStateCTAPolicy.ListType] = [.favorites, .watchlist, .history, .downloads]
        for type in types {
            #expect(!LibraryEmptyStateCTAPolicy.description(for: type).isEmpty, "Description for \(type) should not be empty")
        }
    }

    @Test
    func eachListTypeHasNonEmptyIcon() {
        let types: [LibraryEmptyStateCTAPolicy.ListType] = [.favorites, .watchlist, .history, .downloads]
        for type in types {
            #expect(!LibraryEmptyStateCTAPolicy.icon(for: type).isEmpty, "Icon for \(type) should not be empty")
        }
    }

    @Test
    func favoritesActionIsSwitchToDiscover() {
        #expect(LibraryEmptyStateCTAPolicy.ctaAction(for: .favorites) == .switchToDiscover)
    }

    @Test
    func watchlistActionIsSwitchToDiscover() {
        #expect(LibraryEmptyStateCTAPolicy.ctaAction(for: .watchlist) == .switchToDiscover)
    }

    @Test
    func downloadsActionIsOpenSettings() {
        #expect(LibraryEmptyStateCTAPolicy.ctaAction(for: .downloads) == .openSettings)
    }
}
