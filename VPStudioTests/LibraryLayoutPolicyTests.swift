import Testing
@testable import VPStudio

@Suite("Library Layout Policy")
struct LibraryLayoutPolicyTests {
    @Test
    func emptyLibraryShowsEmptyStateForWatchlist() {
        #expect(LibraryLayoutPolicy.showsEmptyState(for: .watchlist, entryCount: 0, historyCount: 0) == true)
    }

    @Test(arguments: [1, 3, 10])
    func populatedLibraryShowsGridForWatchlist(entryCount: Int) {
        #expect(LibraryLayoutPolicy.showsEmptyState(for: .watchlist, entryCount: entryCount, historyCount: 0) == false)
    }

    @Test
    func emptyHistoryShowsEmptyState() {
        #expect(LibraryLayoutPolicy.showsEmptyState(for: .history, entryCount: 99, historyCount: 0) == true)
    }

    @Test
    func populatedHistoryShowsGrid() {
        #expect(LibraryLayoutPolicy.showsEmptyState(for: .history, entryCount: 0, historyCount: 2) == false)
    }

    @Test
    func libraryHeaderAndEmptyStateRemainTopPinned() {
        #expect(LibraryLayoutPolicy.rootPinsContentToTop == true)
        #expect(LibraryLayoutPolicy.emptyStatePinsContentToTop == true)
    }

    @Test
    func emptyStateTopPaddingIsStable() {
        #expect(Double(LibraryLayoutPolicy.emptyStateTopPadding) == 20)
    }

    @Test
    func folderCreationPolicyTrimsValidInput() {
        #expect(LibraryFolderCreationPolicy.normalizedName("  Sci-Fi  ") == "Sci-Fi")
    }

    @Test
    func folderCreationPolicyRejectsBlankInput() {
        #expect(LibraryFolderCreationPolicy.normalizedName("   \n\t  ") == nil)
    }

    @Test
    func folderCreationKeyboardDismissDelayIsStable() {
        #expect(LibraryFolderCreationPolicy.keyboardDismissDelayMilliseconds == 80)
    }

    @Test
    func selectedManualFolderPolicyFindsManualFolder() {
        let root = LibraryFolder(
            id: "system-watchlist",
            name: "Watchlist",
            listType: .watchlist,
            folderKind: .systemRoot,
            isSystem: true
        )
        let manual = LibraryFolder(
            id: "folder-manual",
            name: "Sci-Fi",
            parentId: root.id,
            listType: .watchlist
        )

        let selected = LibraryFolderSelectionPolicy.selectedManualFolder(
            from: [root, manual],
            selectedFolderID: manual.id
        )
        #expect(selected?.id == manual.id)
    }

    @Test
    func selectedManualFolderPolicyIgnoresSystemFolderSelection() {
        let root = LibraryFolder(
            id: "system-watchlist",
            name: "Watchlist",
            listType: .watchlist,
            folderKind: .systemRoot,
            isSystem: true
        )

        let selected = LibraryFolderSelectionPolicy.selectedManualFolder(
            from: [root],
            selectedFolderID: root.id
        )
        #expect(selected == nil)
    }

    @Test
    func selectedManualFolderPolicyReturnsNilWhenMissing() {
        let manual = LibraryFolder(
            id: "folder-manual",
            name: "Drama",
            listType: .favorites
        )
        let selected = LibraryFolderSelectionPolicy.selectedManualFolder(
            from: [manual],
            selectedFolderID: "unknown"
        )
        #expect(selected == nil)
    }
}
