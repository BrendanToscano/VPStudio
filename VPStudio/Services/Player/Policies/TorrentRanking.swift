import Foundation

/// Language hints that can be detected from torrent titles
enum TorrentLanguageHint: String, CaseIterable, Sendable {
    case english = "EN"
    case french = "FR"
    case german = "DE"
    case spanish = "ES"
    case italian = "IT"
    case japanese = "JA"
    case korean = "KO"
    case chinese = "ZH"
    case hindi = "HI"
    case russian = "RU"
    case portuguese = "PT"
    case polish = "PL"
    case dutch = "NL"
    case swedish = "SV"
    case danish = "DA"
    case norwegian = "NO"
    case finnish = "FI"
    case turkish = "TR"
    case arabic = "AR"
    case hebrew = "HE"
    case thai = "TH"
    case indonesian = "ID"
    case hungarian = "HU"
    case czech = "CS"
    case romanian = "RO"
    case vietnamese = "VI"
    case ukranian = "UK"

    /// Check if this language hint matches a user preference code
    nonisolated func matches(userLanguageCode: String) -> Bool {
        let code = userLanguageCode.lowercased()
        switch self {
        case .english: return code == "en" || code == "eng"
        case .french: return code == "fr" || code == "fra"
        case .german: return code == "de" || code == "ger"
        case .spanish: return code == "es" || code == "spa"
        case .italian: return code == "it" || code == "ita"
        case .japanese: return code == "ja" || code == "jpn"
        case .korean: return code == "ko" || code == "kor"
        case .chinese: return code == "zh" || code == "chi"
        case .hindi: return code == "hi" || code == "hin"
        case .russian: return code == "ru" || code == "rus"
        case .portuguese: return code == "pt" || code == "por"
        case .polish: return code == "pl" || code == "pol"
        case .dutch: return code == "nl" || code == "dut"
        case .swedish: return code == "sv" || code == "swe"
        case .danish: return code == "da" || code == "dan"
        case .norwegian: return code == "no" || code == "nor"
        case .finnish: return code == "fi" || code == "fin"
        case .turkish: return code == "tr" || code == "tur"
        case .arabic: return code == "ar" || code == "ara"
        case .hebrew: return code == "he" || code == "heb"
        case .thai: return code == "th" || code == "tha"
        case .indonesian: return code == "id" || code == "ind"
        case .hungarian: return code == "hu" || code == "hun"
        case .czech: return code == "cs" || code == "cze"
        case .romanian: return code == "ro" || code == "rum"
        case .vietnamese: return code == "vi" || code == "vie"
        case .ukranian: return code == "uk" || code == "ukr"
        }
    }
}

enum TorrentRanking {
    /// Expected file sizes in bytes for different quality tiers (with some tolerance)
    private enum SizeExpectation {
        static let hd720pMin: Int64 = 1_500_000_000      // ~1.5 GB
        static let hd720pMax: Int64 = 4_000_000_000      // ~4 GB
        static let hd1080pMin: Int64 = 2_500_000_000     // ~2.5 GB
        static let hd1080pMax: Int64 = 15_000_000_000    // ~15 GB
        static let uhd4kMin: Int64 = 8_000_000_000       // ~8 GB
        static let uhd4kMax: Int64 = 80_000_000_000      // ~80 GB

        /// Suspiciously small file threshold (less than 300MB for any quality)
        static let suspiciouslySmall: Int64 = 300_000_000

        /// Suspiciously large file threshold (more than 100GB)
        static let suspiciouslyLarge: Int64 = 100_000_000_000
    }

    /// Detects language hints from torrent title
    nonisolated static func detectLanguage(from title: String) -> TorrentLanguageHint? {
        let lowered = title.lowercased()
        
        // Check for language indicators in title
        for hint in TorrentLanguageHint.allCases {
            // Check for language code patterns like "EN", "FR", etc.
            if lowered.contains("[\(hint.rawValue)]") ||
               lowered.contains("(\(hint.rawValue))") ||
               lowered.contains(".\(hint.rawValue).") ||
               lowered.contains("_\(hint.rawValue)_") ||
               lowered.contains("-\(hint.rawValue)-") {
                return hint
            }
            
            // Check for full language names
            switch hint {
            case .english:
                if lowered.contains("english") || lowered.contains("engsub") { return hint }
            case .french:
                if lowered.contains("french") || lowered.contains("frsub") { return hint }
            case .german:
                if lowered.contains("german") || lowered.contains("desub") { return hint }
            case .spanish:
                if lowered.contains("spanish") || lowered.contains("essub") { return hint }
            case .italian:
                if lowered.contains("italian") || lowered.contains("itasub") { return hint }
            case .japanese:
                if lowered.contains("japanese") || lowered.contains("japansub") || lowered.contains("jpnsub") { return hint }
            case .korean:
                if lowered.contains("korean") || lowered.contains("korsub") { return hint }
            case .chinese:
                if lowered.contains("chinese") || lowered.contains("chsub") || lowered.contains("mandarin") { return hint }
            case .hindi:
                if lowered.contains("hindi") || lowered.contains("hinsub") { return hint }
            case .russian:
                if lowered.contains("russian") || lowered.contains("rusub") { return hint }
            default:
                break
            }
        }
        
        return nil
    }

    /// Calculates size sanity score based on expected file sizes for quality
    nonisolated static func sizeSanityScore(for torrent: TorrentResult) -> Int {
        let size = torrent.sizeBytes

        // Penalize suspicious sizes
        if size < SizeExpectation.suspiciouslySmall {
            // Very small files are likely samples or fake
            return -100
        }

        if size > SizeExpectation.suspiciouslyLarge {
            // Very large files might be disc rips or bundles
            return -30
        }

        // Check if size is reasonable for the declared quality
        let expectedMin: Int64
        let expectedMax: Int64

        switch torrent.quality {
        case .uhd4k:
            expectedMin = SizeExpectation.uhd4kMin
            expectedMax = SizeExpectation.uhd4kMax
        case .hd1080p:
            expectedMin = SizeExpectation.hd1080pMin
            expectedMax = SizeExpectation.hd1080pMax
        case .hd720p:
            expectedMin = SizeExpectation.hd720pMin
            expectedMax = SizeExpectation.hd720pMax
        case .sd480p, .sd:
            // Lower quality files are typically smaller
            return 10
        case .unknown:
            // Unknown quality - give moderate score
            return 0
        }

        // If size is within expected range, positive score
        if size >= expectedMin && size <= expectedMax {
            return 20
        }

        // Size is outside expected range but not suspicious
        if size < expectedMin {
            // Smaller than expected - might be WEB-DL instead of BluRay
            return -10
        } else {
            // Larger than expected - might include extras/bundles
            return 5
        }
    }

    nonisolated static func sort(
        _ torrents: [TorrentResult],
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference,
        preferredLanguages: [String] = []
    ) -> [TorrentResult] {
        torrents.sorted { lhs, rhs in
            let lhsScore = score(
                lhs,
                preferredQuality: preferredQuality,
                preferCached: preferCached,
                preferAtmos: preferAtmos,
                hdrPreference: hdrPreference,
                preferredLanguages: preferredLanguages
            )
            let rhsScore = score(
                rhs,
                preferredQuality: preferredQuality,
                preferCached: preferCached,
                preferAtmos: preferAtmos,
                hdrPreference: hdrPreference,
                preferredLanguages: preferredLanguages
            )

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            // Deterministic tiebreaker: infoHash comparison
            return lhs.infoHash < rhs.infoHash
        }
    }

    nonisolated static func sortConcurrently(
        _ torrents: [TorrentResult],
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference,
        preferredLanguages: [String] = []
    ) async -> [TorrentResult] {
        guard torrents.count > 8 else {
            return sort(
                torrents,
                preferredQuality: preferredQuality,
                preferCached: preferCached,
                preferAtmos: preferAtmos,
                hdrPreference: hdrPreference,
                preferredLanguages: preferredLanguages
            )
        }

        let scored: [(offset: Int, torrent: TorrentResult, score: Int)] = await withTaskGroup(
            of: (Int, TorrentResult, Int).self
        ) { group in
            for (offset, torrent) in torrents.enumerated() {
                group.addTask {
                    let score = score(
                        torrent,
                        preferredQuality: preferredQuality,
                        preferCached: preferCached,
                        preferAtmos: preferAtmos,
                        hdrPreference: hdrPreference,
                        preferredLanguages: preferredLanguages
                    )
                    return (offset, torrent, score)
                }
            }

            var results: [(offset: Int, torrent: TorrentResult, score: Int)] = []
            results.reserveCapacity(torrents.count)
            for await value in group {
                results.append((value.0, value.1, value.2))
            }
            return results
        }

        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.torrent.seeders != rhs.torrent.seeders { return lhs.torrent.seeders > rhs.torrent.seeders }
            // Deterministic tiebreaker: offset preserves original order
            return lhs.offset < rhs.offset
        }.map(\.torrent)
    }

    /// Backward-compatible wrapper that calls the new sort function
    nonisolated static func sortConcurrently(
        _ torrents: [TorrentResult],
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference
    ) async -> [TorrentResult] {
        await sortConcurrently(
            torrents,
            preferredQuality: preferredQuality,
            preferCached: preferCached,
            preferAtmos: preferAtmos,
            hdrPreference: hdrPreference,
            preferredLanguages: []
        )
    }

    /// Backward-compatible wrapper that calls the new sort function
    nonisolated static func sort(
        _ torrents: [TorrentResult],
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference
    ) -> [TorrentResult] {
        sort(
            torrents,
            preferredQuality: preferredQuality,
            preferCached: preferCached,
            preferAtmos: preferAtmos,
            hdrPreference: hdrPreference,
            preferredLanguages: []
        )
    }

    /// Tiered scoring where resolution is the dominant factor.
    ///
    /// Each quality tier occupies a 1000-point band so no combination of
    /// sub-tier bonuses (max ~460) can push a lower-resolution result above
    /// a higher-resolution one.
    ///
    /// Within a tier the order is: HDR > audio > codec > source > user prefs > seeders.
    ///
    /// - Parameters:
    ///   - torrent: The torrent to score
    ///   - preferredQuality: User's preferred quality setting
    ///   - preferCached: Whether to prefer cached torrents
    ///   - preferAtmos: Whether to prefer Atmos audio
    ///   - hdrPreference: User's HDR preference
    ///   - preferredLanguages: User's preferred language codes (e.g., ["en", "ja"])
    /// - Returns: Deterministic score for ranking
    nonisolated static func score(
        _ torrent: TorrentResult,
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference,
        preferredLanguages: [String] = []
    ) -> Int {
        var score = torrent.quality.sortOrder * 1000

        // --- HDR (0-120) ---
        switch torrent.hdr {
        case .dolbyVision: score += 120
        case .hdr10Plus:   score += 100
        case .hdr10:       score += 80
        case .hlg:         score += 40
        case .sdr:         break
        }

        // --- Audio (0-100) ---
        switch torrent.audio {
        case .atmos:   score += 100
        case .trueHD:  score += 80
        case .dtsHDMA: score += 80
        case .eac3:    score += 40
        case .dts:     score += 35
        case .ac3:     score += 30
        case .flac:    score += 25
        case .aac:     score += 10
        case .unknown: break
        }

        // --- Codec (0-60) ---
        switch torrent.codec {
        case .h265: score += 60
        case .av1:  score += 50
        case .h264: score += 30
        case .xvid: score += 5
        case .unknown: break
        }

        // --- Source (0-50) ---
        switch torrent.source {
        case .bluRay:  score += 50
        case .webDL:   score += 40
        case .webRip:  score += 30
        case .hdRip:   score += 20
        case .hdtv:    score += 15
        case .dvdRip:  score += 10
        case .cam:     break
        case .unknown: break
        }

        // --- User preferences (0-80) ---
        if preferCached && torrent.isCached {
            score += 80
        } else if torrent.isCached {
            score += 40
        }
        if preferAtmos && torrent.audio.spatialAudioHint { score += 20 }
        switch hdrPreference {
        case .auto:        break
        case .dolbyVision: if torrent.hdr == .dolbyVision { score += 20 }
        case .hdr10:       if torrent.hdr == .hdr10 || torrent.hdr == .hdr10Plus { score += 20 }
        }

        // --- Language matching (0-50) ---
        if !preferredLanguages.isEmpty {
            if let detectedLanguage = detectLanguage(from: torrent.title) {
                for userLang in preferredLanguages {
                    if detectedLanguage.matches(userLanguageCode: userLang) {
                        score += 50
                        break
                    }
                }
            }
        }

        // --- Size sanity (-100 to +20) ---
        score += sizeSanityScore(for: torrent)

        // --- Seeders tiebreaker (0-50) ---
        // Normalized to prevent seeders from dominating the score
        score += min(torrent.seeders, 500) / 10

        return score
    }

    /// Simplified score function for backward compatibility
    nonisolated static func score(
        _ torrent: TorrentResult,
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference
    ) -> Int {
        score(
            torrent,
            preferredQuality: preferredQuality,
            preferCached: preferCached,
            preferAtmos: preferAtmos,
            hdrPreference: hdrPreference,
            preferredLanguages: []
        )
    }
}
