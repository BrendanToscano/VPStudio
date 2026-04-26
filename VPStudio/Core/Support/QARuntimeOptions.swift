import Foundation

struct QADebridFixture: Sendable, Equatable {
    var hash: String
    var serviceType: DebridServiceType
    var streamURLs: [URL]
    var fileName: String
}

/// Lightweight QA runtime switches used only for simulator/manual validation flows.
enum QARuntimeOptions {
    enum DownloadAction: String {
        case cancelFirstActive
        case retryFirstFailed
        case removeFirst
        case removeFirstGroup
        case playFirstCompleted
    }

    struct EnvironmentSnapshot: Sendable {
        var values: [String: String]

        init(_ values: [String: String] = ProcessInfo.processInfo.environment) {
            self.values = values
        }

        var isQAEnabled: Bool {
            values.keys.contains { $0.hasPrefix("VPSTUDIO_QA_") || $0.hasPrefix("SIMCTL_CHILD_VPSTUDIO_QA_") }
        }

        func value(_ key: String) -> String? {
            values[key] ?? values["SIMCTL_CHILD_\(key)"]
        }

        func bool(_ key: String) -> Bool {
            guard let value = value(key)?.lowercased() else { return false }
            return ["1", "true", "yes", "on"].contains(value)
        }

        func string(_ key: String) -> String? {
            guard let value = value(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }

        func double(_ key: String) -> Double? {
            guard let value = value(key) else { return nil }
            return Double(value)
        }

        func stringList(_ key: String) -> [String] {
            guard let value = value(key) else { return [] }
            return value
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    static let environment = EnvironmentSnapshot()

    static let isEnabled = environment.isQAEnabled

    private static func env(_ key: String) -> String? {
        environment.value(key)
    }

    private static func bool(_ key: String) -> Bool {
        environment.bool(key)
    }

    private static func string(_ key: String) -> String? {
        environment.string(key)
    }

    private static func double(_ key: String) -> Double? {
        environment.double(key)
    }

    private static func stringList(_ key: String) -> [String] {
        environment.stringList(key)
    }

    static func absoluteURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme,
              !scheme.isEmpty,
              url.host != nil else {
            return nil
        }
        return url
    }

    static func sampleURLs(from snapshot: EnvironmentSnapshot) -> [URL] {
        let configured = snapshot.stringList("VPSTUDIO_QA_SAMPLE_URLS").compactMap(absoluteURL(from:))
        if !configured.isEmpty {
            return configured
        }
        if let sampleURL = snapshot.value("VPSTUDIO_QA_SAMPLE_URL").flatMap(absoluteURL(from:)) {
            return [sampleURL]
        }
        return []
    }

    static func debridFixture(from snapshot: EnvironmentSnapshot) -> QADebridFixture? {
        guard let hash = snapshot.string("VPSTUDIO_QA_DEBRID_FIXTURE_HASH")?.lowercased() else {
            return nil
        }

        let streamURLs = snapshot.stringList("VPSTUDIO_QA_DEBRID_FIXTURE_URLS").compactMap(absoluteURL(from:))
        guard !streamURLs.isEmpty else { return nil }

        let serviceType = snapshot.string("VPSTUDIO_QA_DEBRID_FIXTURE_SERVICE")
            .flatMap(DebridServiceType.init(rawValue:)) ?? .realDebrid
        let fileName = snapshot.string("VPSTUDIO_QA_DEBRID_FIXTURE_FILE_NAME")
            ?? "QA.Debrid.\(hash.prefix(8)).mp4"

        return QADebridFixture(
            hash: hash,
            serviceType: serviceType,
            streamURLs: streamURLs,
            fileName: fileName
        )
    }

    static func syntheticTorrent(from snapshot: EnvironmentSnapshot) -> TorrentResult? {
        guard let fixture = debridFixture(from: snapshot) else { return nil }

        var torrent = TorrentResult.fromSearch(
            infoHash: fixture.hash,
            title: snapshot.string("VPSTUDIO_QA_SYNTHETIC_TORRENT_TITLE") ?? fixture.fileName,
            sizeBytes: 1_500_000_000,
            seeders: 42,
            leechers: 3,
            indexerName: "QA Debrid Fixture"
        )
        torrent.isCached = true
        torrent.cachedOnService = fixture.serviceType.rawValue
        return torrent
    }

    static let searchQuery = env("VPSTUDIO_QA_SEARCH_QUERY")
    static let autoSubmitSearchQuery = bool("VPSTUDIO_QA_AUTO_SUBMIT_SEARCH")
    static let postSubmitDraftQuery = env("VPSTUDIO_QA_POST_SUBMIT_DRAFT_QUERY")
    static let postSubmitDraftDelaySeconds = double("VPSTUDIO_QA_POST_SUBMIT_DRAFT_DELAY_SECONDS")
        ?? double("VPSTUDIO_QA_POST_SUBMIT_DRAFT_DELAY")
        ?? 1.0
    static let preferredResultTitle = env("VPSTUDIO_QA_PREFERRED_RESULT_TITLE")
    static let autoOpenFirstSearchResult = bool("VPSTUDIO_QA_AUTO_OPEN_FIRST_RESULT")
    static let scrollDebug = bool("VPSTUDIO_QA_SCROLL_DEBUG")
    static let autoOpenSearchFilterSheet = bool("VPSTUDIO_QA_AUTO_OPEN_FILTER_SHEET")
    static let autoApplySearchFilterSheet = bool("VPSTUDIO_QA_AUTO_APPLY_FILTER_SHEET")
    static let autoSelectFilterGenre = bool("VPSTUDIO_QA_AUTO_SELECT_FILTER_GENRE")
    static let autoSelectMoodCard = bool("VPSTUDIO_QA_AUTO_SELECT_MOOD_CARD")

    static let selectedSeason = Int(env("VPSTUDIO_QA_SELECTED_SEASON") ?? "")
    static let selectedEpisode = Int(env("VPSTUDIO_QA_SELECTED_EPISODE") ?? "")
    static let libraryList = env("VPSTUDIO_QA_LIBRARY_LIST").flatMap(UserLibraryEntry.ListType.init(rawValue:))

    static let autoAddWatchlist = bool("VPSTUDIO_QA_AUTO_ADD_WATCHLIST")
    static let autoAddFavorites = bool("VPSTUDIO_QA_AUTO_ADD_FAVORITES")
    static let autoRemoveWatchlist = bool("VPSTUDIO_QA_AUTO_REMOVE_WATCHLIST")
    static let autoRemoveFavorites = bool("VPSTUDIO_QA_AUTO_REMOVE_FAVORITES")
    static let sampleURL = env("VPSTUDIO_QA_SAMPLE_URL").flatMap(absoluteURL(from:))
    static let sampleURLs = sampleURLs(from: environment)
    static let sampleRefreshURL = env("VPSTUDIO_QA_SAMPLE_REFRESH_URL").flatMap(absoluteURL(from:))
    static let sampleRefreshSignalURL = env("VPSTUDIO_QA_SAMPLE_REFRESH_SIGNAL_URL").flatMap(absoluteURL(from:))
    static let autoQueueSampleDownload = bool("VPSTUDIO_QA_AUTO_QUEUE_SAMPLE_DOWNLOAD")
    static let autoPlaySample = bool("VPSTUDIO_QA_AUTO_PLAY_SAMPLE")
    static let debridFixture = debridFixture(from: environment)
    static let autoPlaySyntheticTorrent = bool("VPSTUDIO_QA_AUTO_PLAY_SYNTHETIC_TORRENT")
    static let syntheticTorrent = syntheticTorrent(from: environment)

    static let downloadAction = env("VPSTUDIO_QA_DOWNLOAD_ACTION").flatMap(DownloadAction.init(rawValue:))
    static let playerAutoCloseAfterSeconds = double("VPSTUDIO_QA_PLAYER_AUTOCLOSE_SECONDS")
    static let playerAspectRatioSelection = env("VPSTUDIO_QA_PLAYER_ASPECT_RATIO")
    static let showAspectRatioBadge = bool("VPSTUDIO_QA_SHOW_ASPECT_BADGE")

    static let autoOpenResetSheet = bool("VPSTUDIO_QA_AUTO_OPEN_RESET_SHEET")
    static let autoExecuteReset = bool("VPSTUDIO_QA_AUTO_EXECUTE_RESET")
    static let traktRefreshFixturePath = string("VPSTUDIO_QA_TRAKT_REFRESH_FIXTURE")
    static let traktRefreshDelaySeconds = double("VPSTUDIO_QA_TRAKT_REFRESH_DELAY_SECONDS")
        ?? double("VPSTUDIO_QA_TRAKT_REFRESH_DELAY")

    // QA-only visual/debug helpers for deterministic screenshot capture.
    static let forceCompactNavScale = bool("VPSTUDIO_QA_FORCE_COMPACT_NAV_SCALE")

    static let setupAutoAdvance = bool("VPSTUDIO_QA_SETUP_AUTO_ADVANCE")
    static let setupTMDBApiKey = env("VPSTUDIO_QA_SETUP_TMDB_API_KEY")
    static let setupPreferredQuality = env("VPSTUDIO_QA_SETUP_PREFERRED_QUALITY").flatMap(VideoQuality.init(rawValue:))
    static let setupSubtitleLanguage = env("VPSTUDIO_QA_SETUP_SUBTITLE_LANGUAGE").flatMap(SubtitleLanguageOption.init(rawValue:))

    static func sleepNanoseconds(for seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}
