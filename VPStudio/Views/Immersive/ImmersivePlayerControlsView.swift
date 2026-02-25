#if os(visionOS)
import SwiftUI

/// Floating transport controls displayed inside immersive cinema environments.
///
/// This is the ONLY user interface available while in an immersive space. It
/// communicates with `PlayerView` via `NotificationCenter` messages and reads
/// state from the shared `VPPlayerEngine` injected into the SwiftUI environment.
struct ImmersivePlayerControlsView: View {
    @Environment(VPPlayerEngine.self) private var engine

    @State private var isDraggingScrubber = false
    @State private var scrubPercent: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            mediaInfoHeader
                .padding(.bottom, 14)

            scrubBar
                .padding(.bottom, 4)

            timeLabels
                .padding(.bottom, 14)

            transportRow
                .padding(.bottom, 14)

            secondaryControlsRow
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.clear)
                .glassBackgroundEffect()
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: .black.opacity(0.07), radius: 24)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
    }

    // MARK: - Media Info Header

    private var mediaInfoHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title = engine.currentTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            if let chapter = engine.currentChapter(at: engine.currentTime) {
                Text(chapter.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Scrub Bar

    private var scrubBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let displayPercent = isDraggingScrubber ? scrubPercent : engine.progressPercent

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: 4)

                // Buffered indicator
                Capsule()
                    .fill(.white.opacity(0.12))
                    .frame(width: width * engine.bufferedPercent, height: 4)

                // Chapter tick marks
                if !engine.chapters.isEmpty, engine.duration > 0 {
                    ForEach(engine.chapters) { chapter in
                        let x = (chapter.startTime / engine.duration) * width
                        Rectangle()
                            .fill(.white.opacity(0.5))
                            .frame(width: 1.5, height: 8)
                            .position(x: x, y: geo.size.height / 2)
                    }
                }

                // Filled progress
                Capsule()
                    .fill(.white)
                    .frame(width: width * max(0, min(1, displayPercent)), height: 4)

                // Scrub thumb
                Circle()
                    .fill(.white)
                    .frame(width: isDraggingScrubber ? 16 : 10, height: isDraggingScrubber ? 16 : 10)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .position(
                        x: width * max(0, min(1, displayPercent)),
                        y: geo.size.height / 2
                    )
                    .animation(.easeOut(duration: 0.15), value: isDraggingScrubber)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingScrubber = true
                        scrubPercent = max(0, min(1, Double(value.location.x / width)))
                    }
                    .onEnded { _ in
                        isDraggingScrubber = false
                        NotificationCenter.default.post(
                            name: .immersiveControlSeekToPercent,
                            object: NSNumber(value: scrubPercent)
                        )
                    }
            )
        }
        .frame(height: 20)
    }

    // MARK: - Time Labels

    private var timeLabels: some View {
        HStack {
            Text(engine.currentTimeFormatted)
                .font(.caption2)
                .monospacedDigit()
            Spacer()
            Text("-\(engine.remainingFormatted)")
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.55))
    }

    // MARK: - Transport Row

    private var transportRow: some View {
        HStack(spacing: 24) {
            // Previous chapter (conditional)
            if !engine.chapters.isEmpty {
                controlButton(icon: "backward.end.fill", size: .caption) {
                    NotificationCenter.default.post(name: .immersiveControlPreviousChapter, object: nil)
                }
                .accessibilityLabel("Previous chapter")
            }

            // Seek back
            controlButton(icon: "gobackward.10", size: .body) {
                NotificationCenter.default.post(name: .immersiveControlSeekBack, object: nil)
            }
            .accessibilityLabel("Rewind 10 seconds")

            // Play / Pause — prominent center button
            Button {
                NotificationCenter.default.post(name: .immersiveControlTogglePlayPause, object: nil)
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")

            // Seek forward
            controlButton(icon: "goforward.30", size: .body) {
                NotificationCenter.default.post(name: .immersiveControlSeekForward, object: nil)
            }
            .accessibilityLabel("Fast forward 30 seconds")

            // Next chapter (conditional)
            if !engine.chapters.isEmpty {
                controlButton(icon: "forward.end.fill", size: .caption) {
                    NotificationCenter.default.post(name: .immersiveControlNextChapter, object: nil)
                }
                .accessibilityLabel("Next chapter")
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Secondary Controls

    private var secondaryControlsRow: some View {
        HStack(spacing: 20) {
            // Playback speed
            Button {
                NotificationCenter.default.post(name: .immersiveControlCycleRate, object: nil)
            } label: {
                Text(rateLabel)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Playback speed \(rateLabel)")

            Spacer()

            // Subtitles
            controlButton(
                icon: engine.selectedSubtitleTrack >= 0 ? "captions.bubble.fill" : "captions.bubble",
                size: .callout
            ) {
                NotificationCenter.default.post(name: .immersiveControlToggleSubtitles, object: nil)
            }
            .accessibilityLabel("Subtitles")

            // Audio tracks
            controlButton(icon: "speaker.wave.3", size: .callout) {
                NotificationCenter.default.post(name: .immersiveControlToggleAudio, object: nil)
            }
            .accessibilityLabel("Audio track")

            // Screen size
            controlButton(icon: "tv", size: .callout) {
                NotificationCenter.default.post(name: .immersiveControlCycleScreenSize, object: nil)
            }
            .accessibilityLabel("Cycle screen size")

            // Environment switch
            controlButton(icon: "mountain.2", size: .callout) {
                NotificationCenter.default.post(name: .immersiveControlRequestEnvironmentSwitch, object: nil)
            }
            .accessibilityLabel("Change environment")

            Spacer()

            // Exit immersive
            controlButton(icon: "xmark.circle", size: .callout) {
                NotificationCenter.default.post(name: .immersiveControlDismiss, object: nil)
            }
            .accessibilityLabel("Exit immersive space")
        }
    }

    // MARK: - Helpers

    private var rateLabel: String {
        let rate = engine.playbackRate
        if rate == Float(Int(rate)) {
            return "\(Int(rate)).0x"
        }
        return String(format: "%.1fx", rate)
    }

    private func controlButton(
        icon: String,
        size: Font.TextStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size, design: .default))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}
#endif
