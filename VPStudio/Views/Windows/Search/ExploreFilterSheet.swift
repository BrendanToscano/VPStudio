import SwiftUI

struct ExploreFilterSheet: View {
    @Binding var sortOption: DiscoverFilters.SortOption
    @Binding var selectedYear: Int?
    @Binding var selectedLanguages: Set<String>
    let genres: [Genre]
    @Binding var selectedGenre: Genre?
    let displayedSortOptions: [DiscoverFilters.SortOption]
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    private static let yearRange: [Int] = {
        let current = Calendar.current.component(.year, from: Date())
        return Array((1950...current).reversed())
    }()

    var body: some View {
        NavigationStack {
            Form {
                // Genre
                if !genres.isEmpty {
                    Section("Genre") {
                        Picker("Genre", selection: $selectedGenre) {
                            Text("All Genres").tag(nil as Genre?)
                            ForEach(genres) { genre in
                                Text(genre.name).tag(genre as Genre?)
                            }
                        }
                    }
                }

                // Sort
                Section("Sort By") {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(displayedSortOptions, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // Year
                Section("Release Year") {
                    Picker("Year", selection: $selectedYear) {
                        Text("Any Year").tag(nil as Int?)
                        ForEach(Self.yearRange, id: \.self) { year in
                            Text(String(year)).tag(year as Int?)
                        }
                    }
                }

                // Language (multi-select)
                Section("Languages") {
                    languageRows
                }
            }
            .navigationTitle("Filters")
            #if os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(visionOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private var languageRows: some View {
        ForEach(SearchLanguageOption.common, id: \SearchLanguageOption.Option.code) { option in
            LanguageToggleRow(
                name: option.name,
                isSelected: selectedLanguages.contains(option.code),
                onTap: { toggleLanguage(option.code) }
            )
        }
    }

    private func toggleLanguage(_ code: String) {
        if selectedLanguages.contains(code) {
            selectedLanguages.remove(code)
        } else {
            selectedLanguages.insert(code)
        }
    }
}

private struct LanguageToggleRow: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
