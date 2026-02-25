import SwiftUI

struct ExploreMoodCard: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let movieGenreId: Int
    let tvGenreId: Int

    var isNewReleases: Bool { movieGenreId == -1 }
    var isFutureReleases: Bool { movieGenreId == -2 }
    var isSpecialCard: Bool { movieGenreId < 0 }
}

enum ExploreGenreCatalog {
    static let cards: [ExploreMoodCard] = [
        ExploreMoodCard(id: "scifi", title: "Sci-Fi", subtitle: "FUTURISTIC", symbol: "atom", color: .cyan, movieGenreId: 878, tvGenreId: 10765),
        ExploreMoodCard(id: "drama", title: "Drama", subtitle: "EMOTIONAL", symbol: "theatermasks.fill", color: .pink, movieGenreId: 18, tvGenreId: 18),
        ExploreMoodCard(id: "comedy", title: "Comedy", subtitle: "HILARIOUS", symbol: "face.smiling", color: .yellow, movieGenreId: 35, tvGenreId: 35),
        ExploreMoodCard(id: "action", title: "Action", subtitle: "HIGH ENERGY", symbol: "bolt.fill", color: .orange, movieGenreId: 28, tvGenreId: 10759),
        ExploreMoodCard(id: "deep", title: "Deep", subtitle: "MIND-BENDING", symbol: "brain.head.profile", color: .purple, movieGenreId: 9648, tvGenreId: 9648),
        ExploreMoodCard(id: "horror", title: "Horror", subtitle: "SUSPENSEFUL", symbol: "eye.fill", color: .red, movieGenreId: 27, tvGenreId: 27),
        ExploreMoodCard(id: "animation", title: "Animation", subtitle: "WHIMSICAL", symbol: "paintpalette", color: .mint, movieGenreId: 16, tvGenreId: 16),
        ExploreMoodCard(id: "mystery", title: "Mystery", subtitle: "ENIGMATIC", symbol: "magnifyingglass", color: .teal, movieGenreId: 9648, tvGenreId: 9648),
        ExploreMoodCard(id: "docs", title: "Docs", subtitle: "REAL STORIES", symbol: "globe.americas", color: .green, movieGenreId: 99, tvGenreId: 99),
        ExploreMoodCard(id: "fantasy", title: "Fantasy", subtitle: "MAGICAL", symbol: "wand.and.stars", color: .indigo, movieGenreId: 14, tvGenreId: 10765),
        ExploreMoodCard(id: "chill", title: "Chill", subtitle: "RELIEVE STRESS", symbol: "leaf.fill", color: .green, movieGenreId: 10749, tvGenreId: 10749),
        ExploreMoodCard(id: "classics", title: "Classics", subtitle: "TIMELESS", symbol: "clock.arrow.circlepath", color: .gray, movieGenreId: 36, tvGenreId: 36),
        ExploreMoodCard(id: "new", title: "New Releases", subtitle: "JUST DROPPED", symbol: "flame.fill", color: .vpRed, movieGenreId: -1, tvGenreId: -1),
        ExploreMoodCard(id: "upcoming", title: "Coming Soon", subtitle: "FUTURE RELEASES", symbol: "calendar.badge.clock", color: .blue, movieGenreId: -2, tvGenreId: -2),
    ]
}
