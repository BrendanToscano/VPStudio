import AVFoundation
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

    @Test func codecHintTakesPriorityOverFilenameHeuristics() {
        #expect(
            SpatialVideoTitleDetector.stereoMode(fromTitle: "Flat.Movie.1080p.mp4", codecHint: "mv_hevc")
            == .mvHevc
        )
        #expect(
            SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.SBS.1080p.mp4", codecHint: "MV-HEVC")
            == .mvHevc
        )
        #expect(
            SpatialVideoTitleDetector.stereoMode(fromTitle: "Flat.Movie.1080p.mp4", codecHint: "mvhevc")
            == .mvHevc
        )
    }

    @Test func additionalFilenameTokensMapToExpectedStereoModes() {
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.sidebyside.1080p") == .sideBySide)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.side-by-side.1080p") == .sideBySide)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.half-sbs.1080p") == .sideBySide)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.OU.1080p") == .overUnder)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.over-under.1080p") == .overUnder)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.TAB.1080p") == .overUnder)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Documentary 360-video") == .sphere360)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Documentary 360\u{00B0}") == .sphere360)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Documentary 360") == .sphere360)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "iPhone spatial capture") == .mvHevc)
    }

    @Test func nonSpatialCodecHintsDoNotOverrideRegularTitleDetection() {
        #expect(
            SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.SBS.1080p", codecHint: "hevc")
            == .sideBySide
        )
        #expect(
            SpatialVideoTitleDetector.stereoMode(fromTitle: "Documentary.360p.H264", codecHint: "h264")
            == .mono
        )
    }

    @Test func vrDegreeTokensRequireVRContextAndAvoidResolutionFalsePositives() {
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.180.1080p") == .mono)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.180.3D") == .sphere180)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.180.VR") == .sphere180)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.360.1080p") == .sphere360)
        #expect(SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.360p") == .mono)
    }

    @Test func invalidCodecHintsDoNotCreateMVHEVCFalsePositives() {
        #expect(
            SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.1080p", codecHint: nil)
            == .mono
        )
        #expect(
            SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.1080p", codecHint: "mvh264")
            == .mono
        )
        #expect(
            SpatialVideoTitleDetector.stereoMode(fromTitle: "Movie.1080p", codecHint: "hevc-main")
            == .mono
        )
    }

    @Test func assetMVHEVCDetectionReturnsFalseForUnreadableAsset() async {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/vpstudio-missing-spatial-video.mov"))

        let isMVHEVC = await SpatialVideoTitleDetector.detectMVHEVC(from: asset)

        #expect(isMVHEVC == false)
    }
}
