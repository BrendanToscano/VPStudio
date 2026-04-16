import Foundation

// MARK: - Test Mode Shared Data

/// Hardcoded mock data for VPStudio visual QA.
/// Uses only types with clean public memberwise initializers.
enum TestModeData {

    // MARK: - Media Previews

    static let moviePreview = MediaPreview(
        id: "test-movie-1",
        type: .movie,
        title: "Dune: Part Two",
        year: 2024,
        posterPath: "/8b8R8l88QJejddJmXAdzF9xFGAD.jpg",
        backdropPath: "/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg",
        imdbRating: 8.8,
        tmdbId: 693134
    )

    static let seriesPreview = MediaPreview(
        id: "test-series-1",
        type: .series,
        title: "Shrinking",
        year: 2023,
        posterPath: "/vEF6xlpIIyJPKJLRG0llLxM5sQS.jpg",
        backdropPath: "/sIhNMJZzW1V3R9O8VwR2F8XJE1W.jpg",
        imdbRating: 8.1,
        tmdbId: 209163
    )

    // MARK: - Torrent Results

    static let torrentResults: [TorrentResult] = [
        .fromSearch(
            infoHash: "abcd1234567890efabcd1234567890efabcd1234",
            title: "Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1 Atmos.HDR.H.265-GROUP",
            sizeBytes: 8_500_000_000,
            seeders: 342,
            leechers: 28,
            indexerName: "AwesomeTracker"
        ),
        .fromSearch(
            infoHash: "efcd567890abcd1234efcd567890abcd1234ef56",
            title: "Dune Part Two 2024 1080p WEB-DL DDP 5.1 x264-GROUP",
            sizeBytes: 3_200_000_000,
            seeders: 1204,
            leechers: 89,
            indexerName: "PublicHD"
        ),
        .fromSearch(
            infoHash: "7890abcdef1234567890abcdef1234567890abcd",
            title: "Dune.Part.Two.2024.720p.WEB.x264-GROUP",
            sizeBytes: 1_800_000_000,
            seeders: 567,
            leechers: 34,
            indexerName: "RARBG"
        ),
    ]

    static let episodeTorrentResults: [TorrentResult] = [
        .fromSearch(
            infoHash: "1111aaaa2222bbbb3333cccc4444dddd5555eeee",
            title: "Shrinking.S03E01.2160p.WEB-DL.DDP5.1.HDR.H.265-GROUP",
            sizeBytes: 4_100_000_000,
            seeders: 88,
            leechers: 12,
            indexerName: "AwesomeTracker"
        ),
        .fromSearch(
            infoHash: "2222bbbb3333cccc4444dddd5555eeee6666ffff",
            title: "Shrinking.S03E01.1080p.WEB-DL.DDP5.1.x264-GROUP",
            sizeBytes: 1_900_000_000,
            seeders: 341,
            leechers: 22,
            indexerName: "PublicHD"
        ),
    ]

    // MARK: - Seasons / Episodes (Series)

    static let seasons: [Season] = [
        Season(id: 1, seasonNumber: 1, name: "Season 1", overview: "A therapist starts breaking the rules with his patients.", posterPath: nil, episodeCount: 10, airDate: "2023-01-26"),
        Season(id: 2, seasonNumber: 2, name: "Season 2", overview: "Life continues to complicate everything.", posterPath: nil, episodeCount: 10, airDate: "2024-05-23"),
        Season(id: 3, seasonNumber: 3, name: "Season 3", overview: "The final chapter.", posterPath: nil, episodeCount: 9, airDate: "2025-02-06"),
    ]

    static let episodes: [Episode] = [
        Episode(id: "ep-s3e1", mediaId: "209163", seasonNumber: 3, episodeNumber: 1, title: "Fanatics", overview: "Jimmy makes a radical change after a tragedy. Gaby and Alice have a breakthrough.", airDate: "2025-02-06", stillPath: "/xV1r1aO4P6f4z1B5c9d3e7f2a8b.jpg", runtime: 35),
        Episode(id: "ep-s3e2", mediaId: "209163", seasonNumber: 3, episodeNumber: 2, title: "The Ghosts of Princeton", overview: "Jimmy deals with the aftermath of his confession. Dr. Gaby meets her new patient.", airDate: "2025-02-13", stillPath: nil, runtime: 34),
        Episode(id: "ep-s3e3", mediaId: "209163", seasonNumber: 3, episodeNumber: 3, title: "The Medal", overview: "Jimmy receives an unexpected honor. Paul's therapy takes an unexpected turn.", airDate: "2025-02-20", stillPath: nil, runtime: 36),
        Episode(id: "ep-s3e4", mediaId: "209163", seasonNumber: 3, episodeNumber: 4, title: "The River", overview: "Jimmy and Paul embark on a journey. Gaby faces a difficult choice.", airDate: "2025-02-27", stillPath: "/p5q4r3s2t1u0v9w8x7y6z5a4b3c2d1e0.jpg", runtime: 37),
        Episode(id: "ep-s3e5", mediaId: "209163", seasonNumber: 3, episodeNumber: 5, title: "The Bowl", overview: "A dinner party goes sideways. Alice discovers something shocking.", airDate: "2025-03-06", stillPath: "/f1e2d3c4b5a697886809a7b6c5d4e3f2.jpg", runtime: 35),
        Episode(id: "ep-s3e6", mediaId: "209163", seasonNumber: 3, episodeNumber: 6, title: "The High Price of Love", overview: "Jimmy makes a big decision about his future. Liz and Paul reconnect.", airDate: "2025-03-13", stillPath: "/z9y8x7w6v5u4t3s2r1q0p9o8n7m6l5k.jpg", runtime: 38),
    ]

    // MARK: - Library / Watch History

    static let libraryEntries: [MediaPreview] = [
        MediaPreview(id: "lib-1", type: .movie, title: "Oppenheimer", year: 2023, posterPath: "/8kXqEj8GNaIPwsj3DBkJriBk0mC.jpg", backdropPath: nil, imdbRating: 8.9, tmdbId: 872_585),
        MediaPreview(id: "lib-2", type: .movie, title: "Poor Things", year: 2023, posterPath: "/kCGlIMHnOm8JPXq3rXM6c5wMxcT.jpg", backdropPath: nil, imdbRating: 8.0, tmdbId: 739_542),
        MediaPreview(id: "lib-3", type: .series, title: "The Bear", year: 2022, posterPath: "/sHFlbKS3WLqMnp9t2ghADIJFnuQ.jpg", backdropPath: nil, imdbRating: 8.6, tmdbId: 1_062_719),
        MediaPreview(id: "lib-4", type: .movie, title: "Killers of the Flower Moon", year: 2023, posterPath: "/dB6Krk806zeqd0YNp2ngQ9zXteF.jpg", backdropPath: nil, imdbRating: 7.7, tmdbId: 466_420),
        MediaPreview(id: "lib-5", type: .series, title: "Slow Horses", year: 2022, posterPath: "/vKuhWpMaXGh3S4KpKpv9UeAIpak.jpg", backdropPath: nil, imdbRating: 8.1, tmdbId: 735_86),
        MediaPreview(id: "lib-6", type: .movie, title: "The Holdovers", year: 2023, posterPath: "/VHSzNBTwxV8vh7wylo7O9CLdac.jpg", backdropPath: nil, imdbRating: 7.9, tmdbId: 840_430),
    ]
}
