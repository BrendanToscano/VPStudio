import Foundation
import Testing
@testable import VPStudio

@Suite("Detail Feedback", .serialized)
struct DetailFeedbackTests {
    private func makePreview(id: String = "preview-\(UUID().uuidString)", title: String = "Rating Candidate") -> MediaPreview {
        MediaPreview(
            id: id,
            type: .movie,
            title: title,
            year: 2026,
            posterPath: nil,
            imdbRating: nil,
            tmdbId: nil
        )
    }

    @MainActor private func makeIsolatedAppState() throws -> (AppState, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("feedback-test.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        let appState = AppState(database: database)
        return (appState, tempDir)
    }

    @MainActor
    @Test func submitFeedbackPersistsRatingEventAndUpdatesSummary() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()
        try await appState.settingsManager.setString(
            key: SettingsKeys.feedbackScaleMode,
            value: FeedbackScaleMode.oneToTen.rawValue
        )

        let preview = makePreview()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.setPreviewContext(preview)

        await viewModel.submitFeedback(value: 8)

        let latest = try await appState.database.fetchLatestTasteRating(mediaId: preview.id)
        #expect(latest != nil)
        #expect(latest?.feedbackScale?.canonicalMode == .oneToTen)
        #expect(latest?.feedbackValue == 8)
        #expect(viewModel.currentFeedbackSummary == "8/10")
    }

    @MainActor
    @Test func submitFeedbackShowsActionableMessageWhenIdentifierMissing() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()

        let viewModel = DetailViewModel(appState: appState)
        await viewModel.submitFeedback(value: 10)

        #expect(viewModel.libraryStatusMessage?.contains("missing media identifier") == true)
    }

    @MainActor
    @Test func reloadFeedbackStateConvertsStoredScoreIntoSelectedScale() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()

        let preview = makePreview(title: "Scale Bridge")
        try await appState.database.saveTasteEvent(
            TasteEvent(
                mediaId: preview.id,
                eventType: .rated,
                signalStrength: 0.8,
                feedbackScale: .oneToTen,
                feedbackValue: 8,
                source: .manual,
                metadata: ["title": preview.title]
            )
        )
        try await appState.settingsManager.setString(
            key: SettingsKeys.feedbackScaleMode,
            value: FeedbackScaleMode.oneToHundred.rawValue
        )

        let viewModel = DetailViewModel(appState: appState)
        viewModel.setPreviewContext(preview)

        await viewModel.reloadFeedbackState()

        #expect(viewModel.feedbackScaleMode == .oneToHundred)
        #expect(viewModel.currentFeedbackValue == 78)
        #expect(viewModel.currentFeedbackSummary == "78/100")
    }

    // MARK: - clearFeedback Tests

    @MainActor
    @Test func clearFeedbackRemovesRatingAndNilsCurrentValue() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()
        try await appState.settingsManager.setString(
            key: SettingsKeys.feedbackScaleMode,
            value: FeedbackScaleMode.oneToTen.rawValue
        )

        let preview = makePreview()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.setPreviewContext(preview)

        // Submit a rating first
        await viewModel.submitFeedback(value: 7)
        #expect(viewModel.currentFeedbackValue == 7)
        #expect(viewModel.currentFeedbackSummary == "7/10")

        // Clear it
        await viewModel.clearFeedback()

        #expect(viewModel.currentFeedbackValue == nil)
        #expect(viewModel.currentFeedbackSummary == nil)

        // Verify DB no longer has the rating
        let latest = try await appState.database.fetchLatestTasteRating(mediaId: preview.id)
        #expect(latest == nil)
    }

    @MainActor
    @Test func clearFeedbackShowsStatusMessage() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()
        try await appState.settingsManager.setString(
            key: SettingsKeys.feedbackScaleMode,
            value: FeedbackScaleMode.oneToTen.rawValue
        )

        let preview = makePreview()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.setPreviewContext(preview)

        await viewModel.submitFeedback(value: 5)
        await viewModel.clearFeedback()

        #expect(viewModel.libraryStatusMessage == "Rating cleared.")
    }

    @MainActor
    @Test func clearFeedbackWithNoIdentifierShowsError() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()

        let viewModel = DetailViewModel(appState: appState)
        // Don't set preview context
        await viewModel.clearFeedback()

        #expect(viewModel.libraryStatusMessage?.contains("missing media identifier") == true)
    }

    @MainActor
    @Test func clearFeedbackWhenNoRatingExistsDoesNotError() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()

        let preview = makePreview()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.setPreviewContext(preview)

        // Clear without ever setting a rating
        await viewModel.clearFeedback()

        #expect(viewModel.currentFeedbackValue == nil)
        #expect(viewModel.libraryStatusMessage == "Rating cleared.")
    }

    @MainActor
    @Test func clearThenResubmitPreservesNewRating() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()
        try await appState.settingsManager.setString(
            key: SettingsKeys.feedbackScaleMode,
            value: FeedbackScaleMode.oneToTen.rawValue
        )

        let preview = makePreview()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.setPreviewContext(preview)

        // Rate, clear, re-rate
        await viewModel.submitFeedback(value: 3)
        #expect(viewModel.currentFeedbackValue == 3)

        await viewModel.clearFeedback()
        #expect(viewModel.currentFeedbackValue == nil)

        await viewModel.submitFeedback(value: 9)
        #expect(viewModel.currentFeedbackValue == 9)
        #expect(viewModel.currentFeedbackSummary == "9/10")

        let latest = try await appState.database.fetchLatestTasteRating(mediaId: preview.id)
        #expect(latest?.feedbackValue == 9)
    }

    @MainActor
    @Test func clearFeedbackPostsTasteProfileNotification() async throws {
        let (appState, tempDir) = try makeIsolatedAppState()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await appState.database.migrate()
        try await appState.settingsManager.setString(
            key: SettingsKeys.feedbackScaleMode,
            value: FeedbackScaleMode.oneToTen.rawValue
        )

        let preview = makePreview()
        let viewModel = DetailViewModel(appState: appState)
        viewModel.setPreviewContext(preview)

        await viewModel.submitFeedback(value: 6)

        var notificationReceived = false
        let token = NotificationCenter.default.addObserver(
            forName: .tasteProfileDidChange,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await viewModel.clearFeedback()

        // Allow notification delivery
        try await Task.sleep(for: .milliseconds(50))
        #expect(notificationReceived)
    }
}

// MARK: - Database deleteLatestTasteRating Tests

@Suite("Database - deleteLatestTasteRating", .serialized)
struct DatabaseDeleteLatestTasteRatingTests {

    @MainActor private func makeIsolatedDB() throws -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbPath = tempDir.appendingPathComponent("delete-rating-test.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        return (database, tempDir)
    }

    @MainActor
    @Test func deleteLatestTasteRatingRemovesMostRecentRating() async throws {
        let (db, tempDir) = try makeIsolatedDB()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await db.migrate()

        let mediaId = "tt-delete-\(UUID().uuidString)"
        try await db.saveTasteEvent(
            TasteEvent(
                mediaId: mediaId,
                eventType: .rated,
                signalStrength: 0.7,
                feedbackScale: .oneToTen,
                feedbackValue: 7,
                source: .manual
            )
        )

        // Verify it exists
        let before = try await db.fetchLatestTasteRating(mediaId: mediaId)
        #expect(before != nil)

        // Delete
        try await db.deleteLatestTasteRating(mediaId: mediaId)

        // Verify removed
        let after = try await db.fetchLatestTasteRating(mediaId: mediaId)
        #expect(after == nil)
    }

    @MainActor
    @Test func deleteLatestTasteRatingOnlyDeletesMostRecent() async throws {
        let (db, tempDir) = try makeIsolatedDB()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await db.migrate()

        let mediaId = "tt-multi-\(UUID().uuidString)"

        // Insert two ratings with different timestamps
        try await db.saveTasteEvent(
            TasteEvent(
                mediaId: mediaId,
                eventType: .rated,
                signalStrength: 0.3,
                feedbackScale: .oneToTen,
                feedbackValue: 3,
                source: .manual,
                createdAt: Date().addingTimeInterval(-100)
            )
        )
        try await db.saveTasteEvent(
            TasteEvent(
                mediaId: mediaId,
                eventType: .rated,
                signalStrength: 0.9,
                feedbackScale: .oneToTen,
                feedbackValue: 9,
                source: .manual,
                createdAt: Date()
            )
        )

        // Delete the most recent (9/10)
        try await db.deleteLatestTasteRating(mediaId: mediaId)

        // The older one (3/10) should remain
        let remaining = try await db.fetchLatestTasteRating(mediaId: mediaId)
        #expect(remaining != nil)
        #expect(remaining?.feedbackValue == 3)
    }

    @MainActor
    @Test func deleteLatestTasteRatingDoesNotCrashWhenNoRatingExists() async throws {
        let (db, tempDir) = try makeIsolatedDB()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await db.migrate()

        // Should not throw
        try await db.deleteLatestTasteRating(mediaId: "nonexistent-media")
    }

    @MainActor
    @Test func deleteLatestTasteRatingDoesNotRemoveWatchEvents() async throws {
        let (db, tempDir) = try makeIsolatedDB()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await db.migrate()

        let mediaId = "tt-mixed-\(UUID().uuidString)"

        // Insert a watched event
        try await db.saveTasteEvent(
            TasteEvent(
                mediaId: mediaId,
                eventType: .watched,
                signalStrength: 1.0,
                source: .automatic
            )
        )

        // Insert a rated event
        try await db.saveTasteEvent(
            TasteEvent(
                mediaId: mediaId,
                eventType: .rated,
                signalStrength: 0.8,
                feedbackScale: .oneToTen,
                feedbackValue: 8,
                source: .manual
            )
        )

        // Delete the rating
        try await db.deleteLatestTasteRating(mediaId: mediaId)

        // The rating should be gone
        let rating = try await db.fetchLatestTasteRating(mediaId: mediaId)
        #expect(rating == nil)

        // But the watched event should still exist
        let allEvents = try await db.fetchTasteEvents(eventType: .watched)
        let watchedEvents = allEvents.filter { $0.mediaId == mediaId }
        #expect(watchedEvents.count == 1)
    }
}
