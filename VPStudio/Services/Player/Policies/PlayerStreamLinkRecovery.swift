import Foundation

enum PlayerStreamLinkRefreshPlan: Equatable {
    case replace(StreamInfo)
    case reResolve(StreamRecoveryContext)
}

enum PlayerStreamLinkRecovery {
    static func attemptTrackingKey(for stream: StreamInfo) -> String {
        guard let context = normalizedRecoveryContext(for: stream) else {
            return stream.id
        }

        let service = context.preferredService?.rawValue ?? stream.debridService
        let season = context.seasonNumber.map(String.init) ?? "-"
        let episode = context.episodeNumber.map(String.init) ?? "-"
        return "\(service)|\(context.infoHash)|s\(season)|e\(episode)"
    }

    static func refreshPlan(for stream: StreamInfo, priorAttempts: Int) -> PlayerStreamLinkRefreshPlan? {
        refreshPlan(
            for: stream,
            priorAttempts: priorAttempts,
            qaRefreshURL: QARuntimeOptions.sampleRefreshURL
        )
    }

    static func refreshPlan(
        for stream: StreamInfo,
        priorAttempts: Int,
        qaRefreshURL: URL?
    ) -> PlayerStreamLinkRefreshPlan? {
        guard priorAttempts == 0 else { return nil }

        if stream.debridService == "qa-sample",
           let qaRefreshURL {
            return .replace(stream.withStreamURL(qaRefreshURL))
        }

        guard let context = normalizedRecoveryContext(for: stream) else { return nil }

        return .reResolve(context)
    }

    private static func normalizedRecoveryContext(for stream: StreamInfo) -> StreamRecoveryContext? {
        guard var context = stream.recoveryContext else { return nil }

        if context.preferredService == nil {
            context.preferredService = DebridServiceType(rawValue: stream.debridService)
        }

        return context
    }
}
