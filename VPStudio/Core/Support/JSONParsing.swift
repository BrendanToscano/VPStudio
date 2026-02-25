import Foundation

/// Shared JSON value-extraction helpers used by indexer parsers that process
/// untyped `JSONSerialization` payloads (Stremio, Torznab/Prowlarr, etc.).
enum JSONValueParsing {
    /// Coerce a loosely-typed JSON value to `Int`.
    /// Handles `Int`, `Int64`, `Double`, and numeric `String` representations.
    static func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let int64Value = value as? Int64 { return Int(int64Value) }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    /// Coerce a loosely-typed JSON value to `Int64`.
    /// Handles `Int64`, `Int`, `Double`, and numeric `String` representations.
    static func parseInt64(_ value: Any?) -> Int64? {
        if let intValue = value as? Int64 { return intValue }
        if let intValue = value as? Int { return Int64(intValue) }
        if let doubleValue = value as? Double { return Int64(doubleValue) }
        if let stringValue = value as? String { return Int64(stringValue) }
        return nil
    }

    /// Extract a BitTorrent info-hash from a magnet URI.
    /// Returns `nil` if the URI is not a valid magnet link or lacks the `xt` parameter.
    static func extractInfoHash(from magnetURI: String?) -> String? {
        guard let magnetURI,
              let components = URLComponents(string: magnetURI),
              let xt = components.queryItems?.first(where: { $0.name.lowercased() == "xt" })?.value else {
            return nil
        }

        let prefix = "urn:btih:"
        guard xt.lowercased().hasPrefix(prefix) else { return nil }
        return String(xt.dropFirst(prefix.count))
    }
}
