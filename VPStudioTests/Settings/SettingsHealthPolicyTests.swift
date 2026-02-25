import Testing
@testable import VPStudio

@Suite("Settings Health Policy")
struct SettingsHealthPolicyTests {
    @Test
    func progressZeroOfFiveReturnsZero() {
        let progress = SettingsHealthPolicy.configurationProgress(configured: 0, total: 5)
        #expect(progress == 0.0)
    }

    @Test
    func progressThreeOfFiveReturnsSixTenths() {
        let progress = SettingsHealthPolicy.configurationProgress(configured: 3, total: 5)
        #expect(progress == 0.6)
    }

    @Test
    func progressFiveOfFiveReturnsOne() {
        let progress = SettingsHealthPolicy.configurationProgress(configured: 5, total: 5)
        #expect(progress == 1.0)
    }

    @Test
    func warningCountFiltersCorrectly() {
        let statuses: [SettingsRowIndicatorPolicy.StatusKind] = [
            .configured, .warning, .unconfigured, .warning, .disabled,
        ]
        let count = SettingsHealthPolicy.warningCount(statuses: statuses)
        #expect(count == 2)
    }

    @Test
    func progressLabelFormatting() {
        let label = SettingsHealthPolicy.progressLabel(configured: 3, total: 6)
        #expect(label == "3/6 configured")
    }

    @Test
    func warningBadgeVisibleWhenWarningsExist() {
        #expect(SettingsHealthPolicy.shouldShowWarningBadge(warningCount: 1) == true)
        #expect(SettingsHealthPolicy.shouldShowWarningBadge(warningCount: 3) == true)
    }

    @Test
    func warningBadgeHiddenWhenNoWarnings() {
        #expect(SettingsHealthPolicy.shouldShowWarningBadge(warningCount: 0) == false)
    }

    @Test
    func progressWithZeroTotalReturnsZero() {
        let progress = SettingsHealthPolicy.configurationProgress(configured: 0, total: 0)
        #expect(progress == 0.0)
    }

    // MARK: - Essential Destinations

    @Test
    func essentialTotalCountsOnlyEssentialDestinations() {
        // Essential: debrid, indexers, metadata, ai, trakt, simkl = 6
        // Non-essential: player, subtitles, environments = 3
        #expect(SettingsHealthPolicy.essentialTotal == 6)
    }

    @Test
    func essentialConfiguredCountIgnoresNonEssentialPositives() {
        // Player and subtitles are non-essential — even if positive, they shouldn't count
        let statuses: [SettingsDestination: SettingsDestinationStatus] = [
            .player: SettingsDestinationStatus(message: "Configured", kind: .positive),
            .subtitles: SettingsDestinationStatus(message: "Configured", kind: .positive),
            .environments: SettingsDestinationStatus(message: "Configured", kind: .positive),
        ]
        let count = SettingsHealthPolicy.essentialConfiguredCount(statuses: statuses)
        #expect(count == 0)
    }

    @Test
    func essentialConfiguredCountIncludesOnlyEssentialPositives() {
        let statuses: [SettingsDestination: SettingsDestinationStatus] = [
            .debrid: SettingsDestinationStatus(message: "1 active service", kind: .positive),
            .metadata: SettingsDestinationStatus(message: "API key configured", kind: .positive),
            .ai: SettingsDestinationStatus(message: "Anthropic configured", kind: .positive),
            .player: SettingsDestinationStatus(message: "Playback preferences", kind: .neutral),
            .subtitles: SettingsDestinationStatus(message: "OpenSubtitles enabled", kind: .positive),
        ]
        let count = SettingsHealthPolicy.essentialConfiguredCount(statuses: statuses)
        // Only debrid, metadata, ai are essential AND positive
        #expect(count == 3)
    }

    @Test
    func essentialConfiguredCountWithAllEssentialConfigured() {
        let statuses: [SettingsDestination: SettingsDestinationStatus] = [
            .debrid: SettingsDestinationStatus(message: "Active", kind: .positive),
            .indexers: SettingsDestinationStatus(message: "Active", kind: .positive),
            .metadata: SettingsDestinationStatus(message: "Configured", kind: .positive),
            .ai: SettingsDestinationStatus(message: "Configured", kind: .positive),
            .trakt: SettingsDestinationStatus(message: "Connected", kind: .positive),
            .simkl: SettingsDestinationStatus(message: "Connected", kind: .positive),
        ]
        let count = SettingsHealthPolicy.essentialConfiguredCount(statuses: statuses)
        #expect(count == 6)
        #expect(count == SettingsHealthPolicy.essentialTotal)
    }

    @Test
    func essentialConfiguredCountWithEmptyStatuses() {
        let statuses: [SettingsDestination: SettingsDestinationStatus] = [:]
        let count = SettingsHealthPolicy.essentialConfiguredCount(statuses: statuses)
        #expect(count == 0)
    }

    @Test
    func essentialConfiguredCountExcludesWarningStatuses() {
        let statuses: [SettingsDestination: SettingsDestinationStatus] = [
            .debrid: SettingsDestinationStatus(message: "Not configured", kind: .warning),
            .indexers: SettingsDestinationStatus(message: "No active indexers", kind: .warning),
            .metadata: SettingsDestinationStatus(message: "API key required", kind: .warning),
            .ai: SettingsDestinationStatus(message: "Needs credentials", kind: .warning),
            .trakt: SettingsDestinationStatus(message: "Not connected", kind: .warning),
            .simkl: SettingsDestinationStatus(message: "Not connected", kind: .warning),
        ]
        let count = SettingsHealthPolicy.essentialConfiguredCount(statuses: statuses)
        #expect(count == 0)
    }

    @Test
    func healthProgressUsesEssentialDenominator() {
        // With 3 of 6 essential configured, progress should be 0.5
        let progress = SettingsHealthPolicy.configurationProgress(
            configured: 3,
            total: SettingsHealthPolicy.essentialTotal
        )
        #expect(progress == 0.5)
    }

    @Test
    func healthLabelUsesEssentialDenominator() {
        let label = SettingsHealthPolicy.progressLabel(
            configured: 4,
            total: SettingsHealthPolicy.essentialTotal
        )
        #expect(label == "4/6 configured")
    }
}
