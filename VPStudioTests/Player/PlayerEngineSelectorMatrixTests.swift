import Foundation
import Testing
@testable import VPStudio

@Suite("Player Engine Selector Matrix")
struct PlayerEngineSelectorMatrixTests {
    struct CaseData: Sendable {
        let stream: StreamInfo
        let shouldBeRisky: Bool
    }

    private static let cases: [CaseData] = {
        let riskyExtensions = ["mkv", "avi", "wmv", "flv", "ts", "m2ts", "mpeg", "mpg", "webm", ""]
        let safeExtensions = ["mp4", "m4v", "mov"]
        let riskyTokens = ["remux", "truehd", "dts-hd", "dv", "hevc"]

        var values: [CaseData] = []
        for index in 0..<96 {
            let useRiskyExt = index % 2 == 0
            let ext = useRiskyExt ? riskyExtensions[index % riskyExtensions.count] : safeExtensions[index % safeExtensions.count]
            let includeRiskyToken = index % 3 == 0
            let token = includeRiskyToken ? riskyTokens[index % riskyTokens.count] : ""
            let codec: VideoCodec = index % 5 == 0 ? .av1 : (index % 7 == 0 ? .unknown : .h264)
            let fileNameBase = token.isEmpty ? "Movie.2025.1080p" : "Movie.2025.\(token).1080p"
            let fileName = ext.isEmpty ? fileNameBase : "\(fileNameBase).\(ext)"
            let url = ext.isEmpty ? "https://cdn.example.com/video" : "https://cdn.example.com/video.\(ext)"
            let risky = riskyExtensions.contains(ext) || codec == .av1 || codec == .unknown || !token.isEmpty
            values.append(
                CaseData(
                    stream: Fixtures.stream(url: url, codec: codec, fileName: fileName),
                    shouldBeRisky: risky
                )
            )
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(24)), full: cases))
    func engineOrderMatrix(data: CaseData) {
        let selector = PlayerEngineSelector()
        let adaptive = selector.engineOrder(for: data.stream, strategy: .adaptive)
        let performance = selector.engineOrder(for: data.stream, strategy: .performance)
        let compatibility = selector.engineOrder(for: data.stream, strategy: .compatibility)

        #expect(Set(adaptive) == Set(PlayerEngineKind.allCases))
        #expect(Set(performance) == Set(PlayerEngineKind.allCases))
        #expect(Set(compatibility) == Set(PlayerEngineKind.allCases))
        #expect(performance == [.avPlayer, .ksPlayer])

        // Compatibility mode ALWAYS uses KSPlayer first, regardless of stream profile.
        #expect(compatibility == [.ksPlayer, .avPlayer])

        // Adaptive mode only falls back to KSPlayer for truly incompatible streams.
        let ext = data.stream.streamURL.pathExtension.lowercased()
        let adaptiveCompatibilityExtensions: Set<String> = ["avi", "wmv", "flv", "ts", "m2ts", "mpeg", "mpg"]
        let shouldUseCompatibilityFirstInAdaptive = adaptiveCompatibilityExtensions.contains(ext) || data.stream.codec == .unknown
        let hasDV = data.stream.hdr == .dolbyVision || data.stream.hdr == .hdr10Plus
        let isSpatial = SpatialVideoTitleDetector.stereoMode(fromTitle: data.stream.fileName) != .mono
        let prefersNative = hasDV || isSpatial
        if prefersNative || !shouldUseCompatibilityFirstInAdaptive {
            #expect(adaptive == [.avPlayer, .ksPlayer])
        } else {
            #expect(adaptive == [.ksPlayer, .avPlayer])
        }
    }
}
