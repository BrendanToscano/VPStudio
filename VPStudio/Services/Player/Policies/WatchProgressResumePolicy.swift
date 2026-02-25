import Foundation

enum WatchProgressResumePolicy {
    static func resumeTime(for history: WatchHistory?) -> TimeInterval? {
        guard let history else { return nil }

        let progress = max(0, history.progress)
        let duration = max(0, history.duration)
        guard progress >= 15 else { return nil }

        if duration > 0 {
            let completion = progress / duration
            if completion >= 0.95 {
                return nil
            }
            return min(progress, max(duration - 5, 0))
        }

        return progress
    }
}
