import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct AppStateBootstrapMatrixTests {
    struct CaseData: Sendable {
        let id: Int
        let failMigrate: Bool
        let failDebridInit: Bool
        let failEnvironmentBootstrap: Bool
        let hasDebridConfig: Bool
        let hasReadyService: Bool
        let hasActiveEnvironment: Bool
    }

    private static let allCases: [CaseData] = {
        var cases: [CaseData] = []
        var id = 0
        for failMigrate in [false, true] {
            for failDebridInit in [false, true] {
                for failEnvironmentBootstrap in [false, true] {
                    for hasDebridConfig in [false, true] {
                        for hasReadyService in [false, true] {
                            for hasActiveEnvironment in [false, true] {
                                cases.append(
                                    CaseData(
                                        id: id,
                                        failMigrate: failMigrate,
                                        failDebridInit: failDebridInit,
                                        failEnvironmentBootstrap: failEnvironmentBootstrap,
                                        hasDebridConfig: hasDebridConfig,
                                        hasReadyService: hasReadyService,
                                        hasActiveEnvironment: hasActiveEnvironment
                                    )
                                )
                                id += 1
                            }
                        }
                    }
                }
            }
        }
        return cases
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(allCases.prefix(16)), full: allCases))
    @MainActor
    func bootstrapStateMatrix(data: CaseData) async throws {
        struct HookError: Error {}

        let environmentAsset = data.hasActiveEnvironment
            ? EnvironmentAsset(id: "env-\(data.id)", name: "Env", sourceType: .bundled, assetPath: "theater", isActive: true)
            : nil

        let hooks = AppState.TestHooks(
            migrate: {
                if data.failMigrate { throw HookError() }
            },
            initializeDebrid: {
                if data.failDebridInit { throw HookError() }
            },
            bootstrapEnvironments: {
                if data.failEnvironmentBootstrap { throw HookError() }
            },
            fetchActiveEnvironment: {
                environmentAsset
            },
            fetchDebridConfigs: {
                data.hasDebridConfig
                    ? [DebridConfig(serviceType: .realDebrid, apiTokenRef: "ref")]
                    : []
            },
            availableDebridServices: {
                data.hasReadyService ? [.realDebrid] : []
            }
        )

        let appState = AppState(testHooks: hooks)
        await appState.bootstrap()

        // Migration or debrid init failure is fatal — triggers setup mode
        let fatalFailure = data.failMigrate || data.failDebridInit
        if fatalFailure {
            #expect(appState.isShowingSetup)
            #expect(appState.setupRecommendationNeeded == false)
            return
        }

        // Environment bootstrap failure is non-fatal — app continues normally
        let expectRecommendation = !data.hasDebridConfig || !data.hasReadyService
        #expect(appState.isShowingSetup == false)
        #expect(appState.setupRecommendationNeeded == expectRecommendation)

        if !data.failEnvironmentBootstrap {
            #expect(appState.selectedEnvironmentAsset?.id == environmentAsset?.id)
        } else {
            // Environment failed, so no active environment was set
            #expect(appState.selectedEnvironmentAsset == nil)
        }
    }
}
