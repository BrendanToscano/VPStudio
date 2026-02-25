import SwiftUI
import UniformTypeIdentifiers

struct LibraryCSVImportSheet: View {
    let onImportComplete: (LibraryCSVImportSummary) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var csvImportDestination: LibraryCSVImportDestination = .auto
    @State private var csvImportRatings = true
    @State private var csvPromoteLikedToFavorites = true
    @State private var folderName = ""
    @State private var importToFolder = true
    @State private var autoSubfolderPerFile = true
    @State private var existingFolderOptions: [String] = []
    @State private var selectedExistingFolderName = Self.createNewFolderOption
    @State private var importPickerMode: ImportPickerMode?
    @State private var csvImportInFlight = false
    @State private var csvImportError: String?
    @State private var csvImportNotice: String?
    @State private var importSummary: LibraryCSVImportSummary?
    @State private var multiImportSummaries: [LibraryCSVImportSummary] = []
    @State private var importDiagnostics: [String] = []

    private enum ImportPickerMode: Identifiable {
        case csvFiles
        case folder

        var id: Int { hashValue }
    }

    private static let createNewFolderOption = "__create_new_folder_option__"

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    Picker("Import to", selection: $csvImportDestination) {
                        ForEach(LibraryCSVImportDestination.allCases, id: \.self) { destination in
                            Text(destination.displayName).tag(destination)
                        }
                    }
                }

                Section("Folder") {
                    Toggle("Import into a named folder", isOn: $importToFolder)

                    if importToFolder {
                        if destinationSupportsFolders {
                            Toggle("Auto subfolder from each filename", isOn: $autoSubfolderPerFile)

                            if autoSubfolderPerFile {
                                Text("Each CSV is imported into its own subfolder (derived from filename).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                if !existingFolderOptions.isEmpty {
                                    Picker("Existing subfolder", selection: $selectedExistingFolderName) {
                                        Text("Create New Folder").tag(Self.createNewFolderOption)
                                        ForEach(existingFolderOptions, id: \.self) { name in
                                            Text(name).tag(name)
                                        }
                                    }
                                }

                                if shouldShowCustomFolderField {
                                    TextField("Subfolder name", text: $folderName)
                                        .textFieldStyle(.roundedBorder)

                                    Text("All selected CSV files will import into this subfolder. If it exists, it will be reused.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("All selected CSV files will import into “\(selectedExistingFolderName)”.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("History imports do not use folders. This setting is ignored for History destination.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Ratings") {
                    Toggle("Import ratings into AI profile", isOn: $csvImportRatings)
                    Toggle("Promote liked ratings to Favorites (Auto)", isOn: $csvPromoteLikedToFavorites)
                        .disabled(!csvImportRatings || csvImportDestination != .auto)
                }

                Section {
                    Button(csvImportInFlight ? "Importing..." : "Choose CSV Files", systemImage: "square.and.arrow.down") {
                        importPickerMode = .csvFiles
                    }
                    .disabled(csvImportInFlight)

                    Button(csvImportInFlight ? "Importing..." : "Import from Folder", systemImage: "folder") {
                        importPickerMode = .folder
                    }
                    .disabled(csvImportInFlight)

                    Text("Choose individual CSV files, or select a folder to import all CSVs inside it. Supports IMDb exports and VPStudio exports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !multiImportSummaries.isEmpty {
                    Section("Import Results (\(multiImportSummaries.count) file\(multiImportSummaries.count == 1 ? "" : "s"))") {
                        let totals = aggregatedSummary(multiImportSummaries)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total rows: \(totals.rowsImported)/\(totals.rowsRead) imported (\(totals.rowsSkipped) skipped)")
                            Text("Created: \(totals.mediaItemsCreated) media \u{00B7} Updated: \(totals.mediaItemsUpdated)")
                            Text("Watchlist: \(totals.watchlistImported) \u{00B7} Favorites: \(totals.favoritesImported) \u{00B7} History: \(totals.historyImported) \u{00B7} Ratings: \(totals.ratingsImported)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(Array(multiImportSummaries.enumerated()), id: \.offset) { _, summary in
                            VStack(alignment: .leading, spacing: 2) {
                                if let folderName = summary.targetFolderName {
                                    Text(folderName)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                Text("\(summary.detectedFormat.displayName) \u{00B7} \(summary.rowsImported) imported \u{00B7} W:\(summary.watchlistImported) F:\(summary.favoritesImported) H:\(summary.historyImported)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if let summary = importSummary {
                    Section("Import Results") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Format: \(summary.detectedFormat.displayName)")
                            Text("Rows: \(summary.rowsImported)/\(summary.rowsRead) imported (\(summary.rowsSkipped) skipped)")
                            Text("Created: \(summary.mediaItemsCreated) media \u{00B7} Updated: \(summary.mediaItemsUpdated)")
                            Text("Watchlist: \(summary.watchlistImported) \u{00B7} Favorites: \(summary.favoritesImported) \u{00B7} History: \(summary.historyImported) \u{00B7} Ratings: \(summary.ratingsImported)")
                            if let folderName = summary.targetFolderName {
                                Text("Folder: \(folderName)")
                            }
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

                if let notice = csvImportNotice {
                    Section {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if !importDiagnostics.isEmpty {
                    Section("Diagnostics") {
                        Text("Build marker: import-diag-20260225b")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Trace file: \(Self.traceLogURL.path)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        ForEach(Array(importDiagnostics.suffix(10).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Import CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: isPickerPresented,
                allowedContentTypes: activeContentTypes,
                allowsMultipleSelection: importPickerMode != .folder
            ) { result in
                let mode = importPickerMode
                importPickerMode = nil
                trace("picker result mode=\(String(describing: mode))")
                switch mode {
                case .csvFiles:
                    Task { await importCSVFiles(result) }
                case .folder:
                    Task { await importFolder(result) }
                case nil:
                    break
                }
            }
            .task {
                await refreshExistingFolderOptions()
            }
            .onChange(of: csvImportDestination) { _, _ in
                Task { await refreshExistingFolderOptions() }
            }
        }
        .frame(minWidth: 400, minHeight: 440)
    }

    /// Single binding that drives the one `.fileImporter` modifier.
    private var isPickerPresented: Binding<Bool> {
        Binding(
            get: { importPickerMode != nil },
            // Keep mode until fileImporter completion callback reads it.
            // Clearing here races with callback and can drop the import action.
            set: { _ in }
        )
    }

    /// Content types switch based on which button was tapped.
    private var activeContentTypes: [UTType] {
        importPickerMode == .folder ? [.folder] : supportedCSVTypes
    }

    private var destinationFolderListTypes: [UserLibraryEntry.ListType] {
        switch csvImportDestination {
        case .watchlist:
            return [.watchlist]
        case .favorites:
            return [.favorites]
        case .auto:
            return [.watchlist, .favorites]
        case .history:
            return []
        }
    }

    private var destinationSupportsFolders: Bool {
        !destinationFolderListTypes.isEmpty
    }

    private var shouldShowCustomFolderField: Bool {
        existingFolderOptions.isEmpty || selectedExistingFolderName == Self.createNewFolderOption
    }

    private var selectedManualFolderName: String {
        if shouldShowCustomFolderField {
            return folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedExistingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supportedCSVTypes: [UTType] {
        let types: [UTType?] = [
            UTType.commaSeparatedText,
            UTType(filenameExtension: "csv"),
            UTType.plainText,
            UTType.text,
        ]
        let compact = types.compactMap { $0 }
        return compact.isEmpty ? [.data] : compact
    }

    @MainActor
    private func importCSVFiles(_ result: Result<[URL], any Error>) async {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            trace("importCSVFiles start files=\(urls.count) importToFolder=\(importToFolder) autoSubfolderPerFile=\(autoSubfolderPerFile)")
            csvImportError = nil
            csvImportNotice = nil
            csvImportInFlight = true
            defer { csvImportInFlight = false }

            let manualFolderName = selectedManualFolderName
            let useAutoSubfolderPerFile = importToFolder && destinationSupportsFolders && autoSubfolderPerFile

            if urls.count > 1, importToFolder, destinationSupportsFolders, !useAutoSubfolderPerFile, manualFolderName.isEmpty {
                csvImportError = "Enter a subfolder name, or enable auto subfolder by filename."
                trace("importCSVFiles validation error=missing manual subfolder name")
                return
            }

            // Single file — use existing single-import behavior
            if urls.count == 1 {
                let summary = try await importSingleCSV(
                    urls[0],
                    autoFolderFromFilename: useAutoSubfolderPerFile
                )
                try? await appState.database.pruneEmptyManualFolders()
                importSummary = summary
                multiImportSummaries = []
                print("[VPStudio Import] file=\(urls[0].lastPathComponent) \(Self.summaryLogLine(summary))")
                trace("single file=\(urls[0].lastPathComponent) \(Self.summaryLogLine(summary))")
                if !Self.hasLibraryChanges(in: summary) {
                    csvImportNotice = Self.noLibraryChangesNotice(anyRatingsImported: summary.ratingsImported > 0)
                }
                onImportComplete(summary)
                return
            }

            // Multi-file — either per-file auto subfolders, or one manual subfolder.
            var summaries: [LibraryCSVImportSummary] = []
            var anyLibraryChange = false
            var anyRatingChange = false

            for url in urls {
                do {
                    let summary = try await importSingleCSV(
                        url,
                        autoFolderFromFilename: useAutoSubfolderPerFile
                    )
                    summaries.append(summary)
                    print("[VPStudio Import] file=\(url.lastPathComponent) \(Self.summaryLogLine(summary))")
                    trace("file=\(url.lastPathComponent) \(Self.summaryLogLine(summary))")
                    if Self.hasLibraryChanges(in: summary) {
                        anyLibraryChange = true
                    }
                    if summary.ratingsImported > 0 {
                        anyRatingChange = true
                    }
                } catch {
                    print("[VPStudio Import] file=\(url.lastPathComponent) error=\(error.localizedDescription)")
                    trace("file=\(url.lastPathComponent) error=\(error.localizedDescription)")
                    // Record error for this file but continue with the rest
                    csvImportError = (csvImportError ?? "") + "\(url.lastPathComponent): \(error.localizedDescription)\n"
                }
            }

            multiImportSummaries = summaries
            importSummary = nil

            if !summaries.isEmpty && !anyLibraryChange {
                csvImportNotice = Self.noLibraryChangesNotice(anyRatingsImported: anyRatingChange)
            }

            if anyLibraryChange {
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            }
            if anyRatingChange {
                NotificationCenter.default.post(name: .tasteProfileDidChange, object: nil)
            }

            // Clean up any empty folders left from previous imports
            try? await appState.database.pruneEmptyManualFolders()

            if !summaries.isEmpty {
                let aggregate = aggregatedSummary(summaries)
                print("[VPStudio Import] aggregate files=\(summaries.count) \(Self.summaryLogLine(aggregate))")
                trace("aggregate files=\(summaries.count) \(Self.summaryLogLine(aggregate))")
                onImportComplete(aggregate)
            }
        } catch {
            csvImportNotice = nil
            print("[VPStudio Import] import error=\(error.localizedDescription)")
            trace("import error=\(error.localizedDescription)")
            csvImportError = error.localizedDescription
        }
    }

    @MainActor
    private func importFolder(_ result: Result<[URL], any Error>) async {
        do {
            let urls = try result.get()
            guard let folderURL = urls.first else { return }
            trace("importFolder path=\(folderURL.path)")

            let hasSecurityScope = folderURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }

            let contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let csvURLs = contents.filter { $0.pathExtension.lowercased() == "csv" }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

            guard !csvURLs.isEmpty else {
                csvImportNotice = nil
                csvImportError = "No CSV files found in the selected folder."
                trace("importFolder no csv files")
                return
            }

            trace("importFolder csv files=\(csvURLs.count)")
            // Feed into existing multi-file import path
            await importCSVFiles(.success(csvURLs))
        } catch {
            csvImportNotice = nil
            trace("importFolder error=\(error.localizedDescription)")
            csvImportError = error.localizedDescription
        }
    }

    @MainActor
    private func importSingleCSV(_ url: URL, autoFolderFromFilename: Bool = false) async throws -> LibraryCSVImportSummary {
        trace("importSingleCSV file=\(url.lastPathComponent) autoFolder=\(autoFolderFromFilename)")
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        trace("importSingleCSV stats=\(Self.debugFileStats(at: url))")

        let resolvedFolderName: String?
        if autoFolderFromFilename {
            // Multi-import: always use filename as folder name
            resolvedFolderName = LibraryCSVImportService.defaultFolderName(from: url)
        } else if importToFolder, destinationSupportsFolders {
            // Single import: use selected/typed folder, defaulting to filename when empty.
            var manualName = selectedManualFolderName
            if manualName.isEmpty {
                folderName = LibraryCSVImportService.defaultFolderName(from: url)
                manualName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            resolvedFolderName = manualName.isEmpty ? nil : manualName
        } else {
            resolvedFolderName = nil
        }

        // When destination is Auto, infer from filename so items land in the right list
        let resolvedDestination: LibraryCSVImportDestination
        if csvImportDestination == .auto,
           let inferred = LibraryCSVImportService.inferredDestination(from: url) {
            resolvedDestination = inferred
        } else {
            resolvedDestination = csvImportDestination
        }
        trace("importSingleCSV destination=\(resolvedDestination.rawValue) folder=\(resolvedFolderName ?? "nil")")

        let options = LibraryCSVImportOptions(
            destination: resolvedDestination,
            importRatings: csvImportRatings,
            promoteLikedRatingsToFavorites: csvPromoteLikedToFavorites,
            targetFolderName: resolvedFolderName
        )

        let summary = try await appState.libraryCSVImportService.importCSV(from: url, options: options)

        // Refresh library only when list entries actually changed.
        if Self.hasLibraryChanges(in: summary) {
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
        if summary.ratingsImported > 0 {
            NotificationCenter.default.post(name: .tasteProfileDidChange, object: nil)
        }

        return summary
    }

    @MainActor
    private func refreshExistingFolderOptions() async {
        guard destinationSupportsFolders else {
            existingFolderOptions = []
            selectedExistingFolderName = Self.createNewFolderOption
            return
        }

        do {
            var names: [String] = []
            for listType in destinationFolderListTypes {
                let folders = try await appState.database.fetchAllLibraryFolders(listType: listType)
                names.append(contentsOf: folders.filter { !$0.isSystem }.map(\.name))
            }

            var uniqueNames: [String] = []
            let sorted = names.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            for name in sorted {
                if uniqueNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    continue
                }
                uniqueNames.append(name)
            }

            existingFolderOptions = uniqueNames

            if uniqueNames.isEmpty {
                selectedExistingFolderName = Self.createNewFolderOption
                return
            }

            if let match = uniqueNames.first(where: {
                $0.caseInsensitiveCompare(selectedExistingFolderName) == .orderedSame
            }) {
                selectedExistingFolderName = match
            } else if selectedExistingFolderName == Self.createNewFolderOption {
                selectedExistingFolderName = uniqueNames[0]
            } else {
                selectedExistingFolderName = uniqueNames[0]
            }
        } catch {
            existingFolderOptions = []
            selectedExistingFolderName = Self.createNewFolderOption
            trace("existing folders load error=\(error.localizedDescription)")
        }
    }

    private func aggregatedSummary(_ summaries: [LibraryCSVImportSummary]) -> LibraryCSVImportSummary {
        var total = LibraryCSVImportSummary(
            detectedFormat: .generic,
            rowsRead: 0, rowsImported: 0, rowsSkipped: 0,
            mediaItemsCreated: 0, mediaItemsUpdated: 0,
            watchlistImported: 0, favoritesImported: 0,
            historyImported: 0, ratingsImported: 0
        )
        for s in summaries {
            total.rowsRead += s.rowsRead
            total.rowsImported += s.rowsImported
            total.rowsSkipped += s.rowsSkipped
            total.mediaItemsCreated += s.mediaItemsCreated
            total.mediaItemsUpdated += s.mediaItemsUpdated
            total.watchlistImported += s.watchlistImported
            total.favoritesImported += s.favoritesImported
            total.historyImported += s.historyImported
            total.ratingsImported += s.ratingsImported
        }
        return total
    }

    private static func hasLibraryChanges(in summary: LibraryCSVImportSummary) -> Bool {
        summary.watchlistImported > 0 || summary.favoritesImported > 0 || summary.historyImported > 0
    }

    private static func noLibraryChangesNotice(anyRatingsImported: Bool) -> String {
        if anyRatingsImported {
            return "Import finished, but no new library items were added. Ratings were imported."
        }
        return "Import finished, but no new library items were added. The imported titles may already exist."
    }

    private static func summaryLogLine(_ summary: LibraryCSVImportSummary) -> String {
        "rows=\(summary.rowsImported)/\(summary.rowsRead) skipped=\(summary.rowsSkipped) W=\(summary.watchlistImported) F=\(summary.favoritesImported) H=\(summary.historyImported) R=\(summary.ratingsImported)"
    }

    private static func debugFileStats(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return "read=failed path=\(url.path)"
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        guard let text else {
            return "bytes=\(data.count) text=undecodable"
        }
        let header = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lineCount = text.split(whereSeparator: \.isNewline).count
        return "bytes=\(data.count) lines=\(lineCount) header=\"\(header.prefix(80))\""
    }

    @MainActor
    private func trace(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        importDiagnostics.append(line)
        if importDiagnostics.count > 80 {
            importDiagnostics.removeFirst(importDiagnostics.count - 80)
        }
        appendTraceLine(line)
    }

    private func appendTraceLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        let url = Self.traceLogURL
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                return
            } catch {
                // Fall through to rewrite when append fails.
            }
        }
        try? data.write(to: url)
    }

    private static var traceLogURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vpstudio-import-trace.log")
    }
}
