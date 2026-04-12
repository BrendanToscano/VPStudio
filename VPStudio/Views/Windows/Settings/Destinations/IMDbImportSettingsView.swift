import SwiftUI
import UniformTypeIdentifiers

// MARK: - IMDb Import Settings

struct IMDbImportSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingImportSheet = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("IMDb Export Support", systemImage: "film.stack")
                        .font(.headline)

                    Text("VPStudio supports importing your IMDb data via CSV exports from IMDb. This lets you bring your watchlist, ratings, and watch history into VPStudio without a direct sync API.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Supported Exports") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("IMDb Watchlist", value: "Your CSV export from imdb.com/watchlist")
                    LabeledContent("IMDb Ratings", value: "Your ratings CSV export from imdb.com/user")
                    LabeledContent("Watch History", value: "Your watched items CSV")
                }
                .font(.caption)
            }

            Section("How to Export from IMDb") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Go to imdb.com and sign in")
                    Text("2. Navigate to your **Watchlist** or **Ratings** page")
                    Text("3. Click **Export** to download a CSV file")
                    Text("4. Use the button below to import it into VPStudio")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    isShowingImportSheet = true
                } label: {
                    Label("Import from CSV", systemImage: "square.and.arrow.down")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About IMDb Sync")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("IMDb does not offer a public sync API. VPStudio handles IMDb data through CSV imports, which is the only officially supported method. Ratings and watchlist items are imported into your VPStudio library and AI taste profile.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("IMDb Import")
        .sheet(isPresented: $isShowingImportSheet) {
            IMDbCSVImportSheet()
        }
    }
}

// MARK: - IMDb-aware CSV Import Sheet

struct IMDbCSVImportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var csvImportDestination: LibraryCSVImportDestination = .auto
    @State private var csvImportRatings = true
    @State private var csvPromoteLikedToFavorites = true
    @State private var importToFolder = true
    @State private var folderName = ""
    @State private var csvImportInFlight = false
    @State private var csvImportError: String?
    @State private var importSummary: LibraryCSVImportSummary?
    @State private var isShowingPreview = false
    @State private var selectedFileURL: URL?
    @State private var previewDetected = false

    // Preview state
    @State private var previewHeaders: [String] = []
    @State private var previewFirstRows: [[String]] = []
    @State private var detectedMappings: [String: String] = [:]
    @State private var isAnalyzingHeaders = false
    @State private var aiSuggestedMappings: [String: String] = [:]
    @State private var aiAnalysisError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Import Destination") {
                    Picker("Import to", selection: $csvImportDestination) {
                        ForEach(LibraryCSVImportDestination.allCases, id: \.self) { dest in
                            Text(dest.displayName).tag(dest)
                        }
                    }
                    Text("When set to **Auto**, VPStudio infers the destination from the filename.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Options") {
                    Toggle("Import ratings into AI profile", isOn: $csvImportRatings)
                    Toggle("Promote liked ratings to Favorites", isOn: $csvPromoteLikedToFavorites)
                        .disabled(!csvImportRatings || csvImportDestination != .auto)

                    Toggle("Import into named folder", isOn: $importToFolder)

                    if importToFolder {
                        TextField("Folder name (optional)", text: $folderName)
                        Text("If blank, VPStudio uses the CSV filename.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        if selectedFileURL == nil {
                            isShowingPreview = true
                        } else {
                            Task { await importSelectedOrPickedCSV() }
                        }
                    } label: {
                        Label(
                            selectedFileURL == nil
                                ? (previewDetected ? "Change CSV File" : "Preview CSV Before Importing")
                                : (csvImportInFlight ? "Importing..." : "Import Selected CSV"),
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .disabled(csvImportInFlight)
                }

                if selectedFileURL != nil || previewDetected {
                    Section {
                        if let url = selectedFileURL {
                            HStack {
                                Image(systemName: "doc.text")
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Button("Clear") {
                                    selectedFileURL = nil
                                    previewDetected = false
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                if let summary = importSummary {
                    Section("Import Results") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Format: \(summary.detectedFormat.displayName)")
                            Text("Rows: \(summary.rowsImported)/\(summary.rowsRead) imported (\(summary.rowsSkipped) skipped)")
                            Text("Watchlist: \(summary.watchlistImported) \u{00B7} Favorites: \(summary.favoritesImported) \u{00B7} History: \(summary.historyImported) \u{00B7} Ratings: \(summary.ratingsImported)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let error = csvImportError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("IMDb Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isShowingPreview,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            selectedFileURL = url
                            await analyzeCSVHeaders(url: url)
                            previewDetected = true
                            isShowingPreview = false
                        }
                    case .failure(let error):
                        csvImportError = error.localizedDescription
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    @MainActor
    private func importSelectedOrPickedCSV() async {
        guard let url = selectedFileURL else {
            // Trigger file picker if nothing selected yet
            isShowingPreview = true
            return
        }

        csvImportError = nil
        importSummary = nil
        csvImportInFlight = true
        defer { csvImportInFlight = false }

        do {
            let options = LibraryCSVImportOptions(
                destination: csvImportDestination,
                importRatings: csvImportRatings,
                promoteLikedRatingsToFavorites: csvPromoteLikedToFavorites,
                targetFolderName: importToFolder && !folderName.isEmpty ? folderName : nil
            )

            let summary = try await appState.libraryCSVImportService.importCSV(from: url, options: options)
            importSummary = summary
        } catch {
            csvImportError = error.localizedDescription
        }
    }

    @MainActor
    private func analyzeCSVHeaders(url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.components(separatedBy: .newlines)
            guard let headerLine = lines.first else { return }

            let headers = parseCSVLine(headerLine)
            previewHeaders = headers

            // Get first 3 data rows
            var firstRows: [[String]] = []
            for line in lines.dropFirst().prefix(3) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                firstRows.append(parseCSVLine(trimmed))
            }
            previewFirstRows = firstRows

            // Auto-detect format and column mappings
            let normalizedHeaders = headers.map { h in
                h.lowercased().filter { $0.isLetter || $0.isNumber }
            }
            detectedMappings = detectColumnMappings(from: normalizedHeaders)
        } catch {
            csvImportError = "Could not read CSV: \(error.localizedDescription)"
        }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private func detectColumnMappings(from headers: [String]) -> [String: String] {
        var mappings: [String: String] = [:]
        let knownMappings: [Set<String>: String] = [
            ["title", "name", "primarytitle", "originaltitle", "movie", "show"]: "title",
            ["year", "releaseyear", "startyear"]: "year",
            ["type", "titletype", "mediatype", "kind"]: "mediaType",
            ["const", "tconst", "imdbid", "imdbconst", "titleconst", "id"]: "imdbID",
            ["yourrating", "userrating", "rating", "myscore", "myrating", "score", "yourscore", "yourated"]: "userRating",
            ["imdbrating", "imdbscore"]: "imdbRating",
            ["liked", "favorite", "favourite", "isliked"]: "liked",
            ["created", "daterated", "dateadded", "watcheddate", "watchedat", "added", "date"]: "date",
        ]
        for header in headers {
            for (keys, field) in knownMappings {
                if keys.contains(header) {
                    mappings[header] = field
                    break
                }
            }
        }
        return mappings
    }
}

// MARK: - CSV Header Preview / AI Mapping Sheet

struct CSVHeaderPreviewSheet: View {
    @Binding var headers: [String]
    @Binding var firstRows: [[String]]
    @Binding var detectedMappings: [String: String]
    @Binding var isAnalyzing: Bool
    @Binding var aiSuggestedMappings: [String: String]
    @Binding var aiAnalysisError: String?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var csvImportInFlight = false
    @State private var csvImportError: String?
    @State private var importSummary: LibraryCSVImportSummary?

    enum MappingChoice: String, CaseIterable {
        case detected = "Auto"
        case ai = "AI"
        case ignore = "Ignore"
    }

    @State private var selectedMappingOption: [String: MappingChoice] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if headers.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No CSV Loaded")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else {
                    Section("Detected Columns (\(headers.count))") {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(header)
                                    .font(.caption)
                                    .fontWeight(.semibold)

                                if let mapping = detectedMappings[header] {
                                    Text("Auto: \(mapping)")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }

                                if let aiMapping = aiSuggestedMappings[header], aiMapping != detectedMappings[header] {
                                    Text("AI: \(aiMapping)")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }

                    if !firstRows.isEmpty {
                        Section("Sample Data (first \(min(3, firstRows.count)) rows)") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(headers.joined(separator: " | "))
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    ForEach(Array(firstRows.prefix(3).enumerated()), id: \.offset) { _, row in
                                        Text(row.prefix(headers.count).joined(separator: " | "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            Task { await analyzeWithAI() }
                        } label: {
                            HStack {
                                if isAnalyzing {
                                    ProgressView().scaleEffect(0.8)
                                }
                                Text(isAnalyzing ? "Analyzing with AI..." : "Analyze Headers with AI")
                            }
                        }
                        .disabled(isAnalyzing || headers.isEmpty)

                        if let error = aiAnalysisError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let summary = importSummary {
                        Section("Import Results") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Format: \(summary.detectedFormat.displayName)")
                                Text("Rows: \(summary.rowsImported)/\(summary.rowsRead) imported (\(summary.rowsSkipped) skipped)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if let error = csvImportError {
                        Section {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("CSV Preview")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    @MainActor
    private func analyzeWithAI() async {
        guard !headers.isEmpty else { return }
        isAnalyzing = true
        aiAnalysisError = nil
        aiSuggestedMappings = [:]
        defer { isAnalyzing = false }

        let headerList = headers.joined(separator: ", ")
        let prompt = """
        VPStudio imports CSV files and maps column headers to these internal fields:
        - title, name (movie/show title)
        - year, releaseyear, startyear
        - type, titletype, mediatype, kind (movie or series)
        - const, tconst, imdbid (IMDb ID like tt1234567)
        - yourrating, userrating, rating, myscore, myrating (user's personal rating)
        - imdbrating, imdbscore (IMDb official rating)
        - liked, favorite, favourite, favourite
        - created, daterated, dateadded, watcheddate (dates)
        - url, imdburl, link

        Respond with ONLY a valid JSON object mapping each header to the best VPStudio field name, or null to ignore it.
        Example: {"my rating":"yourrating","Date Added":"dateadded","Notes":null}

        CSV headers: \(headerList)
        """

        do {
            let response = try await appState.aiAssistantManager.ask(prompt: prompt)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")

            if let data = cleaned.data(using: .utf8),
               let parsed = try? JSONDecoder().decode([String: String?].self, from: data) {
                var suggestions: [String: String] = [:]
                for (header, field) in parsed {
                    if let field {
                        suggestions[header] = field
                    }
                }
                aiSuggestedMappings = suggestions
            } else {
                aiAnalysisError = "AI response was not valid JSON. Try again."
            }
        } catch {
            aiAnalysisError = "AI analysis failed: \(error.localizedDescription)"
        }
    }
}
