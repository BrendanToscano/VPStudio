import Testing
import Foundation
@testable import VPStudio

@Suite("SimklSyncService")
struct SimklSyncServiceTests {

    @Test func throwsNotConnectedWhenTokenIsNil() async {
        let service = SimklSyncService(clientId: "test-client-id")
        // Token is nil by default
        do {
            let _ = try await service.getWatchlist()
            Issue.record("Expected SimklError.notConnected")
        } catch let error as SimklError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func throwsNotConnectedWhenTokenIsEmpty() async {
        let service = SimklSyncService(clientId: "test-client-id")
        await service.setAccessToken("")
        do {
            let _ = try await service.getWatchlist()
            Issue.record("Expected SimklError.notConnected")
        } catch let error as SimklError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func addToListThrowsNotConnectedWhenNoToken() async {
        let service = SimklSyncService(clientId: "test-client-id")
        do {
            try await service.addToList(imdbId: "tt1234567", type: .movie)
            Issue.record("Expected SimklError.notConnected")
        } catch let error as SimklError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func markWatchedThrowsNotConnectedWhenNoToken() async {
        let service = SimklSyncService(clientId: "test-client-id")
        do {
            try await service.markWatched(imdbId: "tt1234567", type: .movie)
            Issue.record("Expected SimklError.notConnected")
        } catch let error as SimklError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected SimklError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}
