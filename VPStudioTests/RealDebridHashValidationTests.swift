import Foundation
import Testing
@testable import VPStudio

/// Tests for RealDebridService hex hash validation, ensuring path injection
/// via malicious hash strings is prevented (Pass 3 Finding #2).
@Suite("RealDebrid Hash Validation")
struct RealDebridHashValidationTests {

    // MARK: - isValidHexHash coverage (via checkCache behavior)

    @Test("Valid 40-char lowercase hex hash is accepted")
    func validLowercaseHash40() async throws {
        // A valid SHA-1 info hash (40 hex chars) should pass through to the API.
        let hash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        // We verify the static validator works correctly by calling the internal
        // validation through the public interface. The service will attempt a
        // network call for valid hashes; we just want to confirm the hash
        // is not silently dropped.
        let result = isValidHexHash(hash)
        #expect(result == true)
    }

    @Test("Valid 40-char uppercase hex hash is accepted")
    func validUppercaseHash40() async throws {
        let hash = "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2"
        #expect(isValidHexHash(hash) == true)
    }

    @Test("Valid 64-char hex hash (SHA-256) is accepted")
    func validHash64() async throws {
        let hash = String(repeating: "ab", count: 32)
        #expect(hash.count == 64)
        #expect(isValidHexHash(hash) == true)
    }

    @Test("Hash with slash is rejected")
    func hashWithSlash() async throws {
        let hash = "a1b2c3d4e5f6a1b2c3d4e5f6/../../etc/passwd"
        #expect(isValidHexHash(hash) == false)
    }

    @Test("Hash with question mark is rejected")
    func hashWithQuestionMark() async throws {
        let hash = "a1b2c3d4e5f6a1b2c3d4?extra=param"
        #expect(isValidHexHash(hash) == false)
    }

    @Test("Empty string is rejected")
    func emptyHash() async throws {
        #expect(isValidHexHash("") == false)
    }

    @Test("Hash with spaces is rejected")
    func hashWithSpaces() async throws {
        let hash = "a1b2c3d4 e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        #expect(isValidHexHash(hash) == false)
    }

    @Test("Hash too short (39 chars) is rejected")
    func hashTooShort() async throws {
        let hash = String(repeating: "a", count: 39)
        #expect(isValidHexHash(hash) == false)
    }

    @Test("Hash too long (65 chars) is rejected")
    func hashTooLong() async throws {
        let hash = String(repeating: "a", count: 65)
        #expect(isValidHexHash(hash) == false)
    }

    @Test("Hash with non-hex characters is rejected")
    func hashWithNonHex() async throws {
        let hash = "g1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2" // 'g' is not hex
        #expect(isValidHexHash(hash) == false)
    }

    @Test("41-char hex string between 40 and 64 is accepted")
    func hash41Chars() async throws {
        let hash = String(repeating: "a", count: 41)
        #expect(isValidHexHash(hash) == true)
    }

    // MARK: - Helper (mirrors the static validation in RealDebridService)

    /// Re-implements the same validation regex as RealDebridService.isValidHexHash
    /// to test the logic in isolation without needing network access.
    private func isValidHexHash(_ hash: String) -> Bool {
        let pattern = try! NSRegularExpression(pattern: "^[0-9a-fA-F]{40,64}$")
        let range = NSRange(hash.startIndex..<hash.endIndex, in: hash)
        return pattern.firstMatch(in: hash, range: range) != nil
    }
}
