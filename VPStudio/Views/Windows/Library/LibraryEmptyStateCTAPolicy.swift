import Foundation

enum LibraryEmptyStateCTAPolicy {
    enum ListType: Equatable, Sendable {
        case favorites
        case watchlist
        case history
        case downloads
    }

    enum CTAAction: Equatable, Sendable {
        case switchToDiscover
        case openSettings
        case none
    }

    static func title(for type: ListType) -> String {
        switch type {
        case .favorites:
            return "No Favorites Yet"
        case .watchlist:
            return "Your Watchlist Is Empty"
        case .history:
            return "No Watch History"
        case .downloads:
            return "No Downloads"
        }
    }

    static func description(for type: ListType) -> String {
        switch type {
        case .favorites:
            return "Mark movies and shows as favorites to keep them here for easy access."
        case .watchlist:
            return "Add titles you want to watch later to your watchlist."
        case .history:
            return "Movies and shows you watch will automatically appear here."
        case .downloads:
            return "Downloaded content for offline viewing will appear here."
        }
    }

    static func ctaLabel(for type: ListType) -> String {
        switch type {
        case .favorites, .watchlist:
            return "Browse Discover"
        case .history:
            return "Start Watching"
        case .downloads:
            return "Go to Settings"
        }
    }

    static func icon(for type: ListType) -> String {
        switch type {
        case .favorites:
            return "heart"
        case .watchlist:
            return "bookmark"
        case .history:
            return "clock"
        case .downloads:
            return "arrow.down.circle"
        }
    }

    static func ctaAction(for type: ListType) -> CTAAction {
        switch type {
        case .favorites, .watchlist:
            return .switchToDiscover
        case .history:
            return .switchToDiscover
        case .downloads:
            return .openSettings
        }
    }
}
