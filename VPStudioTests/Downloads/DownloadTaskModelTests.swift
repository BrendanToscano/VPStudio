import Foundation
import Testing
@testable import VPStudio

@Suite struct DownloadTaskModelTests {
    // MARK: - displayTitle

    @Test func displayTitleShowsEpisodeLabelWithTitle() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Breaking Bad", seasonNumber: 5, episodeNumber: 14, episodeTitle: "Ozymandias"
        )
        #expect(task.displayTitle == "S05E14 - Ozymandias")
    }

    @Test func displayTitleShowsEpisodeLabelWithoutTitle() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Breaking Bad", seasonNumber: 2, episodeNumber: 3
        )
        #expect(task.displayTitle == "S02E03")
    }

    @Test func displayTitleShowsEpisodeLabelWithEmptyTitle() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Breaking Bad", seasonNumber: 1, episodeNumber: 1, episodeTitle: ""
        )
        #expect(task.displayTitle == "S01E01")
    }

    @Test func displayTitleFallsBackToMediaTitle() {
        let task = DownloadTask(
            mediaId: "tt200", streamURL: "https://example.com/video.mkv", fileName: "inception.mkv",
            mediaTitle: "Inception"
        )
        #expect(task.displayTitle == "Inception")
    }

    @Test func displayTitleFallsBackToFileName() {
        let task = DownloadTask(
            mediaId: "tt200", streamURL: "https://example.com/video.mkv", fileName: "inception.mkv"
        )
        #expect(task.displayTitle == "inception.mkv")
    }

    @Test func displayTitleFallsBackToFileNameWhenMediaTitleEmpty() {
        let task = DownloadTask(
            mediaId: "tt200", streamURL: "https://example.com/video.mkv", fileName: "inception.mkv",
            mediaTitle: ""
        )
        #expect(task.displayTitle == "inception.mkv")
    }

    @Test func displayTitleWithOnlySeasonNumber() {
        // Only seasonNumber set, episodeNumber nil -- should fall back to mediaTitle
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Show", seasonNumber: 3
        )
        #expect(task.displayTitle == "Show")
    }

    @Test func displayTitleWithOnlyEpisodeNumber() {
        // Only episodeNumber set, seasonNumber nil -- should fall back to mediaTitle
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Show", episodeNumber: 5
        )
        #expect(task.displayTitle == "Show")
    }

    // MARK: - posterURL

    @Test func posterURLConstructsValidURL() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            posterPath: "/abc123.jpg"
        )
        #expect(task.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342/abc123.jpg")
    }

    @Test func posterURLIsNilWhenPathNil() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.posterURL == nil)
    }

    // MARK: - episodeSortKey

    @Test func episodeSortKeyForEpisode() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            seasonNumber: 2, episodeNumber: 5
        )
        #expect(task.episodeSortKey == 20005)
    }

    @Test func episodeSortKeyForMovie() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.episodeSortKey == 0)
    }

    @Test func episodeSortKeyOrdering() {
        let s1e1 = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "e1.mkv",
            seasonNumber: 1, episodeNumber: 1
        )
        let s1e10 = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "e10.mkv",
            seasonNumber: 1, episodeNumber: 10
        )
        let s2e1 = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "e1s2.mkv",
            seasonNumber: 2, episodeNumber: 1
        )
        #expect(s1e1.episodeSortKey < s1e10.episodeSortKey)
        #expect(s1e10.episodeSortKey < s2e1.episodeSortKey)
    }

    // MARK: - destinationURL

    @Test func destinationURLFromPath() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            destinationPath: "/tmp/video.mkv"
        )
        #expect(task.destinationURL?.path == "/tmp/video.mkv")
    }

    @Test func destinationURLNilWhenNoPath() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.destinationURL == nil)
    }

    // MARK: - Default values

    @Test func defaultMediaTitle() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.mediaTitle == "")
    }

    @Test func defaultMediaType() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.mediaType == "movie")
    }

    @Test func defaultStatus() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.status == .queued)
    }

    @Test func defaultProgress() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.progress == 0)
    }

    @Test func defaultBytesWritten() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.bytesWritten == 0)
    }

    @Test func defaultOptionalFieldsAreNil() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.episodeId == nil)
        #expect(task.totalBytes == nil)
        #expect(task.destinationPath == nil)
        #expect(task.errorMessage == nil)
        #expect(task.posterPath == nil)
        #expect(task.seasonNumber == nil)
        #expect(task.episodeNumber == nil)
        #expect(task.episodeTitle == nil)
    }

    // MARK: - DownloadStatus.isTerminal

    @Test func statusIsTerminal() {
        #expect(DownloadStatus.completed.isTerminal == true)
        #expect(DownloadStatus.failed.isTerminal == true)
        #expect(DownloadStatus.cancelled.isTerminal == true)
        #expect(DownloadStatus.queued.isTerminal == false)
        #expect(DownloadStatus.resolving.isTerminal == false)
        #expect(DownloadStatus.downloading.isTerminal == false)
    }

    @Test func allStatusCasesAccountedForTerminal() {
        let terminalStatuses: Set<DownloadStatus> = [.completed, .failed, .cancelled]
        let nonTerminalStatuses: Set<DownloadStatus> = [.queued, .resolving, .downloading]
        let allCases = Set(DownloadStatus.allCases)
        #expect(terminalStatuses.union(nonTerminalStatuses) == allCases)
    }

    // MARK: - DownloadStatus raw values

    @Test func statusRawValues() {
        #expect(DownloadStatus.queued.rawValue == "queued")
        #expect(DownloadStatus.resolving.rawValue == "resolving")
        #expect(DownloadStatus.downloading.rawValue == "downloading")
        #expect(DownloadStatus.completed.rawValue == "completed")
        #expect(DownloadStatus.failed.rawValue == "failed")
        #expect(DownloadStatus.cancelled.rawValue == "cancelled")
    }

    // MARK: - Equatable

    @Test func equalityByAllFields() {
        let a = DownloadTask(
            id: "same-id", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Test", mediaType: "movie", posterPath: "/test.jpg"
        )
        let b = DownloadTask(
            id: "same-id", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Test", mediaType: "movie", posterPath: "/test.jpg"
        )
        #expect(a == b)
    }

    @Test func inequalityOnDifferentId() {
        let a = DownloadTask(
            id: "id-a", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        let b = DownloadTask(
            id: "id-b", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(a != b)
    }

    @Test func inequalityOnDifferentStatus() {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 1000)
        let a = DownloadTask(
            id: "same-id", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            status: .queued, createdAt: fixedDate, updatedAt: fixedDate
        )
        let b = DownloadTask(
            id: "same-id", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            status: .completed, createdAt: fixedDate, updatedAt: fixedDate
        )
        #expect(a != b)
    }

    @Test func inequalityOnDifferentProgress() {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 1000)
        let a = DownloadTask(
            id: "same-id", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            progress: 0.0, createdAt: fixedDate, updatedAt: fixedDate
        )
        let b = DownloadTask(
            id: "same-id", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            progress: 0.5, createdAt: fixedDate, updatedAt: fixedDate
        )
        #expect(a != b)
    }

    // MARK: - Zero-padded episode labels

    @Test func displayTitlePadsSingleDigitSeasonAndEpisode() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Show", seasonNumber: 1, episodeNumber: 2, episodeTitle: "Pilot"
        )
        #expect(task.displayTitle.hasPrefix("S01E02"))
    }

    @Test func displayTitleHandlesLargeNumbers() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Show", seasonNumber: 12, episodeNumber: 100, episodeTitle: "Finale"
        )
        #expect(task.displayTitle == "S12E100 - Finale")
    }

    // MARK: - Identifiable

    @Test func identifiableUsesId() {
        let task = DownloadTask(
            id: "unique-id-123", mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(task.id == "unique-id-123")
    }

    @Test func autoGeneratedIdIsUUID() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        #expect(!task.id.isEmpty)
        #expect(UUID(uuidString: task.id) != nil)
    }

    // MARK: - databaseTableName

    @Test func databaseTableNameIsCorrect() {
        #expect(DownloadTask.databaseTableName == "download_tasks")
    }

    // MARK: - episodeSortKey edge cases

    @Test func episodeSortKeyWithOnlySeason() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            seasonNumber: 3
        )
        // (3 * 10000) + 0 = 30000
        #expect(task.episodeSortKey == 30000)
    }

    @Test func episodeSortKeyWithOnlyEpisode() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            episodeNumber: 7
        )
        // (0 * 10000) + 7 = 7
        #expect(task.episodeSortKey == 7)
    }

    @Test func episodeSortKeyManyEpisodesWithinSeason() {
        // Verify that sort keys within the same season are contiguous and ordered
        let keys = (1...20).map { ep in
            DownloadTask(
                mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "e\(ep).mkv",
                seasonNumber: 1, episodeNumber: ep
            ).episodeSortKey
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == 20) // all unique
    }

    // MARK: - posterURL edge cases

    @Test func posterURLWithPathMissingLeadingSlash() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            posterPath: "abc123.jpg"
        )
        // Should still construct a URL (even if path has no leading slash)
        #expect(task.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342abc123.jpg")
    }

    @Test func posterURLWithEmptyPath() {
        // posterPath is non-nil but empty string
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            posterPath: ""
        )
        #expect(task.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342")
    }

    // MARK: - destinationURL edge cases

    @Test func destinationURLWithSpacesInPath() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            destinationPath: "/tmp/my downloads/video file.mkv"
        )
        #expect(task.destinationURL != nil)
        #expect(task.destinationURL?.lastPathComponent == "video file.mkv")
    }

    // MARK: - Field storage

    @Test func allFieldsStoredCorrectly() {
        let created = Date(timeIntervalSinceReferenceDate: 1000)
        let updated = Date(timeIntervalSinceReferenceDate: 2000)

        let task = DownloadTask(
            id: "test-id",
            mediaId: "tt999",
            episodeId: "ep-42",
            streamURL: "https://example.com/stream.mkv",
            fileName: "stream.mkv",
            status: .downloading,
            progress: 0.75,
            bytesWritten: 768_000,
            totalBytes: 1_024_000,
            destinationPath: "/downloads/stream.mkv",
            errorMessage: nil,
            mediaTitle: "Test Movie",
            mediaType: "series",
            posterPath: "/poster.jpg",
            seasonNumber: 3,
            episodeNumber: 7,
            episodeTitle: "The One",
            createdAt: created,
            updatedAt: updated
        )

        #expect(task.id == "test-id")
        #expect(task.mediaId == "tt999")
        #expect(task.episodeId == "ep-42")
        #expect(task.streamURL == "https://example.com/stream.mkv")
        #expect(task.fileName == "stream.mkv")
        #expect(task.status == .downloading)
        #expect(task.progress == 0.75)
        #expect(task.bytesWritten == 768_000)
        #expect(task.totalBytes == 1_024_000)
        #expect(task.destinationPath == "/downloads/stream.mkv")
        #expect(task.errorMessage == nil)
        #expect(task.mediaTitle == "Test Movie")
        #expect(task.mediaType == "series")
        #expect(task.posterPath == "/poster.jpg")
        #expect(task.seasonNumber == 3)
        #expect(task.episodeNumber == 7)
        #expect(task.episodeTitle == "The One")
        #expect(task.createdAt == created)
        #expect(task.updatedAt == updated)
    }

    // MARK: - Codable round-trip

    @Test func codableRoundTrip() throws {
        let original = DownloadTask(
            id: "round-trip-id",
            mediaId: "tt500",
            episodeId: "ep-10",
            streamURL: "https://example.com/video.mkv",
            fileName: "video.mkv",
            status: .completed,
            progress: 1.0,
            bytesWritten: 2048,
            totalBytes: 2048,
            destinationPath: "/downloads/video.mkv",
            errorMessage: nil,
            mediaTitle: "Encoded Movie",
            mediaType: "movie",
            posterPath: "/encoded.jpg",
            seasonNumber: nil,
            episodeNumber: nil,
            episodeTitle: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 5000),
            updatedAt: Date(timeIntervalSinceReferenceDate: 6000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DownloadTask.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.mediaId == original.mediaId)
        #expect(decoded.episodeId == original.episodeId)
        #expect(decoded.streamURL == original.streamURL)
        #expect(decoded.fileName == original.fileName)
        #expect(decoded.status == original.status)
        #expect(decoded.progress == original.progress)
        #expect(decoded.bytesWritten == original.bytesWritten)
        #expect(decoded.totalBytes == original.totalBytes)
        #expect(decoded.destinationPath == original.destinationPath)
        #expect(decoded.errorMessage == original.errorMessage)
        #expect(decoded.mediaTitle == original.mediaTitle)
        #expect(decoded.mediaType == original.mediaType)
        #expect(decoded.posterPath == original.posterPath)
        #expect(decoded.seasonNumber == original.seasonNumber)
        #expect(decoded.episodeNumber == original.episodeNumber)
        #expect(decoded.episodeTitle == original.episodeTitle)
    }

    @Test func codableRoundTripWithEpisodeFields() throws {
        let original = DownloadTask(
            id: "ep-round-trip",
            mediaId: "tt600",
            streamURL: "https://example.com/episode.mkv",
            fileName: "episode.mkv",
            status: .downloading,
            progress: 0.5,
            mediaTitle: "Series Name",
            mediaType: "series",
            seasonNumber: 4,
            episodeNumber: 12,
            episodeTitle: "Mid-Season"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DownloadTask.self, from: data)

        #expect(decoded.seasonNumber == 4)
        #expect(decoded.episodeNumber == 12)
        #expect(decoded.episodeTitle == "Mid-Season")
        #expect(decoded.displayTitle == "S04E12 - Mid-Season")
    }

    // MARK: - DownloadStatus Codable

    @Test func downloadStatusCodableRoundTrip() throws {
        for status in DownloadStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(DownloadStatus.self, from: data)
            #expect(decoded == status)
        }
    }

    // MARK: - Sendable conformance (compile-time check)

    @Test func sendableConformance() async {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv"
        )
        // If DownloadTask were not Sendable, passing it across actor boundaries would not compile
        let result: DownloadTask = await Task.detached {
            return task
        }.value
        #expect(result.id == task.id)
    }

    // MARK: - displayTitle with various episode title edge cases

    @Test func displayTitleWithWhitespaceOnlyEpisodeTitle() {
        // Whitespace-only episode title: depends on implementation (isEmpty check on whitespace)
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Show", seasonNumber: 1, episodeNumber: 1, episodeTitle: "   "
        )
        // "   ".isEmpty is false, so it should include the whitespace title
        #expect(task.displayTitle == "S01E01 -    ")
    }

    @Test func displayTitleWithSeasonZeroEpisodeZero() {
        let task = DownloadTask(
            mediaId: "tt100", streamURL: "https://example.com/video.mkv", fileName: "video.mkv",
            mediaTitle: "Show", seasonNumber: 0, episodeNumber: 0
        )
        // Both are non-nil so episode label branch is taken
        #expect(task.displayTitle == "S00E00")
    }
}
