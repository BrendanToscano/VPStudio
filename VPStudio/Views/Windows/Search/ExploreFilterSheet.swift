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
                    Section {
                        Picker("Genre", selection: $selectedGenre) {
                            Text("All Genres").tag(nil as Genre?)
                            ForEach(genres) { genre in
                                Text(genre.name).tag(genre as Genre?)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("Filter by genre")
                    } header: {
                        Label("Genre", systemImage: "theatermasks")
                            .font(.headline)
                    }
                }

                // Sort
                Section {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(displayedSortOptions, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityLabel("Sort results by")
                } header: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                        .font(.headline)
                }

                // Year
                Section {
                    Picker("Year", selection: $selectedYear) {
                        Text("Any Year").tag(nil as Int?)
                        ForEach(Self.yearRange, id: \.self) { year in
                            Text(String(year)).tag(year as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Filter by release year")
                } header: {
                    Label("Release Year", systemImage: "calendar")
                        .font(.headline)
                }

                // Language (multi-select)
                Section {
                    languageRows
                } header: {
                    Label("Languages", systemImage: "globe")
                        .font(.headline)
                } footer: {
                    Text("Select one or more content languages")
                        .font(.caption)
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
                    .accessibilityLabel("Apply filters")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel and close filters")
                }
            }
        }
        #if os(visionOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private var languageRows: some View {
        ForEach(SearchLanguageOption.common, id: \.code) { option in
            LanguageToggleRow(
                name: option.name,
                isSelected: selectedLanguages.contains(option.code),
                onTap: { toggleLanguage(option.code) }
            )
            .accessibilityLabel("\(option.name), \(selectedLanguages.contains(option.code) ? "selected" : "not selected")")
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
        .contentShape(Rectangle())
    }
}
