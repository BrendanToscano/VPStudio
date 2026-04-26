import Foundation

/// Defines the available sort options for media items within a library folder.
enum LibrarySortOption: String, CaseIterable, Hashable, Sendable {
    case dateAddedDesc
    case dateAddedAsc
    case titleAsc
    case titleDesc
    case yearDesc
    case yearAsc

    var displayName: String {
        switch self {
        case .dateAddedDesc: return "Recently Added"
        case .dateAddedAsc: return "Oldest Added"
        case .titleAsc: return "Title A\u{2013}Z"
        case .titleDesc: return "Title Z\u{2013}A"
        case .yearDesc: return "Newest Release"
        case .yearAsc: return "Oldest Release"
        }
    }

    var symbolName: String {
        switch self {
        case .dateAddedDesc: return "clock.arrow.circlepath"
        case .dateAddedAsc: return "clock"
        case .titleAsc: return "textformat.abc"
        case .titleDesc: return "textformat.abc"
        case .yearDesc: return "calendar"
        case .yearAsc: return "calendar"
        }
    }
}
