import Testing
import Foundation
@testable import VPStudio

@Suite("String.containsStandaloneToken")
struct StringMatchingTests {

    // MARK: - Basic Matching

    @Test func matchesDotDelimited() {
        #expect("movie.sbs.1080p".containsStandaloneToken("sbs") == true)
    }

    @Test func doesNotMatchSubstring() {
        #expect("absurdly".containsStandaloneToken("sbs") == false)
    }

    @Test func matchesHyphenDelimited() {
        #expect("movie-sbs-1080p".containsStandaloneToken("sbs") == true)
    }

    @Test func matchesSpaceDelimited() {
        #expect("movie sbs 1080p".containsStandaloneToken("sbs") == true)
    }

    @Test func matchesUnderscoreDelimited() {
        #expect("movie_sbs_1080p".containsStandaloneToken("sbs") == true)
    }

    // MARK: - Position

    @Test func matchesTokenAtStart() {
        #expect("sbs.1080p.movie".containsStandaloneToken("sbs") == true)
    }

    @Test func matchesTokenAtEnd() {
        #expect("movie.1080p.sbs".containsStandaloneToken("sbs") == true)
    }

    @Test func matchesTokenInMiddle() {
        #expect("movie.sbs.1080p".containsStandaloneToken("sbs") == true)
    }

    @Test func matchesTokenAsEntireString() {
        #expect("sbs".containsStandaloneToken("sbs") == true)
    }

    // MARK: - Case Insensitivity

    @Test func caseInsensitiveMatch() {
        #expect("Movie.SBS.1080p".containsStandaloneToken("sbs") == true)
    }

    @Test func caseInsensitiveUpperInput() {
        #expect("movie.sbs.1080p".containsStandaloneToken("SBS") == true)
    }

    @Test func caseInsensitiveMixedCase() {
        #expect("Movie.Sbs.1080p".containsStandaloneToken("sbs") == true)
    }

    // MARK: - No Match

    @Test func doesNotMatchEmbeddedToken() {
        // "sd" should not match inside "hsd" or "sdr"
        #expect("hsd.movie".containsStandaloneToken("sd") == false)
    }

    @Test func doesNotMatchPartialPrefix() {
        #expect("sdr.movie".containsStandaloneToken("sd") == false)
    }

    @Test func emptyStringDoesNotMatch() {
        #expect("".containsStandaloneToken("sbs") == false)
    }

    // MARK: - Special Characters

    @Test func matchesBracketDelimited() {
        #expect("[sbs]movie".containsStandaloneToken("sbs") == true)
    }

    @Test func matchesParenDelimited() {
        #expect("(sbs)movie".containsStandaloneToken("sbs") == true)
    }

    // MARK: - DV Token (used in HDRFormat.parse)

    @Test func dvMatchesStandalone() {
        #expect("Movie.DV.2160p".containsStandaloneToken("dv") == true)
    }

    @Test func dvDoesNotMatchInDVDRip() {
        // "dvdrip" should not match "dv" as standalone
        #expect("Movie.DVDRip.720p".containsStandaloneToken("dv") == false)
    }

    // MARK: - CAM Token (used in SourceType.parse)

    @Test func camMatchesStandalone() {
        #expect("Movie.CAM.2024".containsStandaloneToken("cam") == true)
    }

    @Test func camDoesNotMatchInCamera() {
        #expect("Camera.Man.2024".containsStandaloneToken("cam") == false)
    }

    // MARK: - TS Token (used in SourceType.parse)

    @Test func tsMatchesStandalone() {
        #expect("Movie.TS.2024".containsStandaloneToken("ts") == true)
    }

    @Test func tsDoesNotMatchInTitle() {
        #expect("Monsters.2024".containsStandaloneToken("ts") == false)
    }

    // MARK: - AVC Token (used in VideoCodec.parse)

    @Test func avcMatchesStandalone() {
        #expect("Movie.AVC.1080p".containsStandaloneToken("avc") == true)
    }

    @Test func avcDoesNotMatchInAdvanced() {
        #expect("Advanced.Video.Coding".containsStandaloneToken("avc") == false)
    }
}
