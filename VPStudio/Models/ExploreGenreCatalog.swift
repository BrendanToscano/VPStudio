import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ExploreMoodCard: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let artImageName: String?
    let color: Color
    let movieGenreId: Int
    let tvGenreId: Int

    init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        artImageName: String? = nil,
        color: Color,
        movieGenreId: Int,
        tvGenreId: Int
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.artImageName = Self.resolveArtImageName(artImageName)
        self.color = color
        self.movieGenreId = movieGenreId
        self.tvGenreId = tvGenreId
    }

    var hasResolvedArtImage: Bool { artImageName != nil }
    var isNewReleases: Bool { movieGenreId == -1 }
    var isFutureReleases: Bool { movieGenreId == -2 }
    var isSpecialCard: Bool { movieGenreId < 0 }

    private static func resolveArtImageName(_ candidate: String?) -> String? {
        // The asset names are already declared in the asset catalog.
        // Returning them directly avoids false negatives during early/static initialization
        // on visionOS where UIImage/NSImage lookups can resolve nil even though the asset exists.
        candidate
    }
}

enum ExploreGenreCatalog {
    static let cards: [ExploreMoodCard] = [
        ExploreMoodCard(id: "scifi", title: "Sci-Fi", subtitle: "FUTURISTIC", symbol: "rocket.fill", artImageName: "genre-art-scifi", color: .cyan, movieGenreId: 878, tvGenreId: 10765),
        ExploreMoodCard(id: "drama", title: "Drama", subtitle: "EMOTIONAL", symbol: "theatermasks.fill", artImageName: "genre-art-drama", color: .pink, movieGenreId: 18, tvGenreId: 18),
        ExploreMoodCard(id: "comedy", title: "Comedy", subtitle: "HILARIOUS", symbol: "face.smiling.inverse", artImageName: "genre-art-comedy", color: .yellow, movieGenreId: 35, tvGenreId: 35),
        ExploreMoodCard(id: "action", title: "Action", subtitle: "HIGH ENERGY", symbol: "bolt.fill", artImageName: "genre-art-action", color: .orange, movieGenreId: 28, tvGenreId: 10759),
        ExploreMoodCard(id: "deep", title: "Deep", subtitle: "MIND-BENDING", symbol: "brain", artImageName: "genre-art-deep", color: .purple, movieGenreId: 9648, tvGenreId: 9648),
        ExploreMoodCard(id: "horror", title: "Horror", subtitle: "SUSPENSEFUL", symbol: "eye.fill", artImageName: "genre-art-horror", color: .red, movieGenreId: 27, tvGenreId: 27),
        ExploreMoodCard(id: "animation", title: "Animation", subtitle: "WHIMSICAL", symbol: "moon.stars.fill", artImageName: "genre-art-animation", color: .mint, movieGenreId: 16, tvGenreId: 16),
        ExploreMoodCard(id: "mystery", title: "Mystery", subtitle: "ENIGMATIC", symbol: "magnifyingglass", artImageName: "genre-art-mystery", color: .teal, movieGenreId: 9648, tvGenreId: 9648),
        ExploreMoodCard(id: "docs", title: "Docs", subtitle: "REAL STORIES", symbol: "globe.americas.fill", artImageName: "genre-art-docs", color: .green, movieGenreId: 99, tvGenreId: 99),
        ExploreMoodCard(id: "fantasy", title: "Fantasy", subtitle: "MAGICAL", symbol: "wand.and.stars", artImageName: "genre-art-fantasy", color: .indigo, movieGenreId: 14, tvGenreId: 10765),
        ExploreMoodCard(id: "chill", title: "Chill", subtitle: "RELIEVE STRESS", symbol: "leaf.fill", artImageName: "genre-art-chill", color: .green, movieGenreId: 10749, tvGenreId: 10749),
        ExploreMoodCard(id: "classics", title: "Classics", subtitle: "TIMELESS", symbol: "film.circle.fill", artImageName: "genre-art-classics", color: .gray, movieGenreId: 36, tvGenreId: 36),
        ExploreMoodCard(id: "new", title: "New Releases", subtitle: "JUST DROPPED", symbol: "flame.fill", artImageName: "genre-art-new", color: .vpRed, movieGenreId: -1, tvGenreId: -1),
        ExploreMoodCard(id: "upcoming", title: "Coming Soon", subtitle: "FUTURE RELEASES", symbol: "calendar.badge.clock", artImageName: "genre-art-upcoming", color: .blue, movieGenreId: -2, tvGenreId: -2),
    ]
}
