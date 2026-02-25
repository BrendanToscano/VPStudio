import Foundation

enum TorrentRanking {
    nonisolated static func sort(
        _ torrents: [TorrentResult],
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference
    ) -> [TorrentResult] {
        torrents.sorted { lhs, rhs in
            let lhsScore = score(
                lhs,
                preferredQuality: preferredQuality,
                preferCached: preferCached,
                preferAtmos: preferAtmos,
                hdrPreference: hdrPreference
            )
            let rhsScore = score(
                rhs,
                preferredQuality: preferredQuality,
                preferCached: preferCached,
                preferAtmos: preferAtmos,
                hdrPreference: hdrPreference
            )

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.seeders > rhs.seeders
        }
    }

    nonisolated static func sortConcurrently(
        _ torrents: [TorrentResult],
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference
    ) async -> [TorrentResult] {
        guard torrents.count > 8 else {
            return sort(
                torrents,
                preferredQuality: preferredQuality,
                preferCached: preferCached,
                preferAtmos: preferAtmos,
                hdrPreference: hdrPreference
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
                        hdrPreference: hdrPreference
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
            return lhs.offset < rhs.offset
        }.map(\.torrent)
    }

    /// Tiered scoring where resolution is the dominant factor.
    ///
    /// Each quality tier occupies a 1000-point band so no combination of
    /// sub-tier bonuses (max ~460) can push a lower-resolution result above
    /// a higher-resolution one.
    ///
    /// Within a tier the order is: HDR > audio > codec > source > user prefs > seeders.
    nonisolated static func score(
        _ torrent: TorrentResult,
        preferredQuality: VideoQuality,
        preferCached: Bool,
        preferAtmos: Bool,
        hdrPreference: HDRPreference
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

        // --- Seeders tiebreaker (0-50) ---
        score += min(torrent.seeders, 500) / 10

        return score
    }
}
