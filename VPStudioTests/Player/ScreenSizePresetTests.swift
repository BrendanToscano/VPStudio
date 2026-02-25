#if os(visionOS)
import Testing
@testable import VPStudio

@Suite("ScreenSizePreset")
struct ScreenSizePresetPlayerTests {

    // MARK: - Dimensions

    @Test func personalDimensions() {
        #expect(ScreenSizePreset.personal.width == 6)
        #expect(ScreenSizePreset.personal.height == 3.375)
        #expect(ScreenSizePreset.personal.distance == 10)
    }

    @Test func cinemaDimensions() {
        #expect(ScreenSizePreset.cinema.width == 10)
        #expect(ScreenSizePreset.cinema.height == 5.625)
        #expect(ScreenSizePreset.cinema.distance == 20)
    }

    @Test func imaxDimensions() {
        #expect(ScreenSizePreset.imax.width == 16)
        #expect(ScreenSizePreset.imax.height == 9)
        #expect(ScreenSizePreset.imax.distance == 35)
    }

    // MARK: - Aspect Ratio

    @Test func aspectRatioIsConsistentAcrossPresets() {
        for preset in ScreenSizePreset.allCases {
            let ratio = preset.width / preset.height
            let expected: Float = 16.0 / 9.0
            #expect(abs(ratio - expected) < 0.01,
                    "Preset \(preset.rawValue) has aspect ratio \(ratio), expected ~\(expected)")
        }
    }

    // MARK: - Cycling

    @Test func nextCyclesCorrectly() {
        var current = ScreenSizePreset.personal
        #expect(current == .personal)

        current = current.next
        #expect(current == .cinema)

        current = current.next
        #expect(current == .imax)

        current = current.next
        #expect(current == .personal)
    }

    @Test func cyclingWrapsAroundFromLastToFirst() {
        let last = ScreenSizePreset.allCases.last!
        let first = ScreenSizePreset.allCases.first!
        #expect(last.next == first)
    }

    // MARK: - Ordering

    @Test func distanceOrderingIsSensible() {
        let presets = ScreenSizePreset.allCases
        for i in 1..<presets.count {
            #expect(presets[i].distance > presets[i - 1].distance,
                    "\(presets[i].rawValue) should be farther than \(presets[i - 1].rawValue)")
            #expect(presets[i].width > presets[i - 1].width,
                    "\(presets[i].rawValue) should be wider than \(presets[i - 1].rawValue)")
            #expect(presets[i].height > presets[i - 1].height,
                    "\(presets[i].rawValue) should be taller than \(presets[i - 1].rawValue)")
        }
    }

    // MARK: - Raw Values

    @Test func rawValues() {
        #expect(ScreenSizePreset.personal.rawValue == "Personal")
        #expect(ScreenSizePreset.cinema.rawValue == "Cinema")
        #expect(ScreenSizePreset.imax.rawValue == "IMAX")
    }

    @Test func allCasesHasThreePresets() {
        #expect(ScreenSizePreset.allCases.count == 3)
    }
}
#endif
