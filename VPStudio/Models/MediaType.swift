import Foundation

enum MediaType: String, Codable, Sendable, CaseIterable {
    case movie
    case series

    var displayName: String {
        switch self {
        case .movie: return "Movie"
        case .series: return "TV Show"
        }
    }

    nonisolated var tmdbPath: String {
        switch self {
        case .movie: return "movie"
        case .series: return "tv"
        }
    }
}

enum VideoQuality: String, Codable, Sendable, CaseIterable, Comparable {
    case uhd4k = "4K"
    case hd1080p = "1080p"
    case hd720p = "720p"
    case sd480p = "480p"
    case sd = "SD"
    case unknown

    nonisolated var sortOrder: Int {
        switch self {
        case .uhd4k: return 5
        case .hd1080p: return 4
        case .hd720p: return 3
        case .sd480p: return 2
        case .sd: return 1
        case .unknown: return 0
        }
    }

    nonisolated static func < (lhs: VideoQuality, rhs: VideoQuality) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    nonisolated static func parse(from title: String) -> VideoQuality {
        let lowered = title.lowercased()
        if lowered.contains("2160p") || lowered.contains("4k") || lowered.contains("uhd") {
            return .uhd4k
        } else if lowered.contains("1080p") || lowered.contains("1080i") {
            return .hd1080p
        } else if lowered.contains("720p") {
            return .hd720p
        } else if lowered.contains("480p") {
            return .sd480p
        } else if lowered.containsStandaloneToken("sd") || lowered.contains("dvdrip") || lowered.contains("cam") {
            return .sd
        }
        return .unknown
    }
}

enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264 = "H.264"
    case h265 = "H.265"
    case av1 = "AV1"
    case xvid = "XviD"
    case unknown

    nonisolated static func parse(from title: String) -> VideoCodec {
        let lowered = title.lowercased()
        if lowered.contains("x265") || lowered.contains("h265") || lowered.contains("h.265") || lowered.contains("hevc") {
            return .h265
        } else if lowered.contains("x264") || lowered.contains("h264") || lowered.contains("h.264") || lowered.containsStandaloneToken("avc") {
            return .h264
        } else if lowered.contains("av1") {
            return .av1
        } else if lowered.contains("xvid") || lowered.contains("divx") {
            return .xvid
        }
        return .unknown
    }
}

enum AudioFormat: String, Codable, Sendable, CaseIterable {
    case atmos = "Atmos"
    case dtsHDMA = "DTS-HD MA"
    case trueHD = "TrueHD"
    case dts = "DTS"
    case ac3 = "AC3"
    case eac3 = "EAC3"
    case aac = "AAC"
    case flac = "FLAC"
    case unknown

    var spatialAudioHint: Bool {
        switch self {
        case .atmos, .dtsHDMA, .trueHD: return true
        default: return false
        }
    }

    var surroundHint: Bool {
        switch self {
        case .atmos, .dtsHDMA, .trueHD, .dts, .ac3, .eac3: return true
        default: return false
        }
    }

    nonisolated static func parse(from title: String) -> AudioFormat {
        let lowered = title.lowercased()
        if lowered.contains("atmos") {
            return .atmos
        } else if lowered.contains("dts-hd") || lowered.contains("dts.hd") || lowered.contains("dtshd") {
            return .dtsHDMA
        } else if lowered.contains("truehd") || lowered.contains("true-hd") {
            return .trueHD
        } else if lowered.contains("eac3") || lowered.contains("e-ac3") || lowered.contains("eac-3") || lowered.contains("ddp") {
            return .eac3
        } else if lowered.contains("dts") {
            return .dts
        } else if lowered.contains("ac3") || lowered.contains("ac-3") || lowered.contains("dd5") || lowered.contains("dd2") {
            return .ac3
        } else if lowered.contains("aac") {
            return .aac
        } else if lowered.contains("flac") {
            return .flac
        }
        return .unknown
    }
}

enum SourceType: String, Codable, Sendable, CaseIterable {
    case bluRay = "BluRay"
    case webDL = "WEB-DL"
    case webRip = "WEBRip"
    case hdRip = "HDRip"
    case dvdRip = "DVDRip"
    case hdtv = "HDTV"
    case cam = "CAM"
    case unknown

    var qualityTier: Int {
        switch self {
        case .bluRay: return 6
        case .webDL: return 5
        case .webRip: return 4
        case .hdRip: return 3
        case .dvdRip: return 2
        case .hdtv: return 2
        case .cam: return 1
        case .unknown: return 0
        }
    }

    nonisolated static func parse(from title: String) -> SourceType {
        let lowered = title.lowercased()
        if lowered.contains("bluray") || lowered.contains("blu-ray") || lowered.contains("bdrip") || lowered.contains("brrip") {
            return .bluRay
        } else if lowered.contains("web-dl") || lowered.contains("webdl") {
            return .webDL
        } else if lowered.contains("webrip") || lowered.contains("web-rip") {
            return .webRip
        } else if lowered.contains("hdrip") {
            return .hdRip
        } else if lowered.contains("dvdrip") || lowered.contains("dvd-rip") {
            return .dvdRip
        } else if lowered.contains("hdtv") {
            return .hdtv
        } else if lowered.contains("hdcam")
            || lowered.contains("telesync")
            || lowered.containsStandaloneToken("cam")
            || lowered.containsStandaloneToken("ts") {
            return .cam
        }
        return .unknown
    }
}

enum HDRFormat: String, Codable, Sendable, CaseIterable {
    case dolbyVision = "DV"
    case hdr10Plus = "HDR10+"
    case hdr10 = "HDR10"
    case hlg = "HLG"
    case sdr = "SDR"

    nonisolated static func parse(from title: String) -> HDRFormat {
        let lowered = title.lowercased()
        if lowered.contains("dolby vision")
            || lowered.contains("dolby.vision")
            || lowered.contains("dolby-vision")
            || lowered.contains("dolbyvision")
            || lowered.contains("dovi")
            || lowered.containsStandaloneToken("dv") {
            return .dolbyVision
        } else if lowered.contains("hdr10+") || lowered.contains("hdr10plus") {
            return .hdr10Plus
        } else if lowered.contains("hdr10") || lowered.containsStandaloneToken("hdr") {
            return .hdr10
        } else if lowered.contains("hlg") {
            return .hlg
        }
        return .sdr
    }
}

enum HDRPreference: String, Codable, Sendable, CaseIterable {
    case auto
    case dolbyVision = "dolby_vision"
    case hdr10 = "hdr10"

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .dolbyVision:
            return "Dolby Vision"
        case .hdr10:
            return "HDR10/HDR10+"
        }
    }
}
