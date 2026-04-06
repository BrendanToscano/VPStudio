import Foundation

enum PlayerStartupFailurePolicy {
    private static let directLinkKeywords: [String] = [
        "expired",
        "forbidden",
        "unauthorized",
        "access denied",
        "permission denied",
        "not found",
        "bad server response",
        "file does not exist"
    ]

    private static let directLinkStatusCodes = [401, 403, 404, 410]
    private static let directLinkNSErrorCodes = [-1011, -1100]

    static func shouldSkipRemainingEnginesAndRefreshCurrentStream(
        after error: Error,
        stream: StreamInfo,
        priorRefreshAttempts: Int
    ) -> Bool {
        guard PlayerStreamLinkRecovery.refreshPlan(
            for: stream,
            priorAttempts: priorRefreshAttempts,
            qaRefreshURL: QARuntimeOptions.sampleRefreshURL
        ) != nil else {
            return false
        }

        if case .startupTimeout = error as? PlayerEngineError {
            return false
        }

        let description = normalizedDescription(for: error)
        guard !description.isEmpty else { return false }

        if directLinkStatusCodes.contains(where: { matches(statusCode: $0, in: description) }) {
            return true
        }

        if directLinkKeywords.contains(where: { description.contains($0) }) {
            return true
        }

        return directLinkNSErrorCodes.contains(where: {
            description.contains("error \($0)") ||
            description.contains("code=\($0)") ||
            description.contains("code \($0)")
        })
    }

    static func normalizedDescription(for error: Error) -> String {
        var fragments: [String] = []

        func append(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            fragments.append(trimmed.lowercased())
        }

        append(error.localizedDescription)

        if let engineError = error as? PlayerEngineError {
            switch engineError {
            case .invalidStreamURL(let value):
                append(value)
            case .startupTimeout:
                break
            case .initializationFailed(_, let message):
                append(message)
            }
        }

        let nsError = error as NSError
        append(nsError.domain)
        append("code=\(nsError.code)")
        append(nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String)

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            append(underlying.domain)
            append("code=\(underlying.code)")
            append(underlying.localizedDescription)
            append(underlying.userInfo[NSLocalizedFailureReasonErrorKey] as? String)
        }

        return fragments.joined(separator: " | ")
    }

    private static func matches(statusCode: Int, in description: String) -> Bool {
        description.contains("http \(statusCode)") ||
        description.contains("status code \(statusCode)") ||
        description.contains("status=\(statusCode)") ||
        description.contains("response \(statusCode)") ||
        description.contains("error \(statusCode)")
    }
}
