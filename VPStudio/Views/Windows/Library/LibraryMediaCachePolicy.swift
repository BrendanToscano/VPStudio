import Foundation

/// Shared guardrails for Library media-item cache growth.
enum LibraryMediaCachePolicy {
    static let defaultMaxEntries = 200

    static func deduplicatedIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return id
        }
    }

    static func touch(id: String, order: inout [String]) {
        if let existingIndex = order.firstIndex(of: id) {
            order.remove(at: existingIndex)
        }
        order.append(id)
    }

    static func trimCache(
        items: inout [String: MediaItem],
        order: inout [String],
        preserving pinnedIDs: Set<String>,
        maxEntries: Int = defaultMaxEntries
    ) {
        guard maxEntries >= 0 else {
            items.removeAll()
            order.removeAll()
            return
        }

        // Keep order and cache keys aligned.
        order = deduplicatedIDs(order.filter { items[$0] != nil })

        guard items.count > maxEntries else { return }

        func remove(_ key: String) {
            items.removeValue(forKey: key)
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
            }
        }

        // First pass: drop oldest entries that are not currently pinned.
        var index = 0
        while items.count > maxEntries && index < order.count {
            let candidate = order[index]
            if pinnedIDs.contains(candidate) {
                index += 1
                continue
            }
            remove(candidate)
        }

        // Second pass: enforce hard cap even if everything was pinned.
        index = 0
        while items.count > maxEntries && index < order.count {
            let candidate = order[index]
            remove(candidate)
        }

        // Final guard for any keys not represented in order.
        if items.count > maxEntries {
            for key in items.keys.sorted() where items.count > maxEntries {
                remove(key)
            }
        }
    }
}
