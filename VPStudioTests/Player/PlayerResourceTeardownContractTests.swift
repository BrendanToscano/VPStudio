import Foundation
import Testing
@testable import VPStudio

@Suite("Player Resource Teardown Contracts")
struct PlayerResourceTeardownContractTests {
    @Test
    func avPlayerSurfaceViewClearsPlayerOnDismantle() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/AVPlayerSurfaceView.swift")
        #expect(source.contains("static func dismantleNSView"))
        #expect(source.contains("static func dismantleUIView"))
        #expect(source.contains("nsView.player = nil"))
        #expect(source.contains("uiView.player = nil"))
    }

    @Test
    func apmpRendererClearsDisplayLayerOnDismantle() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/APMPRendererView.swift")
        #expect(source.contains("static func dismantleUIView"))
        #expect(source.contains("func clearDisplayLayer()"))
        #expect(source.contains("hostedLayer?.sampleBufferRenderer.flush()"))
        #expect(source.contains("hostedLayer?.removeFromSuperlayer()"))
    }

    @Test
    func headTrackerCancelsPollTaskInDeinit() throws {
        let source = try contents(of: "VPStudio/Services/Player/Immersive/HeadTracker.swift")
        #expect(source.contains("deinit"))
        #expect(source.contains("pollTask?.cancel()"))
    }

    @Test
    func apmpInjectorRunsFullStopPathInDeinit() throws {
        let source = try contents(of: "VPStudio/Services/Player/Immersive/APMPInjector.swift")
        #expect(source.contains("deinit"))
        #expect(source.contains("stop()"))
    }

    @Test
    func playerViewChecksCancellationDuringAsyncEnginePreparation() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("let prepared = try await ksPlayerEngine.prepare(stream: stream)\n                    try Task.checkCancellation()"))
        #expect(source.contains("let prepared = try await avPlayerEngine.prepare(stream: stream)\n                    try Task.checkCancellation()"))
        #expect(source.contains("catch is CancellationError"))
        #expect(source.contains("guard Self.preparePlaybackShouldRun("))
        #expect(source.contains("cleanupPlayback(clearSession: false)"))
        #expect(source.contains("@State private var preparePlaybackTask: Task<Void, Never>?"))
        #expect(source.contains("@State private var activePreparePlaybackID: UUID?"))
        #expect(source.contains("activePreparePlaybackID = preparationID"))
        #expect(source.contains("preparePlaybackTask?.cancel()"))
        #expect(source.contains("preparePlaybackTask = Task { await preparePlayback(for: currentStream, preparationID: preparationID) }"))
        #expect(source.contains("preparePlaybackTask = Task { await preparePlayback(for: stream, preparationID: preparationID) }"))
        #expect(source.contains("static func preparePlaybackShouldRun(requestedPreparationID: UUID, activePreparationID: UUID?) -> Bool"))
    }

    @Test
    func playerViewAssignsNewPreparationIDBeforeCancellingPreviousTask() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        let taskBody = try section(
            from: ".task(id: currentStream.id) {",
            to: ".onAppear {",
            in: source
        )
        let assignRange = try requiredRange(of: "activePreparePlaybackID = preparationID", in: taskBody)
        let cancelRange = try requiredRange(of: "preparePlaybackTask?.cancel()", in: taskBody)
        #expect(assignRange.lowerBound < cancelRange.lowerBound)
    }

    @Test
    func playerViewCancelsSubtitleDownloadTasksAndGuardsStreamMutation() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("@State private var subtitleDownloadTask: Task<Void, Never>?"))
        #expect(source.contains("@State private var subtitleCatalogTask: Task<Void, Never>?"))
        #expect(source.contains("@State private var initialPlayerStateTask: Task<Void, Never>?"))
        #expect(source.contains("initialPlayerStateTask?.cancel()"))
        #expect(source.contains("initialPlayerStateTask = Task { await loadInitialPlayerState() }"))
        #expect(source.contains("subtitleCatalogTask?.cancel()"))
        #expect(source.contains("subtitleCatalogTask = nil"))
        // Subtitle catalog refresh may be inlined or a named helper
        let hasSubtitleRefresh = source.contains("scheduleSubtitleCatalogRefresh") ||
            source.contains("refreshSubtitleCatalog(for:")
        #expect(hasSubtitleRefresh)
        #expect(source.contains("subtitleDownloadTask?.cancel()"))
        #expect(source.contains("subtitleDownloadTask = nil"))
        #expect(source.contains("guard stream.id == currentStream.id else { return }"))
    }

    @Test
    func playerViewResetsSubtitleModeAcrossStreamTransitionsAndRefreshesKeyedSubtitleServices() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("subtitleSelectionMode = .automaticPreferred"))
        #expect(source.contains("if let existing = subtitleService, subtitleServiceAPIKey == apiKey"))
        #expect(source.contains("subtitleServiceAPIKey = apiKey"))
        #expect(source.contains("preferredLanguageCodes("))
        #expect(source.contains("matchesPreferredLanguage("))
    }

    @Test
    func playerViewAppliesEngineAudioSelectionsInsteadOfOnlyMutatingState() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("refreshKSAudioTracks(from: coordinator)"))
        #expect(source.contains("private func selectEngineAudio("))
        #expect(source.contains("coordinator.playerLayer?.player.select(track: mediaTrack)"))
        #expect(source.contains("selectEngineAudio(track)"))
    }

    @Test
    func playerViewClosePlayerCancelsTrackedLoadingTasksAndDismissesWindowBeforeImmersiveTeardown() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        let closePlayerBody = try functionBody(named: "closePlayer", in: source)
        let cleanupRange = try requiredRange(of: "cleanupPlayback(clearSession: true)", in: closePlayerBody)

        for taskName in [
            "initialPlayerStateTask",
            "preparePlaybackTask",
            "subtitleCatalogTask",
            "subtitleDownloadTask"
        ] {
            let cancelRange = try requiredRange(of: "\(taskName)?.cancel()", in: closePlayerBody)
            let clearRange = try requiredRange(of: "\(taskName) = nil", in: closePlayerBody)

            #expect(cancelRange.lowerBound < clearRange.lowerBound)
            #expect(cancelRange.lowerBound < cleanupRange.lowerBound)
            #expect(clearRange.lowerBound < cleanupRange.lowerBound)
        }

        let visionOSBranch = try section(
            from: "#if os(visionOS)",
            to: "#elseif os(macOS)",
            in: closePlayerBody
        )

        #expect(containsIgnoringWhitespace(
            visionOSBranch,
            "if PlayerLifecyclePolicy.closesDedicatedPlayerWindowOnBack { dismissWindow(id: \"player\") } if PlayerLifecyclePolicy.dismissesCurrentPresentationOnBack { dismiss() }"
        ))

        let dismissWindowRange = try requiredRange(
            of: "if PlayerLifecyclePolicy.closesDedicatedPlayerWindowOnBack",
            in: visionOSBranch
        )
        let dismissPresentationRange = try requiredRange(
            of: "if PlayerLifecyclePolicy.dismissesCurrentPresentationOnBack",
            in: visionOSBranch
        )
        let immersiveTaskRange = try requiredRange(of: "Task {", in: visionOSBranch)
        let immersiveDismissRange = try requiredRange(
            of: "await dismissImmersiveIfNeeded(reason: .playerClosed)",
            in: visionOSBranch
        )

        #expect(dismissWindowRange.lowerBound < dismissPresentationRange.lowerBound)
        #expect(dismissPresentationRange.lowerBound < immersiveTaskRange.lowerBound)
        #expect(immersiveTaskRange.lowerBound < immersiveDismissRange.lowerBound)
    }

    @Test
    func playerViewOnDisappearCancelsTrackedTasksBeforeCleanup() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        let onDisappearSection = try section(
            from: ".onDisappear {",
            to: "RuntimeMemoryDiagnostics.capture(",
            in: source
        )
        let cleanupRange = try requiredRange(of: "cleanupPlayback()", in: onDisappearSection)

        for taskName in [
            "initialPlayerStateTask",
            "preparePlaybackTask",
            "subtitleCatalogTask",
            "subtitleDownloadTask"
        ] {
            let cancelRange = try requiredRange(of: "\(taskName)?.cancel()", in: onDisappearSection)
            #expect(cancelRange.lowerBound < cleanupRange.lowerBound)
        }
    }

    @Test
    func playerViewLoadInitialStateBailsOutWhenCancelledBeforeSideEffects() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        let loadInitialBody = try functionBody(named: "loadInitialPlayerState", in: source)

        #expect(containsIgnoringWhitespace(
            loadInitialBody,
            "guard !Task.isCancelled else { return } streamQueue = await PlayerSessionRouting.playbackQueue("
        ))
        #expect(containsIgnoringWhitespace(
            loadInitialBody,
            "await loadEnvironmentAssets() guard !Task.isCancelled else { return } startProgressPersistence()"
        ))
        #expect(containsIgnoringWhitespace(
            loadInitialBody,
            "await refreshSubtitleCatalog(for: currentStream) guard !Task.isCancelled else { return } await autoLoadSubtitlesIfEnabled(for: currentStream)"
        ))
        #expect(containsIgnoringWhitespace(
            loadInitialBody,
            "await autoLoadSubtitlesIfEnabled(for: currentStream) guard !Task.isCancelled else { return } scheduleControlsHide()"
        ))
    }

    @Test
    func playerViewBindsPlayPauseIconToControlPresentationMapper() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("private var playPausePresentation: PlayerControlPresentation"))
        #expect(source.contains("PlayerControlPresentationMapper.playPause("))
        #expect(source.contains("playbackState: playbackState"))
        #expect(source.contains("isCurrentlyPlaying: isCurrentlyPlaying"))
        #expect(source.contains("Image(systemName: playPausePresentation.symbolName)"))
        #expect(source.contains(".accessibilityLabel(playPausePresentation.label)"))
        #expect(source.contains(".accessibilityValue(playPausePresentation.accessibilityValue)"))
    }

    @Test
    func playerViewSeedsAndResetsSessionTitleState() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("engine.currentTitle = mediaTitle ?? currentStream.fileName"))
        #expect(source.contains("engine.currentTitle = mediaTitle ?? stream.fileName"))
        #expect(source.contains("engine.resetSessionState()"))
    }

    @Test
    func playerViewEnvironmentSwitchOpensThePicker() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("onRequestEnvironmentSwitch: { requestEnvironmentPicker() }"))
        #expect(source.contains("private func requestEnvironmentPicker()"))
        #expect(source.contains("isShowingEnvironmentPicker = true"))
    }

    @Test
    func playerViewCoalescesNotificationDrivenRefreshTasks() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("@State private var environmentAssetsTask: Task<Void, Never>?"))
        #expect(source.contains("environmentAssetsTask?.cancel()"))
        #expect(source.contains("environmentAssetsTask = Task { await loadEnvironmentAssets() }"))
        #expect(source.contains("@State private var scenePhaseTask: Task<Void, Never>?"))
        #expect(source.contains("scenePhaseTask?.cancel()"))
        #expect(source.contains("scenePhaseTask = Task { await handleScenePhaseChange(phase) }"))
        #expect(source.contains("@State private var memoryPressureTask: Task<Void, Never>?"))
        #expect(source.contains("memoryPressureTask?.cancel()"))
        #expect(source.contains("memoryPressureTask = Task { await handleMemoryPressureWarning() }"))
    }

    @Test
    func playerViewHasControlsOverlayAndTransportLayout() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        // Verify player has the core control overlays and transport elements
        #expect(source.contains(".overlay(alignment: .bottom)") || source.contains("transportBar") || source.contains("transportControls"))
        // Cinematic policies exist as separate files; usage may be direct or indirect
        let cinematicPolicySource = try contents(of: "VPStudio/Views/Windows/Player/PlayerCinematicVisualPolicy.swift")
        #expect(cinematicPolicySource.contains("enum PlayerCinematicVisualPolicy"))
        let chromePolicySource = try contents(of: "VPStudio/Views/Windows/Player/PlayerCinematicChromePolicy.swift")
        #expect(chromePolicySource.contains("enum PlayerCinematicChromePolicy"))
    }

    @Test
    func playerViewTeardownCancelsNotificationTasksBeforeCleanup() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        let onDisappearSection = try section(
            from: ".onDisappear {",
            to: "RuntimeMemoryDiagnostics.capture(",
            in: source
        )
        let onDisappearCleanupRange = try requiredRange(of: "cleanupPlayback()", in: onDisappearSection)

        for taskName in [
            "environmentAssetsTask",
            "scenePhaseTask",
            "memoryPressureTask",
        ] {
            let cancelRange = try requiredRange(of: "\(taskName)?.cancel()", in: onDisappearSection)
            #expect(cancelRange.lowerBound < onDisappearCleanupRange.lowerBound)
        }

        let closePlayerBody = try functionBody(named: "closePlayer", in: source)
        let closePlayerCleanupRange = try requiredRange(of: "cleanupPlayback(clearSession: true)", in: closePlayerBody)

        for taskName in [
            "environmentAssetsTask",
        ] {
            let cancelRange = try requiredRange(of: "\(taskName)?.cancel()", in: closePlayerBody)
            let clearRange = try requiredRange(of: "\(taskName) = nil", in: closePlayerBody)
            #expect(cancelRange.lowerBound < clearRange.lowerBound)
            #expect(clearRange.lowerBound < closePlayerCleanupRange.lowerBound)
        }

        #expect(closePlayerBody.contains("cancelVisionLifecycleTasksOnClose()"))

        let visionTaskCancelBody = try functionBody(
            named: "cancelVisionLifecycleTasksOnClose",
            in: source
        )
        for taskName in [
            "scenePhaseTask",
            "memoryPressureTask",
        ] {
            let cancelRange = try requiredRange(of: "\(taskName)?.cancel()", in: visionTaskCancelBody)
            let clearRange = try requiredRange(of: "\(taskName) = nil", in: visionTaskCancelBody)
            #expect(cancelRange.lowerBound < clearRange.lowerBound)
        }
    }

    @Test
    func playerViewUsesHigherCadenceAVPlayerObserverForSubtitleUpdates() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("static let avPlayerPeriodicObserverIntervalSeconds: TimeInterval = 0.25"))
        #expect(source.contains("engine.updateSubtitleText(at: newTime)"))
    }

    @Test
    func playerViewChecksPreparationCancellationBeforeTearingDownCurrentSession() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        let prepareBody = try section(
            from: "private func preparePlayback(for stream: StreamInfo, preparationID: UUID) async {",
            to: "static func audioTrackRefreshShouldRun",
            in: source
        )

        #expect(containsIgnoringWhitespace(
            prepareBody,
            """
            hasPlayedOnce = false
            guard Self.preparePlaybackShouldRun(
                requestedPreparationID: preparationID,
                activePreparationID: activePreparePlaybackID
            ), !Task.isCancelled else {
                return
            }
            cleanupPlayback(clearSession: true)
            """
        ))
    }

    @Test
    func playerViewGuardsAsyncPlaybackCallbacksAgainstStaleSessions() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("private func isCurrentAVPlayer(_ player: AVPlayer) -> Bool"))
        #expect(source.contains("private func isCurrentKSPlayerCoordinator(_ coordinator: KSVideoPlayer.Coordinator) -> Bool"))
        #expect(source.contains("guard self.isCurrentKSPlayerCoordinator(coordinator) else { return }"))
        #expect(source.contains("guard self.isCurrentAVPlayer(player) else { return }"))
        #expect(source.contains("Task { await detectVideoRatio(from: asset, player: player) }"))
        #expect(source.contains("guard isCurrentAVPlayer(player) else { return }"))
        #expect(source.contains("guard isCurrentKSPlayerCoordinator(coordinator) else { return }"))
    }

    @Test
    func playerViewRebuildsSubtitleServiceWhenApiKeyChangesAndClearsSessionCacheOnCleanup() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("@State private var subtitleServiceAPIKey: String?"))
        #expect(source.contains("if let existing = subtitleService, subtitleServiceAPIKey == apiKey"))
        #expect(source.contains("subtitleServiceAPIKey = apiKey"))
        #expect(source.contains("subtitleService = nil"))
        #expect(source.contains("subtitleServiceAPIKey = nil"))
    }

    @Test
    func playerViewManualSubtitleDownloadDoesNotRequireAutomaticSelectionMode() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        let downloadBody = try section(
            from: "private func downloadAndSelectSubtitle(_ subtitle: Subtitle, streamID: String) async {",
            to: "private func writeExternalSubtitle(content: String, source: Subtitle) throws -> URL {",
            in: source
        )

        #expect(!downloadBody.contains("subtitleSelectionMode == .automaticPreferred"))
        #expect(downloadBody.contains("Self.subtitleMutationShouldRun("))
    }

    @Test
    func playerViewRoutesEngineAudioSelectionThroughActiveKSPlayerTracks() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("selectEngineAudio(track)"))

        let selectEngineAudioBody = try section(
            from: "private func selectEngineAudio(_ track: VPPlayerEngine.TrackInfo) {",
            to: "private func scheduleSubtitleCatalogRefresh(for stream: StreamInfo) {",
            in: source
        )

        #expect(selectEngineAudioBody.contains("engine.selectAudioTrack(track.id)"))
        #expect(selectEngineAudioBody.contains("tracks(mediaType: .audio)"))
        #expect(selectEngineAudioBody.contains("player.select(track: mediaTrack)"))
        #expect(selectEngineAudioBody.contains("refreshKSAudioTracks(from: coordinator)"))
    }

    @Test
    func customEnvironmentViewUsesSharedImmersiveFallbacksAndErrorSurface() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/CustomEnvironmentView.swift")
        #expect(source.contains("ImmersiveControlsPolicy.smoothedPosition("))
        #expect(source.contains("ImmersiveControlsPolicy.fallbackControlsPosition"))
        #expect(source.contains("Attachment(id: \"loadingIndicator\")"))
        #expect(source.contains("makeFallbackScreen()"))
        #expect(source.contains("loadingState = .failed"))
    }

    @Test
    func playerAccessibilityHelpersHonorReduceMotionAndSystemCaptionFallbacks() {
        #expect(!PlayerView.shouldAnimateForAccessibility(reduceMotion: true))
        #expect(PlayerView.shouldAnimateForAccessibility(reduceMotion: false))

        #expect(
            PlayerView.automaticSubtitleLanguageCodes(
                configuredLanguageSetting: "es, fr",
                systemPreferredLanguages: ["de-DE"],
                closedCaptioningEnabled: true
            ) == ["de", "es", "fr"]
        )

        #expect(
            PlayerView.automaticSubtitleLanguageCodes(
                configuredLanguageSetting: nil,
                systemPreferredLanguages: ["fr-CA", "en-US"],
                closedCaptioningEnabled: true
            ) == ["fr", "en"]
        )

        #expect(
            PlayerView.automaticSubtitleLanguageCodes(
                configuredLanguageSetting: nil,
                systemPreferredLanguages: ["fr-CA"],
                closedCaptioningEnabled: false
            ) == ["fr"]
        )
    }

    @Test
    func playerAndImmersiveSourcesGateAnimationsBehindReduceMotion() throws {
        let playerSource = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        let immersiveControlsSource = try contents(of: "VPStudio/Views/Immersive/ImmersivePlayerControlsView.swift")
        let customEnvironmentSource = try contents(of: "VPStudio/Views/Immersive/CustomEnvironmentView.swift")
        let hdriSource = try contents(of: "VPStudio/Views/Immersive/HDRISkyboxEnvironment.swift")

        #expect(playerSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(playerSource.contains("motionAnimationsEnabled"))
        #expect(playerSource.contains("performOptionalAnimation(.easeInOut(duration: 0.22))"))
        #expect(playerSource.contains("performOptionalAnimation(.easeInOut(duration: 0.25))"))
        #expect(playerSource.contains("UIAccessibility.isClosedCaptioningEnabled"))

        #expect(immersiveControlsSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(immersiveControlsSource.contains(".animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.15), value: isDraggingScrubber)"))

        #expect(customEnvironmentSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(customEnvironmentSource.contains("performOptionalAnimation(.easeInOut(duration: 0.25))"))
        #expect(customEnvironmentSource.contains(".animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.15), value: subtitleText)"))

        #expect(hdriSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(hdriSource.contains("screen.move(to: temp.transform, relativeTo: nil, duration: accessibilityReduceMotion ? 0 : 0.4)"))
        #expect(hdriSource.contains("performOptionalAnimation(.easeInOut(duration: 0.25))"))
    }

    @Test
    func playerSubtitleCatalogAndWarningsStayAccessibilityAligned() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")

        #expect(source.contains("let languages = Self.automaticSubtitleLanguageCodes("))
        #expect(!source.contains("MACaptionAppearanceAddSelectedLanguage"))
        #expect(source.contains(
            """
            warningsOverlay
                                .padding(.top, 6)
                                .compositingGroup()
            """
        ))
    }

    private func functionBody(named functionName: String, in source: String) throws -> String {
        guard let signatureRange = source.range(of: "func \(functionName)()") else {
            throw NSError(
                domain: "PlayerResourceTeardownContractTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing function: \(functionName)"]
            )
        }

        guard let openingBrace = source.range(
            of: "{",
            range: signatureRange.upperBound..<source.endIndex
        )?.lowerBound else {
            throw NSError(
                domain: "PlayerResourceTeardownContractTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing opening brace for function: \(functionName)"]
            )
        }

        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let bodyStart = source.index(after: openingBrace)
                    return String(source[bodyStart..<cursor])
                }
            }
            cursor = source.index(after: cursor)
        }

        throw NSError(
            domain: "PlayerResourceTeardownContractTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Missing closing brace for function: \(functionName)"]
        )
    }

    private func section(from startToken: String, to endToken: String, in source: String) throws -> String {
        let startRange = try requiredRange(of: startToken, in: source)
        guard let endRange = source.range(
            of: endToken,
            range: startRange.upperBound..<source.endIndex
        ) else {
            throw NSError(
                domain: "PlayerResourceTeardownContractTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Missing section terminator: \(endToken)"]
            )
        }
        return String(source[startRange.upperBound..<endRange.lowerBound])
    }

    private func requiredRange(of token: String, in source: String) throws -> Range<String.Index> {
        guard let range = source.range(of: token) else {
            throw NSError(
                domain: "PlayerResourceTeardownContractTests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Missing token: \(token)"]
            )
        }
        return range
    }

    private func containsIgnoringWhitespace(_ source: String, _ snippet: String) -> Bool {
        normalizedWhitespace(source).contains(normalizedWhitespace(snippet))
    }

    private func normalizedWhitespace(_ source: String) -> String {
        source
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func contents(of relativePath: String) throws -> String {
        let absolutePath = repoRootURL().appendingPathComponent(relativePath).path
        return try String(contentsOfFile: absolutePath, encoding: .utf8)
    }

    private func repoRootURL() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return url
    }
}
