import Foundation

enum CuratedEnvironmentProvider: String, Codable, Sendable, CaseIterable {
    case official
    case github
    case polyHaven

    var displayName: String {
        switch self {
        case .official:
            return "Official"
        case .github:
            return "GitHub"
        case .polyHaven:
            return "Poly Haven"
        }
    }
}

struct CuratedEnvironmentPreset: Identifiable, Sendable, Equatable {
    var id: String
    var name: String
    var description: String
    var provider: CuratedEnvironmentProvider
    var downloadURL: URL
    var sourceAttributionURL: String
    var licenseName: String
    var defaultHdriYawOffset: Float?
}
