import CoreFoundation
import Testing
@testable import VPStudio

@Suite("Library Grid Policy")
struct LibraryGridPolicyTests {
    @Test
    func cardMinWidthMatchesExpected() {
        #expect(Double(LibraryGridPolicy.cardMinWidth) == 180)
    }

    @Test
    func gridSpacingMatchesExpected() {
        #expect(Double(LibraryGridPolicy.gridSpacing) == 16)
    }

    @Test
    func columnCountForNarrowContainer() {
        let columns = LibraryGridPolicy.columns(containerWidth: 300)
        #expect(columns >= 1)
    }

    @Test
    func columnCountForWideContainer() {
        // 1200 - 40 padding + 16 spacing = 1176
        // 1176 / (180 + 16) = 6.0
        let columns = LibraryGridPolicy.columns(containerWidth: 1200)
        #expect(columns == 6)
    }
}
