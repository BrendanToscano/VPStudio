import Foundation
enum AIProviderKind: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case ollama = "ollama"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .ollama: return "Ollama"
        case .gemini: return "Gemini"
        }
    }
}

struct AIMovieRecommendation: Codable, Sendable, Equatable, Identifiable {
    var id: String {
        if let tmdbId { return "\(type.rawValue)-tmdb-\(tmdbId)" }
        return "\(title.lowercased())-\(year ?? 0)-\(type.rawValue)"
    }

    var title: String
    var year: Int?
    var type: MediaType
    var reason: String
    var tmdbId: Int?
    var score: Double?
}

struct AIProviderResponse: Sendable {
    var provider: AIProviderKind
    var content: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
}

struct AICompareResult: Sendable {
    var prompt: String
    var responses: [AIProviderKind: AIProviderResponse]
    var errors: [AIProviderKind: String]
}

extension AIMovieRecommendation {
    func toMediaPreview() -> MediaPreview {
        let id: String
        if let tmdbId {
            id = "\(type.rawValue)-tmdb-\(tmdbId)"
        } else {
            id = "\(title.lowercased().replacingOccurrences(of: " ", with: "-"))-\(year ?? 0)-\(type.rawValue)"
        }
        return MediaPreview(
            id: id,
            type: type,
            title: title,
            year: year,
            posterPath: nil,
            imdbRating: nil,
            tmdbId: tmdbId
        )
    }
}

struct AIPersonalizedAnalysis: Codable, Sendable, Equatable {
    var personalizedDescription: String
    var predictedRating: Double
    var verdict: Verdict
    var reasons: [String]

    enum Verdict: String, Codable, Sendable, Equatable {
        case strongYes = "strong_yes"
        case yes
        case maybe
        case no
        case strongNo = "strong_no"

        var label: String {
            switch self {
            case .strongYes: return "You'd Love This"
            case .yes: return "You'd Enjoy This"
            case .maybe: return "It's a Coin Flip"
            case .no: return "Probably Not For You"
            case .strongNo: return "Skip This One"
            }
        }

        var systemImage: String {
            switch self {
            case .strongYes: return "heart.fill"
            case .yes: return "hand.thumbsup.fill"
            case .maybe: return "hand.raised.fill"
            case .no: return "hand.thumbsdown"
            case .strongNo: return "xmark.circle"
            }
        }

        var tint: String {
            switch self {
            case .strongYes: return "green"
            case .yes: return "green"
            case .maybe: return "yellow"
            case .no: return "orange"
            case .strongNo: return "red"
            }
        }
    }
}
