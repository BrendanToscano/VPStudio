import Foundation
import Testing
@testable import VPStudio

@Suite("App Event Policies")
struct AppEventPoliciesTests {
    @Test
    func discoverRefreshPolicyTriggersOnDiscoverReselect() {
        let event = TabSelectionEvent(previousTab: .discover, selectedTab: .discover)
        #expect(DiscoverRefreshTriggerPolicy.reason(for: event) == .tabReselected)
    }

    @Test
    func discoverRefreshPolicyTriggersWhenReturningToDiscover() {
        let event = TabSelectionEvent(previousTab: .library, selectedTab: .discover)
        #expect(DiscoverRefreshTriggerPolicy.reason(for: event) == .returnedToDiscover)
    }

    @Test(arguments: SidebarTab.allCases.filter { $0 != .discover })
    func discoverRefreshPolicyIgnoresOtherTargetTabs(tab: SidebarTab) {
        let event = TabSelectionEvent(previousTab: .discover, selectedTab: tab)
        #expect(DiscoverRefreshTriggerPolicy.reason(for: event) == nil)
    }

    @Test
    func onboardingAutoPresentationRequiresIncompleteOnboardingAndSetupNeed() {
        #expect(OnboardingPresentationPolicy.shouldAutoPresentSetup(
            setupRecommendationNeeded: true,
            hasCompletedOnboarding: false
        ))
        #expect(!OnboardingPresentationPolicy.shouldAutoPresentSetup(
            setupRecommendationNeeded: true,
            hasCompletedOnboarding: true
        ))
        #expect(!OnboardingPresentationPolicy.shouldAutoPresentSetup(
            setupRecommendationNeeded: false,
            hasCompletedOnboarding: false
        ))
    }
}

@Suite("Setup Completion Event Flow", .serialized)
struct SetupCompletionEventFlowTests {
    @Test
    @MainActor
    func setupCompletionPostsDiscoverRefreshAndIncrementsToken() async {
        let appState = AppState(
            testHooks: .init(
                migrate: {},
                initializeDebrid: {},
                bootstrapEnvironments: {},
                fetchActiveEnvironment: { nil },
                fetchDebridConfigs: { [] },
                availableDebridServices: { [] }
            )
        )

        var setupDidCompleteReceived = false
        var setupRecommendationNeeded: Bool?
        var refreshReason: DiscoverRefreshReason?

        let setupObserver = NotificationCenter.default.addObserver(
            forName: .setupDidComplete,
            object: nil,
            queue: nil
        ) { notification in
            setupDidCompleteReceived = true
            setupRecommendationNeeded = notification.userInfo?[AppNotificationUserInfoKey.setupRecommendationNeeded] as? Bool
        }

        let refreshObserver = NotificationCenter.default.addObserver(
            forName: .discoverRefreshRequested,
            object: nil,
            queue: nil
        ) { notification in
            refreshReason = notification.discoverRefreshReason
        }

        defer {
            NotificationCenter.default.removeObserver(setupObserver)
            NotificationCenter.default.removeObserver(refreshObserver)
        }

        let initialToken = appState.discoverRefreshToken
        await appState.handleSetupCompletion()

        #expect(setupDidCompleteReceived)
        #expect(setupRecommendationNeeded == true)
        #expect(refreshReason == .setupCompleted)
        #expect(appState.discoverRefreshToken == initialToken + 1)
    }
}
