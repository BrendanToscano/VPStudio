import Foundation

struct Subtitle: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var language: String
    var fileName: String
    var url: String
    var format: SubtitleFormat
    var fileId: Int?
    var rating: Double?
    var downloadCount: Int?
    var isHearingImpaired: Bool?
    var source: String?

    var downloadURL: URL? {
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            return nil
        }
        return parsed
    }

    var displayName: String {
        var name = language.uppercased()
        if let hi = isHearingImpaired, hi { name += " (HI)" }
        return name
    }
}

enum SubtitleFormat: String, Codable, Sendable {
    case srt
    case vtt
    case ass
    case ssa
    case unknown

    static func parse(from filename: String) -> SubtitleFormat {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "srt": return .srt
        case "vtt", "webvtt": return .vtt
        case "ass": return .ass
        case "ssa": return .ssa
        default: return .unknown
        }
    }

    /// File extension used when writing a subtitle to disk.
    var fileExtension: String {
        switch self {
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .ass: return "ass"
        case .ssa: return "ssa"
        case .unknown: return "srt"
        }
    }
}
