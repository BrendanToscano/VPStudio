# FILEREGISTRY.md

## Modified Files

### Core/Settings
| File | Purpose | Functions/Classes | Dependencies | Last Modified |
|------|---------|-------------------|--------------|---------------|
| `VPStudio/Core/Database/SettingsManager.swift` | Settings persistence | SettingsKeys enum, SettingsManager actor | DatabaseManager, SecretStore | 2026-02-28 |

### Views/Components
| File | Purpose | Functions/Classes | Dependencies | Last Modified |
|------|---------|-------------------|--------------|---------------|
| `VPStudio/Views/Components/GlassPillPicker.swift` | Glass-morphism segmented picker | GlassPillPicker, PillPickerAnimationPolicy | SwiftUI | 2026-02-28 |

### Views/Search
| File | Purpose | Functions/Classes | Dependencies | Last Modified |
|------|---------|-------------------|--------------|---------------|
| `VPStudio/Views/Windows/Search/SearchView.swift` | Main search/explore view | SearchView, TypeFilterOption, InlineFilterChip, SearchLanguageOption | SwiftUI, Combine | 2026-02-28 |
| `VPStudio/Views/Windows/Search/ExploreFilterSheet.swift` | Filter sheet modal | ExploreFilterSheet, LanguageToggleRow | SwiftUI | 2026-02-28 |
| `VPStudio/Views/Windows/Search/ExploreGenreGrid.swift` | Genre/mood grid | ExploreGenreGrid, ExploreMoodCardView | SwiftUI | 2026-02-28 |

## New Files

### Tests
| File | Purpose | Test Cases | Dependencies | Last Modified |
|------|---------|------------|--------------|---------------|
| `VPStudioTests/Views/SearchFilterTests.swift` | Unit tests for search UI components | TypeFilterOption, SearchLanguageOption, InlineFilterChip, GlassPillPicker, SettingsKeys | XCTest, SwiftUI | 2026-02-28 |

### Documentation
| File | Purpose | Last Modified |
|------|---------|---------------|
| `CHANGELOG.md` | Version history | 2026-02-28 |
| `FILEREGISTRY.md` | File tracking | 2026-02-28 |

---

## Summary of Changes

### 1. Language Preference Settings
- Added `contentLanguage` and `audioLanguage` to SettingsKeys
- Added convenience methods to SettingsManager for getting/setting language preferences
- Enables persistent user content language preferences across sessions

### 2. Improved Dual Filter UX
- Replaced segmented Picker with GlassPillPicker for type filter (All/Movies/TV Shows)
- Increased touch targets: 44pt height, 20pt horizontal padding (Vision Pro optimized)
- Added accessibility labels to all interactive elements

### 3. Accessibility Improvements
- Added accessibility labels to GlassPillPicker
- Added accessibility labels to InlineFilterChip
- Added accessibility labels to ExploreFilterSheet sections and pickers
- Added accessibility labels to ExploreGenreGrid cards
- Added VoiceOver support throughout search/filter components

### 4. Filter Sheet Improvements
- Added section headers with SF Symbols icons
- Changed Picker styles to .menu for better touch interaction
- Added footer text explaining language multi-select
- Added accessibility labels to all form controls
