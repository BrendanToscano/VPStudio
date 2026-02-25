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
        snapshot.hasOpenAIKey = false

        let warningStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(warningStatus.kind == .warning)
        #expect(warningStatus.message == "OpenAI needs credentials")

        snapshot.hasOpenAIKey = true
        let okStatus = SettingsStatusFormatter.status(for: .ai, snapshot: snapshot)
        #expect(okStatus.kind == .positive)
        #expect(okStatus.message == "OpenAI configured")
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
    func syncStatusTracksTraktAndSimklCredentials() {
        var snapshot = SettingsStatusSnapshot()
        snapshot.hasTraktCredentials = false
        snapshot.hasSimklCredentials = true

        let traktStatus = SettingsStatusFormatter.status(for: .trakt, snapshot: snapshot)
        let simklStatus = SettingsStatusFormatter.status(for: .simkl, snapshot: snapshot)

        #expect(traktStatus.kind == .warning)
        #expect(traktStatus.message == "Not connected")
        #expect(simklStatus.kind == .positive)
        #expect(simklStatus.message == "Connected")
    }
}
