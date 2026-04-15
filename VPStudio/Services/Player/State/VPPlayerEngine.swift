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
    var subtitlesEnabled: Bool = false

    // MARK: - Subtitle Display

    var currentSubtitleText: String?

    // MARK: - Video Info

    var videoSize: CGSize = .zero
    var fps: Double = 0
    var videoBitrate: Int64 = 0

    // MARK: - HDR Metadata

    /// Mastering-display and content-light-level metadata extracted from the
    /// active video track.  `nil` until the first video track is inspected.
    var hdrMetadata: HDRDisplayMetadata?

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

    /// Infers and sets `stereoMode` from a media title or filename and optional codec hint.
    func updateStereoMode(from title: String, codecHint: String? = nil) {
        stereoMode = SpatialVideoTitleDetector.stereoMode(fromTitle: title, codecHint: codecHint)
    }

    // MARK: - Track Selection

    func selectAudioTrack(_ index: Int) {
        selectedAudioTrack = index
    }

    func loadAudioTracks(_ tracks: [TrackInfo], selectedTrackID: Int? = nil) {
        audioTracks = tracks

        guard let firstTrack = tracks.first else {
            selectedAudioTrack = 0
            return
        }

        if let selectedTrackID, tracks.contains(where: { $0.id == selectedTrackID }) {
            selectedAudioTrack = selectedTrackID
        } else if !tracks.contains(where: { $0.id == selectedAudioTrack }) {
            selectedAudioTrack = firstTrack.id
        }
    }

    func selectSubtitleTrack(_ index: Int) {
        guard index >= -1, index < subtitleTracks.count else { return }
        selectedSubtitleTrack = index
        if index == -1 {
            subtitlesEnabled = false
            currentSubtitleText = nil
        } else {
            subtitlesEnabled = true
            updateSubtitleText(at: currentTime)
        }
    }

    /// Clears session-scoped playback state when a stream ends, is canceled,
    /// or is being replaced by a different stream.
    func resetSessionState() {
        currentTitle = nil
        currentTime = 0
        duration = 0
        bufferedPercent = 0
        isPlaying = false
        isBuffering = true
        audioTracks = []
        subtitleTracks = []
        selectedAudioTrack = 0
        selectedSubtitleTrack = -1
        subtitlesEnabled = false
        currentSubtitleText = nil
        videoSize = .zero
        fps = 0
        videoBitrate = 0
        hdrMetadata = nil
        stereoMode = .mono
        chapters = []
        error = nil
        externalSubtitles = []
        parsedSubtitleCues = [:]
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
        let renderableSubtitles = subtitles.filter { $0.isSupportedSubtitle }
        externalSubtitles = renderableSubtitles
        parsedSubtitleCues = [:]
        subtitleTracks = renderableSubtitles.enumerated().map { offset, subtitle in
            if let subtitleURL = subtitle.downloadURL,
               subtitleURL.isFileURL,
               let cues = loadSubtitleCues(from: subtitleURL, format: subtitle.format),
               !cues.isEmpty {
                parsedSubtitleCues[offset] = cues
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
            subtitlesEnabled = false
            currentSubtitleText = nil
        } else if selectedSubtitleTrack < 0 || selectedSubtitleTrack >= subtitleTracks.count {
            selectedSubtitleTrack = subtitleTracks[0].id
            subtitlesEnabled = true
            updateSubtitleText(at: currentTime)
        } else {
            subtitlesEnabled = true
            updateSubtitleText(at: currentTime)
        }
    }

    private func loadSubtitleCues(from subtitleURL: URL, format: SubtitleFormat) -> [SubtitleParser.SubtitleCue]? {
        guard let data = try? Data(contentsOf: subtitleURL) else {
            return nil
        }

        // Try the encodings we actually see in subtitle files before giving up.
        let candidateEncodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1252,
            .isoLatin1,
        ]

        for encoding in candidateEncodings {
            guard let content = String(data: data, encoding: encoding) else {
                continue
            }

            let cues = SubtitleParser.parse(content: content, format: format)
            if !cues.isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cues
            }
        }

        return nil
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
