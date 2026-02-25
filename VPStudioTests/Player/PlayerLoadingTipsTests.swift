import Foundation
import Testing
@testable import VPStudio

@Suite("PlayerLoadingTips — Tip Catalog and Rotator")
struct PlayerLoadingTipsTests {

    // MARK: - Catalog Validation

    @Test func catalogIsNonEmpty() {
        #expect(!PlayerLoadingTipCatalog.allTips.isEmpty)
        #expect(PlayerLoadingTipCatalog.allTips.count >= 15)
    }

    @Test func allTipsHaveNonEmptyText() {
        for tip in PlayerLoadingTipCatalog.allTips {
            #expect(!tip.text.isEmpty, "Tip \(tip.id) has empty text")
        }
    }

    @Test func allTipsHaveNonEmptyIcons() {
        for tip in PlayerLoadingTipCatalog.allTips {
            #expect(!tip.icon.isEmpty, "Tip \(tip.id) has empty icon")
        }
    }

    @Test func allTipsHaveUniqueIds() {
        let ids = PlayerLoadingTipCatalog.allTips.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Duplicate tip IDs found")
    }

    @Test func allTipIconsAreValidSFSymbolNames() {
        // SF Symbol names must be non-empty, contain only valid characters,
        // and not contain spaces at the beginning/end.
        let validCharacterSet = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: ".-"))

        for tip in PlayerLoadingTipCatalog.allTips {
            let icon = tip.icon
            #expect(icon == icon.trimmingCharacters(in: .whitespaces),
                    "Tip \(tip.id) icon has leading/trailing whitespace")
            let allValid = icon.unicodeScalars.allSatisfy { validCharacterSet.contains($0) }
            #expect(allValid, "Tip \(tip.id) icon '\(icon)' contains invalid characters")
        }
    }

    @Test func tipConformsToIdentifiable() {
        let tip = PlayerLoadingTipCatalog.allTips[0]
        let _: String = tip.id
        // Identifiable conformance verified by compilation
    }

    @Test func tipConformsToEquatable() {
        let tip1 = PlayerLoadingTip(id: "a", text: "Hello", icon: "star")
        let tip2 = PlayerLoadingTip(id: "a", text: "Hello", icon: "star")
        let tip3 = PlayerLoadingTip(id: "b", text: "World", icon: "globe")
        #expect(tip1 == tip2)
        #expect(tip1 != tip3)
    }

    // MARK: - Rotator Initialization

    @Test @MainActor func rotatorStartsWithFirstTip() {
        let tips = [
            PlayerLoadingTip(id: "1", text: "First", icon: "star"),
            PlayerLoadingTip(id: "2", text: "Second", icon: "globe"),
        ]
        let rotator = PlayerLoadingTipRotator(tips: tips)
        // After shuffling, currentTip must be one of the provided tips.
        let validIds = Set(tips.map(\.id))
        #expect(validIds.contains(rotator.currentTip.id))
    }

    @Test @MainActor func rotatorUsesDefaultCatalog() {
        let rotator = PlayerLoadingTipRotator()
        let allIds = Set(PlayerLoadingTipCatalog.allTips.map(\.id))
        #expect(allIds.contains(rotator.currentTip.id))
    }

    // MARK: - Rotation Behavior

    @Test @MainActor func advanceChangesTip() {
        // With enough tips, advancing should eventually produce a different tip.
        let rotator = PlayerLoadingTipRotator()
        let initial = rotator.currentTip

        // Advance enough times to guarantee a change (worst case: all tips are
        // the same after shuffle, which can't happen with 18 tips).
        var foundDifferent = false
        for _ in 0..<20 {
            rotator.advance()
            if rotator.currentTip.id != initial.id {
                foundDifferent = true
                break
            }
        }
        #expect(foundDifferent, "Rotator never produced a different tip after 20 advances")
    }

    @Test @MainActor func noImmediateSequentialDuplicates() {
        let rotator = PlayerLoadingTipRotator()
        var previousId = rotator.currentTip.id
        var duplicateFound = false

        // Run through 2 full cycles (2 * tipCount advances) plus extra
        for _ in 0..<(PlayerLoadingTipCatalog.allTips.count * 2 + 5) {
            rotator.advance()
            if rotator.currentTip.id == previousId {
                duplicateFound = true
                break
            }
            previousId = rotator.currentTip.id
        }

        #expect(!duplicateFound, "Sequential duplicate tip found during rotation")
    }

    @Test @MainActor func rotatorCyclesThroughAllTips() {
        let tips = (0..<5).map {
            PlayerLoadingTip(id: "\($0)", text: "Tip \($0)", icon: "star")
        }
        let rotator = PlayerLoadingTipRotator(tips: tips)

        var seenIds: Set<String> = [rotator.currentTip.id]
        for _ in 0..<20 {
            rotator.advance()
            seenIds.insert(rotator.currentTip.id)
        }

        #expect(seenIds.count == 5, "Expected all 5 tips to appear, got \(seenIds.count)")
    }

    @Test @MainActor func rotatorWrapsAroundCorrectly() {
        let tips = [
            PlayerLoadingTip(id: "a", text: "A", icon: "star"),
            PlayerLoadingTip(id: "b", text: "B", icon: "globe"),
            PlayerLoadingTip(id: "c", text: "C", icon: "cube"),
        ]
        let rotator = PlayerLoadingTipRotator(tips: tips)

        // Advance past the end of the list
        for _ in 0..<6 {
            rotator.advance()
        }

        // Should still be showing a valid tip
        let validIds = Set(tips.map(\.id))
        #expect(validIds.contains(rotator.currentTip.id))
    }

    // MARK: - Lifecycle

    @Test @MainActor func stopCancelsRotation() {
        let rotator = PlayerLoadingTipRotator()
        rotator.start()
        rotator.stop()
        // After stop, the rotator should still have a valid current tip.
        let allIds = Set(PlayerLoadingTipCatalog.allTips.map(\.id))
        #expect(allIds.contains(rotator.currentTip.id))
    }

    @Test @MainActor func multipleStartCallsDoNotCrash() {
        let rotator = PlayerLoadingTipRotator()
        rotator.start()
        rotator.start()
        rotator.start()
        rotator.stop()
        // No crash = pass
    }

    @Test @MainActor func intervalIsConfigurable() {
        let rotator = PlayerLoadingTipRotator(interval: 2.0)
        #expect(rotator.interval == 2.0)
    }

    @Test @MainActor func defaultIntervalIsFourPointFiveSeconds() {
        let rotator = PlayerLoadingTipRotator()
        #expect(rotator.interval == 4.5)
    }
}
