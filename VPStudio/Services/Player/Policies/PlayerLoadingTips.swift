import Foundation
import Observation

/// A single "Did You Know?" tip shown during player loading.
struct PlayerLoadingTip: Identifiable, Sendable, Equatable {
    let id: String
    let text: String
    /// SF Symbol name displayed alongside the tip.
    let icon: String
}

// MARK: - Tip Catalog

enum PlayerLoadingTipCatalog {
    /// The full collection of loading tips. Order is arbitrary; the rotator
    /// shuffles them on each cycle.
    static let allTips: [PlayerLoadingTip] = [
        PlayerLoadingTip(
            id: "dolby-vision",
            text: "VPStudio supports Dolby Vision and HDR10+ content for stunning visual quality.",
            icon: "sparkles.tv"
        ),
        PlayerLoadingTip(
            id: "aspect-ratio",
            text: "You can change the video aspect ratio from the quick actions menu.",
            icon: "rectangle.expand.vertical"
        ),
        PlayerLoadingTip(
            id: "seek-bar",
            text: "Drag the seek bar for precise scrubbing through your content.",
            icon: "slider.horizontal.below.rectangle"
        ),
        PlayerLoadingTip(
            id: "auto-quality",
            text: "VPStudio automatically selects the best stream quality for your connection.",
            icon: "antenna.radiowaves.left.and.right"
        ),
        PlayerLoadingTip(
            id: "watchlist",
            text: "You can add titles to your watchlist from the detail page.",
            icon: "bookmark"
        ),
        PlayerLoadingTip(
            id: "trakt-sync",
            text: "Enable Trakt sync in Settings to track your watch history across devices.",
            icon: "arrow.triangle.2.circlepath"
        ),
        PlayerLoadingTip(
            id: "immersive-cinema",
            text: "Try immersive cinema mode for a theater-like viewing experience.",
            icon: "mountain.2"
        ),
        PlayerLoadingTip(
            id: "imdb-import",
            text: "You can import your IMDb ratings and watchlist from Settings.",
            icon: "square.and.arrow.down"
        ),
        PlayerLoadingTip(
            id: "spatial-video",
            text: "Spatial video content is automatically detected and played in 3D.",
            icon: "cube"
        ),
        PlayerLoadingTip(
            id: "custom-environment",
            text: "You can customize the virtual environment while watching.",
            icon: "globe"
        ),
        PlayerLoadingTip(
            id: "playback-speed",
            text: "Tap the speed button to cycle through playback rates from 0.5x to 2x.",
            icon: "gauge.with.dots.needle.33percent"
        ),
        PlayerLoadingTip(
            id: "subtitles",
            text: "VPStudio can automatically search and download subtitles via OpenSubtitles.",
            icon: "captions.bubble"
        ),
        PlayerLoadingTip(
            id: "chapters",
            text: "Chapter markers appear as tick marks on the progress bar for easy navigation.",
            icon: "bookmark.fill"
        ),
        PlayerLoadingTip(
            id: "resume-playback",
            text: "VPStudio remembers where you left off and resumes automatically.",
            icon: "clock.arrow.circlepath"
        ),
        PlayerLoadingTip(
            id: "multi-audio",
            text: "Switch between audio tracks using the speaker icon in the transport bar.",
            icon: "speaker.wave.3"
        ),
        PlayerLoadingTip(
            id: "engine-fallback",
            text: "VPStudio automatically tries alternate player engines if one cannot handle the stream.",
            icon: "arrow.triangle.swap"
        ),
        PlayerLoadingTip(
            id: "subtitle-size",
            text: "Long-press on subtitles to adjust the font size to your preference.",
            icon: "textformat.size"
        ),
        PlayerLoadingTip(
            id: "stream-quality",
            text: "You can manually switch between available stream qualities during playback.",
            icon: "list.bullet.rectangle"
        ),
    ]
}

// MARK: - Tip Rotator

/// Cycles through loading tips at a configurable interval, ensuring no
/// immediate sequential duplicates.
///
/// Attach as `@State` in the view that shows the loading overlay. The
/// `currentTip` property updates automatically via the Observation framework.
@Observable
final class PlayerLoadingTipRotator: @unchecked Sendable {
    // MARK: - Public State

    private(set) var currentTip: PlayerLoadingTip

    // MARK: - Configuration

    /// Seconds between tip rotations.
    let interval: TimeInterval

    // MARK: - Internal

    private var tips: [PlayerLoadingTip]
    private var currentIndex: Int = 0
    private var rotationTask: Task<Void, Never>?

    // MARK: - Init

    init(
        tips: [PlayerLoadingTip] = PlayerLoadingTipCatalog.allTips,
        interval: TimeInterval = 4.5
    ) {
        precondition(!tips.isEmpty, "PlayerLoadingTipRotator requires at least one tip.")
        let shuffled = tips.shuffled()
        self.interval = interval
        self.tips = shuffled
        self.currentTip = shuffled[0]
    }

    // MARK: - Lifecycle

    /// Begins automatic tip rotation. Safe to call multiple times; subsequent
    /// calls cancel the previous timer.
    @MainActor
    func start() {
        stop()
        rotationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.interval))
                guard !Task.isCancelled else { return }
                self.advance()
            }
        }
    }

    /// Stops automatic rotation and leaves the current tip visible.
    func stop() {
        rotationTask?.cancel()
        rotationTask = nil
    }

    // MARK: - Manual Advance

    /// Advances to the next tip, wrapping around and reshuffling when
    /// the end of the list is reached. Guarantees no immediate repeat.
    @MainActor
    func advance() {
        currentIndex += 1
        if currentIndex >= tips.count {
            let previousTip = currentTip
            tips.shuffle()
            currentIndex = 0
            // If the first tip after reshuffle matches the last shown, swap it.
            if tips.count > 1, tips[0] == previousTip {
                tips.swapAt(0, 1)
            }
        }
        currentTip = tips[currentIndex]
    }
}
