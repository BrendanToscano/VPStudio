import Foundation
import Testing
@testable import VPStudio

@Suite("Media Item Image URL Tests")
struct MediaItemImageURLTests {
    @Test func mediaItemPosterURLConstructsCorrectPath() {
        let item = MediaItem(
            id: "tt1234567",
            type: .movie,
            title: "Test Movie",
            year: 2024,
            posterPath: "/abc123.jpg",
            backdropPath: "/back456.jpg",
            overview: nil,
            genres: [],
            imdbRating: 7.5,
            runtime: 120,
            status: nil,
            tmdbId: 123,
            lastFetched: Date()
        )

        let posterURL = item.posterURL
        #expect(posterURL != nil)
        #expect(posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/abc123.jpg")
    }

    @Test func mediaItemBackdropURLConstructsCorrectPath() {
        let item = MediaItem(
            id: "tt1234567",
            type: .movie,
            title: "Test Movie",
            year: 2024,
            posterPath: "/abc123.jpg",
            backdropPath: "/back456.jpg",
            overview: nil,
            genres: [],
            imdbRating: 7.5,
            runtime: 120,
            status: nil,
            tmdbId: 123,
            lastFetched: Date()
        )

        let backdropURL = item.backdropURL
        #expect(backdropURL != nil)
        #expect(backdropURL?.absoluteString == "https://image.tmdb.org/t/p/original/back456.jpg")
    }

    @Test func mediaItemPosterURLReturnsNilWhenNoPosterPath() {
        let item = MediaItem(
            id: "tt1234567",
            type: .movie,
            title: "Test Movie",
            year: 2024,
            posterPath: nil,
            backdropPath: nil,
            overview: nil,
            genres: [],
            imdbRating: 7.5,
            runtime: 120,
            status: nil,
            tmdbId: 123,
            lastFetched: Date()
        )

        #expect(item.posterURL == nil)
    }

    @Test func mediaPreviewPosterURLConstructsCorrectPath() {
        let preview = MediaPreview(
            id: "tt1234567",
            type: .movie,
            title: "Test Movie",
            year: 2024,
            posterPath: "/xyz789.jpg",
            backdropPath: "/back111.jpg",
            imdbRating: 8.0,
            tmdbId: 456
        )

        let posterURL = preview.posterURL
        #expect(posterURL != nil)
        #expect(posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342/xyz789.jpg")
    }

    @Test func mediaPreviewBackdropURLConstructsCorrectPath() {
        let preview = MediaPreview(
            id: "tt1234567",
            type: .movie,
            title: "Test Movie",
            year: 2024,
            posterPath: "/xyz789.jpg",
            backdropPath: "/back111.jpg",
            imdbRating: 8.0,
            tmdbId: 456
        )

        let backdropURL = preview.backdropURL
        #expect(backdropURL != nil)
        #expect(backdropURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/back111.jpg")
    }

    @Test func mediaPreviewPosterURLReturnsNilWhenNoPosterPath() {
        let preview = MediaPreview(
            id: "tt1234567",
            type: .series,
            title: "Test Show",
            year: 2024,
            posterPath: nil,
            backdropPath: nil,
            imdbRating: nil,
            tmdbId: nil
        )

        #expect(preview.posterURL == nil)
    }

    @Test func mediaPreviewBackdropURLFallsBackToPosterWhenNoBackdrop() {
        let preview = MediaPreview(
            id: "tt1234567",
            type: .movie,
            title: "Test Movie",
            year: 2024,
            posterPath: "/poster.jpg",
            backdropPath: nil,
            imdbRating: nil,
            tmdbId: nil
        )

        // backdropURL in MediaPreview doesn't fall back to poster, it returns nil
        #expect(preview.backdropURL == nil)
    }
}
