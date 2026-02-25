import Foundation
import Testing
@testable import VPStudio

@Suite("Notification Contract")
struct NotificationContractTests {
    private static let expectedNames: [Notification.Name] = [
        .libraryDidChange,
        .downloadsDidChange,
        .environmentsDidChange,
        .indexersDidChange,
        .tmdbApiKeyDidChange,
    ]

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<8), full: Array(0..<16)))
    func notificationNamesAreStable(_: Int) {
        #expect(Notification.Name.libraryDidChange.rawValue == "VPStudio.LibraryDidChange")
        #expect(Notification.Name.downloadsDidChange.rawValue == "VPStudio.DownloadsDidChange")
        #expect(Notification.Name.environmentsDidChange.rawValue == "VPStudio.EnvironmentsDidChange")
        #expect(Notification.Name.indexersDidChange.rawValue == "VPStudio.IndexersDidChange")
        #expect(Notification.Name.tmdbApiKeyDidChange.rawValue == "VPStudio.TMDBApiKeyDidChange")
        AssertionHelpers.expectUnique(Self.expectedNames.map(\.rawValue))
    }
}
