import Testing
@testable import VPStudio

struct SettingsStatusFormatterTests {
    @Test
    func debridStatusReflectsActiveServiceCount() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.activeDebridCount = 2

        let status = SettingsStatusFormatter.status(for: .debrid, snapshot: snapshot)
        #expect(status.kind == .positive)
        #expect(status.message == "2 active services")
    }

    @Test
    func metadataStatusWarnsWhenTMDBMissing() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.hasTMDBKey = false

        let status = SettingsStatusFormatter.status(for: .metadata, snapshot: snapshot)
        #expect(status.kind == .warning)
        #expect(status.message == "API key required")
    }

    @Test
    func aiStatusUsesSelectedProviderRequirements() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.aiProvider = .openAI
        snapshot.hasOllamaEndpoint = true

        let warningStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(warningStatus.kind == .warning)
        #expect(warningStatus.message == "Using Ollama")

        snapshot.hasOpenAIKey = true
        let okStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(okStatus.kind == .positive)
        #expect(okStatus.message == "OpenAI configured")
    }

    @Test
    func aiStatusUsesOpenRouterCredentialsWhenSelected() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.aiProvider = .openRouter
        snapshot.hasOpenRouterKey = false
        snapshot.hasOllamaEndpoint = false

        let warningStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(warningStatus.kind == .warning)
        #expect(warningStatus.message == "OpenRouter needs credentials")

        snapshot.hasOpenRouterKey = true
        let okStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(okStatus.kind == .positive)
        #expect(okStatus.message == "OpenRouter configured")
    }

    @Test
    func aiStatusTreatsLocalAsConfiguredOnlyWhenEnabledAndUsable() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.aiProvider = .local
        snapshot.isLocalAIEnabled = false
        snapshot.hasUsableLocalModel = false
        snapshot.hasOllamaEndpoint = false

        let disabledStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(disabledStatus.kind == .warning)
        #expect(disabledStatus.message == "On-Device (Local) is disabled")

        snapshot.isLocalAIEnabled = true
        let missingModelStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(missingModelStatus.kind == .warning)
        #expect(missingModelStatus.message == "On-Device (Local) needs a downloaded model")

        snapshot.hasUsableLocalModel = true
        let readyStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(readyStatus.kind == .positive)
        #expect(readyStatus.message == "On-Device (Local) configured")
    }

    @Test
    func aiStatusWarnsWhenStoredProviderFallsBackToConfiguredRuntimeProvider() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.aiProvider = .ollama
        snapshot.hasOllamaEndpoint = true
        snapshot.hasOpenAIKey = true

        let status = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(status.kind == .positive)
        #expect(status.message == "Ollama configured")
    }

    @Test
    func environmentsStatusWarnsWhenNoneImported() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.environmentAssetCount = 0

        let status = SettingsStatusFormatter.status(for: .environments, snapshot: snapshot)
        #expect(status.kind == .warning)
        #expect(status.message == "No environments added")
    }

    @Test
    func syncStatusTracksRuntimeConnectionAndSavedAuthorization() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.hasTraktCredentials = false
        snapshot.hasSimklCredentials = true

        let traktStatus = SettingsStatusFormatter.status(for: .trakt, snapshot: snapshot)
        let simklStatus = SettingsStatusFormatter.status(for: .simkl, snapshot: snapshot)

        #expect(traktStatus.kind == .warning)
        #expect(traktStatus.message == "Not connected")
        #expect(simklStatus.kind == .neutral)
        #expect(simklStatus.message == "Unavailable in this build")
    }

    @Test
    func traktStatusOnlyShowsConnectedForAnActiveSession() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.hasTraktCredentials = true

        let readyStatus = SettingsStatusFormatter.status(for: .trakt, snapshot: snapshot)
        #expect(readyStatus.kind == .neutral)
        #expect(readyStatus.message == "Ready to connect")

        snapshot.hasTraktConnection = true
        let connectedStatus = SettingsStatusFormatter.status(for: .trakt, snapshot: snapshot)
        #expect(connectedStatus.kind == .positive)
        #expect(connectedStatus.message == "Connected")
    }
}
