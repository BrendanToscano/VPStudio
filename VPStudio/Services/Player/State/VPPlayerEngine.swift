import CoreGraphics
import Foundation
import Observation

/// Shared playback state and subtitle renderer for the active player session.
///
/// `VPPlayerEngine` is a pure state-container: it tracks time, buffering,
/// tracks, and rendered subtitle text. Actual player control (AVPlayer /
/// KSPlayer) lives in `PlayerView`. The engine is updated from the outside
/// via direct property writes and the dedicated mutation methods below.
@Observable
@MainActor
final class VPPlayerEngine {
    // MARK: - Media Info

    /// Title of the currently playing media. Set by `PlayerView` when a new
    /// session begins. Read by `ImmersivePlayerControlsView` to show in the
    /// floating panel header.
    var currentTitle: String?

    // MARK: - Playback State

    var isPlaying = false
    var isBuffering = true
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0
    var volume: Float = 1.0
    var bufferedPercent: Double = 0

    // MARK: - Track Info

    var audioTracks: [TrackInfo] = []
    var subtitleTracks: [TrackInfo] = []
    var selectedAudioTrack: Int = 0
    var selectedSubtitleTrack: Int = -1

    // MARK: - Subtitle Display

    var currentSubtitleText: String?

    // MARK: - Video Info

    var videoSize: CGSize = .zero
    var fps: Double = 0
    var videoBitrate: Int64 = 0

    // MARK: - Dim Passthrough (visionOS)

    /// Whether the passthrough (real world) should be dimmed during playback.
    /// Persisted via `SettingsKeys.playerDimPassthrough`. Defaults to `true`.
    var isDimEnabled: Bool = true

    // MARK: - 3D / Spatial

    var stereoMode: StereoMode = .mono
    var is3DContent: Bool { stereoMode != .mono }

    // MARK: - Chapters

    var chapters: [ChapterInfo] = []

    // MARK: - Error State

    var error: String?

    // MARK: - Internal Subtitle Storage

    private var externalSubtitles: [Subtitle] = []
    private var parsedSubtitleCues: [Int: [SubtitleParser.SubtitleCue]] = [:]

    // MARK: - Supporting Types

    struct TrackInfo: Identifiable {
        let id: Int
        let name: String
        let language: String?
        let codec: String?
    }

    struct ChapterInfo: Identifiable, Sendable {
        let id: Int
        let title: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    enum StereoMode: String, Sendable {
        case mono
        case sideBySide = "sbs"
        case overUnder = "ou"
        case mvHevc = "mv-hevc"
        case sphere180 = "180"
        case sphere360 = "360"
    }

    // MARK: - Stereo Mode Detection

    /// Infers and sets `stereoMode` from a media title or filename.
    func updateStereoMode(from title: String) {
        stereoMode = SpatialVideoTitleDetector.stereoMode(fromTitle: title)
    }

    // MARK: - Track Selection

    func selectAudioTrack(_ index: Int) {
        selectedAudioTrack = index
    }

    func selectSubtitleTrack(_ index: Int) {
        guard index >= -1, index < subtitleTracks.count else { return }
        selectedSubtitleTrack = index
        if index == -1 {
            currentSubtitleText = nil
        } else {
            updateSubtitleText(at: currentTime)
        }
    }

    // MARK: - Playback Rate

    func setRate(_ rate: Float) {
        playbackRate = rate
    }

    func cycleRate() {
        let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        if let idx = rates.firstIndex(of: playbackRate) {
            setRate(rates[(idx + 1) % rates.count])
        } else {
            setRate(1.0)
        }
    }

    // MARK: - Chapter Navigation

    /// Loads chapter metadata, sorted by start time.
    func loadChapters(_ chapters: [ChapterInfo]) {
        self.chapters = chapters.sorted { $0.startTime < $1.startTime }
    }

    /// Returns the chapter containing the given time, if any.
    func currentChapter(at time: TimeInterval) -> ChapterInfo? {
        chapters.last { $0.startTime <= time }
    }

    /// Returns the start time for the next chapter after the current time,
    /// or `nil` if already in or past the last chapter.
    func nextChapterTime() -> TimeInterval? {
        guard let current = currentChapter(at: currentTime),
              let idx = chapters.firstIndex(where: { $0.id == current.id }),
              chapters.indices.contains(idx + 1) else {
            // If before any chapter, jump to the first one
            if let first = chapters.first, currentTime < first.startTime {
                return first.startTime
            }
            return nil
        }
        return chapters[idx + 1].startTime
    }

    /// Returns the start time for the previous chapter. If more than 3 seconds
    /// into the current chapter, returns the current chapter's start instead.
    func previousChapterTime() -> TimeInterval? {
        guard let current = currentChapter(at: currentTime) else {
            return nil
        }
        // If more than 3s into the current chapter, restart it
        if currentTime - current.startTime > 3 {
            return current.startTime
        }
        // Otherwise go to the previous chapter
        guard let idx = chapters.firstIndex(where: { $0.id == current.id }),
              idx > 0 else {
            return current.startTime
        }
        return chapters[idx - 1].startTime
    }

    // MARK: - External Subtitles

    func loadExternalSubtitles(_ subtitles: [Subtitle]) {
        externalSubtitles = subtitles
        parsedSubtitleCues = [:]
        subtitleTracks = subtitles.enumerated().map { offset, subtitle in
            if let subtitleURL = subtitle.downloadURL,
               subtitleURL.isFileURL,
               let content = try? String(contentsOf: subtitleURL, encoding: .utf8) {
                let cues = SubtitleParser.parse(content: content, format: subtitle.format)
                if !cues.isEmpty {
                    parsedSubtitleCues[offset] = cues
                }
            }

            return TrackInfo(
                id: offset,
                name: subtitle.fileName,
                language: subtitle.language,
                codec: subtitle.format.rawValue
            )
        }

        if subtitleTracks.isEmpty {
            selectedSubtitleTrack = -1
            currentSubtitleText = nil
        } else if selectedSubtitleTrack < 0 || selectedSubtitleTrack >= subtitleTracks.count {
            selectedSubtitleTrack = subtitleTracks[0].id
            updateSubtitleText(at: currentTime)
        }
    }

    func updateSubtitleText(at time: TimeInterval) {
        guard selectedSubtitleTrack >= 0 else {
            currentSubtitleText = nil
            return
        }
        guard let cues = parsedSubtitleCues[selectedSubtitleTrack] else {
            currentSubtitleText = nil
            return
        }
        currentSubtitleText = SubtitleParser.activeCue(at: time, in: cues)?.text
    }

    // MARK: - Computed

    var progressPercent: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var currentTimeFormatted: String { currentTime.formattedDuration }
    var durationFormatted: String { duration.formattedDuration }
    var remainingFormatted: String { max(0, duration - currentTime).formattedDuration }
}
