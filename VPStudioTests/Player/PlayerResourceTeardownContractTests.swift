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
        #expect(source.contains("catch is CancellationError {\n                cleanupPlayback(clearSession: false)\n                return"))
        #expect(source.contains("@State private var preparePlaybackTask: Task<Void, Never>?"))
        #expect(source.contains("preparePlaybackTask?.cancel()"))
        #expect(source.contains("preparePlaybackTask = Task { await preparePlayback(for: currentStream) }"))
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
        #expect(source.contains("private func scheduleSubtitleCatalogRefresh(for stream: StreamInfo)"))
        #expect(containsIgnoringWhitespace(
            source,
            "subtitleCatalogTask = Task { await refreshSubtitleCatalog(for: stream) }"
        ))
        #expect(source.contains("scheduleSubtitleCatalogRefresh(for: currentStream)"))
        #expect(source.contains("scheduleSubtitleCatalogRefresh(for: stream)"))
        #expect(source.contains("subtitleDownloadTask?.cancel()"))
        #expect(source.contains("subtitleDownloadTask = nil"))
        #expect(containsIgnoringWhitespace(
            source,
            "subtitleDownloadTask = Task { await downloadAndSelectSubtitle(subtitle, streamID: currentStream.id) }"
        ))
        #expect(source.contains("guard streamID == currentStream.id else { return }"))
        #expect(source.contains("private func autoLoadSubtitlesIfEnabled(for stream: StreamInfo) async"))
        #expect(source.contains("guard stream.id == currentStream.id else { return }"))
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
    func playerViewUsesCinematicVisualPolicyForPrimaryControls() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("topBarIconSurface(symbolName: PlayerCinematicVisualPolicy.backSymbolName)"))
        #expect(source.contains("topBarIconSurface(symbolName: PlayerCinematicVisualPolicy.menuSymbolName)"))
        #expect(source.contains("transportIconButton(systemName: PlayerCinematicVisualPolicy.subtitlesSymbolName"))
        #expect(source.contains("transportIconButton(systemName: PlayerCinematicVisualPolicy.audioSymbolName"))
        #expect(source.contains("systemImage: PlayerCinematicVisualPolicy.qualitySymbolName"))
        #expect(containsIgnoringWhitespace(
            source,
            "transportControls .padding(.horizontal, PlayerCinematicChromePolicy.transportCardHorizontalPadding) .padding(.vertical, PlayerCinematicChromePolicy.transportCardVerticalPadding) .frame(maxWidth: PlayerCinematicChromePolicy.transportCardMaxWidth) .background( chromeCardBackground, in: RoundedRectangle("
        ))
        #expect(source.contains(".overlay(alignment: .bottom)"))
        #expect(source.contains("controlsDock"))
        #expect(source.contains(".background(chromeIconBackground, in: Circle())"))
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
