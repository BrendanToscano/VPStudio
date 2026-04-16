import Foundation

struct PlayerSessionRequest: Codable, Sendable, Identifiable, Hashable {
    var id: UUID
    var stream: StreamInfo
    var availableStreams: [StreamInfo]
    var mediaTitle: String
    var mediaId: String
    var episodeId: String?

    init(
        id: UUID = UUID(),
        stream: StreamInfo,
        availableStreams: [StreamInfo] = [],
        mediaTitle: String,
        mediaId: String,
        episodeId: String? = nil
    ) {
        self.id = id
        self.stream = stream
        self.availableStreams = availableStreams
        self.mediaTitle = mediaTitle
        self.mediaId = mediaId
        self.episodeId = episodeId
    }
}
