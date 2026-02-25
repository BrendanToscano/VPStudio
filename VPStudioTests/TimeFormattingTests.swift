import Testing
import Foundation
@testable import VPStudio

@Suite("TimeInterval.formattedDuration")
struct TimeFormattingTests {

    // MARK: - Basic Values

    @Test func zeroReturns0Colon00() {
        let result = TimeInterval(0).formattedDuration
        #expect(result == "0:00")
    }

    @Test func oneSecond() {
        #expect(TimeInterval(1).formattedDuration == "0:01")
    }

    @Test func thirtySeconds() {
        #expect(TimeInterval(30).formattedDuration == "0:30")
    }

    @Test func fiftyNineSeconds() {
        #expect(TimeInterval(59).formattedDuration == "0:59")
    }

    @Test func sixtySecondsShowsOneMinute() {
        #expect(TimeInterval(60).formattedDuration == "1:00")
    }

    @Test func ninetySeconds() {
        #expect(TimeInterval(90).formattedDuration == "1:30")
    }

    // MARK: - Hour Boundary

    @Test func thirtyFiftyNineMinutesFiftyNineSeconds() {
        // 3599 = 59:59
        #expect(TimeInterval(3599).formattedDuration == "59:59")
    }

    @Test func oneHour() {
        // 3600 = 1:00:00
        #expect(TimeInterval(3600).formattedDuration == "1:00:00")
    }

    @Test func oneHourOneMinuteOneSecond() {
        // 3661 = 1:01:01
        #expect(TimeInterval(3661).formattedDuration == "1:01:01")
    }

    @Test func twoHoursThirtyMinutes() {
        // 9000 = 2:30:00
        #expect(TimeInterval(9000).formattedDuration == "2:30:00")
    }

    @Test func tenHours() {
        // 36000 = 10:00:00
        #expect(TimeInterval(36000).formattedDuration == "10:00:00")
    }

    // MARK: - Edge Cases

    @Test func negativeReturns0Colon00() {
        #expect(TimeInterval(-1).formattedDuration == "0:00")
        #expect(TimeInterval(-100).formattedDuration == "0:00")
    }

    @Test func infinityReturns0Colon00() {
        #expect(TimeInterval.infinity.formattedDuration == "0:00")
    }

    @Test func negativeInfinityReturns0Colon00() {
        #expect((-TimeInterval.infinity).formattedDuration == "0:00")
    }

    @Test func nanReturns0Colon00() {
        #expect(TimeInterval.nan.formattedDuration == "0:00")
    }

    // MARK: - Fractional Seconds (truncated)

    @Test func fractionalSecondsTruncated() {
        // 61.9 should show 1:01 (Int truncation)
        #expect(TimeInterval(61.9).formattedDuration == "1:01")
    }

    @Test func fractionalHourBoundary() {
        // 3599.9 → Int(3599.9) = 3599 → 59:59
        #expect(TimeInterval(3599.9).formattedDuration == "59:59")
    }

    // MARK: - Padding Verification

    @Test func minutePaddedToTwoDigitsInHourMode() {
        // 1 hour and 5 minutes = 3900s
        #expect(TimeInterval(3900).formattedDuration == "1:05:00")
    }

    @Test func secondPaddedToTwoDigits() {
        #expect(TimeInterval(5).formattedDuration == "0:05")
    }

    @Test func minuteNotPaddedWithoutHours() {
        // 5 minutes = 300s → "5:00" not "05:00"
        #expect(TimeInterval(300).formattedDuration == "5:00")
    }
}
