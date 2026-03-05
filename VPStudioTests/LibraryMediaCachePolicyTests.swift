import Foundation
import Testing
@testable import VPStudio

@Suite("Library Media Cache Policy")
struct LibraryMediaCachePolicyTests {
    @Test
    func deduplicatedIDsPreservesFirstSeenOrder() {
        let ids = ["tt1", "tt2", "tt1", "tt3", "tt2", "tt4"]
        #expect(LibraryMediaCachePolicy.deduplicatedIDs(ids) == ["tt1", "tt2", "tt3", "tt4"])
    }

    @Test
    func touchMovesIDToMostRecentPosition() {
        var order = ["a", "b", "c"]
        LibraryMediaCachePolicy.touch(id: "b", order: &order)
        #expect(order == ["a", "c", "b"])

        LibraryMediaCachePolicy.touch(id: "d", order: &order)
        #expect(order == ["a", "c", "b", "d"])
    }

    @Test
    func trimPrefersEvictingOldestUnpinnedEntries() {
        var items = [
            "a": mediaItem("a"),
            "b": mediaItem("b"),
            "c": mediaItem("c"),
            "d": mediaItem("d"),
        ]
        var order = ["a", "b", "c", "d"]

        LibraryMediaCachePolicy.trimCache(
            items: &items,
            order: &order,
            preserving: ["d"],
            maxEntries: 2
        )

        #expect(items.count == 2)
        #expect(items["d"] != nil)
        #expect(items["c"] != nil)
        #expect(order == ["c", "d"])
    }

    @Test
    func trimEnforcesHardCapWhenPinnedSetExceedsCapacity() {
        var items = [
            "a": mediaItem("a"),
            "b": mediaItem("b"),
            "c": mediaItem("c"),
            "d": mediaItem("d"),
        ]
        var order = ["a", "b", "c", "d"]

        LibraryMediaCachePolicy.trimCache(
            items: &items,
            order: &order,
            preserving: Set(["a", "b", "c", "d"]),
            maxEntries: 2
        )

        #expect(items.count == 2)
        #expect(order == ["c", "d"])
    }

    private func mediaItem(_ id: String) -> MediaItem {
        MediaItem(id: id, type: .movie, title: id)
    }
}
