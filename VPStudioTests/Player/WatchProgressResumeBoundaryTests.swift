import Foundation
import Testing
@testable import VPStudio

@Suite("Watch Progress Resume Boundary Matrix")
struct WatchProgressResumeBoundaryTests {
    struct CaseData: Sendable {
        let progress: Double
        let duration: Double
        let expected: TimeInterval?
    }

    private static let cases: [CaseData] = {
        var values: [CaseData] = []
        for index in 0..<30 {
            let progress = Double(index * 7)
            let duration = Double(100 + index * 9)

            let expected: TimeInterval?
            if progress < 15 {
                expected = nil
            } else {
                let completion = progress / duration
                if completion >= 0.95 {
                    expected = nil
                } else {
                    expected = min(progress, max(duration - 5, 0))
                }
            }
            values.append(CaseData(progress: progress, duration: duration, expected: expected))
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(10)), full: cases))
    func resumeBoundaryMatrix(data: CaseData) {
        let history = Fixtures.watchHistory(progress: data.progress, duration: data.duration)
        let resume = WatchProgressResumePolicy.resumeTime(for: history)
        #expect(resume == data.expected)
    }
}
