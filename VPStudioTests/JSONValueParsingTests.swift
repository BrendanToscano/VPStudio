import Foundation
import Testing
@testable import VPStudio

@Suite("JSONValueParsing")
struct JSONValueParsingTests {
    // MARK: - parseInt

    @Test
    func parseIntFromInt() {
        let value: Any = 42
        #expect(JSONValueParsing.parseInt(value) == 42)
    }

    @Test
    func parseIntFromString() {
        let value: Any = "123"
        #expect(JSONValueParsing.parseInt(value) == 123)
    }

    @Test
    func parseIntFromDouble() {
        let value: Any = 99.7
        #expect(JSONValueParsing.parseInt(value) == 99)
    }

    @Test
    func parseIntFromNilReturnsNil() {
        #expect(JSONValueParsing.parseInt(nil) == nil)
    }

    // MARK: - parseInt64

    @Test
    func parseInt64FromInt64() {
        let value: Any = Int64(5_000_000_000)
        #expect(JSONValueParsing.parseInt64(value) == 5_000_000_000)
    }

    @Test
    func parseInt64FromString() {
        let value: Any = "9876543210"
        #expect(JSONValueParsing.parseInt64(value) == 9_876_543_210)
    }

    // MARK: - extractInfoHash

    @Test
    func extractInfoHashFromValidMagnetURI() {
        let magnet = "magnet:?xt=urn:btih:ABCDEF1234567890ABCDEF1234567890ABCDEF12&dn=Test"
        let hash = JSONValueParsing.extractInfoHash(from: magnet)
        #expect(hash == "ABCDEF1234567890ABCDEF1234567890ABCDEF12")
    }

    @Test
    func extractInfoHashFromInvalidStringReturnsNil() {
        #expect(JSONValueParsing.extractInfoHash(from: "not a magnet link") == nil)
        #expect(JSONValueParsing.extractInfoHash(from: nil) == nil)
        #expect(JSONValueParsing.extractInfoHash(from: "") == nil)
    }
}
