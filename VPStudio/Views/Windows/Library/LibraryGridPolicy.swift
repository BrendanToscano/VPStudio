import Foundation

enum LibraryGridPolicy {
    static let cardMinWidth: CGFloat = 180
    static let gridSpacing: CGFloat = 16
    static let horizontalPadding: CGFloat = 20

    static func columns(containerWidth: CGFloat) -> Int {
        guard containerWidth > 0 else { return 1 }
        let available = containerWidth - (2 * horizontalPadding) + gridSpacing
        let count = Int(available / (cardMinWidth + gridSpacing))
        return max(1, count)
    }
}
