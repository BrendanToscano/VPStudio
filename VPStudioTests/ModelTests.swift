import Testing
import Foundation
@testable import VPStudio

// MARK: - VideoQuality Parsing Tests

@Suite("VideoQuality Parsing")
struct VideoQualityParsingTests {

    @Test func parsesUHD4KVariants() {
        #expect(VideoQuality.parse(from: "Movie.2025.2160p.WEB-DL") == .uhd4k)
        #expect(VideoQuality.parse(from: "Movie.4K.BluRay") == .uhd4k)
        #expect(VideoQuality.parse(from: "Movie.UHD.x265") == .uhd4k)
    }

    @Test func parses1080pVariants() {
        #expect(VideoQuality.parse(from: "Movie.1080p.BluRay") == .hd1080p)
        #expect(VideoQuality.parse(from: "Movie.1080i.HDTV") == .hd1080p)
    }

    @Test func parses720p() {
        #expect(VideoQuality.parse(from: "Movie.720p.WEBRip") == .hd720p)
    }

    @Test func parses480p() {
        #expect(VideoQuality.parse(from: "Movie.480p.DVDRip") == .sd480p)
    }

    @Test func parsesSDFromDVDRipAndCam() {
        #expect(VideoQuality.parse(from: "Movie.SD.XviD") == .sd)
        #expect(VideoQuality.parse(from: "Movie.DVDRip.XviD") == .sd)
        #expect(VideoQuality.parse(from: "Movie.CAM.2025") == .sd)
    }

    @Test func returnsUnknownForUnrecognizedQuality() {
        #expect(VideoQuality.parse(from: "Movie.2025") == .unknown)
        #expect(VideoQuality.parse(from: "") == .unknown)
    }

    @Test func sdDoesNotFalsePositiveOnSubstrings() {
        // P2-002: "sd" substring should not match in words like "Wednesday"
        #expect(VideoQuality.parse(from: "Wednesday.S01E01.1080p") != .sd)
        #expect(VideoQuality.parse(from: "SDR.Movie.1080p") != .sd)
    }

    @Test func qualityComparableOrderIsCorrect() {
        #expect(VideoQuality.sd < VideoQuality.hd720p)
        #expect(VideoQuality.hd720p < VideoQuality.hd1080p)
        #expect(VideoQuality.hd1080p < VideoQuality.uhd4k)
        #expect(VideoQuality.unknown < VideoQuality.sd)
    }

    @Test func sortOrderMatchesEnumIntent() {
        #expect(VideoQuality.uhd4k.sortOrder == 5)
        #expect(VideoQuality.hd1080p.sortOrder == 4)
        #expect(VideoQuality.hd720p.sortOrder == 3)
        #expect(VideoQuality.sd480p.sortOrder == 2)
        #expect(VideoQuality.sd.sortOrder == 1)
        #expect(VideoQuality.unknown.sortOrder == 0)
    }
}

// MARK: - VideoCodec Parsing Tests

@Suite("VideoCodec Parsing")
struct VideoCodecParsingTests {

    @Test func parsesH265Variants() {
        #expect(VideoCodec.parse(from: "Movie.x265.1080p") == .h265)
        #expect(VideoCodec.parse(from: "Movie.H265.BluRay") == .h265)
        #expect(VideoCodec.parse(from: "Movie.H.265") == .h265)
        #expect(VideoCodec.parse(from: "Movie.HEVC.10bit") == .h265)
    }

    @Test func parsesH264Variants() {
        #expect(VideoCodec.parse(from: "Movie.x264.1080p") == .h264)
        #expect(VideoCodec.parse(from: "Movie.H264") == .h264)
        #expect(VideoCodec.parse(from: "Movie.H.264") == .h264)
        #expect(VideoCodec.parse(from: "Movie.AVC.BluRay") == .h264)
    }

    @Test func parsesAV1() {
        #expect(VideoCodec.parse(from: "Movie.AV1.2160p") == .av1)
    }

    @Test func parsesXviDAndDivX() {
        #expect(VideoCodec.parse(from: "Movie.XviD") == .xvid)
        #expect(VideoCodec.parse(from: "Movie.DivX.DVDRip") == .xvid)
    }

    @Test func returnsUnknownForUnrecognizedCodec() {
        #expect(VideoCodec.parse(from: "Movie.2025.1080p") == .unknown)
        #expect(VideoCodec.parse(from: "") == .unknown)
    }

    @Test func avcDoesNotFalsePositiveOnSubstrings() {
        // P2-003: "avc" substring should not match in words like "advanced"
        #expect(VideoCodec.parse(from: "Advanced.Feature.1080p") == .unknown)
    }
}

// MARK: - AudioFormat Parsing Tests

@Suite("AudioFormat Parsing")
struct AudioFormatParsingTests {

    @Test func parsesAtmos() {
        #expect(AudioFormat.parse(from: "Movie.2025.Atmos.TrueHD") == .atmos)
    }

    @Test func parsesDTSHDMA() {
        #expect(AudioFormat.parse(from: "Movie.DTS-HD.MA.1080p") == .dtsHDMA)
        #expect(AudioFormat.parse(from: "Movie.DTS.HD.MA") == .dtsHDMA)
        #expect(AudioFormat.parse(from: "Movie.DTSHD") == .dtsHDMA)
    }

    @Test func parsesTrueHD() {
        #expect(AudioFormat.parse(from: "Movie.TrueHD.7.1") == .trueHD)
        #expect(AudioFormat.parse(from: "Movie.True-HD") == .trueHD)
    }

    @Test func parsesEAC3Variants() {
        #expect(AudioFormat.parse(from: "Movie.EAC3.5.1") == .eac3)
        #expect(AudioFormat.parse(from: "Movie.E-AC3") == .eac3)
        #expect(AudioFormat.parse(from: "Movie.DDP5.1") == .eac3)
    }

    @Test func parsesDTS() {
        #expect(AudioFormat.parse(from: "Movie.DTS.5.1") == .dts)
    }

    @Test func parsesAC3Variants() {
        #expect(AudioFormat.parse(from: "Movie.AC3.5.1") == .ac3)
        #expect(AudioFormat.parse(from: "Movie.AC-3") == .ac3)
        #expect(AudioFormat.parse(from: "Movie.DD5.1") == .ac3)
        #expect(AudioFormat.parse(from: "Movie.DD2.0") == .ac3)
    }

    @Test func parsesAACAndFLAC() {
        #expect(AudioFormat.parse(from: "Movie.AAC.2.0") == .aac)
        #expect(AudioFormat.parse(from: "Movie.FLAC.5.1") == .flac)
    }

    @Test func spatialAudioHintIsCorrect() {
        #expect(AudioFormat.atmos.spatialAudioHint == true)
        #expect(AudioFormat.dtsHDMA.spatialAudioHint == true)
        #expect(AudioFormat.trueHD.spatialAudioHint == true)
        #expect(AudioFormat.aac.spatialAudioHint == false)
        #expect(AudioFormat.ac3.spatialAudioHint == false)
        #expect(AudioFormat.unknown.spatialAudioHint == false)
    }

    @Test func returnsUnknownForUnrecognizedAudio() {
        #expect(AudioFormat.parse(from: "Movie.2025") == .unknown)
    }
}

// MARK: - SourceType Parsing Tests

@Suite("SourceType Parsing")
struct SourceTypeParsingTests {

    @Test func parsesBluRayVariants() {
        #expect(SourceType.parse(from: "Movie.BluRay.1080p") == .bluRay)
        #expect(SourceType.parse(from: "Movie.Blu-Ray") == .bluRay)
        #expect(SourceType.parse(from: "Movie.BDRip") == .bluRay)
        #expect(SourceType.parse(from: "Movie.BRRip") == .bluRay)
    }

    @Test func parsesWebDLVariants() {
        #expect(SourceType.parse(from: "Movie.WEB-DL.1080p") == .webDL)
        #expect(SourceType.parse(from: "Movie.WEBDL") == .webDL)
    }

    @Test func parsesWebRipVariants() {
        #expect(SourceType.parse(from: "Movie.WEBRip") == .webRip)
        #expect(SourceType.parse(from: "Movie.WEB-Rip") == .webRip)
    }

    @Test func parsesHDRipAndDVDRip() {
        #expect(SourceType.parse(from: "Movie.HDRip") == .hdRip)
        #expect(SourceType.parse(from: "Movie.DVDRip") == .dvdRip)
        #expect(SourceType.parse(from: "Movie.DVD-Rip") == .dvdRip)
    }

    @Test func parsesHDTV() {
        #expect(SourceType.parse(from: "Movie.HDTV.720p") == .hdtv)
    }

    @Test func parsesCAMVariants() {
        #expect(SourceType.parse(from: "Movie.HDCAM.2025") == .cam)
        #expect(SourceType.parse(from: "Movie.Telesync.2025") == .cam)
    }

    @Test func qualityTierOrderIsCorrect() {
        #expect(SourceType.bluRay.qualityTier > SourceType.webDL.qualityTier)
        #expect(SourceType.webDL.qualityTier > SourceType.webRip.qualityTier)
        #expect(SourceType.webRip.qualityTier > SourceType.hdRip.qualityTier)
        #expect(SourceType.cam.qualityTier < SourceType.dvdRip.qualityTier)
        #expect(SourceType.unknown.qualityTier == 0)
    }
}

// MARK: - HDRFormat Parsing Tests

@Suite("HDRFormat Parsing")
struct HDRFormatParsingTests {

    @Test func parsesDolbyVisionVariants() {
        #expect(HDRFormat.parse(from: "Movie.Dolby.Vision") == .dolbyVision)
        #expect(HDRFormat.parse(from: "Movie.DolbyVision") == .dolbyVision)
        #expect(HDRFormat.parse(from: "Movie.DoVi.2160p") == .dolbyVision)
    }

    @Test func parsesHDR10Plus() {
        #expect(HDRFormat.parse(from: "Movie.HDR10+.2160p") == .hdr10Plus)
        #expect(HDRFormat.parse(from: "Movie.HDR10Plus") == .hdr10Plus)
    }

    @Test func parsesHDR10AndGenericHDR() {
        #expect(HDRFormat.parse(from: "Movie.HDR10.2160p") == .hdr10)
        #expect(HDRFormat.parse(from: "Movie.HDR.UHD") == .hdr10)
    }

    @Test func parsesHLG() {
        #expect(HDRFormat.parse(from: "Movie.HLG.2160p") == .hlg)
    }

    @Test func returnsSDRForNoHDRInfo() {
        #expect(HDRFormat.parse(from: "Movie.1080p.BluRay") == .sdr)
        #expect(HDRFormat.parse(from: "") == .sdr)
    }

    @Test func hdrDoesNotFalsePositiveOnHDRip() {
        // P1-004: "HDRip" is an SDR source tag, not HDR content
        #expect(HDRFormat.parse(from: "Movie.HDRip.1080p") == .sdr)
        #expect(HDRFormat.parse(from: "Movie.1080p.HDRip.x264") == .sdr)
    }

    @Test func hdrStandaloneStillMatchesHDR10() {
        // Standalone "HDR" should still match
        #expect(HDRFormat.parse(from: "Movie.HDR.2160p") == .hdr10)
        #expect(HDRFormat.parse(from: "Movie.2160p.HDR.BluRay") == .hdr10)
    }
}

// MARK: - StreamInfo Tests

@Suite("StreamInfo")
struct StreamInfoTests {

    @Test func sizeStringFormatsGigabytes() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "a.mkv",
            sizeBytes: 2_684_354_560, // 2.5 GB
            debridService: "rd"
        )
        #expect(stream.sizeString == "2.5 GB")
    }

    @Test func sizeStringFormatsMegabytes() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv")!,
            quality: .hd720p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "a.mkv",
            sizeBytes: 524_288_000, // 500 MB
            debridService: "rd"
        )
        #expect(stream.sizeString == "500 MB")
    }

    @Test func sizeStringIsEmptyWhenNil() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "a.mkv",
            sizeBytes: nil,
            debridService: "rd"
        )
        #expect(stream.sizeString == "")
    }

    @Test func qualityBadgeOmitsUnknownValues() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv")!,
            quality: .hd1080p, codec: .unknown, audio: .unknown,
            source: .webDL, hdr: .sdr, fileName: "a.mkv",
            sizeBytes: 1000, debridService: "rd"
        )
        #expect(stream.qualityBadge == "1080p")
    }

    @Test func qualityBadgeCombinesAllKnownValues() {
        let stream = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv")!,
            quality: .uhd4k, codec: .h265, audio: .atmos,
            source: .bluRay, hdr: .dolbyVision, fileName: "a.mkv",
            sizeBytes: 1000, debridService: "rd"
        )
        #expect(stream.qualityBadge == "4K / DV / H.265 / Atmos")
    }

    @Test func idIsStableAcrossURLChanges() {
        let a = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv?token=abc")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "same.mkv",
            sizeBytes: 1000, debridService: "rd"
        )
        let b = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv?token=xyz")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "same.mkv",
            sizeBytes: 1000, debridService: "rd"
        )
        // Same logical stream with different tokens should have same ID
        #expect(a.id == b.id)
    }

    @Test func idDiffersByQualityOrCodec() {
        let a = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv")!,
            quality: .hd1080p, codec: .h264, audio: .aac,
            source: .webDL, hdr: .sdr, fileName: "movie.mkv",
            sizeBytes: 1000, debridService: "rd"
        )
        let b = StreamInfo(
            streamURL: URL(string: "https://example.com/a.mkv")!,
            quality: .uhd4k, codec: .h265, audio: .atmos,
            source: .bluRay, hdr: .dolbyVision, fileName: "movie.mkv",
            sizeBytes: 5000, debridService: "rd"
        )
        #expect(a.id != b.id)
    }
}

// MARK: - TorrentResult Tests

@Suite("TorrentResult")
struct TorrentResultTests {

    @Test func fromSearchParsesQualityFromTitle() {
        let result = TorrentResult.fromSearch(
            infoHash: "ABC123",
            title: "Movie.2025.2160p.BluRay.DV.x265.Atmos-GROUP",
            sizeBytes: 50_000_000_000,
            seeders: 100,
            leechers: 10,
            indexerName: "YTS"
        )
        #expect(result.quality == .uhd4k)
        #expect(result.source == .bluRay)
        #expect(result.hdr == .dolbyVision)
        #expect(result.codec == .h265)
        #expect(result.audio == .atmos)
    }

    @Test func fromSearchLowercasesInfoHash() {
        let result = TorrentResult.fromSearch(
            infoHash: "ABCDEF123456",
            title: "Movie.1080p",
            sizeBytes: 1000,
            seeders: 5,
            leechers: 1,
            indexerName: "APIBay"
        )
        #expect(result.infoHash == "abcdef123456")
    }

    @Test func sizeStringFormatsCorrectly() {
        let small = TorrentResult(
            infoHash: "a", title: "", sizeBytes: 734_003_200, // ~700 MB
            seeders: 0, leechers: 0, quality: .unknown, codec: .unknown,
            audio: .unknown, source: .unknown, hdr: .sdr, indexerName: ""
        )
        #expect(small.sizeString == "700 MB")

        let large = TorrentResult(
            infoHash: "b", title: "", sizeBytes: 4_294_967_296, // 4 GB
            seeders: 0, leechers: 0, quality: .unknown, codec: .unknown,
            audio: .unknown, source: .unknown, hdr: .sdr, indexerName: ""
        )
        #expect(large.sizeString == "4.0 GB")
    }

    @Test func qualityBadgeIncludesSource() {
        let result = TorrentResult(
            infoHash: "a", title: "", sizeBytes: 0,
            seeders: 0, leechers: 0,
            quality: .hd1080p, codec: .h265, audio: .eac3,
            source: .webDL, hdr: .hdr10, indexerName: ""
        )
        #expect(result.qualityBadge.contains("WEB-DL"))
        #expect(result.qualityBadge.contains("1080p"))
        #expect(result.qualityBadge.contains("HDR10"))
    }

    @Test func idIncludesIndexerName() {
        let result = TorrentResult(
            infoHash: "abc123", title: "", sizeBytes: 0,
            seeders: 0, leechers: 0, quality: .unknown, codec: .unknown,
            audio: .unknown, source: .unknown, hdr: .sdr, indexerName: "YTS"
        )
        #expect(result.id == "abc123-YTS")
    }

    @Test func sameHashDifferentIndexersHaveDifferentIds() {
        let a = TorrentResult.fromSearch(
            infoHash: "abc123", title: "Movie", sizeBytes: 1000,
            seeders: 10, leechers: 5, indexerName: "YTS"
        )
        let b = TorrentResult.fromSearch(
            infoHash: "abc123", title: "Movie", sizeBytes: 1000,
            seeders: 20, leechers: 3, indexerName: "EZTV"
        )
        #expect(a.id != b.id)
    }
}

// MARK: - WatchHistory Tests

@Suite("WatchHistory")
struct WatchHistoryTests {

    @Test func progressPercentCalculation() {
        let history = WatchHistory(
            id: "1", mediaId: "m1", title: "Movie",
            progress: 3600, duration: 7200, watchedAt: Date(), isCompleted: false
        )
        #expect(abs(history.progressPercent - 0.5) < 0.001)
    }

    @Test func progressPercentCapsAtOne() {
        let history = WatchHistory(
            id: "1", mediaId: "m1", title: "Movie",
            progress: 9000, duration: 7200, watchedAt: Date(), isCompleted: true
        )
        #expect(history.progressPercent == 1.0)
    }

    @Test func progressPercentIsZeroWhenDurationIsZero() {
        let history = WatchHistory(
            id: "1", mediaId: "m1", title: "Movie",
            progress: 100, duration: 0, watchedAt: Date(), isCompleted: false
        )
        #expect(history.progressPercent == 0)
    }

    @Test func progressStringFormatsMinutes() {
        let history = WatchHistory(
            id: "1", mediaId: "m1", title: "Movie",
            progress: 1800, duration: 5400, watchedAt: Date(), isCompleted: false
        )
        #expect(history.progressString == "30m / 90m")
    }

    @Test func remainingStringFormatsMinutes() {
        let history = WatchHistory(
            id: "1", mediaId: "m1", title: "Movie",
            progress: 1800, duration: 5400, watchedAt: Date(), isCompleted: false
        )
        #expect(history.remainingString == "60m remaining")
    }

    @Test func remainingStringDoesNotGoNegative() {
        let history = WatchHistory(
            id: "1", mediaId: "m1", title: "Movie",
            progress: 6000, duration: 5400, watchedAt: Date(), isCompleted: true
        )
        #expect(history.remainingString == "0m remaining")
    }
}

// MARK: - Episode Tests

@Suite("Episode")
struct EpisodeTests {

    @Test func displayTitleFormatsWithTitle() {
        let episode = Episode(id: "1", mediaId: "m1", seasonNumber: 2, episodeNumber: 5, title: "Pilot")
        #expect(episode.displayTitle == "S02E05 - Pilot")
    }

    @Test func displayTitleFormatsWithoutTitle() {
        let episode = Episode(id: "1", mediaId: "m1", seasonNumber: 1, episodeNumber: 1, title: nil)
        #expect(episode.displayTitle == "S01E01")
    }

    @Test func displayTitleFormatsWithEmptyTitle() {
        let episode = Episode(id: "1", mediaId: "m1", seasonNumber: 1, episodeNumber: 1, title: "")
        #expect(episode.displayTitle == "S01E01")
    }

    @Test func shortLabelFormats() {
        let episode = Episode(id: "1", mediaId: "m1", seasonNumber: 10, episodeNumber: 3)
        #expect(episode.shortLabel == "S10E03")
    }

    @Test func stillURLConstructsFromPath() {
        let episode = Episode(id: "1", mediaId: "m1", seasonNumber: 1, episodeNumber: 1, stillPath: "/abc.jpg")
        #expect(episode.stillURL?.absoluteString == "https://image.tmdb.org/t/p/w300/abc.jpg")
    }

    @Test func stillURLIsNilWhenNoPath() {
        let episode = Episode(id: "1", mediaId: "m1", seasonNumber: 1, episodeNumber: 1, stillPath: nil)
        #expect(episode.stillURL == nil)
    }
}

// MARK: - MediaItem Tests

@Suite("MediaItem")
struct MediaItemTests {

    @Test func posterURLConstructsFromPath() {
        let item = MediaItem(id: "1", type: .movie, title: "Test", posterPath: "/poster.jpg")
        #expect(item.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/poster.jpg")
    }

    @Test func posterURLIsNilWhenNoPath() {
        let item = MediaItem(id: "1", type: .movie, title: "Test", posterPath: nil)
        #expect(item.posterURL == nil)
    }

    @Test func backdropURLConstructsFromPath() {
        let item = MediaItem(id: "1", type: .movie, title: "Test", backdropPath: "/bg.jpg")
        #expect(item.backdropURL?.absoluteString == "https://image.tmdb.org/t/p/original/bg.jpg")
    }

    @Test func yearStringFormatsCorrectly() {
        let withYear = MediaItem(id: "1", type: .movie, title: "Test", year: 2025)
        #expect(withYear.yearString == "2025")

        let withoutYear = MediaItem(id: "1", type: .movie, title: "Test", year: nil)
        #expect(withoutYear.yearString == "")
    }

    @Test func ratingStringFormatsCorrectly() {
        let rated = MediaItem(id: "1", type: .movie, title: "Test", imdbRating: 7.56)
        #expect(rated.ratingString == "7.6")

        let unrated = MediaItem(id: "1", type: .movie, title: "Test", imdbRating: nil)
        #expect(unrated.ratingString == "")
    }

    @Test func runtimeStringFormatsHoursAndMinutes() {
        let long = MediaItem(id: "1", type: .movie, title: "Test", runtime: 148)
        #expect(long.runtimeString == "2h 28m")

        let short = MediaItem(id: "1", type: .movie, title: "Test", runtime: 45)
        #expect(short.runtimeString == "45m")

        let noRuntime = MediaItem(id: "1", type: .movie, title: "Test", runtime: nil)
        #expect(noRuntime.runtimeString == "")
    }
}

// MARK: - Subtitle Tests

@Suite("Subtitle")
struct SubtitleTests {

    @Test func subtitleFormatParsesFromFilename() {
        #expect(SubtitleFormat.parse(from: "movie.srt") == .srt)
        #expect(SubtitleFormat.parse(from: "movie.vtt") == .vtt)
        #expect(SubtitleFormat.parse(from: "movie.webvtt") == .vtt)
        #expect(SubtitleFormat.parse(from: "movie.ass") == .ass)
        #expect(SubtitleFormat.parse(from: "movie.ssa") == .ssa)
        #expect(SubtitleFormat.parse(from: "movie.txt") == .unknown)
        #expect(SubtitleFormat.parse(from: "noextension") == .unknown)
    }

    @Test func displayNameIncludesLanguage() {
        let sub = Subtitle(id: "1", language: "en", fileName: "a.srt", url: "https://x.com/a.srt", format: .srt)
        #expect(sub.displayName == "EN")
    }

    @Test func displayNameIncludesHIWhenSet() {
        let sub = Subtitle(id: "1", language: "en", fileName: "a.srt", url: "https://x.com/a.srt", format: .srt, isHearingImpaired: true)
        #expect(sub.displayName == "EN (HI)")
    }

    @Test func displayNameOmitsHIWhenFalse() {
        let sub = Subtitle(id: "1", language: "en", fileName: "a.srt", url: "https://x.com/a.srt", format: .srt, isHearingImpaired: false)
        #expect(sub.displayName == "EN")
    }

    @Test func downloadURLParsesValidURL() {
        let sub = Subtitle(id: "1", language: "en", fileName: "a.srt", url: "https://example.com/a.srt", format: .srt)
        #expect(sub.downloadURL != nil)
        #expect(sub.downloadURL?.host == "example.com")
    }
}

// MARK: - DownloadStatus Tests

@Suite("DownloadStatus")
struct DownloadStatusTests {

    @Test func terminalStatesAreCorrect() {
        #expect(DownloadStatus.completed.isTerminal == true)
        #expect(DownloadStatus.failed.isTerminal == true)
        #expect(DownloadStatus.cancelled.isTerminal == true)
    }

    @Test func nonTerminalStatesAreCorrect() {
        #expect(DownloadStatus.queued.isTerminal == false)
        #expect(DownloadStatus.resolving.isTerminal == false)
        #expect(DownloadStatus.downloading.isTerminal == false)
    }
}

// MARK: - DownloadTask Tests

@Suite("DownloadTask")
struct DownloadTaskTests {

    @Test func destinationURLConstructsFromPath() {
        let task = DownloadTask(
            mediaId: "m1", streamURL: "https://x.com/a.mkv",
            fileName: "a.mkv", destinationPath: "/tmp/vpstudio-tests/a.mkv"
        )
        #expect(task.destinationURL?.path == "/tmp/vpstudio-tests/a.mkv")
    }

    @Test func destinationURLIsNilWhenNoPath() {
        let task = DownloadTask(
            mediaId: "m1", streamURL: "https://x.com/a.mkv",
            fileName: "a.mkv", destinationPath: nil
        )
        #expect(task.destinationURL == nil)
    }
}

// MARK: - UserLibraryEntry Tests

@Suite("UserLibraryEntry")
struct UserLibraryEntryTests {

    @Test func listTypeDisplayNames() {
        #expect(UserLibraryEntry.ListType.watchlist.displayName == "Watchlist")
        #expect(UserLibraryEntry.ListType.favorites.displayName == "Favorites")
        #expect(UserLibraryEntry.ListType.history.displayName == "History")
    }

    @Test func supportsFoldersIsCorrect() {
        #expect(UserLibraryEntry.ListType.watchlist.supportsFolders == true)
        #expect(UserLibraryEntry.ListType.favorites.supportsFolders == true)
        #expect(UserLibraryEntry.ListType.history.supportsFolders == false)
    }

    @Test func legacyCustomListTypeMapsToFavorites() {
        #expect(UserLibraryEntry.ListType.fromStoredValue("custom") == .favorites)
    }
}

// MARK: - LibraryFolder Tests

@Suite("LibraryFolder")
struct LibraryFolderTests {

    @Test func systemFolderIDsAreUniquePerListType() {
        let watchlistID = LibraryFolder.systemFolderID(for: .watchlist)
        let favoritesID = LibraryFolder.systemFolderID(for: .favorites)
        let historyID = LibraryFolder.systemFolderID(for: .history)

        #expect(watchlistID != favoritesID)
        #expect(favoritesID != historyID)
        #expect(watchlistID != historyID)
    }

    @Test func systemFolderIDFormat() {
        #expect(LibraryFolder.systemFolderID(for: .watchlist) == "system-watchlist")
        #expect(LibraryFolder.systemFolderID(for: .favorites) == "system-favorites")
    }

    @Test func systemFolderNames() {
        #expect(LibraryFolder.systemFolderName(for: .watchlist) == "Watchlist")
        #expect(LibraryFolder.systemFolderName(for: .favorites) == "Favorites")
        #expect(LibraryFolder.systemFolderName(for: .history) == "History")
    }

    @Test func specialFolderConstants() {
        #expect(LibraryFolder.watchedFolderID == "system-favorites-watched")
        #expect(LibraryFolder.releaseWaitFolderID == "system-favorites-release-wait")
    }
}

// MARK: - FeedbackScaleMode Tests

@Suite("FeedbackScaleMode")
struct FeedbackScaleModeTests {

    @Test func selectableModesMatchProductRequirements() {
        #expect(FeedbackScaleMode.selectableCases == [.likeDislike, .oneToTen, .oneToHundred])
    }

    @Test func legacyStoredValuesMapToCanonicalMode() {
        #expect(FeedbackScaleMode.fromStoredValue("ten_point") == .oneToTen)
        #expect(FeedbackScaleMode.fromStoredValue("five_star") == .oneToTen)
    }

    @Test func sentimentClassificationWorksAcrossScales() {
        #expect(FeedbackScaleMode.likeDislike.sentiment(for: 1) == .liked)
        #expect(FeedbackScaleMode.likeDislike.sentiment(for: 0) == .disliked)
        #expect(FeedbackScaleMode.oneToTen.sentiment(for: 9) == .liked)
        #expect(FeedbackScaleMode.oneToTen.sentiment(for: 2) == .disliked)
        #expect(FeedbackScaleMode.oneToTen.sentiment(for: 5) == .neutral)
        #expect(FeedbackScaleMode.oneToHundred.sentiment(for: 90) == .liked)
        #expect(FeedbackScaleMode.oneToHundred.sentiment(for: 20) == .disliked)
    }

    @Test func normalizedRoundTripKeepsIntent() {
        let normalized = FeedbackScaleMode.oneToTen.normalizedValue(8)
        let converted = FeedbackScaleMode.oneToHundred.value(fromNormalized: normalized)
        #expect(converted == 78)
    }
}

// MARK: - DebridServiceType Tests

@Suite("DebridServiceType")
struct DebridServiceTypeTests {

    @Test func allServicesHaveDisplayNames() {
        for service in DebridServiceType.allCases {
            #expect(!service.displayName.isEmpty)
        }
    }

    @Test func allServicesHaveBaseURLs() {
        for service in DebridServiceType.allCases {
            #expect(URL(string: service.baseURL) != nil)
        }
    }

    @Test func idMatchesRawValue() {
        for service in DebridServiceType.allCases {
            #expect(service.id == service.rawValue)
        }
    }
}

// MARK: - SecretReference Tests

@Suite("SecretReference")
struct SecretReferenceTests {

    @Test func encodeAddsPrefix() {
        let encoded = SecretReference.encode(key: "my.key")
        #expect(encoded == "keychain:my.key")
    }

    @Test func decodeStripsPrefix() {
        let decoded = SecretReference.decode("keychain:my.key")
        #expect(decoded == "my.key")
    }

    @Test func decodeReturnsNilForNonPrefixed() {
        let decoded = SecretReference.decode("plain-value")
        #expect(decoded == nil)
    }

    @Test func roundTripPreservesKey() {
        let original = "debrid.real_debrid.config-123"
        let encoded = SecretReference.encode(key: original)
        let decoded = SecretReference.decode(encoded)
        #expect(decoded == original)
    }
}

// MARK: - SecretKey Tests

@Suite("SecretKey")
struct SecretKeyTests {

    @Test func settingKeyFormat() {
        #expect(SecretKey.setting("tmdb_api_key") == "settings.tmdb_api_key")
    }

    @Test func debridTokenWithConfigId() {
        let key = SecretKey.debridToken(service: .realDebrid, configId: "abc")
        #expect(key == "debrid.real_debrid.abc")
    }

    @Test func debridTokenWithoutConfigId() {
        let key = SecretKey.debridToken(service: .allDebrid)
        #expect(key == "debrid.all_debrid")
    }
}

// MARK: - AIMovieRecommendation ID Tests

@Suite("AIMovieRecommendation - ID Uniqueness")
struct AIMovieRecommendationIDTests {

    @Test func idUsesTmdbIdWhenAvailable() {
        let rec = AIMovieRecommendation(title: "Dune", year: 2021, type: .movie, reason: "Great", tmdbId: 438631)
        #expect(rec.id == "movie-tmdb-438631")
    }

    @Test func idFallsBackToTitleYearType() {
        let rec = AIMovieRecommendation(title: "Dune", year: 2021, type: .movie, reason: "Great", tmdbId: nil)
        #expect(rec.id == "dune-2021-movie")
    }

    @Test func differentTypesProduceDifferentIds() {
        let movie = AIMovieRecommendation(title: "Test", year: 2025, type: .movie, reason: "r", tmdbId: nil)
        let series = AIMovieRecommendation(title: "Test", year: 2025, type: .series, reason: "r", tmdbId: nil)
        #expect(movie.id != series.id)
    }

    @Test func sameTitleYearButDifferentTmdbIdsAreUnique() {
        let a = AIMovieRecommendation(title: "Avatar", year: 2009, type: .movie, reason: "r", tmdbId: 19995)
        let b = AIMovieRecommendation(title: "Avatar", year: 2009, type: .movie, reason: "r", tmdbId: 99999)
        #expect(a.id != b.id)
    }
}

// MARK: - SidebarTab Tests

@Suite("SidebarTab")
struct SidebarTabTests {

    @Test func allTabsHaveIcons() {
        for tab in SidebarTab.allCases {
            #expect(!tab.icon.isEmpty)
        }
    }

    @Test func allTabsHaveUniqueIDs() {
        let ids = SidebarTab.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func idMatchesRawValue() {
        for tab in SidebarTab.allCases {
            #expect(tab.id == tab.rawValue)
        }
    }
}

// MARK: - EnvironmentType Tests

@Suite("EnvironmentType")
struct EnvironmentTypeTests {

    @Test func allEnvironmentsHaveDescriptions() {
        for env in EnvironmentType.allCases {
            #expect(!env.description.isEmpty)
        }
    }

    @Test func allEnvironmentsHaveIcons() {
        for env in EnvironmentType.allCases {
            #expect(!env.icon.isEmpty)
        }
    }

    @Test func allEnvironmentsHaveUniqueImmersiveSpaceIds() {
        let ids = EnvironmentType.allCases.map(\.immersiveSpaceId)
        #expect(Set(ids).count == ids.count)
    }

    @Test func idMatchesRawValue() {
        for env in EnvironmentType.allCases {
            #expect(env.id == env.rawValue)
        }
    }
}

// MARK: - Season Tests

@Suite("Season")
struct SeasonTests {

    @Test func posterURLConstructsFromPath() {
        let season = Season(id: 1, seasonNumber: 1, name: "Season 1", posterPath: "/s1.jpg", episodeCount: 10)
        #expect(season.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342/s1.jpg")
    }

    @Test func posterURLIsNilWhenNoPath() {
        let season = Season(id: 1, seasonNumber: 1, name: "Season 1", posterPath: nil, episodeCount: 10)
        #expect(season.posterURL == nil)
    }
}

// MARK: - MediaPreview Tests

@Suite("MediaPreview")
struct MediaPreviewTests {

    @Test func posterURLConstructsFromPath() {
        let preview = MediaPreview(id: "1", type: .movie, title: "Test", posterPath: "/p.jpg")
        #expect(preview.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w342/p.jpg")
    }

    @Test func posterURLIsNilWhenNoPath() {
        let preview = MediaPreview(id: "1", type: .movie, title: "Test", posterPath: nil)
        #expect(preview.posterURL == nil)
    }
}

// MARK: - IndexerConfig.IndexerType Tests

@Suite("IndexerConfig.IndexerType")
struct IndexerTypeTests {

    @Test func allTypesHaveNonEmptyDisplayName() {
        for type in IndexerConfig.IndexerType.allCases {
            #expect(!type.displayName.isEmpty, "Missing displayName for \(type)")
        }
    }

    @Test func displayNamesAreCorrect() {
        #expect(IndexerConfig.IndexerType.apiBay.displayName == "APiBay")
        #expect(IndexerConfig.IndexerType.yts.displayName == "YTS")
        #expect(IndexerConfig.IndexerType.eztv.displayName == "EZTV")
        #expect(IndexerConfig.IndexerType.jackett.displayName == "Jackett")
        #expect(IndexerConfig.IndexerType.prowlarr.displayName == "Prowlarr")
        #expect(IndexerConfig.IndexerType.torznab.displayName == "Torznab")
        #expect(IndexerConfig.IndexerType.zilean.displayName == "Zilean")
        #expect(IndexerConfig.IndexerType.stremio.displayName == "Stremio")
    }

    @Test func builtInTypesAreCorrect() {
        #expect(IndexerConfig.IndexerType.apiBay.isBuiltIn == true)
        #expect(IndexerConfig.IndexerType.yts.isBuiltIn == true)
        #expect(IndexerConfig.IndexerType.eztv.isBuiltIn == true)
    }

    @Test func nonBuiltInTypesAreCorrect() {
        #expect(IndexerConfig.IndexerType.jackett.isBuiltIn == false)
        #expect(IndexerConfig.IndexerType.prowlarr.isBuiltIn == false)
        #expect(IndexerConfig.IndexerType.torznab.isBuiltIn == false)
        #expect(IndexerConfig.IndexerType.zilean.isBuiltIn == false)
        #expect(IndexerConfig.IndexerType.stremio.isBuiltIn == false)
    }

    @Test func allCasesCount() {
        #expect(IndexerConfig.IndexerType.allCases.count == 8)
    }

    @Test func rawValuesAreUnique() {
        let rawValues = IndexerConfig.IndexerType.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }
}

// MARK: - LibraryFolder.FolderKind Tests

@Suite("LibraryFolder.FolderKind")
struct FolderKindTests {

    @Test func rawValuesAreCorrect() {
        #expect(LibraryFolder.FolderKind.systemRoot.rawValue == "system_root")
        #expect(LibraryFolder.FolderKind.manual.rawValue == "manual")
        #expect(LibraryFolder.FolderKind.watched.rawValue == "watched")
        #expect(LibraryFolder.FolderKind.releaseWait.rawValue == "release_wait")
    }

    @Test func rawValuesAreUnique() {
        let rawValues = LibraryFolder.FolderKind.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func allCasesCount() {
        #expect(LibraryFolder.FolderKind.allCases.count == 4)
    }

    @Test func roundTripFromRawValue() {
        for kind in LibraryFolder.FolderKind.allCases {
            let reconstructed = LibraryFolder.FolderKind(rawValue: kind.rawValue)
            #expect(reconstructed == kind)
        }
    }
}

// MARK: - PlayerEngineKind Tests

@Suite("PlayerEngineKind")
struct PlayerEngineKindTests {

    @Test func displayNamesAreNonEmpty() {
        for kind in PlayerEngineKind.allCases {
            #expect(!kind.displayName.isEmpty, "Missing displayName for \(kind)")
        }
    }

    @Test func displayNamesAreCorrect() {
        #expect(PlayerEngineKind.ksPlayer.displayName == "KSPlayer")
        #expect(PlayerEngineKind.avPlayer.displayName == "AVPlayer")
    }

    @Test func rawValuesAreUnique() {
        let rawValues = PlayerEngineKind.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }
}

// MARK: - PlayerPlaybackState Tests

@Suite("PlayerPlaybackState")
struct PlayerPlaybackStateTests {

    @Test func rawValuesAreUnique() {
        let all: [PlayerPlaybackState] = [.preparing, .buffering, .playing, .failed]
        let rawValues = all.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func expectedCasesExist() {
        #expect(PlayerPlaybackState.preparing.rawValue == "preparing")
        #expect(PlayerPlaybackState.buffering.rawValue == "buffering")
        #expect(PlayerPlaybackState.playing.rawValue == "playing")
        #expect(PlayerPlaybackState.failed.rawValue == "failed")
    }
}

// MARK: - AudioFormat Property Tests

@Suite("AudioFormat - Properties")
struct AudioFormatPropertyTests {

    @Test func surroundHintIsCorrect() {
        #expect(AudioFormat.atmos.surroundHint == true)
        #expect(AudioFormat.dtsHDMA.surroundHint == true)
        #expect(AudioFormat.trueHD.surroundHint == true)
        #expect(AudioFormat.dts.surroundHint == true)
        #expect(AudioFormat.ac3.surroundHint == true)
        #expect(AudioFormat.eac3.surroundHint == true)
        #expect(AudioFormat.aac.surroundHint == false)
        #expect(AudioFormat.flac.surroundHint == false)
        #expect(AudioFormat.unknown.surroundHint == false)
    }
}

// MARK: - SourceType CAM Standalone Token Tests

@Suite("SourceType - CAM Standalone Token")
struct SourceTypeCAMTests {

    @Test func camAsStandaloneTokenMatches() {
        #expect(SourceType.parse(from: "Movie.CAM.2025") == .cam)
    }

    @Test func camInsideWordDoesNotMatch() {
        // "camera" should not trigger .cam
        #expect(SourceType.parse(from: "Camera.Movie.1080p") != .cam)
    }

    @Test func tsAsStandaloneTokenMatches() {
        #expect(SourceType.parse(from: "Movie.TS.2025") == .cam)
    }

    @Test func tsInsideWordDoesNotMatch() {
        // "cats" should not trigger .cam from "ts"
        #expect(SourceType.parse(from: "Cats.Movie.1080p") != .cam)
    }
}
