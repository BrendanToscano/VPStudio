import Foundation
import Testing
@testable import VPStudio

@Suite("Spatial Video Detection")
struct SpatialVideoManagerDetectionTests {
    struct CaseData: Sendable {
        let title: String
        let expectedMode: VPPlayerEngine.StereoMode
    }

    private static let cases: [CaseData] = {
        var values: [CaseData] = []
        let presets: [(String, VPPlayerEngine.StereoMode)] = [
            ("Movie HSBS 3D", .sideBySide),
            ("Movie side.by.side trailer", .sideBySide),
            ("Movie HOU 3D", .overUnder),
            ("Movie over.under demo", .overUnder),
            ("Shot on Spatial MV-HEVC", .mvHevc),
            ("Travel 180 VR", .sphere180),
            ("Travel 360 video", .sphere360),
            ("Standard movie 1080p", .mono),
            ("Documentary 360vr", .sphere360),
            ("Documentary 360p encode", .mono),
        ]
        while values.count < 30 {
            let item = presets[values.count % presets.count]
            values.append(CaseData(title: "\(item.0) #\(values.count)", expectedMode: item.1))
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(10)), full: cases))
    func titleDetectionMatrix(data: CaseData) {
        let mode = SpatialVideoTitleDetector.stereoMode(fromTitle: data.title)
        #expect(mode == data.expectedMode)
    }
}
