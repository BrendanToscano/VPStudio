import Foundation
import Testing
@testable import VPStudio

@Suite("Watch Progress Resume Policy")
struct WatchProgressResumePolicyTests {
    @Test func returnsNilWhenNoHistoryExists() {
        #expect(WatchProgressResumePolicy.resumeTime(for: nil) == nil)
    }

    @Test func returnsNilForVeryShortProgress() {
        let history = WatchHistory(
            id: "movie-progress",
            mediaId: "movie",
            episodeId: nil,
            title: "Movie",
            progress: 8,
            duration: 7_200,
            quality: "1080p",
            debridService: "rd",
            streamURL: nil,
            watchedAt: Date(),
            isCompleted: false
        )
        #expect(WatchProgressResumePolicy.resumeTime(for: history) == nil)
    }

    @Test func returnsNilWhenTitleIsEssentiallyCompleted() {
        let history = WatchHistory(
            id: "movie-progress",
            mediaId: "movie",
            episodeId: nil,
            title: "Movie",
            progress: 6_900,
            duration: 7_000,
            quality: "1080p",
            debridService: "rd",
            streamURL: nil,
            watchedAt: Date(),
            isCompleted: true
        )
        #expect(WatchProgressResumePolicy.resumeTime(for: history) == nil)
    }

    @Test func returnsMidPlaybackProgressForResume() {
        let history = WatchHistory(
            id: "episode-progress",
            mediaId: "show",
            episodeId: "s01e03",
            title: "Episode",
            progress: 1_425,
            duration: 3_600,
            quality: "1080p",
            debridService: "rd",
            streamURL: nil,
            watchedAt: Date(),
            isCompleted: false
        )

        let resume = WatchProgressResumePolicy.resumeTime(for: history)
        #expect(resume == 1_425)
    }
}
