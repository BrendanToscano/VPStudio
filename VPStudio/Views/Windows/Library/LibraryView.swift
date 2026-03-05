import SwiftUI

enum LibraryLayoutPolicy {
    static let rootPinsContentToTop = true
    static let emptyStatePinsContentToTop = true
    static let emptyStateTopPadding: CGFloat = 20

    static func showsEmptyState(for selectedList: UserLibraryEntry.ListType, entryCount: Int, historyCount: Int) -> Bool {
        switch selectedList {
        case .history:
            return historyCount == 0
        default:
            return entryCount == 0
        }
    }
}

enum LibraryFolderCreationPolicy {
    static let keyboardDismissDelayMilliseconds: UInt64 = 80

    static func normalizedName(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum LibraryFolderSelectionPolicy {
    static func selectedManualFolder(
        from folders: [LibraryFolder],
        selectedFolderID: String?
    ) -> LibraryFolder? {
        guard let selectedFolderID else { return nil }
        return folders.first(where: { $0.id == selectedFolderID && $0.isSystem == false })
    }
}

struct LibraryView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedList: UserLibraryEntry.ListType = .watchlist
    @State private var selectedFolderID: String?

    @State private var entries: [UserLibraryEntry] = []
    @State private var historyEntries: [WatchHistory] = []
    @State private var folders: [LibraryFolder] = []
    @State private var mediaItems: [String: MediaItem] = [:]

    @State private var selectedItem: MediaPreview?
    @State private var loadTask: Task<Void, Never>?

    @State private var sortOption: LibrarySortOption = .dateAddedDesc
    @State private var userRatings: [String: TasteEvent] = [:]

    @State private var isShowingCreateFolderSheet = false
    @State private var isShowingCSVImportSheet = false
    @State private var isShowingCSVExportSheet = false
    @State private var createFolderListType: UserLibraryEntry.ListType = .watchlist
    @State private var folderPendingDeletion: LibraryFolder?
    @State private var statusMessage: String?
    @State private var isRefreshingTitleDuplicates = false
    @State private var draggedFolderID: String?
    @State private var manualFolderOrderIDs: [String] = []

    private var displayedHistoryMediaIDs: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for entry in historyEntries {
            if seen.insert(entry.mediaId).inserted {
                ordered.append(entry.mediaId)
            }
        }
        return ordered
    }

    private var isEmptyStateVisible: Bool {
        LibraryLayoutPolicy.showsEmptyState(
            for: selectedList,
            entryCount: entries.count,
            historyCount: displayedHistoryMediaIDs.count
        )
    }

    private var titleCount: Int {
        selectedList == .history ? displayedHistoryMediaIDs.count : entries.count
    }

    private var allFolderOptions: [LibraryFolder] {
        folders.filter { $0.listType == selectedList }
    }

    private var userFolders: [LibraryFolder] {
        allFolderOptions.filter { !$0.isSystem }
    }

    private var orderedUserFolders: [LibraryFolder] {
        guard !manualFolderOrderIDs.isEmpty else { return userFolders }
        let byID = Dictionary(uniqueKeysWithValues: userFolders.map { ($0.id, $0) })
        var ordered = manualFolderOrderIDs.compactMap { byID[$0] }
        if ordered.count < userFolders.count {
            let included = Set(ordered.map(\.id))
            ordered.append(contentsOf: userFolders.filter { !included.contains($0.id) })
        }
        return ordered
    }

    private var rootFolder: LibraryFolder? {
        allFolderOptions.first { $0.isSystem && $0.folderKind == .systemRoot }
    }

    private var selectedManualFolder: LibraryFolder? {
        LibraryFolderSelectionPolicy.selectedManualFolder(
            from: allFolderOptions,
            selectedFolderID: selectedFolderID
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)

            if isEmptyStateVisible {
                LibraryEmptyStateView(
                    listType: emptyStateCTAListType
                ) { action in
                    handleCTAAction(action)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: LibraryLayoutPolicy.emptyStatePinsContentToTop ? .top : .center
                )
                .padding(.top, LibraryLayoutPolicy.emptyStateTopPadding)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(
                            .adaptive(minimum: LibraryGridPolicy.cardMinWidth),
                            spacing: LibraryGridPolicy.gridSpacing
                        )],
                        spacing: LibraryGridPolicy.gridSpacing
                    ) {
                        if selectedList == .history {
                            ForEach(displayedHistoryMediaIDs, id: \.self) { mediaId in
                                if let preview = historyPreview(for: mediaId) {
                                    Button { selectedItem = preview } label: {
                                        MediaCardView(item: preview, userRating: userRatings[preview.id])
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            ForEach(entries, id: \.id) { entry in
                                if let preview = preview(for: entry.mediaId) {
                                    Button { selectedItem = preview } label: {
                                        MediaCardView(item: preview, userRating: userRatings[entry.mediaId])
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        if selectedList.supportsFolders {
                                            ForEach(allFolderOptions, id: \.id) { folder in
                                                if folder.id != entry.folderId {
                                                    Button("Move to \(folder.name)") {
                                                        move(entry: entry, to: folder)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LibraryGridPolicy.horizontalPadding)
                    .padding(.vertical)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: LibraryLayoutPolicy.rootPinsContentToTop ? .top : .center
        )
        .navigationTitle("Library")
        .navigationDestination(item: $selectedItem) { item in
            DetailView(preview: item)
        }
        .sheet(isPresented: $isShowingCreateFolderSheet) {
            CreateLibraryFolderSheet(listType: createFolderListType) { name, listType in
                await createFolder(named: name, in: listType)
            }
        }
        .sheet(isPresented: $isShowingCSVImportSheet) {
            LibraryCSVImportSheet { summary in
                if let preferred = preferredListType(after: summary) {
                    selectedList = preferred
                }
                selectedFolderID = nil
                statusMessage = importStatusMessage(from: summary)
                print("[VPStudio Import] visible-list=\(selectedList.rawValue) status=\"\(statusMessage ?? "")\"")
                scheduleReload()
            }
        }
        .sheet(isPresented: $isShowingCSVExportSheet) {
            LibraryCSVExportSheet()
        }
        .confirmationDialog(
            "Delete Folder",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { folderPendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let folder = folderPendingDeletion {
                Button("Delete \"\(folder.name)\"", role: .destructive) {
                    let target = folder
                    folderPendingDeletion = nil
                    delete(folder: target)
                }
            }
            Button("Cancel", role: .cancel) {
                folderPendingDeletion = nil
            }
        } message: {
            if let folder = folderPendingDeletion {
                Text("Items in this folder will be moved to \(folder.listType.displayName).")
            }
        }
        .task {
            scheduleReload()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: selectedList) { _, _ in
            selectedFolderID = nil
            scheduleReload()
        }
        .onChange(of: selectedFolderID) { _, _ in
            guard selectedList.supportsFolders else { return }
            scheduleReload()
        }
        .onChange(of: sortOption) { _, _ in
            scheduleReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { [weak self] _ in
            self?.scheduleReload()
        }
        .task {
            await loadUserRatings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tasteProfileDidChange)) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.loadUserRatings() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedList.displayName)
                        .font(.headline)
                    GlassTag(text: "\(titleCount) titles", symbol: "film")
                }
                Spacer(minLength: 20)

                sortMenu

                Button {
                    isShowingCSVExportSheet = true
                } label: {
                    actionCapsuleLabel(
                        title: "Export",
                        systemImage: "square.and.arrow.up",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isShowingCSVImportSheet = true
                } label: {
                    actionCapsuleLabel(
                        title: "Import",
                        systemImage: "square.and.arrow.down",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)

                Button {
                    refreshTitleDuplicates()
                } label: {
                    actionCapsuleLabel(
                        title: isRefreshingTitleDuplicates ? "Refreshing..." : "Refresh",
                        systemImage: isRefreshingTitleDuplicates ? "hourglass" : "arrow.clockwise",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedList == .history || isRefreshingTitleDuplicates)
                .opacity((selectedList == .history || isRefreshingTitleDuplicates) ? 0.5 : 1)
            }

            GlassPillPicker(
                options: UserLibraryEntry.ListType.libraryTopTabs,
                selection: $selectedList
            )

            if selectedList.supportsFolders {
                folderControls
            }

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, LibraryGridPolicy.horizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var folderControls: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    folderChip(title: "All", isSelected: selectedFolderID == nil) {
                        selectedFolderID = nil
                    }

                    if let rootFolder {
                        folderChip(title: rootFolder.name, isSelected: selectedFolderID == rootFolder.id) {
                            selectedFolderID = rootFolder.id
                        }
                    }

                    ForEach(orderedUserFolders, id: \.id) { folder in
                        folderChip(for: folder)
                            .onDrag {
                                draggedFolderID = folder.id
                                if manualFolderOrderIDs.isEmpty {
                                    manualFolderOrderIDs = userFolders.map(\.id)
                                }
                                return NSItemProvider(object: folder.id as NSString)
                            }
                            .onDrop(
                                of: ["public.text"],
                                delegate: FolderChipDropDelegate(
                                    destinationFolderID: folder.id,
                                    orderedFolderIDs: $manualFolderOrderIDs,
                                    draggedFolderID: $draggedFolderID
                                ) { reorderedIDs in
                                    commitFolderReorder(reorderedIDs)
                                }
                            )
                    }
                }
            }

            GlassIconButton(icon: "plus", size: 28) {
                createFolderListType = selectedList
                isShowingCreateFolderSheet = true
            }
            .accessibilityLabel("Create Folder")
            .padding(.vertical, 2)

            if let selectedManualFolder {
                GlassIconButton(icon: "trash", tint: .red, size: 28) {
                    folderPendingDeletion = selectedManualFolder
                }
                .accessibilityLabel("Delete Selected Folder")
                .padding(.vertical, 2)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortOption) {
                ForEach(LibrarySortOption.allCases, id: \.self) { option in
                    Label(option.displayName, systemImage: option.symbolName)
                        .tag(option)
                }
            }
        } label: {
            actionCapsuleLabel(
                title: "Sort",
                systemImage: "arrow.up.arrow.down",
                tint: .teal
            )
        }
        .buttonStyle(.plain)
    }

    private func actionCapsuleLabel(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Capsule())
            .background(.regularMaterial, in: Capsule())
            .overlay {
                ZStack {
                    Capsule()
                        .fill(tint.opacity(0.14))
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 14, y: 2)
    }

    private func folderChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    isSelected ? AnyShapeStyle(Color.vpRed) : AnyShapeStyle(.ultraThinMaterial),
                    in: Capsule()
                )
                .overlay {
                    if !isSelected {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func folderChip(for folder: LibraryFolder) -> some View {
        return folderChip(title: folder.name, isSelected: selectedFolderID == folder.id) {
            selectedFolderID = folder.id
        }
        .contextMenu {
            Button(role: .destructive) {
                folderPendingDeletion = folder
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    private var emptyStateCTAListType: LibraryEmptyStateCTAPolicy.ListType {
        switch selectedList {
        case .watchlist: return .watchlist
        case .favorites: return .favorites
        case .history: return .history
        }
    }

    private func handleCTAAction(_ action: LibraryEmptyStateCTAPolicy.CTAAction) {
        switch action {
        case .switchToDiscover:
            appState.selectedTab = .discover
        case .openSettings:
            appState.selectedTab = .settings
        case .none:
            break
        }
    }

    private func preferredListType(after summary: LibraryCSVImportSummary) -> UserLibraryEntry.ListType? {
        if summary.watchlistImported > 0 { return .watchlist }
        if summary.favoritesImported > 0 { return .favorites }
        if summary.historyImported > 0 { return .history }
        return nil
    }

    private func importStatusMessage(from summary: LibraryCSVImportSummary) -> String {
        if summary.watchlistImported == 0, summary.favoritesImported == 0, summary.historyImported == 0 {
            if summary.ratingsImported > 0 {
                return "Import finished: no new library items, but \(summary.ratingsImported) ratings were imported."
            }
            return "Import finished: no new library items were added."
        }
        return "Import added W:\(summary.watchlistImported) F:\(summary.favoritesImported) H:\(summary.historyImported) from \(summary.rowsImported) rows. Repeated IMDb IDs across files were merged."
    }

    private func scheduleReload() {
        loadTask?.cancel()
        loadTask = Task { await loadSelection() }
    }

    private func loadSelection() async {
        RuntimeMemoryDiagnostics.capture(
            event: .libraryLoadStarted,
            enabled: appState.runtimeDiagnosticsEnabled,
            context: selectedList.displayName
        )
        defer {
            RuntimeMemoryDiagnostics.capture(
                event: .libraryLoadFinished,
                enabled: appState.runtimeDiagnosticsEnabled,
                context: "\(selectedList.displayName):entries=\(entries.count),history=\(displayedHistoryMediaIDs.count)"
            )
        }

        if selectedList == .history {
            await loadHistoryEntries()
            return
        }

        await loadFolders()
        await loadLibraryEntries()
    }

    private func loadFolders() async {
        guard selectedList.supportsFolders else {
            folders = []
            manualFolderOrderIDs = []
            return
        }

        let loadedFolders = (try? await appState.database.fetchAllLibraryFolders(listType: selectedList)) ?? []
        folders = loadedFolders
        if draggedFolderID == nil {
            manualFolderOrderIDs = loadedFolders.filter { !$0.isSystem }.map(\.id)
        }

        if let selectedFolderID,
           !loadedFolders.contains(where: { $0.id == selectedFolderID }) {
            self.selectedFolderID = nil
        }
    }

    private func loadLibraryEntries() async {
        entries = (try? await appState.database.fetchLibraryEntries(
            listType: selectedList,
            folderId: selectedFolderID,
            sortOption: sortOption
        )) ?? []
        historyEntries = []
        await loadMediaItemsIfMissing(ids: entries.map(\.mediaId))
    }

    private func loadHistoryEntries() async {
        selectedFolderID = nil
        folders = []
        entries = []
        historyEntries = (try? await appState.database.fetchWatchHistory(limit: 200)) ?? []
        await loadMediaItemsIfMissing(ids: displayedHistoryMediaIDs)
    }

    private func loadMediaItemsIfMissing(ids: [String]) async {
        let uniqueIDs = ids.reduce(into: [String]()) { partial, id in
            if !partial.contains(id) {
                partial.append(id)
            }
        }

        let database = appState.database
        let missingIDs = uniqueIDs.filter { mediaItems[$0] == nil }
        guard !missingIDs.isEmpty else { return }

        await withTaskGroup(of: (String, MediaItem?).self) { group in
            for id in missingIDs {
                group.addTask {
                    (id, try? await database.fetchMediaItem(id: id))
                }
            }

            for await (id, item) in group {
                if let item {
                    mediaItems[id] = item
                }
            }
        }
    }

    @MainActor
    private func loadUserRatings() async {
        let events = (try? await appState.database.fetchTasteEvents(eventType: .rated, limit: 500)) ?? []
        var dict: [String: TasteEvent] = [:]
        for event in events {
            if let mediaId = event.mediaId {
                dict[mediaId] = event
            }
        }
        userRatings = dict
    }

    private func preview(for mediaID: String) -> MediaPreview? {
        if let item = mediaItems[mediaID] {
            return MediaPreview(
                id: item.id,
                type: item.type,
                title: item.title,
                year: item.year,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                imdbRating: item.imdbRating,
                tmdbId: item.tmdbId
            )
        }
        // Fallback for entries without a cached MediaItem (e.g. Trakt sync stubs)
        return MediaPreview(
            id: mediaID,
            type: .movie,
            title: mediaID.hasPrefix("tt") ? "IMDb: \(mediaID)" : mediaID,
            year: nil,
            posterPath: nil,
            imdbRating: nil,
            tmdbId: nil
        )
    }

    private func historyPreview(for mediaID: String) -> MediaPreview? {
        if let preview = preview(for: mediaID) {
            return preview
        }

        guard let historyEntry = historyEntries.first(where: { $0.mediaId == mediaID }) else {
            return nil
        }

        return MediaPreview(
            id: historyEntry.mediaId,
            type: .movie,
            title: historyEntry.title,
            year: nil,
            posterPath: nil,
            imdbRating: nil,
            tmdbId: nil
        )
    }

    private func createFolder(named name: String, in targetList: UserLibraryEntry.ListType) async -> String? {
        guard let normalizedName = LibraryFolderCreationPolicy.normalizedName(name) else {
            return "Folder name cannot be empty."
        }

        loadTask?.cancel()
        do {
            let existingFolders = try await appState.database.fetchAllLibraryFolders(listType: targetList)
            let alreadyExists = existingFolders.contains(where: {
                !$0.isSystem && $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
            })
            let folder = try await appState.database.createLibraryFolder(name: normalizedName, listType: targetList)
            selectedFolderID = folder.id
            statusMessage = alreadyExists ? "Using existing folder \(folder.name)." : "Created \(folder.name)."
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            await loadSelection()
            return alreadyExists ? "A folder named \"\(folder.name)\" already exists." : nil
        } catch {
            let message = error.localizedDescription
            statusMessage = message
            return message
        }
    }

    private func move(entry: UserLibraryEntry, to folder: LibraryFolder) {
        guard entry.listType == selectedList else { return }

        loadTask?.cancel()
        loadTask = Task {
            do {
                try await appState.database.moveLibraryEntry(
                    mediaId: entry.mediaId,
                    listType: entry.listType,
                    toFolderId: folder.id
                )
                statusMessage = "Moved to \(folder.name)."
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
                await loadSelection()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func refreshTitleDuplicates() {
        guard selectedList != .history else { return }
        guard !isRefreshingTitleDuplicates else { return }

        let listType = selectedList
        loadTask?.cancel()
        isRefreshingTitleDuplicates = true
        statusMessage = "Refreshing title matches in \(listType.displayName)..."

        loadTask = Task {
            defer { isRefreshingTitleDuplicates = false }

            do {
                let removedCount = try await appState.database
                    .dedupeLibraryEntriesByTitleEquivalence(listType: listType)
                try await appState.database.pruneEmptyManualFolders()

                if removedCount == 0 {
                    statusMessage = "Refresh complete: no duplicate titles found in \(listType.displayName)."
                } else if removedCount == 1 {
                    statusMessage = "Refresh complete: merged 1 duplicate title in \(listType.displayName)."
                } else {
                    statusMessage = "Refresh complete: merged \(removedCount) duplicate titles in \(listType.displayName)."
                }
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
                await loadSelection()
            } catch {
                statusMessage = "Refresh failed: \(error.localizedDescription)"
            }
        }
    }

    private func commitFolderReorder(_ reorderedIDs: [String]) {
        let currentIDs = userFolders.map(\.id)
        guard reorderedIDs != currentIDs else { return }
        persistFolderOrder(reorderedIDs)
    }

    private func persistFolderOrder(_ reorderedIDs: [String]) {
        loadTask?.cancel()
        loadTask = Task {
            do {
                try await appState.database.reorderLibraryFolders(
                    ids: reorderedIDs,
                    listType: selectedList
                )
                statusMessage = "Folder order updated."
                await loadFolders()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func delete(folder: LibraryFolder) {
        guard folder.isSystem == false else { return }

        loadTask?.cancel()
        loadTask = Task {
            do {
                try await appState.database.deleteLibraryFolder(id: folder.id, listType: folder.listType)
                if selectedFolderID == folder.id {
                    selectedFolderID = nil
                }
                statusMessage = "Deleted \(folder.name)."
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
                await loadSelection()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

private struct FolderChipDropDelegate: DropDelegate {
    let destinationFolderID: String
    @Binding var orderedFolderIDs: [String]
    @Binding var draggedFolderID: String?
    let onCommit: ([String]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedFolderID,
              draggedFolderID != destinationFolderID,
              let fromIndex = orderedFolderIDs.firstIndex(of: draggedFolderID),
              let toIndex = orderedFolderIDs.firstIndex(of: destinationFolderID),
              fromIndex != toIndex else {
            return
        }

        withAnimation(.easeInOut(duration: 0.14)) {
            orderedFolderIDs.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedFolderID = nil
        onCommit(orderedFolderIDs)
        return true
    }
}

private struct CreateLibraryFolderSheet: View {
    let listType: UserLibraryEntry.ListType
    let onCreate: (String, UserLibraryEntry.ListType) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var folderName = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var isNameFieldFocused: Bool

    private var canSubmit: Bool {
        LibraryFolderCreationPolicy.normalizedName(folderName) != nil && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create a folder in \(listType.displayName).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Folder name", text: $folderName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        submit()
                    }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Create Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissSafely()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Creating..." : "Create") {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    isNameFieldFocused = true
                }
            }
        }
        .frame(minWidth: 360, minHeight: 190)
    }

    private func dismissSafely() {
        isNameFieldFocused = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: LibraryFolderCreationPolicy.keyboardDismissDelayMilliseconds * 1_000_000)
            dismiss()
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        guard let normalizedName = LibraryFolderCreationPolicy.normalizedName(folderName) else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            let creationError = await onCreate(normalizedName, listType)
            await MainActor.run {
                isSubmitting = false
                if let creationError {
                    errorMessage = creationError
                    isNameFieldFocused = true
                } else {
                    dismissSafely()
                }
            }
        }
    }
}
