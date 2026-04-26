import Testing
@testable import VPStudio

@Suite("Downloads Error Surface Policy")
struct DownloadsErrorSurfacePolicyTests {
    @Test
    func noRootErrorUsesNormalPresentation() {
        #expect(
            DownloadsErrorSurfacePolicy.presentationMode(
                groupCount: 0,
                hasRootError: false
            ) == .none
        )

        #expect(
            DownloadsErrorSurfacePolicy.presentationMode(
                groupCount: 3,
                hasRootError: false
            ) == .none
        )
    }

    @Test
    func emptyDownloadsWithRootErrorShowsRootErrorSurface() {
        #expect(
            DownloadsErrorSurfacePolicy.presentationMode(
                groupCount: 0,
                hasRootError: true
            ) == .rootError
        )
    }

    @Test
    func populatedDownloadsWithRootErrorShowsInlineError() {
        #expect(
            DownloadsErrorSurfacePolicy.presentationMode(
                groupCount: 2,
                hasRootError: true
            ) == .inlineError
        )
    }
}
