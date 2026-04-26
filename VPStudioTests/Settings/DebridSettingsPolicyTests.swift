import Foundation
import Testing
@testable import VPStudio

@Suite("Debrid Settings Policy")
struct DebridSettingsPolicyTests {
    @Test func sharedStreamingServiceTypesExcludeEasyNewsOnly() {
        #expect(DebridSettingsPolicy.sharedStreamingServiceTypes == [
            .realDebrid,
            .allDebrid,
            .premiumize,
            .torBox,
            .debridLink,
            .offcloud,
        ])
        #expect(!DebridSettingsPolicy.sharedStreamingServiceTypes.contains(.easyNews))
        #expect(DebridSettingsView.sharedStreamingServiceTypes == DebridSettingsPolicy.sharedStreamingServiceTypes)
    }

    @Test func apiKeyPolicyTrimsWhitespaceBeforeSaveDecision() {
        #expect(DebridSettingsPolicy.trimmedApiKey("  token\n") == "token")
        #expect(DebridSettingsPolicy.canSaveNewService(apiKey: "  token\n"))
        #expect(!DebridSettingsPolicy.canSaveNewService(apiKey: " \n\t "))
    }

    @Test func configGroupingSeparatesSharedStreamingProvidersFromEasyNews() {
        let configs = [
            makeConfig(id: "rd", serviceType: .realDebrid),
            makeConfig(id: "easy", serviceType: .easyNews),
            makeConfig(id: "pm", serviceType: .premiumize),
        ]

        #expect(DebridSettingsPolicy.supportedConfigs(from: configs).map(\.id) == ["rd", "pm"])
        #expect(DebridSettingsPolicy.unsupportedConfigs(from: configs).map(\.id) == ["easy"])
    }

    @Test func validationMessagesUseProviderDisplayNames() {
        #expect(DebridSettingsPolicy.successMessage(for: .realDebrid) == "Real-Debrid token is valid.")
        #expect(DebridSettingsPolicy.rejectedMessage(for: .debridLink) == "Debrid-Link token was rejected.")
    }

    @Test func fallbackTokenHandlesLegacyPlaintextAndBlankValues() {
        #expect(DebridSettingsPolicy.fallbackToken(from: "  legacy-token  ") == "legacy-token")
        #expect(DebridSettingsPolicy.fallbackToken(from: "\n\t ") == nil)
    }

    @Test func normalizePrioritiesSortsByExistingPriorityAndRewritesDensePriorities() {
        let date = Date(timeIntervalSince1970: 123)
        let configs = [
            makeConfig(id: "last", serviceType: .premiumize, priority: 30),
            makeConfig(id: "first", serviceType: .realDebrid, priority: 10),
            makeConfig(id: "middle", serviceType: .offcloud, priority: 20),
        ]

        let normalized = DebridSettingsPolicy.normalizePriorities(configs, updatedAt: date)

        #expect(normalized.map(\.id) == ["first", "middle", "last"])
        #expect(normalized.map(\.priority) == [0, 1, 2])
        #expect(normalized.allSatisfy { $0.updatedAt == date })
        #expect(normalized.map(\.createdAt) == configs.sorted { $0.priority < $1.priority }.map(\.createdAt))
    }

    private func makeConfig(
        id: String,
        serviceType: DebridServiceType,
        priority: Int = 0
    ) -> DebridConfig {
        DebridConfig(
            id: id,
            serviceType: serviceType,
            apiTokenRef: "token-\(id)",
            priority: priority,
            createdAt: Date(timeIntervalSince1970: Double(priority + 1)),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
