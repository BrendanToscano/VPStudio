import Testing
import Foundation
@testable import VPStudio

// MARK: - fromStoredValue Legacy Mapping

@Suite("FeedbackScaleMode - fromStoredValue")
struct FeedbackScaleModeFromStoredValueTests {

    @Test func fiveStarMapsToOneToTen() {
        let mode = FeedbackScaleMode.fromStoredValue("five_star")
        #expect(mode == .oneToTen)
    }

    @Test func tenPointMapsToOneToTen() {
        let mode = FeedbackScaleMode.fromStoredValue("ten_point")
        #expect(mode == .oneToTen)
    }

    @Test func likeDislikePreservesItself() {
        let mode = FeedbackScaleMode.fromStoredValue("like_dislike")
        #expect(mode == .likeDislike)
    }

    @Test func oneToTenPreservesItself() {
        let mode = FeedbackScaleMode.fromStoredValue("one_to_ten")
        #expect(mode == .oneToTen)
    }

    @Test func oneToHundredPreservesItself() {
        let mode = FeedbackScaleMode.fromStoredValue("one_to_hundred")
        #expect(mode == .oneToHundred)
    }

    @Test func nilDefaultsToLikeDislike() {
        let mode = FeedbackScaleMode.fromStoredValue(nil)
        #expect(mode == .likeDislike)
    }

    @Test func unrecognizedDefaultsToLikeDislike() {
        let mode = FeedbackScaleMode.fromStoredValue("invalid_mode")
        #expect(mode == .likeDislike)
    }

    @Test func emptyStringDefaultsToLikeDislike() {
        let mode = FeedbackScaleMode.fromStoredValue("")
        #expect(mode == .likeDislike)
    }
}

// MARK: - canonicalMode

@Suite("FeedbackScaleMode - canonicalMode")
struct FeedbackScaleModeCanonicalTests {

    @Test func likeDislikeIsCanonical() {
        #expect(FeedbackScaleMode.likeDislike.canonicalMode == .likeDislike)
    }

    @Test func oneToTenIsCanonical() {
        #expect(FeedbackScaleMode.oneToTen.canonicalMode == .oneToTen)
    }

    @Test func oneToHundredIsCanonical() {
        #expect(FeedbackScaleMode.oneToHundred.canonicalMode == .oneToHundred)
    }

    @Test func fiveStarCanonicalIsOneToTen() {
        #expect(FeedbackScaleMode.fiveStar.canonicalMode == .oneToTen)
    }

    @Test func tenPointCanonicalIsOneToTen() {
        #expect(FeedbackScaleMode.tenPoint.canonicalMode == .oneToTen)
    }
}

// MARK: - clamp

@Suite("FeedbackScaleMode - clamp")
struct FeedbackScaleModeClampTests {

    @Test func likeDislikeClampMin() {
        #expect(FeedbackScaleMode.likeDislike.clamp(-5) == 0)
    }

    @Test func likeDislikeClampMax() {
        #expect(FeedbackScaleMode.likeDislike.clamp(10) == 1)
    }

    @Test func likeDislikeClampInRange() {
        #expect(FeedbackScaleMode.likeDislike.clamp(0.5) == 0.5)
    }

    @Test func oneToTenClampMin() {
        #expect(FeedbackScaleMode.oneToTen.clamp(0) == 1)
    }

    @Test func oneToTenClampMax() {
        #expect(FeedbackScaleMode.oneToTen.clamp(15) == 10)
    }

    @Test func oneToTenClampInRange() {
        #expect(FeedbackScaleMode.oneToTen.clamp(7) == 7)
    }

    @Test func oneToHundredClampMin() {
        #expect(FeedbackScaleMode.oneToHundred.clamp(-50) == 1)
    }

    @Test func oneToHundredClampMax() {
        #expect(FeedbackScaleMode.oneToHundred.clamp(200) == 100)
    }

    @Test func oneToHundredClampInRange() {
        #expect(FeedbackScaleMode.oneToHundred.clamp(55) == 55)
    }
}

// MARK: - normalizedValue

@Suite("FeedbackScaleMode - normalizedValue")
struct FeedbackScaleModeNormalizedValueTests {

    @Test func likeDislikeNormalization() {
        #expect(FeedbackScaleMode.likeDislike.normalizedValue(0) == 0.0)
        #expect(FeedbackScaleMode.likeDislike.normalizedValue(0.4) == 0.0)
        #expect(FeedbackScaleMode.likeDislike.normalizedValue(0.5) == 1.0)
        #expect(FeedbackScaleMode.likeDislike.normalizedValue(1) == 1.0)
    }

    @Test func oneToTenNormalization() {
        #expect(FeedbackScaleMode.oneToTen.normalizedValue(1) == 0.0)
        let midNormalized = FeedbackScaleMode.oneToTen.normalizedValue(5.5)
        #expect(abs(midNormalized - 0.5) < 0.001)
        #expect(FeedbackScaleMode.oneToTen.normalizedValue(10) == 1.0)
    }

    @Test func oneToHundredNormalization() {
        #expect(FeedbackScaleMode.oneToHundred.normalizedValue(1) == 0.0)
        let midNormalized = FeedbackScaleMode.oneToHundred.normalizedValue(50.5)
        #expect(abs(midNormalized - 0.5) < 0.001)
        #expect(FeedbackScaleMode.oneToHundred.normalizedValue(100) == 1.0)
    }
}

// MARK: - normalizedValue ↔ value(fromNormalized:) Round-Trip

@Suite("FeedbackScaleMode - Normalized Round-Trip")
struct FeedbackScaleModeNormalizedRoundTripTests {

    @Test func oneToTenRoundTrip() {
        for value in stride(from: 1.0, through: 10.0, by: 1.0) {
            let normalized = FeedbackScaleMode.oneToTen.normalizedValue(value)
            let recovered = FeedbackScaleMode.oneToTen.value(fromNormalized: normalized)
            #expect(abs(recovered - value) < 0.01, "Round-trip failed for \(value)")
        }
    }

    @Test func oneToHundredRoundTrip() {
        for value in stride(from: 1.0, through: 100.0, by: 10.0) {
            let normalized = FeedbackScaleMode.oneToHundred.normalizedValue(value)
            let recovered = FeedbackScaleMode.oneToHundred.value(fromNormalized: normalized)
            #expect(abs(recovered - value) < 0.01, "Round-trip failed for \(value)")
        }
    }

    @Test func likeDislikeRoundTrip() {
        // Like
        let likedNorm = FeedbackScaleMode.likeDislike.normalizedValue(1.0)
        let likedRecovered = FeedbackScaleMode.likeDislike.value(fromNormalized: likedNorm)
        #expect(likedRecovered == 1.0)

        // Dislike
        let dislikedNorm = FeedbackScaleMode.likeDislike.normalizedValue(0.0)
        let dislikedRecovered = FeedbackScaleMode.likeDislike.value(fromNormalized: dislikedNorm)
        #expect(dislikedRecovered == 0.0)
    }

    @Test func valueFromNormalizedBoundsZero() {
        #expect(FeedbackScaleMode.oneToTen.value(fromNormalized: 0.0) == 1.0)
        #expect(FeedbackScaleMode.oneToHundred.value(fromNormalized: 0.0) == 1.0)
    }

    @Test func valueFromNormalizedBoundsOne() {
        #expect(FeedbackScaleMode.oneToTen.value(fromNormalized: 1.0) == 10.0)
        #expect(FeedbackScaleMode.oneToHundred.value(fromNormalized: 1.0) == 100.0)
    }

    @Test func valueFromNormalizedClampsBelowZero() {
        #expect(FeedbackScaleMode.oneToTen.value(fromNormalized: -1.0) == 1.0)
    }

    @Test func valueFromNormalizedClampsAboveOne() {
        #expect(FeedbackScaleMode.oneToTen.value(fromNormalized: 2.0) == 10.0)
    }
}

// MARK: - sentiment

@Suite("FeedbackScaleMode - sentiment")
struct FeedbackScaleModeSentimentTests {

    @Test func likedWhenHighValue() {
        // 1-10: 7/10 → normalized = (7-1)/9 = 0.667 → liked
        #expect(FeedbackScaleMode.oneToTen.sentiment(for: 7) == .liked)
    }

    @Test func dislikedWhenLowValue() {
        // 1-10: 3/10 → normalized = (3-1)/9 = 0.222 → disliked
        #expect(FeedbackScaleMode.oneToTen.sentiment(for: 3) == .disliked)
    }

    @Test func neutralWhenMiddleValue() {
        // 1-10: 5/10 → normalized = (5-1)/9 = 0.444 → neutral (between 0.4 and 0.6)
        #expect(FeedbackScaleMode.oneToTen.sentiment(for: 5) == .neutral)
    }

    @Test func likeDislikeSentiment() {
        #expect(FeedbackScaleMode.likeDislike.sentiment(for: 1.0) == .liked)
        #expect(FeedbackScaleMode.likeDislike.sentiment(for: 0.0) == .disliked)
    }

    @Test func oneToHundredSentiment() {
        // 80/100 → normalized = (80-1)/99 ≈ 0.798 → liked
        #expect(FeedbackScaleMode.oneToHundred.sentiment(for: 80) == .liked)
        // 20/100 → normalized = (20-1)/99 ≈ 0.192 → disliked
        #expect(FeedbackScaleMode.oneToHundred.sentiment(for: 20) == .disliked)
        // 50/100 → normalized = (50-1)/99 ≈ 0.495 → neutral
        #expect(FeedbackScaleMode.oneToHundred.sentiment(for: 50) == .neutral)
    }

    @Test func sentimentThresholdBoundary() {
        // Exactly at 0.6 boundary → liked
        // For 1-10: normalized = 0.6 means value = 0.6*9+1 = 6.4
        // value(fromNormalized: 0.6) = round(6.4) = 6
        // normalizedValue(6) = (6-1)/9 ≈ 0.556 → neutral
        // normalizedValue(7) = (7-1)/9 ≈ 0.667 → liked
        #expect(FeedbackScaleMode.oneToTen.sentiment(for: 6) == .neutral)
        #expect(FeedbackScaleMode.oneToTen.sentiment(for: 7) == .liked)
    }
}

// MARK: - format

@Suite("FeedbackScaleMode - format")
struct FeedbackScaleModeFormatTests {

    @Test func likeDislikeFormatLiked() {
        #expect(FeedbackScaleMode.likeDislike.format(1.0) == "Liked")
        #expect(FeedbackScaleMode.likeDislike.format(0.5) == "Liked")
    }

    @Test func likeDislikeFormatDisliked() {
        #expect(FeedbackScaleMode.likeDislike.format(0.0) == "Disliked")
        #expect(FeedbackScaleMode.likeDislike.format(0.4) == "Disliked")
    }

    @Test func oneToTenFormat() {
        #expect(FeedbackScaleMode.oneToTen.format(8) == "8/10")
        #expect(FeedbackScaleMode.oneToTen.format(1) == "1/10")
        #expect(FeedbackScaleMode.oneToTen.format(10) == "10/10")
    }

    @Test func oneToHundredFormat() {
        #expect(FeedbackScaleMode.oneToHundred.format(75) == "75/100")
        #expect(FeedbackScaleMode.oneToHundred.format(1) == "1/100")
        #expect(FeedbackScaleMode.oneToHundred.format(100) == "100/100")
    }

    @Test func formatClampsOutOfRange() {
        // Below min
        #expect(FeedbackScaleMode.oneToTen.format(0) == "1/10")
        // Above max
        #expect(FeedbackScaleMode.oneToTen.format(15) == "10/10")
    }
}

// MARK: - selectableCases

@Suite("FeedbackScaleMode - selectableCases")
struct FeedbackScaleModeSelectableCasesTests {

    @Test func excludesLegacyModes() {
        let selectable = FeedbackScaleMode.selectableCases
        #expect(!selectable.contains(.fiveStar))
        #expect(!selectable.contains(.tenPoint))
    }

    @Test func includesModernModes() {
        let selectable = FeedbackScaleMode.selectableCases
        #expect(selectable.contains(.likeDislike))
        #expect(selectable.contains(.oneToTen))
        #expect(selectable.contains(.oneToHundred))
    }

    @Test func hasThreeSelectableCases() {
        #expect(FeedbackScaleMode.selectableCases.count == 3)
    }
}

// MARK: - displayName

@Suite("FeedbackScaleMode - displayName")
struct FeedbackScaleModeDisplayNameTests {

    @Test func likeDislikeDisplayName() {
        #expect(FeedbackScaleMode.likeDislike.displayName == "Like / Dislike")
    }

    @Test func oneToTenDisplayName() {
        #expect(FeedbackScaleMode.oneToTen.displayName == "1-10")
    }

    @Test func oneToHundredDisplayName() {
        #expect(FeedbackScaleMode.oneToHundred.displayName == "1-100")
    }

    @Test func fiveStarDisplayNameMapsToOneToTen() {
        #expect(FeedbackScaleMode.fiveStar.displayName == "1-10")
    }

    @Test func tenPointDisplayNameMapsToOneToTen() {
        #expect(FeedbackScaleMode.tenPoint.displayName == "1-10")
    }

    @Test func allModesHaveNonEmptyDisplayName() {
        for mode in FeedbackScaleMode.allCases {
            #expect(!mode.displayName.isEmpty, "\(mode.rawValue) should have a displayName")
        }
    }
}

// MARK: - minimumValue / maximumValue

@Suite("FeedbackScaleMode - min/max")
struct FeedbackScaleModeMinMaxTests {

    @Test func likeDislikeRange() {
        #expect(FeedbackScaleMode.likeDislike.minimumValue == 0)
        #expect(FeedbackScaleMode.likeDislike.maximumValue == 1)
    }

    @Test func oneToTenRange() {
        #expect(FeedbackScaleMode.oneToTen.minimumValue == 1)
        #expect(FeedbackScaleMode.oneToTen.maximumValue == 10)
    }

    @Test func oneToHundredRange() {
        #expect(FeedbackScaleMode.oneToHundred.minimumValue == 1)
        #expect(FeedbackScaleMode.oneToHundred.maximumValue == 100)
    }

    @Test func minAlwaysLessThanMax() {
        for mode in FeedbackScaleMode.allCases {
            #expect(mode.minimumValue < mode.maximumValue,
                    "\(mode.rawValue) min should be less than max")
        }
    }
}

// MARK: - FeedbackSentiment

@Suite("FeedbackSentiment")
struct FeedbackSentimentTests {

    @Test func rawValues() {
        #expect(FeedbackSentiment.liked.rawValue == "liked")
        #expect(FeedbackSentiment.disliked.rawValue == "disliked")
        #expect(FeedbackSentiment.neutral.rawValue == "neutral")
    }
}
