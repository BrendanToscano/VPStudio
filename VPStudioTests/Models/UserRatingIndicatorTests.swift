import Testing
import Foundation
@testable import VPStudio

// MARK: - Helpers

/// Replicates the rating color threshold logic from MediaCardView's user rating star indicator.
/// Green star if positive, red star if not.
private func isPositiveRating(scale: FeedbackScaleMode?, value: Double) -> Bool {
    let resolvedScale = (scale ?? .oneToTen).canonicalMode
    let normalized = resolvedScale.normalizedValue(value)
    return normalized >= 0.555
}

// MARK: - oneToTen Threshold Tests

@Suite("UserRatingIndicator - oneToTen threshold")
struct UserRatingIndicatorOneToTenTests {

    @Test func rating6IsGreen() {
        // 6 → (6-1)/9 = 0.5556 → above 0.555 threshold → green
        #expect(isPositiveRating(scale: .oneToTen, value: 6.0))
    }

    @Test func rating5IsRed() {
        // 5 → (5-1)/9 = 0.4444 → below threshold → red
        #expect(!isPositiveRating(scale: .oneToTen, value: 5.0))
    }

    @Test func rating10IsGreen() {
        #expect(isPositiveRating(scale: .oneToTen, value: 10.0))
    }

    @Test func rating1IsRed() {
        #expect(!isPositiveRating(scale: .oneToTen, value: 1.0))
    }
}

// MARK: - oneToHundred Threshold Tests

@Suite("UserRatingIndicator - oneToHundred threshold")
struct UserRatingIndicatorOneToHundredTests {

    @Test func rating56IsGreen() {
        // 56 → (56-1)/99 ≈ 0.5556 → above 0.555 → green
        #expect(isPositiveRating(scale: .oneToHundred, value: 56.0))
    }

    @Test func rating55IsRed() {
        // 55 → (55-1)/99 ≈ 0.5454 → below threshold → red
        #expect(!isPositiveRating(scale: .oneToHundred, value: 55.0))
    }

    @Test func rating100IsGreen() {
        #expect(isPositiveRating(scale: .oneToHundred, value: 100.0))
    }

    @Test func rating1IsRed() {
        #expect(!isPositiveRating(scale: .oneToHundred, value: 1.0))
    }
}

// MARK: - likeDislike Threshold Tests

@Suite("UserRatingIndicator - likeDislike threshold")
struct UserRatingIndicatorLikeDislikeTests {

    @Test func likeIsGreen() {
        #expect(isPositiveRating(scale: .likeDislike, value: 1.0))
    }

    @Test func dislikeIsRed() {
        #expect(!isPositiveRating(scale: .likeDislike, value: 0.0))
    }
}

// MARK: - Legacy Scale (fiveStar via canonicalMode)

@Suite("UserRatingIndicator - legacy fiveStar canonicalMode")
struct UserRatingIndicatorLegacyFiveStarTests {

    @Test func fiveStarCanonicalModeIsOneToTen() {
        #expect(FeedbackScaleMode.fiveStar.canonicalMode == .oneToTen)
    }

    @Test func fiveStarRating4IsRed() {
        // fiveStar.canonicalMode == .oneToTen, so normalizedValue goes through .oneToTen
        // rating 4 → (4-1)/9 = 0.333 → red
        #expect(!isPositiveRating(scale: .fiveStar, value: 4.0))
    }

    @Test func fiveStarRating8IsGreen() {
        // Through canonicalMode .oneToTen: (8-1)/9 = 0.778 → green
        #expect(isPositiveRating(scale: .fiveStar, value: 8.0))
    }
}

// MARK: - Nil feedbackScale Defaults to oneToTen

@Suite("UserRatingIndicator - nil feedbackScale default")
struct UserRatingIndicatorNilScaleTests {

    @Test func nilFeedbackScaleDefaultsToOneToTen() {
        let event = TasteEvent(eventType: .rated, feedbackScale: nil, feedbackValue: 6.0)
        let scale = (event.feedbackScale ?? .oneToTen).canonicalMode
        #expect(scale == .oneToTen)
        #expect(isPositiveRating(scale: nil, value: 6.0))
    }

    @Test func nilScaleRating5IsRed() {
        #expect(!isPositiveRating(scale: nil, value: 5.0))
    }
}

// MARK: - TasteEvent Integration (end-to-end through MediaCardView logic)

@Suite("UserRatingIndicator - TasteEvent integration")
struct UserRatingIndicatorTasteEventIntegrationTests {

    @Test func fullPathOneToTenPositive() {
        let event = TasteEvent(eventType: .rated, feedbackScale: .oneToTen, feedbackValue: 8.0)
        let scale = (event.feedbackScale ?? .oneToTen).canonicalMode
        let normalized = scale.normalizedValue(event.feedbackValue!)
        #expect(normalized >= 0.555)
    }

    @Test func fullPathOneToTenNegative() {
        let event = TasteEvent(eventType: .rated, feedbackScale: .oneToTen, feedbackValue: 3.0)
        let scale = (event.feedbackScale ?? .oneToTen).canonicalMode
        let normalized = scale.normalizedValue(event.feedbackValue!)
        #expect(normalized < 0.555)
    }

    @Test func fullPathLikeDislikePositive() {
        let event = TasteEvent(eventType: .rated, feedbackScale: .likeDislike, feedbackValue: 1.0)
        let scale = (event.feedbackScale ?? .oneToTen).canonicalMode
        let normalized = scale.normalizedValue(event.feedbackValue!)
        #expect(normalized >= 0.555)
    }

    @Test func fullPathOneToHundredBoundary() {
        let event = TasteEvent(eventType: .rated, feedbackScale: .oneToHundred, feedbackValue: 56.0)
        let scale = (event.feedbackScale ?? .oneToTen).canonicalMode
        let normalized = scale.normalizedValue(event.feedbackValue!)
        #expect(normalized >= 0.555)
    }

    @Test func nilFeedbackValueSkipsIndicator() {
        let event = TasteEvent(eventType: .rated, feedbackScale: .oneToTen, feedbackValue: nil)
        #expect(event.feedbackValue == nil)
    }
}
