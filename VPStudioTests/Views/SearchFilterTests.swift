import XCTest
@testable import VPStudio

// MARK: - Search UI Component Tests

final class SearchFilterTests: XCTestCase {
    
    // MARK: - TypeFilterOption Tests
    
    func testTypeFilterOptionDescriptions() {
        XCTAssertEqual(TypeFilterOption.all.description, "All")
        XCTAssertEqual(TypeFilterOption.movies.description, "Movies")
        XCTAssertEqual(TypeFilterOption.tvShows.description, "TV Shows")
    }
    
    func testTypeFilterOptionMediaTypes() {
        XCTAssertNil(TypeFilterOption.all.mediaType)
        XCTAssertEqual(TypeFilterOption.movies.mediaType, .movie)
        XCTAssertEqual(TypeFilterOption.tvShows.mediaType, .series)
    }
    
    func testTypeFilterOptionAllCasesCount() {
        XCTAssertEqual(TypeFilterOption.allCases.count, 3)
    }
    
    func testTypeFilterOptionAccessibilityMap() {
        XCTAssertEqual(TypeFilterOption.accessibilityMap[.all], "Show all content types")
        XCTAssertEqual(TypeFilterOption.accessibilityMap[.movies], "Show only movies")
        XCTAssertEqual(TypeFilterOption.accessibilityMap[.tvShows], "Show only TV shows")
    }
    
    // MARK: - SearchLanguageOption Tests
    
    func testSearchLanguageOptionCommonLanguages() {
        let languages = SearchLanguageOption.common
        XCTAssertFalse(languages.isEmpty)
        
        // Check English is present
        let english = languages.first { $0.code == "en-US" }
        XCTAssertNotNil(english)
        XCTAssertEqual(english?.name, "English")
    }
    
    func testSearchLanguageOptionDisplayName() {
        XCTAssertEqual(SearchLanguageOption.displayName(for: "en-US"), "English")
        XCTAssertEqual(SearchLanguageOption.displayName(for: "es-ES"), "Spanish")
        XCTAssertEqual(SearchLanguageOption.displayName(for: nil), "Language")
        XCTAssertEqual(SearchLanguageOption.displayName(for: "unknown"), "unknown")
    }
    
    func testSearchLanguageOptionSummaryNameSingle() {
        let singleLanguage = Set(["en-US"])
        XCTAssertEqual(SearchLanguageOption.summaryName(for: singleLanguage), "English")
    }
    
    func testSearchLanguageOptionSummaryNameMultiple() {
        let multipleLanguages = Set(["en-US", "es-ES"])
        XCTAssertEqual(SearchLanguageOption.summaryName(for: multipleLanguages), "English, Spanish")
    }
    
    func testSearchLanguageOptionSummaryNameEmpty() {
        let emptySet = Set<String>()
        XCTAssertEqual(SearchLanguageOption.summaryName(for: emptySet), "Any")
    }
    
    func testSearchLanguageOptionSummaryNameMany() {
        let manyLanguages = Set(["en-US", "es-ES", "fr-FR"])
        let result = SearchLanguageOption.summaryName(for: manyLanguages)
        XCTAssertTrue(result.contains("languages"))
        XCTAssertEqual(result, "3 languages")
    }
}

// MARK: - InlineFilterChip Tests

import SwiftUI

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
final class InlineFilterChipTests: XCTestCase {
    
    func testInlineFilterChipInactiveState() {
        let chip = InlineFilterChip(text: "Test", isActive: false)
        XCTAssertFalse(chip.isActive)
    }
    
    func testInlineFilterChipActiveState() {
        let chip = InlineFilterChip(text: "Test", isActive: true, tint: .blue)
        XCTAssertTrue(chip.isActive)
        XCTAssertEqual(chip.tint, .blue)
    }
    
    func testInlineFilterChipWithSymbol() {
        let chip = InlineFilterChip(text: "Test", symbol: "calendar", isActive: false)
        XCTAssertNotNil(chip.symbol)
    }
    
    func testInlineFilterChipAccessibilityLabelActive() {
        let chip = InlineFilterChip(text: "2024", isActive: true)
        XCTAssertEqual(chip.accessibilityLabel, "2024, tap to remove")
    }
    
    func testInlineFilterChipAccessibilityLabelInactive() {
        let chip = InlineFilterChip(text: "Action", isActive: false)
        XCTAssertEqual(chip.accessibilityLabel, "Action")
    }
    
    func testInlineFilterChipCustomAccessibilityLabel() {
        let chip = InlineFilterChip(text: "Test", isActive: false, accessibilityLabel: "Custom label")
        XCTAssertEqual(chip.accessibilityLabel, "Custom label")
    }
}

// MARK: - GlassPillPicker Tests

@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
final class GlassPillPickerTests: XCTestCase {
    
    func testPillPickerAnimationPolicyDefaults() {
        XCTAssertEqual(PillPickerAnimationPolicy.springResponse, 0.35)
        XCTAssertEqual(PillPickerAnimationPolicy.springDamping, 0.82)
        XCTAssertEqual(PillPickerAnimationPolicy.pillHeight, 44)  // Increased for Vision Pro
        XCTAssertEqual(PillPickerAnimationPolicy.horizontalPadding, 20)
    }
}

// MARK: - SettingsKeys Tests

final class SettingsKeysLanguageTests: XCTestCase {
    
    func testContentLanguageKeyExists() {
        // Verify the key is defined
        let key = SettingsKeys.contentLanguage
        XCTAssertEqual(key, "content_language")
    }
    
    func testAudioLanguageKeyExists() {
        // Verify the key is defined
        let key = SettingsKeys.audioLanguage
        XCTAssertEqual(key, "audio_language")
    }
    
    func testSubtitleLanguageKeyStillExists() {
        // Verify existing key still works
        let key = SettingsKeys.subtitleLanguage
        XCTAssertEqual(key, "subtitle_language")
    }
}
