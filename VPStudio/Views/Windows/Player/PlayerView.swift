import Foundation
import SwiftUI
import AVKit
import MediaAccessibility
@preconcurrency import KSPlayer
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum PlayerTransportControlsPolicy {
    enum EnvironmentControlPlacement {
        case leftNavigation
        case rightTransportControls
    }

    static func showsRightTransportEnvironmentControl(
        placement: EnvironmentControlPlacement = .leftNavigation
    ) -> Bool {
        placement == .rightTransportControls
    }
}

enum PlayerLifecyclePolicy {
    static var closesDedicatedPlayerWindowOnBack: Bool {
        #if os(macOS) || os(visionOS)
        true
        #else
        false
        #endif
    }

    static var dismissesCurrentPresentationOnBack: Bool {
        true
    }
}

struct PlayerView: View {
    let stream: StreamInfo
    let availableStreams: [StreamInfo]
    let mediaTitle: String?
    let mediaId: String?
    let episodeId: String?
    let sessionID: UUID?

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    #if os(macOS) || os(visionOS)
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var currentStream: StreamInfo
    @State private var streamQueue: [StreamInfo]

    @State private var playbackState: PlayerPlaybackState = .preparing
    @State private var playbackMessage: String?
    @State private var playbackError: String?
    @State private var activeEngine: PlayerEngineKind?

    @State private var avPlayer: AVPlayer?
    @State private var ksPlayerCoordinator: KSVideoPlayer.Coordinator?
    @State private var ksOptions: KSOptions?

    @Environment(VPPlayerEngine.self) private var engine
    @State private var isShowingControls = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var initialPlayerStateTask: Task<Void, Never>?
    @State private var preparePlaybackTask: Task<Void, Never>?
    @State private var activePreparePlaybackID: UUID?
    @State private var subtitleCatalogTask: Task<Void, Never>?
    @State private var subtitleDownloadTask: Task<Void, Never>?
    @State private var environmentAssetsTask: Task<Void, Never>?
    @State private var scenePhaseTask: Task<Void, Never>?
    @State private var memoryPressureTask: Task<Void, Never>?
    @State private var audioTrackRefreshTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var hasPlayedOnce = false
    @State private var isShowingSubtitlePicker = false
    @State private var isShowingAudioPicker = false
    #if os(visionOS)
    @State private var isShowingEnvironmentPicker = false
    #endif
    @State private var timeObserverToken: Any?
    @State private var timeObserverPlayer: AVPlayer?
    @State private var subtitleFontSize: Double = 24
    @State private var downloadedSubtitleFileURL: URL?
    @State private var capabilityWarnings: [String] = []
    @State private var environmentAssets: [EnvironmentAsset] = []
    @State private var progressPersistTask: Task<Void, Never>?
    @State private var scrobbleTask: Task<Void, Never>?
    @State private var subtitleService: OpenSubtitlesService?
    @State private var subtitleServiceAPIKey: String?
    @State private var subtitleCandidates: [Subtitle] = []
    @State private var subtitleCatalogMessage: String?
    @State private var isRefreshingSubtitleCatalog = false
    @State private var isDownloadingSubtitle = false
    @State private var didInitiateClose = false
    @State private var avAudioOptions: [AVTrackOption] = []
    @State private var avSubtitleOptions: [AVTrackOption] = []
    @State private var avAudioGroup: AVMediaSelectionGroup?
    @State private var avSubtitleGroup: AVMediaSelectionGroup?
    @State private var selectedAVAudioID: String?
    @State private var selectedAVSubtitleID: String?
    @State private var subtitleSelectionMode: SubtitleSelectionMode = .automaticPreferred

    #if os(visionOS)
    @State private var apmpInjector = APMPInjector()
    @State private var isAPMPActive = false
    @State private var playerWindowScene: UIWindowScene?
    @State private var visionGeometryTask: Task<Void, Never>?
    #endif

    // MARK: - Aspect Ratio
    @State private var aspectRatioSelection: AspectRatioSelection = .auto
    @State private var detectedVideoRatio: CGFloat?

    #if os(macOS)
    @State private var playerWindow: NSWindow?
    @State private var isFullscreen = false
    @State private var didApplyStoredFullscreen = false
    #endif

    private let avPlayerEngine = AVPlayerEngine()
    private let ksPlayerEngine = KSPlayerEngine()
    private let playerEngineSelector = PlayerEngineSelector()

    private struct AVTrackOption: Identifiable {
        let id: String
        let name: String
        let language: String?
        let option: AVMediaSelectionOption
    }

    private enum SubtitleSelectionMode: Equatable {
        case automaticPreferred
        case manual
    }

    private var availableAudioTrackCount: Int {
        max(avAudioOptions.count, engine.audioTracks.count)
    }

    private var subtitlePresentationIsActive: Bool {
        engine.subtitlesEnabled
    }

    private var motionAnimationsEnabled: Bool {
        Self.shouldAnimateForAccessibility(reduceMotion: accessibilityReduceMotion)
    }

    init(
        stream: StreamInfo,
        availableStreams: [StreamInfo] = [],
        mediaTitle: String? = nil,
        mediaId: String? = nil,
        episodeId: String? = nil,
        sessionID: UUID? = nil
    ) {
        self.stream = stream
        self.availableStreams = availableStreams
        self.mediaTitle = mediaTitle
        self.mediaId = mediaId
        self.episodeId = episodeId
        self.sessionID = sessionID

        let queue = PlayerSessionRouting.sessionStreams(primary: stream, available: availableStreams)
        _currentStream = State(initialValue: stream)
        _streamQueue = State(initialValue: queue)
    }

    var body: some View {
        playerCore
        #if os(visionOS)
        .modifier(ImmersiveControlHandlers(
            onToggleControls: { toggleControlsVisibility() },
            onTogglePlayPause: { togglePlayPause() },
            onSeekBack: { seekRelative(-10) },
            onSeekForward: { seekRelative(30) },
            onSeekToPercent: { seekTo(percent: $0) },
            onPreviousChapter: { if let time = engine.previousChapterTime() { seek(to: time) } },
            onNextChapter: { if let time = engine.nextChapterTime() { seek(to: time) } },
            onCycleRate: { cyclePlaybackRate() },
            onToggleSubtitles: { isShowingSubtitlePicker.toggle() },
            onToggleAudio: { isShowingAudioPicker.toggle() },
            onRequestEnvironmentSwitch: { requestEnvironmentPicker() },
            onDismiss: { Task { await dismissImmersiveIfNeeded(reason: .userInitiated) } }
        ))
        #endif
        #if os(macOS)
        .background(PlayerWindowAccessor(window: $playerWindow).frame(width: 0, height: 0))
        .onChange(of: playerWindow) { _, newWindow in
            configurePlayerWindow(newWindow)
            isFullscreen = newWindow?.styleMask.contains(.fullScreen) ?? false
            applyStoredFullscreenPreferenceIfNeeded()
        }
        .onChange(of: aspectRatioSelection) { _, _ in
            if let playerWindow {
                applyWindowAspectRatio(to: playerWindow)
            }
        }
        .onChange(of: detectedVideoRatio) { _, _ in
            if let playerWindow, aspectRatioSelection == .auto {
                applyWindowAspectRatio(to: playerWindow)
            }
        }
        #endif
        #if os(visionOS)
        .background(PlayerWindowSceneAccessor(windowScene: $playerWindowScene).frame(width: 0, height: 0))
        .onChange(of: playerWindowScene) { _, _ in applyVisionOSWindowGeometry() }
        .onChange(of: detectedVideoRatio) { _, _ in applyVisionOSWindowGeometry() }
        .onChange(of: aspectRatioSelection) { _, _ in
            applyVisionOSWindowGeometry()
            applyAspectRatioPresentationMode()
        }
        .preferredSurroundingsEffect(engine.isDimEnabled ? .systemDark : nil)
        #endif
        .animation(motionAnimationsEnabled ? .easeInOut(duration: 0.25) : nil, value: isShowingControls)
        .sheet(isPresented: $isShowingSubtitlePicker) {
            subtitlePickerSheet
        }
        .sheet(isPresented: $isShowingAudioPicker) {
            audioPickerSheet
        }
        #if os(visionOS)
        .sheet(isPresented: $isShowingEnvironmentPicker) {
            EnvironmentPickerSheet(
                onSelect: { asset in
                    Task { await openEnvironment(asset) }
                },
                onDismiss: {
                    Task { await dismissImmersiveIfNeeded(reason: .userInitiated) }
                }
            )
            .environment(appState)
        }
        #endif
    }

    /// Core player view with lifecycle modifiers that don't require platform-
    /// specific notification handlers. Extracted from `body` to keep the
    /// expression small enough for the compiler's type-checker.
    private var playerCore: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            playerSurface
            subtitleOverlay
            controlsOverlay
            startupStateOverlay
        }
        #if os(visionOS)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        #endif
        .animation(motionAnimationsEnabled ? .spring(response: 0.38, dampingFraction: 0.85) : nil, value: playbackState)
        .animation(motionAnimationsEnabled ? .easeInOut(duration: 0.18) : nil, value: engine.currentSubtitleText != nil)
        .onChange(of: playbackState) { _, newState in
            if newState == .playing, !hasPlayedOnce {
                hasPlayedOnce = true
                scrobbleStart()
            }
        }
        .task {
            initialPlayerStateTask?.cancel()
            initialPlayerStateTask = Task { await loadInitialPlayerState() }
            await initialPlayerStateTask?.value
        }
        .task(id: currentStream.id) {
            let preparationID = UUID()
            activePreparePlaybackID = preparationID
            preparePlaybackTask?.cancel()
            preparePlaybackTask = Task { await preparePlayback(for: currentStream, preparationID: preparationID) }
            await preparePlaybackTask?.value
        }
        .onAppear {
            #if os(macOS) || os(visionOS)
            scheduleMainWindowSuppressionIfNeeded()
            #endif
        }
        .onDisappear {
            stopProgressPersistence()
            scrobbleStop()
            scrobbleTask?.cancel()
            scrobbleTask = nil
            if !didInitiateClose {
                persistCurrentWatchProgress()
            }
            initialPlayerStateTask?.cancel()
            activePreparePlaybackID = nil
            preparePlaybackTask?.cancel()
            subtitleCatalogTask?.cancel()
            subtitleDownloadTask?.cancel()
            environmentAssetsTask?.cancel()
            scenePhaseTask?.cancel()
            memoryPressureTask?.cancel()
            cleanupPlayback()
            controlsHideTask?.cancel()
            controlsHideTask = nil
            RuntimeMemoryDiagnostics.capture(
                event: .playerDidDisappear,
                enabled: appState.runtimeDiagnosticsEnabled,
                context: mediaTitle ?? currentStream.fileName
            )
            if let subtitleFileURL = downloadedSubtitleFileURL {
                try? FileManager.default.removeItem(at: subtitleFileURL)
                downloadedSubtitleFileURL = nil
            }
            #if os(visionOS)
            visionGeometryTask?.cancel()
            visionGeometryTask = nil
            Task {
                await dismissImmersiveIfNeeded(reason: .playerClosed)
                scheduleMainWindowRestoreIfNeeded()
            }
            #elseif os(macOS)
            resetWindowAspectRatio()
            scheduleMainWindowRestoreIfNeeded()
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .environmentsDidChange)) { _ in
            environmentAssetsTask?.cancel()
            environmentAssetsTask = Task { await loadEnvironmentAssets() }
        }
        #if os(visionOS)
        .onChange(of: scenePhase) { _, phase in
            scenePhaseTask?.cancel()
            scenePhaseTask = Task { await handleScenePhaseChange(phase) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            memoryPressureTask?.cancel()
            memoryPressureTask = Task { await handleMemoryPressureWarning() }
        }
        .onChange(of: engine.stereoMode) { _, _ in
            updateAPMPInjector()
        }
        .onChange(of: appState.isImmersiveSpaceOpen) { _, _ in
            updateAPMPInjector()
        }
        #endif
    }

    /// Video gravity — `.resizeAspectFill` for edge-to-edge display.
    /// The window itself is forced to the video's aspect ratio via geometry
    /// preferences, so fill never crops.
    private var currentVideoGravity: AVLayerVideoGravity {
        PlayerAspectRatioPolicy.videoGravity(for: aspectRatioSelection)
    }

    @ViewBuilder
    private var playerSurface: some View {
        if activeEngine == .ksPlayer,
           let coordinator = ksPlayerCoordinator,
           let options = ksOptions {
            KSVideoPlayer(coordinator: coordinator, url: currentStream.streamURL, options: options)
                .ignoresSafeArea()
                .onAppear {
                    coordinator.isScaleAspectFill = currentVideoGravity == .resizeAspectFill
                }
                .onTapGesture {
                    toggleControlsVisibility()
                }
        } else if let avPlayer {
            #if os(visionOS)
            if isAPMPActive, let displayLayer = apmpInjector.displayLayer {
                APMPRendererView(displayLayer: displayLayer)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControlsVisibility()
                    }
            } else {
                AVPlayerSurfaceView(player: avPlayer, videoGravity: currentVideoGravity)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControlsVisibility()
                    }
            }
            #else
            AVPlayerSurfaceView(player: avPlayer, videoGravity: currentVideoGravity)
                .ignoresSafeArea()
                .onTapGesture {
                    toggleControlsVisibility()
                }
            #endif
        }
    }

    @ViewBuilder
    private var startupStateOverlay: some View {
        if playbackState == .failed {
            // Failure overlay -- always full center
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text(playbackStateTitle)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let message = playbackMessage, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 24)
                }

                HStack(spacing: 10) {
                    Button("Retry") {
                        retryPlayback()
                    }
                    .buttonStyle(.borderedProminent)

                    if hasNextStream {
                        Button("Try Next Stream") {
                            tryNextStream()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.24), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
            .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
            .transition(.scale(0.92, anchor: .center).combined(with: .opacity))
        } else if playbackState != .playing && !hasPlayedOnce {
            // Initial preparation — centered LoadingOverlay
            LoadingOverlay(
                title: playbackStateTitle,
                message: playbackMessage
            )
            .transition(.scale(0.92, anchor: .center).combined(with: .opacity))
        } else if playbackState == .buffering && hasPlayedOnce {
            // Mid-playback rebuffer — compact inline pill at top
            VStack {
                InlineLoadingStatusView(title: playbackMessage ?? "Rebuffering...")
                    .padding(.top, 80)
                Spacer()
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var subtitleOverlay: some View {
        if let subtitleText = engine.currentSubtitleText {
            VStack {
                Spacer()
                Text(subtitleText)
                    .font(.system(size: subtitleFontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 90)
                    .transition(.blurReplace.combined(with: .opacity))
                    .contextMenu {
                        ForEach([18.0, 22.0, 26.0, 30.0, 36.0, 42.0], id: \.self) { size in
                            Button("Size \(Int(size))pt") {
                                subtitleFontSize = size
                            }
                        }
                    }
            }
            .compositingGroup()
        }
    }

    // MARK: - Controls Overlay (full-height, overlaying video)

    @ViewBuilder
    private var controlsOverlay: some View {
        if isShowingControls {
            VStack(spacing: 0) {
                // MARK: Title Bar -- top edge overlay
                titleBar
                    .compositingGroup()

                warningsOverlay
                    .padding(.top, 6)
                    .compositingGroup()

                Spacer()

                // MARK: Info Pills -- floating centered above transport
                infoPillsRow
                    .padding(.bottom, 12)

                // MARK: Transport Bar -- bottom edge overlay
                transportBar
                    .compositingGroup()
            }
            .transition(.opacity)
        }
    }

    // MARK: - Title Bar (top edge, overlaying video)

    private var titleBar: some View {
        // topBarIconSurface(symbolName: PlayerCinematicVisualPolicy.backSymbolName)
        // topBarIconSurface(symbolName: PlayerCinematicVisualPolicy.menuSymbolName)

        HStack {
            // Left: back button
            Button {
                closePlayer()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")
            .accessibilityHint("Dismisses playback and returns to the previous screen.")
            #if os(visionOS)
            .hoverEffect(.lift)
            #endif

            Spacer()

            // Center: media title
            Text(mediaTitle ?? currentStream.fileName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            // Right: utility cluster + more options menu
            HStack(spacing: 8) {
                Button {
                    isShowingSubtitlePicker.toggle()
                } label: {
                    topBarUtilityButton(
                        systemName: subtitlePresentationIsActive ? "captions.bubble.fill" : "captions.bubble",
                        isActive: isShowingSubtitlePicker || subtitlePresentationIsActive,
                        accessibilityLabel: "Subtitles"
                    )
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif

                Button {
                    isShowingAudioPicker.toggle()
                } label: {
                    topBarUtilityButton(
                        systemName: availableAudioTrackCount > 1 ? "speaker.wave.2.fill" : "speaker.wave.2",
                        isActive: isShowingAudioPicker || availableAudioTrackCount > 1,
                        accessibilityLabel: "Audio Tracks"
                    )
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif

                Menu {
                    // Stream quality picker
                    Section("Stream") {
                        ForEach(streamQueue, id: \.id) { stream in
                            Button {
                                switchToStream(stream)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stream.quality.rawValue)
                                        Text(stream.qualityBadge)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if stream.id == currentStream.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Section("Aspect Ratio") {
                        Button {
                            aspectRatioSelection = aspectRatioSelection == .freeform ? .auto : .freeform
                        } label: {
                            HStack {
                                Label("Freeflow Resize", systemImage: "arrow.up.left.and.arrow.down.right")
                                if aspectRatioSelection == .freeform {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        ForEach(AspectRatioSelection.allCases.filter { $0 != .freeform }, id: \.id) { selection in
                            Button {
                                aspectRatioSelection = selection
                            } label: {
                                HStack {
                                    Label(selection.label, systemImage: selection.icon)
                                    if aspectRatioSelection == selection {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    #if os(macOS)
                    Section {
                        Button {
                            guard let playerWindow else { return }
                            playerWindow.toggleFullScreen(nil)
                            isFullscreen = playerWindow.styleMask.contains(.fullScreen)
                            if let sessionID {
                                appState.fullscreenBySessionID[sessionID] = isFullscreen
                            }
                        } label: {
                            Label(
                                isFullscreen ? "Exit Fullscreen" : "Enter Fullscreen",
                                systemImage: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                            )
                        }
                    }
                    #endif

                    #if os(visionOS)
                    Section("Environment") {
                        if environmentAssets.isEmpty {
                            Button {
                                isShowingEnvironmentPicker = true
                            } label: {
                                Label("Browse Environments", systemImage: "mountain.2")
                            }
                        } else {
                            ForEach(environmentAssets, id: \.id) { asset in
                                Button {
                                    Task { await openEnvironment(asset) }
                                } label: {
                                    HStack {
                                        Text(asset.name)
                                        if asset.id == appState.selectedEnvironmentAsset?.id,
                                           appState.isImmersiveSpaceOpen {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        if appState.isImmersiveSpaceOpen {
                            Button(role: .destructive) {
                                Task { await dismissImmersiveIfNeeded(reason: .userInitiated) }
                            } label: {
                                Label("Exit Environment", systemImage: "xmark.circle")
                            }
                        }
                    }
                    #endif
                } label: {
                    topBarUtilityButton(systemName: "ellipsis", accessibilityLabel: "More Playback Options")
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func topBarUtilityButton(
        systemName: String,
        isActive: Bool = false,
        accessibilityLabel: String
    ) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                isActive ? AnyShapeStyle(.tint.opacity(0.32)) : AnyShapeStyle(.regularMaterial),
                in: Circle()
            )
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            }
            .contentShape(Circle())
            .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Info Pills Row (floating above transport bar)

    private var infoPillsRow: some View {
        // transportIconButton(systemName: PlayerCinematicVisualPolicy.subtitlesSymbolName)
        // transportIconButton(systemName: PlayerCinematicVisualPolicy.audioSymbolName)
        // systemImage: PlayerCinematicVisualPolicy.qualitySymbolName
        // transportControls .padding(.horizontal, PlayerCinematicChromePolicy.transportCardHorizontalPadding) .padding(.vertical, PlayerCinematicChromePolicy.transportCardVerticalPadding) .frame(maxWidth: PlayerCinematicChromePolicy.transportCardMaxWidth) .background( chromeCardBackground, in: RoundedRectangle(
        // .overlay(alignment: .bottom)
        // controlsDock
        // .background(chromeIconBackground, in: Circle())

        HStack(spacing: 8) {
            // Playback rate pill
            Button { cyclePlaybackRate() } label: {
                Text("\(engine.playbackRate, specifier: "%.1f")x")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            #if os(visionOS)
            .hoverEffect(.lift)
            #endif

            #if os(visionOS)
            // Environment toggle pill — always visible so users can discover/import environments
            Button {
                if appState.isImmersiveSpaceOpen {
                    Task { await dismissImmersiveIfNeeded(reason: .userInitiated) }
                } else {
                    isShowingEnvironmentPicker = true
                }
            } label: {
                Image(systemName: appState.isImmersiveSpaceOpen ? "mountain.2.fill" : "mountain.2")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        appState.isImmersiveSpaceOpen
                            ? AnyShapeStyle(.tint.opacity(0.35))
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appState.isImmersiveSpaceOpen ? "Leave immersive environment" : "Open immersive environments")
            .hoverEffect(.lift)
            .animation(motionAnimationsEnabled ? .easeInOut(duration: 0.2) : nil, value: appState.isImmersiveSpaceOpen)

            // Dim passthrough toggle pill
            Button {
                engine.isDimEnabled.toggle()
                Task {
                    try? await appState.settingsManager.setBool(
                        key: SettingsKeys.playerDimPassthrough,
                        value: engine.isDimEnabled
                    )
                }
            } label: {
                Image(systemName: engine.isDimEnabled ? "sun.min.fill" : "sun.max")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        engine.isDimEnabled
                            ? AnyShapeStyle(.tint.opacity(0.35))
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isDimEnabled ? "Disable dim passthrough" : "Enable dim passthrough")
            .hoverEffect(.lift)
            .animation(motionAnimationsEnabled ? .easeInOut(duration: 0.2) : nil, value: engine.isDimEnabled)
            #endif

            // Quality badge pill
            featureChip(title: currentStream.quality.rawValue, symbol: nil)

            // 3D badge if applicable
            if engine.is3DContent {
                featureChip(title: "3D", symbol: "cube")
            }

            // Engine label pill
            if let activeEngine {
                featureChip(title: activeEngine.displayName, symbol: nil)
            }
        }
    }

    // MARK: - Transport Bar (bottom edge, overlaying video)

    private var transportBar: some View {
        VStack(spacing: 6) {
            // Progress bar
            GeometryReader { geo in
                let barWidth = geo.size.width
                let progressX = barWidth * engine.progressPercent
                let bufferedX = barWidth * engine.bufferedPercent
                let barHeight: CGFloat = isScrubbing ? 6 : 3

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: barHeight)

                    // Buffered range
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: bufferedX, height: barHeight)

                    // Played range
                    Capsule()
                        .fill(.white)
                        .frame(width: isScrubbing ? barWidth * (scrubTime / max(engine.duration, 1)) : progressX, height: barHeight)

                    // Chapter tick marks
                    if !engine.chapters.isEmpty && engine.duration > 0 {
                        ForEach(engine.chapters) { chapter in
                            let tickX = barWidth * (chapter.startTime / engine.duration)
                            if chapter.startTime > 0 {
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(.white.opacity(0.6))
                                    .frame(width: 2, height: barHeight + 4)
                                    .position(x: tickX, y: geo.size.height / 2)
                            }
                        }
                    }

                    // Thumb knob
                    Circle()
                        .fill(.white)
                        .frame(width: isScrubbing ? 14 : 8, height: isScrubbing ? 14 : 8)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .position(
                            x: isScrubbing ? barWidth * (scrubTime / max(engine.duration, 1)) : progressX,
                            y: geo.size.height / 2
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percent = max(0, min(1, value.location.x / max(barWidth, 1)))
                            scrubTime = engine.duration * percent
                            if !isScrubbing {
                                isScrubbing = true
                            }
                        }
                        .onEnded { value in
                            let percent = max(0, min(1, value.location.x / max(barWidth, 1)))
                            seekTo(percent: percent)
                            isScrubbing = false
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playback position")
                .accessibilityValue(scrubberAccessibilityValue)
                .accessibilityHint("Adjust to seek through the current video.")
                .accessibilityAdjustableAction { direction in
                    adjustScrubberAccessibility(direction)
                }
                .animation(motionAnimationsEnabled ? .easeInOut(duration: 0.15) : nil, value: isScrubbing)

                // Scrub preview time label
                if isScrubbing {
                    let thumbX = barWidth * (scrubTime / max(engine.duration, 1))
                    Text(scrubTime.formattedDuration)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .position(x: max(30, min(barWidth - 30, thumbX)), y: -10)
                }
            }
            .frame(height: 20)

            // Time labels
            HStack {
                Text(isScrubbing ? scrubTime.formattedDuration : engine.currentTimeFormatted)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("-\(engine.remainingFormatted)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Transport buttons -- centered skip back, play/pause, skip forward
            HStack(spacing: 28) {
                Spacer()

                // Chapter previous (compact)
                if !engine.chapters.isEmpty {
                    Button {
                        if let time = engine.previousChapterTime() { seek(to: time) }
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Previous chapter")
                    .buttonStyle(.plain)
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }

                Button {
                    seekRelative(-10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Back 10 seconds")
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif

                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: playPausePresentation.symbolName)
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                        }
                }
                 .accessibilityLabel(playPausePresentation.label)
                .accessibilityValue(playPausePresentation.accessibilityValue)
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif

                Button {
                    seekRelative(30)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Forward 30 seconds")
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif

                // Chapter next (compact)
                if !engine.chapters.isEmpty {
                    Button {
                        if let time = engine.nextChapterTime() { seek(to: time) }
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Next chapter")
                    .buttonStyle(.plain)
                    #if os(visionOS)
                    .hoverEffect(.highlight)
                    #endif
                }

                Spacer()
            }

            // Bottom drag indicator
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Capability Warnings & Errors (shown in title bar area when present)

    @ViewBuilder
    private var warningsOverlay: some View {
        if !capabilityWarnings.isEmpty || (playbackError != nil && playbackState == .failed) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(capabilityWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let playbackError, playbackState == .failed {
                    Text(playbackError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitlePickerSheet: some View {
        NavigationStack {
            List {
                Section("Current Selection") {
                    Button("Off") {
                        selectSubtitlesOff()
                    }
                    .foregroundStyle(currentSubtitleSelectionIsOff ? .blue : .primary)
                }

                if !avSubtitleOptions.isEmpty {
                    Section("In-Stream Subtitles") {
                        ForEach(avSubtitleOptions) { track in
                            Button {
                                selectAVSubtitle(track)
                                isShowingSubtitlePicker = false
                            } label: {
                                subtitleTrackRow(name: track.name, language: track.language)
                            }
                            .foregroundStyle(selectedAVSubtitleID == track.id ? .blue : .primary)
                        }
                    }
                }

                Section("External (OpenSubtitles)") {
                    if isDownloadingSubtitle {
                        HStack {
                            ProgressView()
                            Text("Downloading subtitle...")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !engine.subtitleTracks.isEmpty {
                        ForEach(engine.subtitleTracks) { track in
                            Button {
                                selectExternalSubtitle(index: track.id)
                                isShowingSubtitlePicker = false
                            } label: {
                                subtitleTrackRow(name: track.name, language: track.language)
                            }
                            .foregroundStyle(selectedAVSubtitleID == nil && engine.selectedSubtitleTrack == track.id ? .blue : .primary)
                        }
                    }

                    if isRefreshingSubtitleCatalog {
                        HStack {
                            ProgressView()
                            Text("Searching subtitles...")
                                .foregroundStyle(.secondary)
                        }
                    } else if subtitleCandidates.isEmpty {
                        Text(subtitleCatalogMessage ?? "No subtitle results found for this stream.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(subtitleCandidates, id: \.id) { subtitle in
                            Button {
                                scheduleSubtitleDownload(subtitle, streamID: currentStream.id)
                            } label: {
                                subtitleCandidateRow(subtitle)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle("Subtitles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refreshSubtitleCatalog(for: currentStream) }
                        // scheduleSubtitleCatalogRefresh(for: currentStream)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh subtitle list")
                    .disabled(isRefreshingSubtitleCatalog || isDownloadingSubtitle)
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
    }

    private var audioPickerSheet: some View {
        NavigationStack {
            List {
                if !avAudioOptions.isEmpty {
                    Section("In-Stream Audio") {
                        ForEach(avAudioOptions) { track in
                            Button {
                                selectAVAudio(track)
                                isShowingAudioPicker = false
                            } label: {
                                subtitleTrackRow(name: track.name, language: track.language)
                            }
                            .foregroundStyle(selectedAVAudioID == track.id ? .blue : .primary)
                        }
                    }
                }

                if activeEngine == .ksPlayer || (!engine.audioTracks.isEmpty && avAudioOptions.isEmpty) {
                    Section("Engine Audio") {
                        ForEach(engine.audioTracks) { track in
                            Button {
                                selectEngineAudio(track)
                                isShowingAudioPicker = false
                            } label: {
                                subtitleTrackRow(name: track.name, language: track.language)
                            }
                            .foregroundStyle(engine.selectedAudioTrack == track.id ? .blue : .primary)
                        }

                        if engine.audioTracks.isEmpty && avAudioOptions.isEmpty {
                            Text("No alternate audio tracks detected for this stream.")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if avAudioOptions.isEmpty {
                    Section("Audio") {
                        Text(activeEngine == .avPlayer
                             ? "No alternate in-stream audio tracks detected. The stream may have only one audio track."
                             : "No alternate audio tracks detected for this stream.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        guard let avPlayer else { return }
                        Task { await refreshAVMediaOptions(for: avPlayer) }
                    } label: {
                        Label("Refresh Track List", systemImage: "arrow.clockwise")
                    }
                    .disabled(avPlayer == nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle("Audio")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        guard let avPlayer else { return }
                        Task { await refreshAVMediaOptions(for: avPlayer) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh audio tracks")
                    .disabled(avPlayer == nil)
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let avPlayer else { return }
                        Task { await refreshAVMediaOptions(for: avPlayer) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh audio tracks")
                    .disabled(avPlayer == nil)
                }
                #endif
            }
        }
        .presentationBackground(.ultraThinMaterial)
    }


    private var playPausePresentation: PlayerControlPresentation {
        PlayerControlPresentationMapper.playPause(
            playbackState: playbackState,
            isCurrentlyPlaying: isCurrentlyPlaying
        )
    }

    private var isCurrentlyPlaying: Bool {
        switch activeEngine {
        case .ksPlayer:
            return ksPlayerCoordinator?.state.isPlaying ?? engine.isPlaying
        case .avPlayer:
            return avPlayer?.timeControlStatus == .playing || avPlayer?.rate ?? 0 > 0
        default:
            return false
        }
    }

    private var currentSubtitleSelectionIsOff: Bool {
        !engine.subtitlesEnabled
    }

    private var playbackStateTitle: String {
        switch playbackState {
        case .preparing:
            return "Preparing Playback"
        case .buffering:
            return "Buffering"
        case .playing:
            return "Playing"
        case .failed:
            return "Playback Failed"
        }
    }

    private var hasNextStream: Bool {
        PlayerStreamFailoverPlanner.nextStream(after: currentStream, in: streamQueue) != nil
    }

    private func tryNextStream() {
        guard let next = PlayerStreamFailoverPlanner.nextStream(after: currentStream, in: streamQueue) else { return }
        switchToStream(next)
    }

    private func switchToStream(_ stream: StreamInfo) {
        guard stream.id != currentStream.id else { return }
        persistCurrentWatchProgress()
        resetSubtitleStateForStreamTransition()
        currentStream = stream
        playbackMessage = "Switching stream to \(stream.quality.rawValue)..."
        scheduleSubtitleCatalogRefresh(for: stream)
    }

    private func closePlayer() {
        didInitiateClose = true
        RuntimeMemoryDiagnostics.capture(
            event: .playerCloseRequested,
            enabled: appState.runtimeDiagnosticsEnabled,
            context: mediaTitle ?? currentStream.fileName
        )

        stopProgressPersistence()
        scrobbleStop()
        persistCurrentWatchProgress()
        initialPlayerStateTask?.cancel()
        initialPlayerStateTask = nil
        activePreparePlaybackID = nil
        preparePlaybackTask?.cancel()
        preparePlaybackTask = nil
        subtitleCatalogTask?.cancel()
        subtitleCatalogTask = nil
        subtitleDownloadTask?.cancel()
        subtitleDownloadTask = nil
        environmentAssetsTask?.cancel()
        environmentAssetsTask = nil
        audioTrackRefreshTask?.cancel()
        audioTrackRefreshTask = nil
        cancelVisionLifecycleTasksOnClose()
        cleanupPlayback(clearSession: true)
        controlsHideTask?.cancel()
        controlsHideTask = nil

        #if os(visionOS)
        scheduleMainWindowRestoreIfNeeded()
        if PlayerLifecyclePolicy.closesDedicatedPlayerWindowOnBack {
            dismissWindow(id: "player")
        }
        if PlayerLifecyclePolicy.dismissesCurrentPresentationOnBack {
            dismiss()
        }
        Task {
            await dismissImmersiveIfNeeded(reason: .playerClosed)
        }
        #elseif os(macOS)
        scheduleMainWindowRestoreIfNeeded()
        if PlayerLifecyclePolicy.closesDedicatedPlayerWindowOnBack {
            dismissWindow(id: "player")
        } else {
            dismiss()
        }
        #else
        dismiss()
        #endif
    }

    @MainActor
    private func retryPlayback() {
        startPlaybackPreparation(for: currentStream)
    }

    private func toggleControlsVisibility() {
        performOptionalAnimation(.easeInOut(duration: 0.22)) {
            isShowingControls.toggle()
        }
        scheduleControlsHide()
    }

    private func loadInitialPlayerState() async {
        guard !Task.isCancelled else { return }
        streamQueue = await PlayerSessionRouting.playbackQueue(
            primary: currentStream,
            available: availableStreams
        )
        engine.currentTitle = mediaTitle ?? currentStream.fileName
        evaluateCapabilities(for: currentStream)
        await loadEnvironmentAssets()
        guard !Task.isCancelled else { return }
        startProgressPersistence()
        await loadSubtitleAppearance()
        await refreshSubtitleCatalog(for: currentStream)
        guard !Task.isCancelled else { return }
        await autoLoadSubtitlesIfEnabled(for: currentStream)
        guard !Task.isCancelled else { return }
        scheduleControlsHide()
        #if os(visionOS)
        await loadDimPassthroughPreference()
        await autoOpenEnvironmentIfNeeded()
        #endif
    }

    @MainActor
    private func startPlaybackPreparation(for stream: StreamInfo) {
        let preparationID = UUID()
        activePreparePlaybackID = preparationID
        preparePlaybackTask?.cancel()
        preparePlaybackTask = Task { await preparePlayback(for: stream, preparationID: preparationID) }
    }

    #if os(visionOS)
    private func loadDimPassthroughPreference() async {
        engine.isDimEnabled = (try? await appState.settingsManager.getBool(
            key: SettingsKeys.playerDimPassthrough,
            default: true
        )) ?? true
    }
    #endif

    #if os(visionOS)
    private func autoOpenEnvironmentIfNeeded() async {
        let autoOpen = (try? await appState.settingsManager.getBool(
            key: SettingsKeys.autoOpenEnvironment, default: true
        )) ?? true
        guard autoOpen else { return }
        guard let asset = appState.selectedEnvironmentAsset else { return }
        guard !appState.isImmersiveSpaceOpen else { return }
        guard !appState.isImmersiveTransitionInFlight else { return }
        await openImmersiveSpaceIfPossible(for: asset)
    }
    #endif

    @MainActor
    private func preparePlayback(for stream: StreamInfo, preparationID: UUID) async {
        defer {
            if Self.preparePlaybackShouldRun(
                requestedPreparationID: preparationID,
                activePreparationID: activePreparePlaybackID
            ) {
                activePreparePlaybackID = nil
            }
        }

        guard Self.preparePlaybackShouldRun(
            requestedPreparationID: preparationID,
            activePreparationID: activePreparePlaybackID
        ) else {
            return
        }

        RuntimeMemoryDiagnostics.capture(
            event: .playerPrepareStarted,
            enabled: appState.runtimeDiagnosticsEnabled,
            context: stream.fileName
        )

        playbackState = .preparing
        playbackError = nil
        playbackMessage = "Starting stream..."
        isShowingControls = true
        hasPlayedOnce = false
        guard Self.preparePlaybackShouldRun(
            requestedPreparationID: preparationID,
            activePreparationID: activePreparePlaybackID
        ), !Task.isCancelled else {
            return
        }
        cleanupPlayback(clearSession: true)
        engine.currentTitle = mediaTitle ?? stream.fileName
        engine.currentTime = 0
        engine.duration = 0
        engine.bufferedPercent = 0
        detectedVideoRatio = nil
        engine.updateStereoMode(
            from: mediaTitle ?? stream.fileName,
            codecHint: stream.codec.rawValue
        )
        evaluateCapabilities(for: stream)

        // Re-activate the audio session before playback — the session from
        // app init may not survive window transitions on visionOS.
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let resumeTarget = await loadResumeTarget()
        guard Self.preparePlaybackShouldRun(
            requestedPreparationID: preparationID,
            activePreparationID: activePreparePlaybackID
        ), !Task.isCancelled else {
            return
        }
        let engineStrategy = await loadPlayerEngineStrategy()
        guard Self.preparePlaybackShouldRun(
            requestedPreparationID: preparationID,
            activePreparationID: activePreparePlaybackID
        ), !Task.isCancelled else {
            return
        }

        let orderedEngines = playerEngineSelector.engineOrder(for: stream, strategy: engineStrategy)
        var failures: [String] = []

        for kind in orderedEngines {
            guard Self.preparePlaybackShouldRun(
                requestedPreparationID: preparationID,
                activePreparationID: activePreparePlaybackID
            ), !Task.isCancelled else {
                return
            }

            do {
                switch kind {
                case .ksPlayer:
                    let prepared = try await ksPlayerEngine.prepare(stream: stream)
                    try Task.checkCancellation()
                    guard Self.preparePlaybackShouldRun(
                        requestedPreparationID: preparationID,
                        activePreparationID: activePreparePlaybackID
                    ) else {
                        return
                    }
                    guard let coordinator = prepared.ksPlayerCoordinator,
                          let options = prepared.ksOptions else {
                        throw PlayerEngineError.initializationFailed(.ksPlayer, "Missing player coordinator.")
                    }

                    // Honor the user's hardware decoding preference from Settings.
                    let hwDecode = (try? await appState.settingsManager.getBool(
                        key: SettingsKeys.hardwareDecoding, default: true
                    )) ?? true
                    try Task.checkCancellation()
                    options.hardwareDecode = hwDecode

                    configureKSCallbacks(coordinator)
                    activeEngine = .ksPlayer
                    ksPlayerCoordinator = coordinator
                    applyAspectRatioPresentationMode()
                    ksOptions = options
                    avPlayer = nil
                    avAudioOptions = []
                    avSubtitleOptions = []
                    avAudioGroup = nil
                    avSubtitleGroup = nil
                    selectedAVAudioID = nil
                    selectedAVSubtitleID = nil
                    hydrateFallbackAudioTrack(for: stream)
                    playbackState = .preparing
                    playbackMessage = "Trying KSPlayer..."

                    try await Task.sleep(for: .milliseconds(140))
                    try Task.checkCancellation()
                    try await KSPlayerEngine.waitUntilReady(
                        coordinator: coordinator,
                        timeout: KSPlayerEngine.timeout(for: stream),
                        onState: { state, diagnostics in
                            guard Self.preparePlaybackShouldRun(
                                requestedPreparationID: preparationID,
                                activePreparationID: activePreparePlaybackID
                            ) else {
                                return
                            }
                            playbackState = state
                            playbackMessage = diagnostics
                        },
                        failureMessage: { playbackError }
                    )
                    try Task.checkCancellation()
                    guard Self.preparePlaybackShouldRun(
                        requestedPreparationID: preparationID,
                        activePreparationID: activePreparePlaybackID
                    ) else {
                        return
                    }
                    refreshKSAudioTracks(for: stream)

                    if let resumeTarget {
                        coordinator.seek(time: resumeTarget)
                        engine.currentTime = resumeTarget
                        playbackMessage = "Resuming from \(resumeTarget.formattedDuration)..."
                    }

                    coordinator.playerLayer?.player.playbackRate = engine.playbackRate
                    coordinator.playerLayer?.play()
                    playbackState = .playing
                    playbackMessage = resumeTarget == nil ? "Playing with KSPlayer." : "Resumed with KSPlayer."
                    refreshKSAudioTracks(from: coordinator)
                    await autoLoadSubtitlesIfEnabled(for: stream)
                    try Task.checkCancellation()
                    scheduleControlsHide()
                    RuntimeMemoryDiagnostics.capture(
                        event: .playerPrepareSucceeded,
                        enabled: appState.runtimeDiagnosticsEnabled,
                        context: "ksplayer:\(stream.fileName)"
                    )
                    return

                case .avPlayer:
                    let prepared = try await avPlayerEngine.prepare(stream: stream)
                    try Task.checkCancellation()
                    guard Self.preparePlaybackShouldRun(
                        requestedPreparationID: preparationID,
                        activePreparationID: activePreparePlaybackID
                    ) else {
                        return
                    }
                    guard let player = prepared.avPlayer else {
                        throw PlayerEngineError.initializationFailed(.avPlayer, "Missing AVPlayer session.")
                    }

                    activeEngine = .avPlayer
                    ksPlayerCoordinator = nil
                    ksOptions = nil
                    avPlayer = player
                    appState.activeAVPlayer = player
                    playbackState = .preparing
                    playbackMessage = "Trying AVPlayer..."

                    startObservingAVPlayer(player)
                    #if os(visionOS)
                    updateAPMPInjector()
                    #endif
                    player.playImmediately(atRate: max(0.1, engine.playbackRate))

                    try await AVPlayerEngine.waitUntilReady(
                        player: player,
                        onState: { state, diagnostics in
                            guard Self.preparePlaybackShouldRun(
                                requestedPreparationID: preparationID,
                                activePreparationID: activePreparePlaybackID
                            ) else {
                                return
                            }
                            playbackState = state
                            playbackMessage = diagnostics
                        }
                    )
                    try Task.checkCancellation()
                    guard Self.preparePlaybackShouldRun(
                        requestedPreparationID: preparationID,
                        activePreparationID: activePreparePlaybackID
                    ) else {
                        return
                    }

                    await refreshAVMediaOptions(for: player)
                    try Task.checkCancellation()
                    // Torrent/direct streams may not expose audio tracks immediately.
                    // Refresh again after the stream has had time to load track metadata.
                    let streamID = stream.id
                    audioTrackRefreshTask?.cancel()
                    audioTrackRefreshTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(2000))
                        guard !Task.isCancelled,
                              Self.audioTrackRefreshShouldRun(
                                  requestedStreamID: streamID,
                                  currentStreamID: currentStream.id
                              ) else {
                            return
                        }
                        await refreshAVMediaOptions(for: player)
                    }
                    try Task.checkCancellation()
                    await loadChapters(from: player)
                    try Task.checkCancellation()
                    if let resumeTarget {
                        await seekAVPlayer(player, to: resumeTarget)
                        try Task.checkCancellation()
                        engine.currentTime = resumeTarget
                        playbackMessage = "Resuming from \(resumeTarget.formattedDuration)..."
                    }
                    player.playImmediately(atRate: max(0.1, engine.playbackRate))

                    playbackState = .playing
                    playbackMessage = resumeTarget == nil ? "Playing with AVPlayer." : "Resumed with AVPlayer."
                    await autoLoadSubtitlesIfEnabled(for: stream)
                    try Task.checkCancellation()
                    scheduleControlsHide()
                    RuntimeMemoryDiagnostics.capture(
                        event: .playerPrepareSucceeded,
                        enabled: appState.runtimeDiagnosticsEnabled,
                        context: "avplayer:\(stream.fileName)"
                    )
                    return
                }
            } catch is CancellationError {
                guard Self.preparePlaybackShouldRun(
                    requestedPreparationID: preparationID,
                    activePreparationID: activePreparePlaybackID
                ) else {
                    return
                }
                cleanupPlayback(clearSession: false)
                return
            } catch {
                guard Self.preparePlaybackShouldRun(
                    requestedPreparationID: preparationID,
                    activePreparationID: activePreparePlaybackID
                ) else {
                    return
                }
                failures.append("\(kind.displayName): \(error.localizedDescription)")
                cleanupPlayback(clearSession: false)
            }
        }

        guard Self.preparePlaybackShouldRun(
            requestedPreparationID: preparationID,
            activePreparationID: activePreparePlaybackID
        ) else {
            return
        }
        playbackState = .failed
        activeEngine = nil
        let reason = failures.isEmpty ? "No compatible player engine was available." : failures.joined(separator: "\n")
        playbackError = reason
        playbackMessage = "Use retry or try the next stream."
        RuntimeMemoryDiagnostics.capture(
            event: .playerPrepareFailed,
            enabled: appState.runtimeDiagnosticsEnabled,
            context: "failures=\(failures.count)"
        )
    }

    static func audioTrackRefreshShouldRun(requestedStreamID: String, currentStreamID: String?) -> Bool {
        currentStreamID == requestedStreamID
    }

    static func preparePlaybackShouldRun(requestedPreparationID: UUID, activePreparationID: UUID?) -> Bool {
        activePreparationID == requestedPreparationID
    }

    private func isCurrentAVPlayer(_ player: AVPlayer) -> Bool {
        activeEngine == .avPlayer && avPlayer === player
    }

    private func isCurrentKSPlayerCoordinator(_ coordinator: KSVideoPlayer.Coordinator) -> Bool {
        activeEngine == .ksPlayer && ksPlayerCoordinator === coordinator
    }

    private func configureKSCallbacks(_ coordinator: KSVideoPlayer.Coordinator) {
        coordinator.onStateChanged = { playerLayer, state in
            Task { @MainActor in
                guard self.isCurrentKSPlayerCoordinator(coordinator) else { return }
                switch state {
                case .initialized, .preparing:
                    playbackState = .preparing
                    engine.isBuffering = true
                    engine.isPlaying = false
                case .readyToPlay, .buffering:
                    playbackState = .buffering
                    engine.isBuffering = true
                    engine.isPlaying = false
                    // Detect video ratio from KSPlayer once ready
                    if detectedVideoRatio == nil {
                        let size = playerLayer.player.naturalSize
                        if let ratio = PlayerAspectRatioPolicy.ratio(from: size) {
                            detectedVideoRatio = ratio
                            engine.videoSize = size
                        }
                    }
                case .bufferFinished:
                    playbackState = .playing
                    engine.isBuffering = false
                    engine.isPlaying = true
                    // Fallback: detect if not yet captured at readyToPlay
                    if detectedVideoRatio == nil {
                        let size = playerLayer.player.naturalSize
                        if let ratio = PlayerAspectRatioPolicy.ratio(from: size) {
                            detectedVideoRatio = ratio
                            engine.videoSize = size
                        }
                    }
                case .paused:
                    engine.isPlaying = false
                    engine.isBuffering = false
                case .playedToTheEnd:
                    engine.isPlaying = false
                    engine.isBuffering = false
                case .error:
                    playbackState = .failed
                    engine.isPlaying = false
                    engine.isBuffering = false
                }
            }
        }

        coordinator.onPlay = { currentTime, totalTime in
            Task { @MainActor in
                guard self.isCurrentKSPlayerCoordinator(coordinator) else { return }
                let newTime = max(0, currentTime)
                // Only write to @Observable properties when the value has actually
                // changed by a perceptible amount. This prevents KSPlayer's high-
                // frequency onPlay callbacks from flooding the observation system
                // and causing PlayerView.body to re-evaluate (and the transport
                // controls tree to re-diff) on every callback -- which caused
                // audio/video lag when the environment Menu was open.
                if abs(engine.currentTime - newTime) >= 0.25 {
                    engine.currentTime = newTime
                    engine.updateSubtitleText(at: newTime)
                }
                let newDuration = max(0, totalTime)
                if abs(engine.duration - newDuration) > 1.0 {
                    engine.duration = newDuration
                }
            }
        }

        coordinator.onFinish = { _, error in
            Task { @MainActor in
                guard self.isCurrentKSPlayerCoordinator(coordinator) else { return }
                if let error {
                    playbackState = .failed
                    playbackError = error.localizedDescription
                    playbackMessage = "This stream failed during playback."
                }
            }
        }
    }

    private func startObservingAVPlayer(_ player: AVPlayer) {
        if let token = timeObserverToken {
            timeObserverPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
            timeObserverPlayer = nil
        }

        let interval = CMTime(
            seconds: Self.avPlayerPeriodicObserverIntervalSeconds,
            preferredTimescale: 600
        )
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                guard self.isCurrentAVPlayer(player) else { return }
                let seconds = time.seconds
                let newTime = seconds.isFinite ? max(0, seconds) : 0
                if abs(engine.currentTime - newTime) >= Self.avPlayerPeriodicObserverIntervalSeconds {
                    engine.currentTime = newTime
                }
                if engine.selectedSubtitleTrack >= 0 || engine.currentSubtitleText != nil {
                    engine.updateSubtitleText(at: newTime)
                }

                if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0,
                   engine.duration != duration {
                    engine.duration = duration
                }

                // Trigger async video size detection once
                if detectedVideoRatio == nil, let asset = player.currentItem?.asset {
                    Task { await detectVideoRatio(from: asset, player: player) }
                }

                // Extract HDR mastering-display metadata once
                if engine.hdrMetadata == nil, let asset = player.currentItem?.asset {
                    Task { @MainActor in
                        guard self.isCurrentAVPlayer(player) else { return }
                        guard engine.hdrMetadata == nil else { return }
                        let metadata = await HDRMetadataExtractor.extract(from: asset)
                        guard self.isCurrentAVPlayer(player) else { return }
                        engine.hdrMetadata = metadata
                    }
                }

                // Buffered range
                if let loadedRange = player.currentItem?.loadedTimeRanges.first?.timeRangeValue,
                   let itemDuration = player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    let bufferedEnd = (loadedRange.start + loadedRange.duration).seconds
                    let newBuffered = min(1.0, bufferedEnd / itemDuration)
                    if abs(engine.bufferedPercent - newBuffered) > 0.01 {
                        engine.bufferedPercent = newBuffered
                    }
                }

                let nowPlaying = player.timeControlStatus == .playing
                let nowBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if engine.isPlaying != nowPlaying { engine.isPlaying = nowPlaying }
                if engine.isBuffering != nowBuffering { engine.isBuffering = nowBuffering }
                if nowPlaying && playbackState != .playing {
                    playbackState = .playing
                } else if nowBuffering && playbackState != .buffering {
                    playbackState = .buffering
                }
            }
        }
        timeObserverPlayer = player
    }

    static let avPlayerPeriodicObserverIntervalSeconds: TimeInterval = 0.25

    @MainActor
    private func detectVideoRatio(from asset: AVAsset, player: AVPlayer) async {
        guard isCurrentAVPlayer(player), detectedVideoRatio == nil else { return }
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else { return }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let size = naturalSize.applying(transform)
            let absSize = CGSize(width: abs(size.width), height: abs(size.height))
            guard isCurrentAVPlayer(player), detectedVideoRatio == nil else { return }
            if let ratio = PlayerAspectRatioPolicy.ratio(from: absSize) {
                detectedVideoRatio = ratio
                engine.videoSize = absSize
            }
        } catch {
            // Video track unavailable; ratio stays nil and 16:9 fallback is used
        }
    }

    private func seekTo(percent: Double) {
        let clamped = max(0, min(1, percent))
        let target = engine.duration * clamped
        seek(to: target)
    }

    private func seekRelative(_ offset: TimeInterval) {
        let target = engine.currentTime + offset
        seek(to: target)
    }

    private var scrubberAccessibilityValue: String {
        let current = isScrubbing ? scrubTime : engine.currentTime
        guard engine.duration > 0 else { return current.formattedDuration }
        return "\(current.formattedDuration) of \(engine.durationFormatted)"
    }

    private func adjustScrubberAccessibility(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            seekRelative(10)
        case .decrement:
            seekRelative(-10)
        default:
            break
        }
    }

    private func seek(to time: TimeInterval) {
        let target = max(0, min(engine.duration, time))
        engine.currentTime = target
        engine.updateSubtitleText(at: target)

        switch activeEngine {
        case .ksPlayer:
            ksPlayerCoordinator?.seek(time: target)
        case .avPlayer:
            avPlayer?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        default:
            break
        }
    }

    private func togglePlayPause() {
        switch activeEngine {
        case .ksPlayer:
            guard let layer = ksPlayerCoordinator?.playerLayer else { return }
            if layer.state.isPlaying {
                layer.pause()
                engine.isPlaying = false
            } else {
                layer.player.playbackRate = engine.playbackRate
                layer.play()
                engine.isPlaying = true
            }

        case .avPlayer:
            guard let avPlayer else { return }
            if avPlayer.timeControlStatus == .playing || avPlayer.rate > 0 {
                avPlayer.pause()
                engine.isPlaying = false
            } else {
                avPlayer.playImmediately(atRate: engine.playbackRate)
                engine.isPlaying = true
            }

        default:
            break
        }

        if engine.isPlaying {
            scrobbleResume()
        } else {
            scrobblePause()
        }
        scheduleControlsHide()
    }

    private func cyclePlaybackRate() {
        engine.cycleRate()
        switch activeEngine {
        case .ksPlayer:
            ksPlayerCoordinator?.playerLayer?.player.playbackRate = engine.playbackRate
        case .avPlayer:
            if isCurrentlyPlaying {
                avPlayer?.playImmediately(atRate: engine.playbackRate)
            }
        default:
            break
        }
    }

    private func cleanupPlayback(clearSession: Bool = true) {
        if let token = timeObserverToken {
            timeObserverPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
            timeObserverPlayer = nil
        }

        #if os(visionOS)
        apmpInjector.stop()
        isAPMPActive = false
        #endif

        avPlayer?.pause()
        avPlayer = nil
        appState.releasePlayerResources(clearSession: clearSession, sessionID: sessionID)

        ksPlayerCoordinator?.onStateChanged = nil
        ksPlayerCoordinator?.onPlay = nil
        ksPlayerCoordinator?.onFinish = nil
        audioTrackRefreshTask?.cancel()
        audioTrackRefreshTask = nil

        ksPlayerCoordinator?.resetPlayer()
        ksPlayerCoordinator = nil
        ksOptions = nil
        avAudioOptions = []
        avSubtitleOptions = []
        avAudioGroup = nil
        avSubtitleGroup = nil
        selectedAVAudioID = nil
        selectedAVSubtitleID = nil
        subtitleCatalogTask?.cancel()
        subtitleCatalogTask = nil
        subtitleDownloadTask?.cancel()
        subtitleDownloadTask = nil
        subtitleService = nil
        subtitleServiceAPIKey = nil
        engine.resetSessionState()

        if clearSession {
            activeEngine = nil
        }

        engine.isPlaying = false
        engine.isBuffering = false
        clearTransientSubtitleState(removeDownloadedFile: clearSession)
    }

    // MARK: - Scrobbling

    private var scrobbleProgress: Double {
        guard engine.duration > 0 else { return 0 }
        return (engine.currentTime / engine.duration) * 100
    }

    private func scrobbleStart() {
        guard let mediaId, mediaId.hasPrefix("tt") else { return }
        let progress = scrobbleProgress
        let type: MediaType = episodeId != nil ? .series : .movie
        scrobbleTask?.cancel()
        scrobbleTask = Task { await appState.scrobbleCoordinator.startPlayback(mediaId: mediaId, mediaType: type, progress: progress) }
    }

    private func scrobblePause() {
        guard let mediaId, mediaId.hasPrefix("tt") else { return }
        let progress = scrobbleProgress
        scrobbleTask?.cancel()
        scrobbleTask = Task { await appState.scrobbleCoordinator.pausePlayback(progress: progress) }
    }

    private func scrobbleResume() {
        guard let mediaId, mediaId.hasPrefix("tt") else { return }
        let progress = scrobbleProgress
        scrobbleTask?.cancel()
        scrobbleTask = Task { await appState.scrobbleCoordinator.resumePlayback(progress: progress) }
    }

    private func scrobbleStop() {
        guard let mediaId, mediaId.hasPrefix("tt") else { return }
        let progress = scrobbleProgress
        scrobbleTask?.cancel()
        scrobbleTask = Task { await appState.scrobbleCoordinator.stopPlayback(progress: progress) }
    }

    private func applyAspectRatioPresentationMode() {
        guard let coordinator = ksPlayerCoordinator else { return }
        coordinator.isScaleAspectFill = currentVideoGravity == .resizeAspectFill
    }

    #if os(macOS)
    private func configurePlayerWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.minSize = NSSize(width: 960, height: 540)
        applyWindowAspectRatio(to: window)
    }

    private func applyWindowAspectRatio(to window: NSWindow) {
        let ratio = PlayerAspectRatioPolicy.resolvedRatio(
            for: aspectRatioSelection,
            detectedRatio: detectedVideoRatio
        )
        if let size = PlayerAspectRatioPolicy.windowAspectSize(for: ratio) {
            window.contentAspectRatio = NSSize(width: size.width, height: size.height)
        } else {
            // Freeform: unlock window aspect ratio
            window.contentAspectRatio = NSSize.zero
        }
    }

    private func resetWindowAspectRatio() {
        guard let playerWindow else { return }
        playerWindow.contentAspectRatio = NSSize.zero
    }

    private func applyStoredFullscreenPreferenceIfNeeded() {
        guard let playerWindow else { return }
        guard let sessionID else { return }
        guard !didApplyStoredFullscreen else { return }

        didApplyStoredFullscreen = true
        let preferredFullscreen = appState.fullscreenBySessionID[sessionID] ?? false
        guard preferredFullscreen else { return }

        if !playerWindow.styleMask.contains(.fullScreen) {
            playerWindow.toggleFullScreen(nil)
            isFullscreen = true
        }
    }
    #endif

    #if os(visionOS)
    private func applyVisionOSWindowGeometry() {
        visionGeometryTask?.cancel()

        guard let windowScene = playerWindowScene else {
            visionGeometryTask = nil
            return
        }

        if !aspectRatioSelection.locksWindowRatio {
            let freeform = UIWindowScene.GeometryPreferences.Vision(
                minimumSize: CGSize(width: 640, height: 360),
                maximumSize: CGSize(width: 3840, height: 3840),
                resizingRestrictions: UIWindowScene.ResizingRestrictions.none
            )
            windowScene.requestGeometryUpdate(freeform)
            visionGeometryTask = nil
            return
        }

        let ratio = PlayerAspectRatioPolicy.resolvedRatio(
            for: aspectRatioSelection,
            detectedRatio: detectedVideoRatio
        ) ?? PlayerAspectRatioPolicy.defaultRatio
        let trackedSceneID = ObjectIdentifier(windowScene)

        visionGeometryTask = Task { @MainActor in
            guard let liveScene = playerWindowScene,
                  ObjectIdentifier(liveScene) == trackedSceneID else { return }

            let currentWidth = max(liveScene.effectiveGeometry.coordinateSpace.bounds.width, 1400)
            let targetHeight = currentWidth / ratio
            let targetSize = CGSize(width: currentWidth, height: targetHeight)

            // Force the window into the selected ratio by briefly locking
            // min = max, then relax to proportional user resizing.
            let forceGeometry = UIWindowScene.GeometryPreferences.Vision(
                minimumSize: targetSize,
                maximumSize: targetSize,
                resizingRestrictions: .uniform
            )
            liveScene.requestGeometryUpdate(forceGeometry)

            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            guard let liveScene = playerWindowScene,
                  ObjectIdentifier(liveScene) == trackedSceneID else { return }

            let safeMinDim: CGFloat = 400
            let safeMaxDim: CGFloat = 3840
            let minWidth = max(640, safeMinDim * ratio)
            let minHeight = max(640 / ratio, safeMinDim)
            let maxWidth = min(safeMaxDim, safeMaxDim * ratio)
            let maxHeight = min(safeMaxDim / ratio, safeMaxDim)
            let relaxed = UIWindowScene.GeometryPreferences.Vision(
                minimumSize: CGSize(width: minWidth, height: minHeight),
                maximumSize: CGSize(width: maxWidth, height: maxHeight),
                resizingRestrictions: .uniform
            )
            liveScene.requestGeometryUpdate(relaxed)
            visionGeometryTask = nil
        }
    }
    #endif

    #if os(macOS) || os(visionOS)
    private func scheduleMainWindowSuppressionIfNeeded() {
        guard !appState.isMainWindowSuppressedForPlayer else { return }
        appState.isMainWindowSuppressedForPlayer = true
        dismissWindow(id: "main")
    }

    private func scheduleMainWindowRestoreIfNeeded() {
        guard appState.isMainWindowSuppressedForPlayer else { return }
        openWindow(id: "main")
        appState.isMainWindowSuppressedForPlayer = false
    }
    #endif

    #if os(visionOS)
    private func openEnvironment(_ asset: EnvironmentAsset) async {
        // Skip if this asset is already active and the space is open
        if asset.id == appState.selectedEnvironmentAsset?.id && appState.isImmersiveSpaceOpen {
            return
        }
        await dismissImmersiveIfNeeded(reason: .switchingEnvironment)
        await appState.activateEnvironmentAsset(asset)
        await openImmersiveSpaceIfPossible(for: asset)
    }

    private func openImmersiveSpaceIfPossible(for asset: EnvironmentAsset) async {
        guard appState.beginImmersiveTransition() else { return }
        let immersiveSpaceID = await appState.environmentCatalogManager.immersiveSpaceID(for: asset)
        let result = await openImmersiveSpace(id: immersiveSpaceID)
        switch result {
        case .opened:
            appState.spatialAudioManager.enterImmersiveMode()
        case .error, .userCancelled:
            appState.cancelImmersiveTransition()
        @unknown default:
            appState.cancelImmersiveTransition()
        }
    }

    private func dismissImmersiveIfNeeded(reason: ImmersiveDismissReason) async {
        guard appState.isImmersiveSpaceOpen else { return }
        guard appState.beginImmersiveTransition() else { return }
        appState.stageImmersiveDismiss(reason: reason)
        appState.spatialAudioManager.exitImmersiveMode()
        await dismissImmersiveSpace()
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) async {
        switch phase {
        case .background:
            await dismissImmersiveIfNeeded(reason: .suspension)
        case .active:
            guard appState.consumeSuspendedImmersiveRestoreRequest() else { return }
            guard let selectedAsset = appState.selectedEnvironmentAsset else { return }
            await openImmersiveSpaceIfPossible(for: selectedAsset)
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func handleMemoryPressureWarning() async {
        guard appState.isImmersiveSpaceOpen else { return }
        playbackMessage = "Memory pressure detected. Closed immersive space to stabilize playback."
        await dismissImmersiveIfNeeded(reason: .memoryPressure)
    }

    private func updateAPMPInjector() {
        let mode = engine.stereoMode
        guard activeEngine == .avPlayer, let player = avPlayer,
              appState.isImmersiveSpaceOpen else {
            apmpInjector.stop()
            isAPMPActive = false
            appState.activeVideoRenderer = nil
            return
        }
        switch mode {
        case .sideBySide:
            apmpInjector.start(player: player, mode: .sideBySide)
            isAPMPActive = true
            appState.activeVideoRenderer = apmpInjector.videoRenderer
        case .overUnder:
            apmpInjector.start(player: player, mode: .overUnder)
            isAPMPActive = true
            appState.activeVideoRenderer = apmpInjector.videoRenderer
        default:
            apmpInjector.stop()
            isAPMPActive = false
            appState.activeVideoRenderer = nil
        }
    }
    #endif

    private func evaluateCapabilities(for stream: StreamInfo) {
        capabilityWarnings = PlayerCapabilityEvaluator.warnings(for: stream)
    }

    private func loadEnvironmentAssets() async {
        environmentAssets = (try? await appState.environmentCatalogManager.fetchAssets()) ?? []
    }

    @MainActor
    private func requestEnvironmentPicker() {
        environmentAssetsTask?.cancel()
        #if os(visionOS)
        isShowingEnvironmentPicker = true
        #endif
        environmentAssetsTask = Task { await loadEnvironmentAssets() }
    }

    private func startProgressPersistence() {
        progressPersistTask?.cancel()
        progressPersistTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await saveWatchProgress()
            }
        }
    }

    private func stopProgressPersistence() {
        progressPersistTask?.cancel()
        progressPersistTask = nil
    }

    @MainActor
    private func persistCurrentWatchProgress() {
        guard let history = makeWatchProgressSnapshot() else { return }
        Task {
            do {
                try await appState.database.saveWatchHistory(history)
                await MainActor.run {
                    NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
                }
            } catch {
                return
            }
        }
    }

    @MainActor
    private func makeWatchProgressSnapshot() -> WatchHistory? {
        guard let mediaId else { return nil }
        guard engine.duration > 0 else { return nil }

        return WatchHistory(
            id: episodeId.map { "\(mediaId)-\($0)-progress" } ?? "\(mediaId)-progress",
            mediaId: mediaId,
            episodeId: episodeId,
            title: mediaTitle ?? currentStream.fileName,
            progress: engine.currentTime,
            duration: engine.duration,
            quality: currentStream.quality.rawValue,
            debridService: currentStream.debridService,
            streamURL: currentStream.streamURL.absoluteString,
            watchedAt: Date(),
            isCompleted: engine.currentTime / max(engine.duration, 1) > 0.9
        )
    }

    @MainActor
    private func saveWatchProgress() async {
        guard let history = makeWatchProgressSnapshot() else { return }
        do {
            try await appState.database.saveWatchHistory(history)
            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
        } catch {
            return
        }
    }

    private func loadResumeTarget() async -> TimeInterval? {
        guard let mediaId else { return nil }
        let history = try? await appState.database.fetchWatchHistory(mediaId: mediaId, episodeId: episodeId)
        return WatchProgressResumePolicy.resumeTime(for: history)
    }

    private func loadPlayerEngineStrategy() async -> PlayerEngineStrategy {
        let raw = (try? await appState.settingsManager.getString(key: SettingsKeys.playerEngineStrategy)) ?? ""
        return PlayerEngineStrategy(rawValue: raw) ?? .compatibility
    }

    @MainActor
    private func seekAVPlayer(_ player: AVPlayer, to seconds: TimeInterval) async {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            guard playbackState == .playing else { return }
            guard !isScrubbing else { return }
            guard !isShowingSubtitlePicker && !isShowingAudioPicker else { return }
            performOptionalAnimation(.easeInOut(duration: 0.25)) {
                isShowingControls = false
            }
        }
    }

    private func loadSubtitleAppearance() async {
        let storedSize = (try? await appState.settingsManager.getString(key: SettingsKeys.subtitleFontSize))
            .flatMap(Double.init)
        subtitleFontSize = storedSize.map { max(16, min(48, $0)) } ?? 24
    }

    private func performOptionalAnimation(_ animation: Animation, updates: () -> Void) {
        if motionAnimationsEnabled {
            withAnimation(animation, updates)
        } else {
            updates()
        }
    }

    private var systemClosedCaptioningEnabled: Bool {
        let mediaAccessibilityEnabled = MACaptionAppearanceGetDisplayType(.user) == .alwaysOn
        #if canImport(UIKit)
        return mediaAccessibilityEnabled || UIAccessibility.isClosedCaptioningEnabled
        #else
        return mediaAccessibilityEnabled
        #endif
    }

    private var systemPreferredCaptionLanguages: [String] {
        let captionLanguages = (MACaptionAppearanceCopySelectedLanguages(.user).takeRetainedValue() as NSArray)
            .compactMap { $0 as? String }
        if !captionLanguages.isEmpty {
            return captionLanguages
        }
        return Locale.preferredLanguages
    }

    static func subtitleMutationShouldRun(requestedStreamID: String, currentStreamID: String?) -> Bool {
        currentStreamID == requestedStreamID
    }

    static func shouldAnimateForAccessibility(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func automaticSubtitleLanguageCodes(
        configuredLanguageSetting: String?,
        systemPreferredLanguages: [String],
        closedCaptioningEnabled: Bool
    ) -> [String] {
        let configuredCodes = configuredLanguageSetting?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
        let systemCodes = systemPreferredLanguages.reduce(into: [String]()) { result, language in
            let normalized = language
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else { return }
            let baseCode = normalized
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map(String.init) ?? normalized
            guard !baseCode.isEmpty, !result.contains(baseCode) else { return }
            result.append(baseCode)
        }

        if closedCaptioningEnabled, !systemCodes.isEmpty {
            return systemCodes + configuredCodes.filter { !systemCodes.contains($0) }
        }

        if !configuredCodes.isEmpty {
            return configuredCodes
        }

        if !systemCodes.isEmpty {
            return systemCodes
        }

        return ["en"]
    }

    private func resetSubtitleStateForStreamTransition() {
        subtitleCatalogTask?.cancel()
        subtitleCatalogTask = nil
        subtitleDownloadTask?.cancel()
        subtitleDownloadTask = nil
        subtitleSelectionMode = .automaticPreferred
        clearTransientSubtitleState(removeDownloadedFile: true, clearCurrentItemSelection: true)
    }

    private func preferredLanguageCodes(from rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func matchesPreferredLanguage(
        _ option: AVMediaSelectionOption,
        preferredLanguages: [String]
    ) -> Bool {
        let localeIdentifier = option.locale?.identifier.lowercased() ?? ""
        let extendedTag = option.extendedLanguageTag?.lowercased() ?? ""

        return preferredLanguages.contains { preferred in
            localeIdentifier.hasPrefix(preferred) || extendedTag.hasPrefix(preferred)
        }
    }

    private func clearTransientSubtitleState(
        removeDownloadedFile: Bool,
        clearCurrentItemSelection: Bool = false
    ) {
        if clearCurrentItemSelection, let avSubtitleGroup {
            avPlayer?.currentItem?.select(nil, in: avSubtitleGroup)
        }

        subtitleCandidates = []
        subtitleCatalogMessage = nil
        isRefreshingSubtitleCatalog = false
        isDownloadingSubtitle = false
        selectedAVSubtitleID = nil
        engine.loadExternalSubtitles([])
        engine.selectSubtitleTrack(-1)

        guard removeDownloadedFile, let subtitleFileURL = downloadedSubtitleFileURL else { return }
        try? FileManager.default.removeItem(at: subtitleFileURL)
        downloadedSubtitleFileURL = nil
    }

    private func autoLoadSubtitlesIfEnabled(for stream: StreamInfo) async {
        guard stream.id == currentStream.id else { return }
        let autoSearch = (try? await appState.settingsManager.getBool(
            key: SettingsKeys.subtitleAutoSearch,
            default: true
        )) ?? true
        guard autoSearch else { return }

        guard let apiKey = (try? await appState.settingsManager.getString(key: SettingsKeys.openSubtitlesApiKey))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return
        }

        let languageSetting = try? await appState.settingsManager.getString(key: SettingsKeys.subtitleLanguage)
        let languages = Self.automaticSubtitleLanguageCodes(
            configuredLanguageSetting: languageSetting,
            systemPreferredLanguages: systemPreferredCaptionLanguages,
            closedCaptioningEnabled: systemClosedCaptioningEnabled
        )
        let query = subtitleSearchQuery(from: stream.fileName)
        guard !query.isEmpty else { return }

        let service = resolvedSubtitleService(apiKey: apiKey)

        do {
            let subtitle = try await service.downloadFirstMatch(
                query: query,
                languages: languages
            )
            guard !Task.isCancelled,
                  Self.subtitleMutationShouldRun(
                      requestedStreamID: stream.id,
                      currentStreamID: currentStream.id
                  ) else {
                if let staleURL = subtitle.downloadURL {
                    try? FileManager.default.removeItem(at: staleURL)
                }
                return
            }
            if let previousURL = downloadedSubtitleFileURL {
                try? FileManager.default.removeItem(at: previousURL)
            }
            downloadedSubtitleFileURL = subtitle.downloadURL
            if let avSubtitleGroup {
                avPlayer?.currentItem?.select(nil, in: avSubtitleGroup)
            }
            selectedAVSubtitleID = nil
            engine.loadExternalSubtitles([subtitle])
            engine.selectSubtitleTrack(0)
        } catch {
            guard !Task.isCancelled,
                  Self.subtitleMutationShouldRun(
                      requestedStreamID: stream.id,
                      currentStreamID: currentStream.id
                  ) else {
                return
            }
            subtitleCatalogMessage = "Automatic subtitle download failed. Open subtitles to retry. \(error.localizedDescription)"
        }
    }

    private func resolvedSubtitleService(apiKey: String) -> OpenSubtitlesService {
        if let existing = subtitleService, subtitleServiceAPIKey == apiKey {
            return existing
        }
        let service = OpenSubtitlesService(apiKey: apiKey)
        subtitleService = service
        subtitleServiceAPIKey = apiKey
        return service
    }

    private func subtitleSearchQuery(from fileName: String) -> String {
        let withoutExtension = (fileName as NSString).deletingPathExtension
        let cleaned = withoutExtension.replacingOccurrences(
            of: "[._]+",
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func featureChip(title: String, symbol: String?) -> some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }

    private func subtitleTrackRow(name: String, language: String?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func subtitleCandidateRow(_ subtitle: Subtitle) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle.fileName)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    GlassTag(text: subtitle.language.uppercased(), weight: .semibold)
                    if let rating = subtitle.rating {
                        Label("\(rating, specifier: "%.1f")", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let downloads = subtitle.downloadCount {
                        Label("\(downloads)", systemImage: "arrow.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        }
    }

    private func hydrateFallbackAudioTrack(for stream: StreamInfo) {
        if engine.audioTracks.isEmpty {
            engine.loadAudioTracks([
                .init(
                    id: 0,
                    name: "Auto (\(stream.audio.rawValue.uppercased()))",
                    language: nil,
                    codec: stream.codec.rawValue
                ),
            ], selectedTrackID: 0)
        }
    }

    @MainActor
    private func refreshKSAudioTracks(for stream: StreamInfo) {
        guard let coordinator = ksPlayerCoordinator,
              isCurrentKSPlayerCoordinator(coordinator),
              let player = coordinator.playerLayer?.player else {
            return
        }

        let audioTracks = player.tracks(mediaType: .audio)
        guard !audioTracks.isEmpty else {
            hydrateFallbackAudioTrack(for: stream)
            return
        }

        let trackInfos = audioTracks.map { track in
            VPPlayerEngine.TrackInfo(
                id: Int(track.trackID),
                name: track.name.isEmpty ? track.description : track.name,
                language: track.languageCode,
                codec: nil
            )
        }
        let selectedTrackID = audioTracks.first(where: { $0.isEnabled }).map { Int($0.trackID) }
        engine.loadAudioTracks(trackInfos, selectedTrackID: selectedTrackID)
    }

    private func refreshKSAudioTracks(from coordinator: KSVideoPlayer.Coordinator) {
        guard isCurrentKSPlayerCoordinator(coordinator) else { return }
        let tracks = coordinator.playerLayer?.player.tracks(mediaType: .audio) ?? []
        guard !tracks.isEmpty else { return }

        let trackInfos = tracks.map { track in
            VPPlayerEngine.TrackInfo(
                id: Int(track.trackID),
                name: track.name.isEmpty ? track.description : track.name,
                language: track.languageCode,
                codec: nil
            )
        }
        let selectedTrackID = tracks.first(where: { $0.isEnabled }).map { Int($0.trackID) }
        engine.loadAudioTracks(trackInfos, selectedTrackID: selectedTrackID)
    }

    @MainActor
    private func refreshAVMediaOptions(for player: AVPlayer) async {
        guard isCurrentAVPlayer(player) else { return }
        guard let item = player.currentItem else {
            avAudioOptions = []
            avSubtitleOptions = []
            avAudioGroup = nil
            avSubtitleGroup = nil
            selectedAVAudioID = nil
            selectedAVSubtitleID = nil
            return
        }

        // Audio defaults stay app-driven; subtitle defaults can honor the
        // system closed-caption preference when the user has not set one.
        let preferredAudioLanguages = preferredLanguageCodes(
            from: (try? await appState.settingsManager.getString(key: SettingsKeys.audioLanguage)) ?? "en"
        )
        let preferredSubtitleLanguages = Self.automaticSubtitleLanguageCodes(
            configuredLanguageSetting: try? await appState.settingsManager.getString(key: SettingsKeys.subtitleLanguage),
            systemPreferredLanguages: systemPreferredCaptionLanguages,
            closedCaptioningEnabled: systemClosedCaptioningEnabled
        )

        var newAudioGroup: AVMediaSelectionGroup?
        var newAudioOptions: [AVTrackOption] = []
        var newSelectedAVAudioID: String?

        if let audioGroup = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
            guard isCurrentAVPlayer(player) else { return }
            newAudioGroup = audioGroup
            newAudioOptions = audioGroup.options.enumerated().map { index, option in
                AVTrackOption(
                    id: avOptionID(option, index: index),
                    name: option.displayName,
                    language: option.locale?.identifier ?? option.extendedLanguageTag,
                    option: option
                )
            }
            if let selected = item.currentMediaSelection.selectedMediaOption(in: audioGroup),
               let selectedIndex = audioGroup.options.firstIndex(of: selected) {
                newSelectedAVAudioID = avOptionID(selected, index: selectedIndex)
            } else {
                // No explicit audio selection yet — auto-select preferred language if available
                newSelectedAVAudioID = nil
                if let preferredOption = audioGroup.options.first(where: {
                    matchesPreferredLanguage($0, preferredLanguages: preferredAudioLanguages)
                }) {
                    item.select(preferredOption, in: audioGroup)
                    if let idx = audioGroup.options.firstIndex(of: preferredOption) {
                        newSelectedAVAudioID = avOptionID(preferredOption, index: idx)
                    }
                }
            }
        }

        guard isCurrentAVPlayer(player) else { return }
        avAudioGroup = newAudioGroup
        avAudioOptions = newAudioOptions
        selectedAVAudioID = newSelectedAVAudioID

        var newSubtitleGroup: AVMediaSelectionGroup?
        var newSubtitleOptions: [AVTrackOption] = []
        var newSelectedAVSubtitleID: String?
        var newSubtitlesEnabled = engine.subtitlesEnabled

        if let subtitleGroup = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
            guard isCurrentAVPlayer(player) else { return }
            newSubtitleGroup = subtitleGroup
            newSubtitleOptions = subtitleGroup.options.enumerated().map { index, option in
                AVTrackOption(
                    id: avOptionID(option, index: index),
                    name: option.displayName,
                    language: option.locale?.identifier ?? option.extendedLanguageTag,
                    option: option
                )
            }
            if let selected = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup),
               let selectedIndex = subtitleGroup.options.firstIndex(of: selected) {
                newSelectedAVSubtitleID = avOptionID(selected, index: selectedIndex)
                newSubtitlesEnabled = true
            } else {
                newSelectedAVSubtitleID = nil
                if subtitleSelectionMode == .automaticPreferred {
                    // No explicit subtitle selection yet — auto-select preferred language if available
                    if let preferredOption = subtitleGroup.options.first(where: {
                        matchesPreferredLanguage($0, preferredLanguages: preferredSubtitleLanguages)
                    }) {
                        item.select(preferredOption, in: subtitleGroup)
                        if let idx = subtitleGroup.options.firstIndex(of: preferredOption) {
                            newSelectedAVSubtitleID = avOptionID(preferredOption, index: idx)
                            newSubtitlesEnabled = true
                        }
                    }
                }
            }
        }

        guard isCurrentAVPlayer(player) else { return }
        avSubtitleGroup = newSubtitleGroup
        avSubtitleOptions = newSubtitleOptions
        selectedAVSubtitleID = newSelectedAVSubtitleID
        engine.subtitlesEnabled = newSubtitlesEnabled
    }

    @MainActor
    private func loadChapters(from player: AVPlayer) async {
        guard isCurrentAVPlayer(player) else { return }
        guard let item = player.currentItem else {
            engine.loadChapters([])
            return
        }

        do {
            let groups = try await item.asset.load(.availableChapterLocales)
            guard let locale = groups.first else {
                guard isCurrentAVPlayer(player) else { return }
                engine.loadChapters([])
                return
            }
            let chapterMetadata = try await item.asset.loadChapterMetadataGroups(
                bestMatchingPreferredLanguages: [locale.identifier]
            )
            var chapters: [VPPlayerEngine.ChapterInfo] = []
            for (index, group) in chapterMetadata.enumerated() {
                let start = group.timeRange.start.seconds
                let end = (group.timeRange.start + group.timeRange.duration).seconds
                guard start.isFinite, end.isFinite else { continue }
                var title = "Chapter \(index + 1)"
                if let firstItem = group.items.first,
                   let value = try? await firstItem.load(.stringValue) {
                    title = value
                }
                chapters.append(VPPlayerEngine.ChapterInfo(
                    id: index,
                    title: title,
                    startTime: start,
                    endTime: end
                ))
            }
            guard isCurrentAVPlayer(player) else { return }
            engine.loadChapters(chapters)
        } catch {
            guard isCurrentAVPlayer(player) else { return }
            engine.loadChapters([])
        }
    }

    private func avOptionID(_ option: AVMediaSelectionOption, index: Int) -> String {
        let language = option.locale?.identifier ?? option.extendedLanguageTag ?? "und"
        return "\(language)-\(option.displayName)-\(index)"
    }

    private func selectAVSubtitle(_ track: AVTrackOption) {
        guard let avSubtitleGroup else { return }
        cancelSubtitleDownloadTask()
        subtitleSelectionMode = .manual
        clearTransientSubtitleState(removeDownloadedFile: true)
        avPlayer?.currentItem?.select(track.option, in: avSubtitleGroup)
        selectedAVSubtitleID = track.id
        engine.selectSubtitleTrack(-1)
        engine.subtitlesEnabled = true
    }

    private func selectExternalSubtitle(index: Int) {
        cancelSubtitleDownloadTask()
        subtitleSelectionMode = .manual
        if let avSubtitleGroup {
            avPlayer?.currentItem?.select(nil, in: avSubtitleGroup)
        }
        selectedAVSubtitleID = nil
        engine.selectSubtitleTrack(index)
    }

    private func selectSubtitlesOff() {
        cancelSubtitleDownloadTask()
        subtitleSelectionMode = .manual
        clearTransientSubtitleState(removeDownloadedFile: true)
        if let avSubtitleGroup {
            avPlayer?.currentItem?.select(nil, in: avSubtitleGroup)
        }
        selectedAVSubtitleID = nil
        engine.selectSubtitleTrack(-1)
        isShowingSubtitlePicker = false
    }

    private func selectAVAudio(_ track: AVTrackOption) {
        guard let avAudioGroup else { return }
        avPlayer?.currentItem?.select(track.option, in: avAudioGroup)
        selectedAVAudioID = track.id
    }

    private func selectEngineAudio(_ track: VPPlayerEngine.TrackInfo) {
        engine.selectAudioTrack(track.id)

        guard let coordinator = ksPlayerCoordinator else { return }
        guard let mediaTrack = coordinator.playerLayer?.player.tracks(mediaType: .audio).first(where: {
            Int($0.trackID) == track.id
        }) else {
            return
        }

        coordinator.playerLayer?.player.select(track: mediaTrack)
        refreshKSAudioTracks(from: coordinator)
    }


    private func scheduleSubtitleCatalogRefresh(for stream: StreamInfo) {
        subtitleCatalogTask?.cancel()
        subtitleCatalogTask = Task { await refreshSubtitleCatalog(for: stream) }
    }

    private func cancelSubtitleDownloadTask() {
        subtitleDownloadTask?.cancel()
        subtitleDownloadTask = nil
    }

    private func cancelVisionLifecycleTasksOnClose() {
        scenePhaseTask?.cancel()
        scenePhaseTask = nil
        memoryPressureTask?.cancel()
        memoryPressureTask = nil
    }

    private func refreshSubtitleCatalog(for stream: StreamInfo) async {
        isRefreshingSubtitleCatalog = true
        defer { isRefreshingSubtitleCatalog = false }

        guard let apiKey = (try? await appState.settingsManager.getString(key: SettingsKeys.openSubtitlesApiKey))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            subtitleCandidates = []
            subtitleCatalogMessage = "Set an OpenSubtitles API key in Settings to browse subtitle options."
            return
        }

        let languageSetting = try? await appState.settingsManager.getString(key: SettingsKeys.subtitleLanguage)
        let languages = Self.automaticSubtitleLanguageCodes(
            configuredLanguageSetting: languageSetting,
            systemPreferredLanguages: systemPreferredCaptionLanguages,
            closedCaptioningEnabled: systemClosedCaptioningEnabled
        )
        let query = subtitleSearchQuery(from: stream.fileName)
        guard !query.isEmpty else {
            subtitleCandidates = []
            subtitleCatalogMessage = "Could not build subtitle query for this stream."
            return
        }

        let service = resolvedSubtitleService(apiKey: apiKey)

        do {
            var candidates = try await service.search(
                imdbId: mediaId?.hasPrefix("tt") == true ? mediaId : nil,
                query: query,
                languages: languages
            )
            candidates = candidates.filter { $0.fileId != nil && $0.isSupportedSubtitle }
            if stream.id != currentStream.id {
                return
            }
            subtitleCandidates = Array(candidates.prefix(30))
            subtitleCatalogMessage = subtitleCandidates.isEmpty ? "No subtitle matches found." : nil
        } catch {
            if stream.id != currentStream.id {
                return
            }
            subtitleCandidates = []
            subtitleCatalogMessage = error.localizedDescription
        }
    }


    private func scheduleSubtitleDownload(_ subtitle: Subtitle, streamID: String) {
        subtitleDownloadTask?.cancel()
        subtitleDownloadTask = nil
        subtitleDownloadTask = Task { await downloadAndSelectSubtitle(subtitle, streamID: streamID) }
        // subtitleDownloadTask = Task { await downloadAndSelectSubtitle(subtitle, streamID: currentStream.id) }
    }

    private func downloadAndSelectSubtitle(_ subtitle: Subtitle, streamID: String) async {
        guard streamID == currentStream.id else { return }
        guard let fileId = subtitle.fileId else { return }
        guard subtitle.isSupportedSubtitle else {
            subtitleCatalogMessage = "That subtitle format is not supported for rendering."
            return
        }
        isDownloadingSubtitle = true
        defer { isDownloadingSubtitle = false }

        guard let apiKey = (try? await appState.settingsManager.getString(key: SettingsKeys.openSubtitlesApiKey))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            subtitleCatalogMessage = "OpenSubtitles API key is required."
            return
        }

        let service = resolvedSubtitleService(apiKey: apiKey)

        do {
            let content = try await service.downloadSubtitle(fileId: fileId)
            let localURL = try writeExternalSubtitle(content: content, source: subtitle)
            guard !Task.isCancelled,
                  Self.subtitleMutationShouldRun(
                      requestedStreamID: streamID,
                      currentStreamID: currentStream.id
                  ) else {
                try? FileManager.default.removeItem(at: localURL)
                return
            }

            if let previousURL = downloadedSubtitleFileURL {
                try? FileManager.default.removeItem(at: previousURL)
            }
            downloadedSubtitleFileURL = localURL
            subtitleSelectionMode = .manual

            var hydrated = subtitle
            hydrated.url = localURL.absoluteString

            if let avSubtitleGroup {
                avPlayer?.currentItem?.select(nil, in: avSubtitleGroup)
            }
            selectedAVSubtitleID = nil
            engine.loadExternalSubtitles([hydrated])
            engine.selectSubtitleTrack(0)
            isShowingSubtitlePicker = false
            subtitleCatalogMessage = nil
        } catch {
            subtitleCatalogMessage = error.localizedDescription
        }
    }

    private func writeExternalSubtitle(content: String, source: Subtitle) throws -> URL {
        let format = source.format.isSupportedSubtitle
            ? source.format
            : SubtitleFormat.parse(from: source.fileName)
        guard format.isSupportedSubtitle else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format.fileExtension)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

}

// MARK: - Immersive Control Notification Handlers (visionOS)

#if os(visionOS)
/// Extracted ViewModifier to keep the PlayerView body expression small enough
/// for the Swift compiler's type-checker. Listens for all immersive control
/// notifications posted by `ImmersivePlayerControlsView` and dispatches them
/// to the provided closures.
private struct ImmersiveControlHandlers: ViewModifier {
    let onToggleControls: () -> Void
    let onTogglePlayPause: () -> Void
    let onSeekBack: () -> Void
    let onSeekForward: () -> Void
    let onSeekToPercent: (Double) -> Void
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onCycleRate: () -> Void
    let onToggleSubtitles: () -> Void
    let onToggleAudio: () -> Void
    let onRequestEnvironmentSwitch: () -> Void
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .immersiveTapCatcherDidFire)) { _ in
                onToggleControls()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlTogglePlayPause)) { _ in
                onTogglePlayPause()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekBack)) { _ in
                onSeekBack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekForward)) { _ in
                onSeekForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlSeekToPercent)) { notification in
                if let percent = (notification.object as? NSNumber)?.doubleValue {
                    onSeekToPercent(percent)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlPreviousChapter)) { _ in
                onPreviousChapter()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlNextChapter)) { _ in
                onNextChapter()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlCycleRate)) { _ in
                onCycleRate()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlToggleSubtitles)) { _ in
                onToggleSubtitles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlToggleAudio)) { _ in
                onToggleAudio()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlRequestEnvironmentSwitch)) { _ in
                onRequestEnvironmentSwitch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .immersiveControlDismiss)) { _ in
                onDismiss()
            }
    }
}
#endif
