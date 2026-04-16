import Foundation

// MARK: - Standalone token matching

extension String {
    /// Returns `true` if `token` appears in the receiver as a word-boundary-delimited token.
    ///
    /// A token is "standalone" when it is not immediately preceded or followed by another
    /// alphanumeric character (case-insensitive). For example, `"sbs"` matches `"movie.sbs.1080p"`
    /// but not `"absurdly"`.
    ///
    /// - Parameter token: The token to search for (must already be lowercased if case-insensitivity
    ///   is required, since the receiver is searched case-insensitively regardless).
    func containsStandaloneToken(_ token: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        let pattern = "(^|[^a-z0-9])\(escaped)([^a-z0-9]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}
