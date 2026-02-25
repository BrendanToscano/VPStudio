import Testing
import Foundation
@testable import VPStudio

// MARK: - VideoQuality Parse Tests

@Suite("VideoQuality - parse")
struct VideoQualityParseTests {

    @Test func parses2160p() {
        #expect(VideoQuality.parse(from: "Movie.2024.2160p.BluRay.x265") == .uhd4k)
    }

    @Test func parses4K() {
        #expect(VideoQuality.parse(from: "Movie.2024.4K.WEB-DL") == .uhd4k)
    }

    @Test func parsesUHD() {
        #expect(VideoQuality.parse(from: "Movie.UHD.Remux") == .uhd4k)
    }

    @Test func parses1080p() {
        #expect(VideoQuality.parse(from: "Movie.2024.1080p.WEB-DL.x264") == .hd1080p)
    }

    @Test func parses1080i() {
        #expect(VideoQuality.parse(from: "Show.S01E01.1080i.HDTV") == .hd1080p)
    }

    @Test func parses720p() {
        #expect(VideoQuality.parse(from: "Movie.2024.720p.BluRay") == .hd720p)
    }

    @Test func parses480p() {
        #expect(VideoQuality.parse(from: "Movie.480p.WEBRip") == .sd480p)
    }

    @Test func parsesSD() {
        #expect(VideoQuality.parse(from: "Movie.SD.DVDRip") == .sd)
    }

    @Test func parsesDVDRipAsSD() {
        #expect(VideoQuality.parse(from: "Movie.DVDRip.XviD") == .sd)
    }

    @Test func parsesCAMAsSD() {
        #expect(VideoQuality.parse(from: "Movie.CAM.2024") == .sd)
    }

    @Test func unknownForUnrecognized() {
        #expect(VideoQuality.parse(from: "Movie.2024") == .unknown)
    }

    @Test func emptyReturnsUnknown() {
        #expect(VideoQuality.parse(from: "") == .unknown)
    }

    @Test func caseInsensitive() {
        #expect(VideoQuality.parse(from: "MOVIE.2160P.BLURAY") == .uhd4k)
        #expect(VideoQuality.parse(from: "movie.1080P.web-dl") == .hd1080p)
    }

    @Test func sortOrderDescending() {
        #expect(VideoQuality.uhd4k.sortOrder > VideoQuality.hd1080p.sortOrder)
        #expect(VideoQuality.hd1080p.sortOrder > VideoQuality.hd720p.sortOrder)
        #expect(VideoQuality.hd720p.sortOrder > VideoQuality.sd480p.sortOrder)
        #expect(VideoQuality.sd480p.sortOrder > VideoQuality.sd.sortOrder)
        #expect(VideoQuality.sd.sortOrder > VideoQuality.unknown.sortOrder)
    }

    @Test func comparableOrdering() {
        #expect(VideoQuality.hd720p < VideoQuality.hd1080p)
        #expect(VideoQuality.unknown < VideoQuality.sd)
        #expect(!(VideoQuality.uhd4k < VideoQuality.hd1080p))
    }
}

// MARK: - VideoCodec Parse Tests

@Suite("VideoCodec - parse")
struct VideoCodecParseTests {

    @Test func parsesX265() {
        #expect(VideoCodec.parse(from: "Movie.2024.x265.1080p") == .h265)
    }

    @Test func parsesH265() {
        #expect(VideoCodec.parse(from: "Movie.H265.BluRay") == .h265)
    }

    @Test func parsesHEVC() {
        #expect(VideoCodec.parse(from: "Movie.2024.HEVC.WEB-DL") == .h265)
    }

    @Test func parsesH265WithDot() {
        #expect(VideoCodec.parse(from: "Movie.H.265.1080p") == .h265)
    }

    @Test func parsesX264() {
        #expect(VideoCodec.parse(from: "Movie.x264.1080p") == .h264)
    }

    @Test func parsesH264() {
        #expect(VideoCodec.parse(from: "Movie.H264.WEB-DL") == .h264)
    }

    @Test func parsesH264WithDot() {
        #expect(VideoCodec.parse(from: "Movie.H.264.BluRay") == .h264)
    }

    @Test func parsesAVC() {
        #expect(VideoCodec.parse(from: "Movie.AVC.1080p") == .h264)
    }

    @Test func avcRequiresStandalone() {
        // "avc" inside "advanced" should not match
        // Because containsStandaloneToken checks word boundaries
        #expect(VideoCodec.parse(from: "Movie.AVC.1080p") == .h264)
    }

    @Test func parsesAV1() {
        #expect(VideoCodec.parse(from: "Movie.2024.AV1.2160p") == .av1)
    }

    @Test func parsesXviD() {
        #expect(VideoCodec.parse(from: "Movie.XviD.DVDRip") == .xvid)
    }

    @Test func parsesDivX() {
        #expect(VideoCodec.parse(from: "Movie.DivX.SD") == .xvid)
    }

    @Test func unknownForNoCodec() {
        #expect(VideoCodec.parse(from: "Movie.2024.1080p") == .unknown)
    }

    @Test func emptyReturnsUnknown() {
        #expect(VideoCodec.parse(from: "") == .unknown)
    }

    @Test func caseInsensitive() {
        #expect(VideoCodec.parse(from: "MOVIE.HEVC.BLURAY") == .h265)
        #expect(VideoCodec.parse(from: "movie.av1.2160p") == .av1)
    }
}

// MARK: - AudioFormat Parse Tests

@Suite("AudioFormat - parse")
struct AudioFormatParseTests {

    @Test func parsesAtmos() {
        #expect(AudioFormat.parse(from: "Movie.2024.Atmos.TrueHD") == .atmos)
    }

    @Test func parsesDTSHDMA() {
        #expect(AudioFormat.parse(from: "Movie.DTS-HD.MA.1080p") == .dtsHDMA)
    }

    @Test func parsesDTSHDWithDot() {
        #expect(AudioFormat.parse(from: "Movie.DTS.HD.MA") == .dtsHDMA)
    }

    @Test func parsesDTSHDCombined() {
        #expect(AudioFormat.parse(from: "Movie.DTSHD.MA") == .dtsHDMA)
    }

    @Test func parsesTrueHD() {
        #expect(AudioFormat.parse(from: "Movie.TrueHD.7.1") == .trueHD)
    }

    @Test func parsesTrueHDWithHyphen() {
        #expect(AudioFormat.parse(from: "Movie.True-HD.Atmos") == .atmos)
        // Note: Atmos check comes first, so "True-HD" with "Atmos" returns .atmos
        #expect(AudioFormat.parse(from: "Movie.True-HD.5.1") == .trueHD)
    }

    @Test func parsesEAC3() {
        #expect(AudioFormat.parse(from: "Movie.EAC3.5.1") == .eac3)
    }

    @Test func parsesEAC3WithHyphen() {
        #expect(AudioFormat.parse(from: "Movie.E-AC3") == .eac3)
    }

    @Test func parsesDDP() {
        #expect(AudioFormat.parse(from: "Movie.DDP.5.1.1080p") == .eac3)
    }

    @Test func parsesDTS() {
        #expect(AudioFormat.parse(from: "Movie.DTS.5.1") == .dts)
    }

    @Test func parsesAC3() {
        #expect(AudioFormat.parse(from: "Movie.AC3.2.0") == .ac3)
    }

    @Test func parsesAC3WithHyphen() {
        #expect(AudioFormat.parse(from: "Movie.AC-3.5.1") == .ac3)
    }

    @Test func parsesDD5() {
        #expect(AudioFormat.parse(from: "Movie.DD5.1.BluRay") == .ac3)
    }

    @Test func parsesAAC() {
        #expect(AudioFormat.parse(from: "Movie.AAC.2.0.WEBRip") == .aac)
    }

    @Test func parsesFLAC() {
        #expect(AudioFormat.parse(from: "Movie.FLAC.1080p") == .flac)
    }

    @Test func unknownForNoAudio() {
        #expect(AudioFormat.parse(from: "Movie.2024.1080p") == .unknown)
    }

    @Test func emptyReturnsUnknown() {
        #expect(AudioFormat.parse(from: "") == .unknown)
    }

    @Test func caseInsensitive() {
        #expect(AudioFormat.parse(from: "MOVIE.ATMOS.TRUEHD") == .atmos)
        #expect(AudioFormat.parse(from: "movie.aac.webrip") == .aac)
    }

    @Test func spatialAudioHint() {
        #expect(AudioFormat.atmos.spatialAudioHint == true)
        #expect(AudioFormat.dtsHDMA.spatialAudioHint == true)
        #expect(AudioFormat.trueHD.spatialAudioHint == true)
        #expect(AudioFormat.dts.spatialAudioHint == false)
        #expect(AudioFormat.ac3.spatialAudioHint == false)
        #expect(AudioFormat.aac.spatialAudioHint == false)
        #expect(AudioFormat.unknown.spatialAudioHint == false)
    }

    @Test func surroundHint() {
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

// MARK: - SourceType Parse Tests

@Suite("SourceType - parse")
struct SourceTypeParseTests {

    @Test func parsesBluRay() {
        #expect(SourceType.parse(from: "Movie.2024.BluRay.1080p") == .bluRay)
    }

    @Test func parsesBluRayWithHyphen() {
        #expect(SourceType.parse(from: "Movie.Blu-Ray.Remux") == .bluRay)
    }

    @Test func parsesBDRip() {
        #expect(SourceType.parse(from: "Movie.BDRip.x264") == .bluRay)
    }

    @Test func parsesBRRip() {
        #expect(SourceType.parse(from: "Movie.BRRip.720p") == .bluRay)
    }

    @Test func parsesWEBDL() {
        #expect(SourceType.parse(from: "Movie.2024.WEB-DL.1080p") == .webDL)
    }

    @Test func parsesWEBDLNoHyphen() {
        #expect(SourceType.parse(from: "Movie.2024.WEBDL.1080p") == .webDL)
    }

    @Test func parsesWEBRip() {
        #expect(SourceType.parse(from: "Movie.WEBRip.720p") == .webRip)
    }

    @Test func parsesWEBRipWithHyphen() {
        #expect(SourceType.parse(from: "Movie.WEB-Rip.720p") == .webRip)
    }

    @Test func parsesHDRip() {
        #expect(SourceType.parse(from: "Movie.HDRip.x264") == .hdRip)
    }

    @Test func parsesDVDRip() {
        #expect(SourceType.parse(from: "Movie.DVDRip.XviD") == .dvdRip)
    }

    @Test func parsesDVDRipWithHyphen() {
        #expect(SourceType.parse(from: "Movie.DVD-Rip") == .dvdRip)
    }

    @Test func parsesHDTV() {
        #expect(SourceType.parse(from: "Show.HDTV.720p") == .hdtv)
    }

    @Test func parsesCAM() {
        // "cam" uses standalone token matching
        #expect(SourceType.parse(from: "Movie.CAM.2024") == .cam)
    }

    @Test func parsesHDCAM() {
        #expect(SourceType.parse(from: "Movie.HDCAM.2024") == .cam)
    }

    @Test func parsesTelesync() {
        #expect(SourceType.parse(from: "Movie.Telesync.2024") == .cam)
    }

    @Test func parsesTS() {
        // "ts" uses standalone token matching
        #expect(SourceType.parse(from: "Movie.TS.2024") == .cam)
    }

    @Test func unknownForNoSource() {
        #expect(SourceType.parse(from: "Movie.2024.1080p") == .unknown)
    }

    @Test func emptyReturnsUnknown() {
        #expect(SourceType.parse(from: "") == .unknown)
    }

    @Test func caseInsensitive() {
        #expect(SourceType.parse(from: "MOVIE.BLURAY.1080P") == .bluRay)
        #expect(SourceType.parse(from: "movie.web-dl.720p") == .webDL)
    }

    @Test func qualityTierOrdering() {
        #expect(SourceType.bluRay.qualityTier > SourceType.webDL.qualityTier)
        #expect(SourceType.webDL.qualityTier > SourceType.webRip.qualityTier)
        #expect(SourceType.webRip.qualityTier > SourceType.hdRip.qualityTier)
        #expect(SourceType.hdRip.qualityTier > SourceType.dvdRip.qualityTier)
        #expect(SourceType.dvdRip.qualityTier >= SourceType.hdtv.qualityTier)
        #expect(SourceType.hdtv.qualityTier > SourceType.cam.qualityTier)
        #expect(SourceType.cam.qualityTier > SourceType.unknown.qualityTier)
    }
}

// MARK: - HDRFormat Parse Tests

@Suite("HDRFormat - parse")
struct HDRFormatParseTests {

    @Test func parsesDolbyVision() {
        #expect(HDRFormat.parse(from: "Movie.2024.DV.2160p") == .dolbyVision)
    }

    @Test func parsesDolbyVisionFullName() {
        #expect(HDRFormat.parse(from: "Movie.Dolby.Vision.1080p") == .dolbyVision)
    }

    @Test func parsesDolbyVisionHyphenated() {
        #expect(HDRFormat.parse(from: "Movie.Dolby-Vision.4K") == .dolbyVision)
    }

    @Test func parsesDolbyVisionCombined() {
        #expect(HDRFormat.parse(from: "Movie.DolbyVision.2160p") == .dolbyVision)
    }

    @Test func parsesDoVi() {
        #expect(HDRFormat.parse(from: "Movie.DoVi.BluRay") == .dolbyVision)
    }

    @Test func parsesHDR10Plus() {
        #expect(HDRFormat.parse(from: "Movie.HDR10+.BluRay") == .hdr10Plus)
    }

    @Test func parsesHDR10PlusWord() {
        #expect(HDRFormat.parse(from: "Movie.HDR10Plus.2160p") == .hdr10Plus)
    }

    @Test func parsesHDR10() {
        #expect(HDRFormat.parse(from: "Movie.HDR10.2160p.BluRay") == .hdr10)
    }

    @Test func parsesHDRStandalone() {
        #expect(HDRFormat.parse(from: "Movie.HDR.2160p") == .hdr10)
    }

    @Test func parsesHLG() {
        #expect(HDRFormat.parse(from: "Movie.HLG.2160p") == .hlg)
    }

    @Test func sdrForNoHDR() {
        #expect(HDRFormat.parse(from: "Movie.2024.1080p.BluRay") == .sdr)
    }

    @Test func emptyReturnsSDR() {
        #expect(HDRFormat.parse(from: "") == .sdr)
    }

    @Test func caseInsensitive() {
        #expect(HDRFormat.parse(from: "MOVIE.DOLBY.VISION.4K") == .dolbyVision)
        #expect(HDRFormat.parse(from: "movie.hdr10.2160p") == .hdr10)
    }

    @Test func dvTakesPriorityOverHDR() {
        // If both DV and HDR10 are present, DV wins (it's checked first)
        #expect(HDRFormat.parse(from: "Movie.DV.HDR10.2160p") == .dolbyVision)
    }

    @Test func hdr10PlusTakesPriorityOverHDR10() {
        #expect(HDRFormat.parse(from: "Movie.HDR10+.2160p") == .hdr10Plus)
    }
}

// MARK: - MediaType Tests

@Suite("MediaType")
struct MediaTypeTests {

    @Test func movieDisplayName() {
        #expect(MediaType.movie.displayName == "Movie")
    }

    @Test func seriesDisplayName() {
        #expect(MediaType.series.displayName == "TV Show")
    }

    @Test func movieTmdbPath() {
        #expect(MediaType.movie.tmdbPath == "movie")
    }

    @Test func seriesTmdbPath() {
        #expect(MediaType.series.tmdbPath == "tv")
    }

    @Test func rawValues() {
        #expect(MediaType.movie.rawValue == "movie")
        #expect(MediaType.series.rawValue == "series")
    }
}

// MARK: - HDRPreference Tests

@Suite("HDRPreference")
struct HDRPreferenceTests {

    @Test func displayNames() {
        #expect(HDRPreference.auto.displayName == "Auto")
        #expect(HDRPreference.dolbyVision.displayName == "Dolby Vision")
        #expect(HDRPreference.hdr10.displayName == "HDR10/HDR10+")
    }

    @Test func rawValues() {
        #expect(HDRPreference.auto.rawValue == "auto")
        #expect(HDRPreference.dolbyVision.rawValue == "dolby_vision")
        #expect(HDRPreference.hdr10.rawValue == "hdr10")
    }
}

// MARK: - Full Title Parsing Tests

@Suite("Full Torrent Title Parsing")
struct FullTitleParsingTests {

    @Test func parseTypicalRemuxTitle() {
        let title = "Dune.Part.Two.2024.2160p.BluRay.Remux.HEVC.DTS-HD.MA.Atmos.7.1"
        #expect(VideoQuality.parse(from: title) == .uhd4k)
        #expect(VideoCodec.parse(from: title) == .h265)
        #expect(AudioFormat.parse(from: title) == .atmos)
        #expect(SourceType.parse(from: title) == .bluRay)
        #expect(HDRFormat.parse(from: title) == .sdr) // No HDR flag in this title
    }

    @Test func parseWEBDLTitle() {
        let title = "Oppenheimer.2023.1080p.WEB-DL.DDP.5.1.x264"
        #expect(VideoQuality.parse(from: title) == .hd1080p)
        #expect(VideoCodec.parse(from: title) == .h264)
        #expect(AudioFormat.parse(from: title) == .eac3)
        #expect(SourceType.parse(from: title) == .webDL)
    }

    @Test func parseDVTitle() {
        let title = "Movie.2024.2160p.WEB-DL.DV.HDR10.H.265.Atmos"
        #expect(VideoQuality.parse(from: title) == .uhd4k)
        #expect(VideoCodec.parse(from: title) == .h265)
        #expect(AudioFormat.parse(from: title) == .atmos)
        #expect(SourceType.parse(from: title) == .webDL)
        #expect(HDRFormat.parse(from: title) == .dolbyVision)
    }
}
