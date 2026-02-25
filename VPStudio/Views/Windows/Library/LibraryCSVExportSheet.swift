import SwiftUI
import UniformTypeIdentifiers

struct LibraryCSVExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isExporting = false
    @State private var exportSummary: LibraryCSVExportSummary?
    @State private var exportDirectoryURL: URL?
    @State private var errorMessage: String?
    @State private var isShowingShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Export your library as IMDb-compatible CSV files. Each folder becomes a separate file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let summary = exportSummary {
                    exportResultView(summary)
                } else {
                    exportOptionsView
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Export CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 280)
    }

    private var exportOptionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("What gets exported", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 4) {
                    bulletItem("Watchlist folders as individual CSVs")
                    bulletItem("Favorites folders as individual CSVs")
                    bulletItem("Watch History as a single CSV")
                    bulletItem("Your ratings included where available")
                }
                .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("Format", systemImage: "doc.text")
                    .font(.subheadline.weight(.semibold))
                Text("IMDb-compatible CSV (importable into IMDb, Trakt, Letterboxd, etc.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await performExport() }
            } label: {
                HStack {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Exporting...")
                    } else {
                        Label("Export All Lists", systemImage: "square.and.arrow.up")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.vpRed)
            .disabled(isExporting)
        }
    }

    private func exportResultView(_ summary: LibraryCSVExportSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Export Complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(summary.filesWritten) file(s) created")
                    .font(.subheadline.weight(.medium))
                Text("\(summary.totalItemsExported) total items exported")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !summary.folderNames.isEmpty {
                    Text("Lists: " + summary.folderNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            if let url = exportDirectoryURL {
                #if os(macOS)
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                #else
                ShareLink(
                    items: csvFileURLs(in: url),
                    subject: Text("VPStudio Library Export"),
                    message: Text("Exported library CSVs from VPStudio")
                ) {
                    Label("Share Files", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                #endif
            }

            Button {
                exportSummary = nil
                exportDirectoryURL = nil
                errorMessage = nil
            } label: {
                Text("Export Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func bulletItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func performExport() async {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let service = LibraryCSVExportService(database: appState.database)
            let (dirURL, summary) = try await service.exportAll()
            exportDirectoryURL = dirURL
            exportSummary = summary
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func csvFileURLs(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents.filter { $0.pathExtension.lowercased() == "csv" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
