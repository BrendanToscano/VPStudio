import SwiftUI
#if os(visionOS)
import RealityKit
#endif
#if os(macOS)
import AppKit
#endif

import AVFoundation

// MARK: - macOS App Delegate

#if os(macOS)
/// Prevents macOS from terminating the app when the player window closes
/// while the main window is suppressed (zero-window transient state).
final class VPStudioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
#endif

// MARK: - App

@main
struct VPStudioApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(VPStudioAppDelegate.self) private var appDelegate
    #endif

    init() {
        // Configure audio session for media playback, allowing it to mix or route properly
        #if !os(macOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
        #endif
    }

    @State private var appState = AppState()
    @State private var sharedEngine = VPPlayerEngine()
    #if os(visionOS)
    @State private var hdriImmersionStyle: ImmersionStyle = .full
    @State private var customEnvImmersionStyle: ImmersionStyle = .full
    #endif

    var body: some SwiftUI.Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 1200, height: 800)
        #if os(macOS)
        .windowResizability(.contentMinSize)
        #endif

        WindowGroup(id: "player", for: PlayerSessionRequest.self) { $request in
            if let request {
                PlayerView(
                    stream: request.stream,
                    availableStreams: request.availableStreams,
                    mediaTitle: request.mediaTitle,
                    mediaId: request.mediaId,
                    episodeId: request.episodeId,
                    sessionID: request.id
                )
                    .environment(appState)
                    .environment(sharedEngine)
            }
        }
        .defaultSize(width: 1400, height: 788)
        .windowStyle(.plain)
        #if os(visionOS)
        .windowResizability(.automatic)
        #endif

        #if os(visionOS)
        ImmersiveSpace(id: "hdriSkybox") {
            HDRISkyboxEnvironment()
                .environment(appState)
                .environment(sharedEngine)
        }
        .immersionStyle(selection: $hdriImmersionStyle, in: .full)
        .upperLimbVisibility(.visible)

        ImmersiveSpace(id: "customEnvironment") {
            CustomEnvironmentView()
                .environment(appState)
                .environment(sharedEngine)
        }
        .immersionStyle(selection: $customEnvImmersionStyle, in: .full)
        .upperLimbVisibility(.visible)
        #endif
    }
}
