import Testing
@testable import VPStudio

@Suite("MediaCardView Poster Loading")
struct MediaCardViewPosterLoadingTests {
    @Test func noPosterURLDoesNotShowLoadingIndicator() {
        let preview = MediaPreview(
            id: "movie-1",
            type: .movie,
            title: "No Poster",
            year: 2024,
            posterPath: nil,
            imdbRating: nil,
            tmdbId: nil
        )

        #expect(MediaCardView.shouldShowPosterLoadingIndicator(for: preview) == false)
    }

    @Test func posterURLShowsLoadingIndicator() {
        let preview = MediaPreview(
            id: "movie-1",
            type: .movie,
            title: "Has Poster",
            year: 2024,
            posterPath: "/poster.jpg",
            imdbRating: nil,
            tmdbId: 1
        )

        #expect(MediaCardView.shouldShowPosterLoadingIndicator(for: preview) == true)
    }

    @Test func fullyAnimatedInteractionKeepsCustomHoverChromeOnVisionOS() {
        #expect(MediaCardView.InteractionMode.fullyAnimated.allowsCustomHoverChrome(onVisionOS: true) == true)
    }

    @Test func systemHoverOnlyDisablesCustomHoverChromeOnVisionOS() {
        #expect(MediaCardView.InteractionMode.systemHoverOnly.allowsCustomHoverChrome(onVisionOS: true) == false)
    }

    @Test func systemHoverOnlyStillAllowsLegacyHoverChromeOffVisionOS() {
        #expect(MediaCardView.InteractionMode.systemHoverOnly.allowsCustomHoverChrome(onVisionOS: false) == true)
    }
}
