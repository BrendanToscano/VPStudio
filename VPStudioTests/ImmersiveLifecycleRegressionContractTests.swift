import Foundation
import Testing
@testable import VPStudio

@Suite("Immersive Lifecycle Regression Contracts")
struct ImmersiveLifecycleRegressionContractTests {
    @Test
    func playerDismissPathSettlesImmersiveDismissalBeforeReentry() throws {
        let source = try contents(of: "VPStudio/Views/Windows/Player/PlayerView.swift")
        #expect(source.contains("await dismissImmersiveSpace()"))
        #expect(source.contains("await appState.settleImmersiveDismissal()"))
    }

    @Test
    func contentViewDismissPathSettlesImmersiveDismissal() throws {
        let source = try contents(of: "VPStudio/Views/Windows/ContentView.swift")
        #expect(source.contains("await dismissImmersiveSpace()"))
        #expect(source.contains("await appState.settleImmersiveDismissal()"))
    }

    @Test
    func hdriEnvironmentResetsStateOnReentryAndCleansSceneRootOnDisappear() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/HDRISkyboxEnvironment.swift")
        #expect(source.contains("private func resetStateForReentry()"))
        #expect(source.contains("resetStateForReentry()"))
        #expect(source.contains("sceneRoot?.removeFromParent()"))
        #expect(source.contains("sceneRoot = nil"))
        #expect(source.contains("screenSizePreset = .cinema"))
    }

    @Test
    func customEnvironmentResetsStateOnReentryAndUsesSharedControlsPolicy() throws {
        let source = try contents(of: "VPStudio/Views/Immersive/CustomEnvironmentView.swift")
        #expect(source.contains("private func resetStateForReentry()"))
        #expect(source.contains("sceneRoot?.removeFromParent()"))
        #expect(source.contains("ImmersiveControlsPolicy.smoothedPosition"))
        #expect(source.contains("ImmersiveControlsPolicy.fallbackControlsPosition"))
    }

    private func contents(of relativePath: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .path
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
