# CHANGELOG.md

## [Unreleased]

### Added
- **Language Preference Settings**: Added `contentLanguage` and `audioLanguage` keys to `SettingsKeys` for persistent user content language preferences
- **SettingsManager Convenience Methods**: Added `getContentLanguage()`, `setContentLanguage()`, `getAudioLanguage()`, and `setAudioLanguage()` methods
- **TypeFilterOption Enum**: New enum for type filter (All/Movies/TV Shows) with accessibility labels
- **GlassPillPicker Accessibility**: Added optional accessibility labels support and increased touch targets (44pt height, 20pt padding) for Vision Pro
- **InlineFilterChip Accessibility**: Added accessibility labels and traits for VoiceOver
- **ExploreFilterSheet Accessibility**: Added section headers with icons, accessibility labels on pickers, and improved footer text
- **ExploreGenreGrid Accessibility**: Added accessibility labels to genre cards and header

### Changed
- **Improved Type Filter UX**: Replaced segmented Picker with GlassPillPicker for better Vision Pro touch targets
- **Improved Filter Sheet Layout**: Better organized sections with icons and improved picker styles
- **Increased Touch Targets**: Filter button and pill picker buttons increased for Vision Pro comfort

### Fixed
- **Accessibility**: Added missing accessibility labels throughout search/filter components

---

## [1.x.x] - 2026-02-28
Previous releases...
