import Foundation
import Testing
@testable import VPStudio

@Suite("QA Runtime Options")
struct QARuntimeOptionsTests {
    @Test
    func sleepNanosecondsClampsNegativeSecondsToZero() {
        #expect(QARuntimeOptions.sleepNanoseconds(for: -5) == 0)
        #expect(QARuntimeOptions.sleepNanoseconds(for: 0) == 0)
    }

    @Test
    func sleepNanosecondsConvertsSecondsToNanoseconds() {
        #expect(QARuntimeOptions.sleepNanoseconds(for: 1.25) == 1_250_000_000)
        #expect(QARuntimeOptions.sleepNanoseconds(for: 0.001) == 1_000_000)
    }

    @Test
    func downloadActionRawValuesMatchSimulatorInputs() {
        #expect(QARuntimeOptions.DownloadAction(rawValue: "cancelFirstActive") == .cancelFirstActive)
        #expect(QARuntimeOptions.DownloadAction(rawValue: "retryFirstFailed") == .retryFirstFailed)
        #expect(QARuntimeOptions.DownloadAction(rawValue: "removeFirst") == .removeFirst)
        #expect(QARuntimeOptions.DownloadAction(rawValue: "removeFirstGroup") == .removeFirstGroup)
        #expect(QARuntimeOptions.DownloadAction(rawValue: "playFirstCompleted") == .playFirstCompleted)
        #expect(QARuntimeOptions.DownloadAction(rawValue: "unknown") == nil)
    }

    @Test
    func environmentSnapshotReadsDirectAndSimctlChildValues() {
        let snapshot = QARuntimeOptions.EnvironmentSnapshot([
            "VPSTUDIO_QA_DIRECT": "direct",
            "SIMCTL_CHILD_VPSTUDIO_QA_CHILD": "child"
        ])

        #expect(snapshot.value("VPSTUDIO_QA_DIRECT") == "direct")
        #expect(snapshot.value("VPSTUDIO_QA_CHILD") == "child")
        #expect(snapshot.value("VPSTUDIO_QA_MISSING") == nil)
        #expect(snapshot.isQAEnabled)
    }

    @Test
    func environmentSnapshotDetectsOnlyQAPrefixedKeys() {
        #expect(!QARuntimeOptions.EnvironmentSnapshot([:]).isQAEnabled)
        #expect(!QARuntimeOptions.EnvironmentSnapshot(["UNRELATED": "1"]).isQAEnabled)
        #expect(QARuntimeOptions.EnvironmentSnapshot(["SIMCTL_CHILD_VPSTUDIO_QA_FLAG": "1"]).isQAEnabled)
    }

    @Test
    func environmentSnapshotParsesStrictBooleanInputs() {
        let snapshot = QARuntimeOptions.EnvironmentSnapshot([
            "VPSTUDIO_QA_ONE": "1",
            "VPSTUDIO_QA_TRUE": "TRUE",
            "VPSTUDIO_QA_YES": "yes",
            "VPSTUDIO_QA_ON": "on",
            "VPSTUDIO_QA_ZERO": "0",
            "VPSTUDIO_QA_FALSE": "false",
            "VPSTUDIO_QA_SPACED": " true "
        ])

        #expect(snapshot.bool("VPSTUDIO_QA_ONE"))
        #expect(snapshot.bool("VPSTUDIO_QA_TRUE"))
        #expect(snapshot.bool("VPSTUDIO_QA_YES"))
        #expect(snapshot.bool("VPSTUDIO_QA_ON"))
        #expect(!snapshot.bool("VPSTUDIO_QA_ZERO"))
        #expect(!snapshot.bool("VPSTUDIO_QA_FALSE"))
        #expect(!snapshot.bool("VPSTUDIO_QA_SPACED"))
        #expect(!snapshot.bool("VPSTUDIO_QA_MISSING"))
    }

    @Test
    func environmentSnapshotTrimsStringsAndParsesDoubles() {
        let snapshot = QARuntimeOptions.EnvironmentSnapshot([
            "VPSTUDIO_QA_STRING": "  value  ",
            "VPSTUDIO_QA_BLANK": "   ",
            "VPSTUDIO_QA_DOUBLE": "1.25",
            "VPSTUDIO_QA_INVALID_DOUBLE": "nope"
        ])

        #expect(snapshot.string("VPSTUDIO_QA_STRING") == "value")
        #expect(snapshot.string("VPSTUDIO_QA_BLANK") == nil)
        #expect(snapshot.double("VPSTUDIO_QA_DOUBLE") == 1.25)
        #expect(snapshot.double("VPSTUDIO_QA_INVALID_DOUBLE") == nil)
    }

    @Test
    func environmentSnapshotSplitsCommaAndNewlineLists() {
        let snapshot = QARuntimeOptions.EnvironmentSnapshot([
            "VPSTUDIO_QA_LIST": " one, two\nthree ,, \n four "
        ])

        #expect(snapshot.stringList("VPSTUDIO_QA_LIST") == ["one", "two", "three", "four"])
        #expect(snapshot.stringList("VPSTUDIO_QA_MISSING").isEmpty)
    }

    @Test
    func absoluteURLRejectsRelativeOrHostlessValues() {
        #expect(QARuntimeOptions.absoluteURL(from: "https://cdn.example.com/movie.mp4")?.absoluteString == "https://cdn.example.com/movie.mp4")
        #expect(QARuntimeOptions.absoluteURL(from: "not a url") == nil)
        #expect(QARuntimeOptions.absoluteURL(from: "/local/file.mp4") == nil)
        #expect(QARuntimeOptions.absoluteURL(from: "file:///tmp/movie.mp4") == nil)
    }

    @Test
    func sampleURLsPreferExplicitURLListOverSingleFallback() throws {
        let snapshot = QARuntimeOptions.EnvironmentSnapshot([
            "VPSTUDIO_QA_SAMPLE_URLS": "https://cdn.example.com/one.mp4,\nnot a url, https://cdn.example.com/two.mp4",
            "VPSTUDIO_QA_SAMPLE_URL": "https://cdn.example.com/fallback.mp4"
        ])

        let urls = QARuntimeOptions.sampleURLs(from: snapshot)

        #expect(urls.map(\.absoluteString) == [
            "https://cdn.example.com/one.mp4",
            "https://cdn.example.com/two.mp4"
        ])
    }

    @Test
    func sampleURLsFallsBackToSingleURLWhenListIsEmpty() {
        let snapshot = QARuntimeOptions.EnvironmentSnapshot([
            "VPSTUDIO_QA_SAMPLE_URL": "https://cdn.example.com/fallback.mp4"
        ])

        #expect(QARuntimeOptions.sampleURLs(from: snapshot).map(\.absoluteString) == [
            "https://cdn.example.com/fallback.mp4"
        ])
    }

    @Test
    func sampleURLsReturnsEmptyWhenNoAbsoluteURLIsConfigured() {
        let snapshot = QARuntimeOptions.EnvironmentSnapshot([
            "VPSTUDIO_QA_SAMPLE_URLS": "not a url, /relative.mp4",
            "VPSTUDIO_QA_SAMPLE_URL": "also not a url"
        ])

        #expect(QARuntimeOptions.sampleURLs(from: snapshot).isEmpty)
    }

    @Test
    func debridFixtureEquatableIncludesServiceURLsAndFileName() throws {
        let url = try #require(URL(string: "https://cdn.example.com/movie.mp4"))
        let fixture = QADebridFixture(
            hash: "abcdef",
            serviceType: .realDebrid,
            streamURLs: [url],
            fileName: "Movie.mp4"
        )

        #expect(fixture == QADebridFixture(
            hash: "abcdef",
            serviceType: .realDebrid,
            streamURLs: [url],
            fileName: "Movie.mp4"
        ))
        #expect(fixture != QADebridFixture(
            hash: "abcdef",
            serviceType: .allDebrid,
            streamURLs: [url],
            fileName: "Movie.mp4"
        ))
    }

    @Test
    func debridFixtureRequiresHashAndAtLeastOneValidURL() {
        #expect(QARuntimeOptions.debridFixture(from: .init([
            "VPSTUDIO_QA_DEBRID_FIXTURE_URLS": "https://cdn.example.com/movie.mp4"
        ])) == nil)
        #expect(QARuntimeOptions.debridFixture(from: .init([
            "VPSTUDIO_QA_DEBRID_FIXTURE_HASH": "ABCDEF",
            "VPSTUDIO_QA_DEBRID_FIXTURE_URLS": "not a url"
        ])) == nil)
    }

    @Test
    func debridFixtureNormalizesHashDefaultsServiceAndFileName() throws {
        let fixture = try #require(QARuntimeOptions.debridFixture(from: .init([
            "VPSTUDIO_QA_DEBRID_FIXTURE_HASH": "ABCDEF123456",
            "VPSTUDIO_QA_DEBRID_FIXTURE_URLS": "https://cdn.example.com/movie.mp4"
        ])))

        #expect(fixture.hash == "abcdef123456")
        #expect(fixture.serviceType == .realDebrid)
        #expect(fixture.fileName == "QA.Debrid.abcdef12.mp4")
        #expect(fixture.streamURLs.map(\.absoluteString) == ["https://cdn.example.com/movie.mp4"])
    }

    @Test
    func debridFixtureUsesConfiguredServiceFileNameAndSkipsInvalidURLs() throws {
        let fixture = try #require(QARuntimeOptions.debridFixture(from: .init([
            "VPSTUDIO_QA_DEBRID_FIXTURE_HASH": "ABCDEF123456",
            "VPSTUDIO_QA_DEBRID_FIXTURE_SERVICE": DebridServiceType.allDebrid.rawValue,
            "VPSTUDIO_QA_DEBRID_FIXTURE_FILE_NAME": "Configured.mkv",
            "VPSTUDIO_QA_DEBRID_FIXTURE_URLS": "not a url, https://cdn.example.com/movie.mkv"
        ])))

        #expect(fixture.serviceType == .allDebrid)
        #expect(fixture.fileName == "Configured.mkv")
        #expect(fixture.streamURLs.map(\.absoluteString) == ["https://cdn.example.com/movie.mkv"])
    }

    @Test
    func syntheticTorrentMirrorsDebridFixtureMetadata() throws {
        let torrent = try #require(QARuntimeOptions.syntheticTorrent(from: .init([
            "VPSTUDIO_QA_DEBRID_FIXTURE_HASH": "ABCDEF123456",
            "VPSTUDIO_QA_DEBRID_FIXTURE_SERVICE": DebridServiceType.torBox.rawValue,
            "VPSTUDIO_QA_DEBRID_FIXTURE_URLS": "https://cdn.example.com/movie.mp4",
            "VPSTUDIO_QA_SYNTHETIC_TORRENT_TITLE": "Fixture Title"
        ])))

        #expect(torrent.infoHash == "abcdef123456")
        #expect(torrent.title == "Fixture Title")
        #expect(torrent.isCached)
        #expect(torrent.cachedOnService == DebridServiceType.torBox.rawValue)
    }

    @Test
    func syntheticTorrentFallsBackToFixtureFileNameAndRequiresFixture() throws {
        #expect(QARuntimeOptions.syntheticTorrent(from: .init([:])) == nil)

        let torrent = try #require(QARuntimeOptions.syntheticTorrent(from: .init([
            "VPSTUDIO_QA_DEBRID_FIXTURE_HASH": "ABCDEF123456",
            "VPSTUDIO_QA_DEBRID_FIXTURE_URLS": "https://cdn.example.com/movie.mp4"
        ])))

        #expect(torrent.title == "QA.Debrid.abcdef12.mp4")
        #expect(torrent.indexerName == "QA Debrid Fixture")
        #expect(torrent.seeders == 42)
        #expect(torrent.leechers == 3)
    }

    @Test
    func staticOptionsAreSafeToReadWhenEnvironmentIsAbsent() {
        _ = QARuntimeOptions.isEnabled
        _ = QARuntimeOptions.searchQuery
        _ = QARuntimeOptions.autoSubmitSearchQuery
        _ = QARuntimeOptions.postSubmitDraftQuery
        _ = QARuntimeOptions.postSubmitDraftDelaySeconds
        _ = QARuntimeOptions.preferredResultTitle
        _ = QARuntimeOptions.autoOpenFirstSearchResult
        _ = QARuntimeOptions.scrollDebug
        _ = QARuntimeOptions.autoOpenSearchFilterSheet
        _ = QARuntimeOptions.autoApplySearchFilterSheet
        _ = QARuntimeOptions.autoSelectFilterGenre
        _ = QARuntimeOptions.autoSelectMoodCard
        _ = QARuntimeOptions.selectedSeason
        _ = QARuntimeOptions.selectedEpisode
        _ = QARuntimeOptions.libraryList
        _ = QARuntimeOptions.autoAddWatchlist
        _ = QARuntimeOptions.autoAddFavorites
        _ = QARuntimeOptions.autoRemoveWatchlist
        _ = QARuntimeOptions.autoRemoveFavorites
        _ = QARuntimeOptions.sampleURL
        _ = QARuntimeOptions.sampleURLs
        _ = QARuntimeOptions.sampleRefreshURL
        _ = QARuntimeOptions.sampleRefreshSignalURL
        _ = QARuntimeOptions.autoQueueSampleDownload
        _ = QARuntimeOptions.autoPlaySample
        _ = QARuntimeOptions.debridFixture
        _ = QARuntimeOptions.autoPlaySyntheticTorrent
        _ = QARuntimeOptions.syntheticTorrent
        _ = QARuntimeOptions.downloadAction
        _ = QARuntimeOptions.playerAutoCloseAfterSeconds
        _ = QARuntimeOptions.playerAspectRatioSelection
        _ = QARuntimeOptions.showAspectRatioBadge
        _ = QARuntimeOptions.autoOpenResetSheet
        _ = QARuntimeOptions.autoExecuteReset
        _ = QARuntimeOptions.traktRefreshFixturePath
        _ = QARuntimeOptions.traktRefreshDelaySeconds
        _ = QARuntimeOptions.forceCompactNavScale
        _ = QARuntimeOptions.setupAutoAdvance
        _ = QARuntimeOptions.setupTMDBApiKey
        _ = QARuntimeOptions.setupPreferredQuality
        _ = QARuntimeOptions.setupSubtitleLanguage
    }
}
