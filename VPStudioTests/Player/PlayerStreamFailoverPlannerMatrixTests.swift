import Foundation
import Testing
@testable import VPStudio

@Suite("Player Stream Failover Planner Matrix")
struct PlayerStreamFailoverPlannerMatrixTests {
    struct CaseData: Sendable {
        let primary: StreamInfo
        let available: [StreamInfo]
        let expectedCount: Int
    }

    private static let cases: [CaseData] = {
        var values: [CaseData] = []
        for index in 0..<56 {
            let primary = Fixtures.stream(
                url: "https://cdn.example.com/p-\(index).mkv",
                quality: index % 2 == 0 ? .uhd4k : .hd1080p,
                fileName: "primary-\(index).mkv",
                sizeBytes: Int64(1_000 + index)
            )
            let duplicate = index % 3 == 0 ? primary : Fixtures.stream(
                url: "https://cdn.example.com/a-\(index).mkv",
                quality: .hd1080p,
                fileName: "a-\(index).mkv",
                sizeBytes: 900
            )
            let other = Fixtures.stream(
                url: "https://cdn.example.com/b-\(index).mkv",
                quality: .hd720p,
                fileName: "b-\(index).mkv",
                sizeBytes: 800
            )
            let expectedCount = index % 3 == 0 ? 2 : 3
            values.append(
                CaseData(primary: primary, available: [duplicate, other], expectedCount: expectedCount)
            )
        }
        return values
    }()

    @Test(arguments: ExhaustiveMode.choose(fast: Array(cases.prefix(16)), full: cases))
    func sessionStreamsAndNextStreamMatrix(data: CaseData) {
        let queue = PlayerSessionRouting.sessionStreams(primary: data.primary, available: data.available)
        #expect(queue.count == data.expectedCount)
        #expect(queue.first?.id == data.primary.id)

        let next = PlayerStreamFailoverPlanner.nextStream(after: data.primary, in: queue)
        if queue.count > 1 {
            #expect(next != nil)
        } else {
            #expect(next == nil)
        }
    }
}
