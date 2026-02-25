import Testing
import Foundation
@testable import VPStudio

/// Tests the user-rating lookup logic used by LibraryView to pass
/// `userRating` into `MediaCardView`. The core pattern is:
///   1. Fetch rated taste events keyed by `mediaId`
///   2. Look up `userRatings[mediaId]` when building each card
@Suite("Library User Ratings Lookup")
struct LibraryUserRatingsLookupTests {

    // MARK: - Dictionary keying

    @Test func ratingsKeyedByMediaId() {
        let events = [
            TasteEvent(mediaId: "tt001", eventType: .rated, feedbackScale: .oneToTen, feedbackValue: 8),
            TasteEvent(mediaId: "tt002", eventType: .rated, feedbackScale: .oneToTen, feedbackValue: 3),
        ]
        var dict: [String: TasteEvent] = [:]
        for event in events {
            if let mediaId = event.mediaId {
                dict[mediaId] = event
            }
        }
        #expect(dict.count == 2)
        #expect(dict["tt001"]?.feedbackValue == 8)
        #expect(dict["tt002"]?.feedbackValue == 3)
    }

    @Test func nilMediaIdEventsAreSkipped() {
        let event = TasteEvent(mediaId: nil, eventType: .rated, feedbackScale: .oneToTen, feedbackValue: 7)
        var dict: [String: TasteEvent] = [:]
        if let mediaId = event.mediaId {
            dict[mediaId] = event
        }
        #expect(dict.isEmpty)
    }

    @Test func laterEventOverwritesEarlier() {
        let early = TasteEvent(
            id: "e1", mediaId: "tt001", eventType: .rated,
            feedbackScale: .oneToTen, feedbackValue: 5,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        let late = TasteEvent(
            id: "e2", mediaId: "tt001", eventType: .rated,
            feedbackScale: .oneToTen, feedbackValue: 9,
            createdAt: Date(timeIntervalSince1970: 2000)
        )
        var dict: [String: TasteEvent] = [:]
        // Simulate fetching in chronological order (DB returns ordered by createdAt)
        for event in [early, late] {
            if let mediaId = event.mediaId {
                dict[mediaId] = event
            }
        }
        #expect(dict["tt001"]?.feedbackValue == 9, "Latest rating should win")
    }

    @Test func lookupReturnsNilForUnratedMedia() {
        let dict: [String: TasteEvent] = [
            "tt001": TasteEvent(mediaId: "tt001", eventType: .rated, feedbackScale: .oneToTen, feedbackValue: 7),
        ]
        #expect(dict["tt999"] == nil)
    }

    @Test func onlyRatedEventsAreRelevant() {
        // Non-rated events (watched, browsed) should not appear in the ratings dict
        // The DB query filters by eventType: .rated, but verify the keying logic handles mixed input
        let events = [
            TasteEvent(mediaId: "tt001", eventType: .watched),
            TasteEvent(mediaId: "tt002", eventType: .rated, feedbackScale: .oneToTen, feedbackValue: 8),
            TasteEvent(mediaId: "tt003", eventType: .browsed),
        ]
        // Simulate the filter the DB applies (eventType: .rated)
        let rated = events.filter { $0.eventType == .rated }
        var dict: [String: TasteEvent] = [:]
        for event in rated {
            if let mediaId = event.mediaId {
                dict[mediaId] = event
            }
        }
        #expect(dict.count == 1)
        #expect(dict["tt002"]?.feedbackValue == 8)
    }

    // MARK: - Scale display consistency

    @Test func differentScalesPreservedInLookup() {
        let events = [
            TasteEvent(mediaId: "tt001", eventType: .rated, feedbackScale: .oneToTen, feedbackValue: 8),
            TasteEvent(mediaId: "tt002", eventType: .rated, feedbackScale: .likeDislike, feedbackValue: 1),
            TasteEvent(mediaId: "tt003", eventType: .rated, feedbackScale: .oneToHundred, feedbackValue: 75),
        ]
        var dict: [String: TasteEvent] = [:]
        for event in events {
            if let mediaId = event.mediaId { dict[mediaId] = event }
        }
        #expect(dict["tt001"]?.feedbackScale == .oneToTen)
        #expect(dict["tt002"]?.feedbackScale == .likeDislike)
        #expect(dict["tt003"]?.feedbackScale == .oneToHundred)
    }

    @Test func emptyEventsListProducesEmptyDict() {
        let events: [TasteEvent] = []
        var dict: [String: TasteEvent] = [:]
        for event in events {
            if let mediaId = event.mediaId { dict[mediaId] = event }
        }
        #expect(dict.isEmpty)
    }
}
