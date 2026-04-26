import Foundation

extension TimeInterval {
    /// Returns a human-readable time string in `H:MM:SS` or `M:SS` format.
    var formattedDuration: String {
        guard isFinite && self >= 0 else { return "0:00" }
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
