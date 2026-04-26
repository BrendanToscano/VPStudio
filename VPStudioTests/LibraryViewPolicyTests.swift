import Foundation
import Testing
@testable import VPStudio

@Suite("Library Action Row Policy")
struct LibraryActionRowPolicyTests {
    @Test
    func actionOrderIsStable() {
        let actions = LibraryActionRowPolicy.actions(selectedList: .watchlist, isRefreshing: false)
        #expect(actions.map(\.kind) == [.sort, .export, .import, .refresh])
    }

    @Test
    func refreshIsAvailableForWatchlistWhenIdle() {
        let refresh = LibraryActionRowPolicy.actions(selectedList: .watchlist, isRefreshing: false).last

        #expect(refresh?.kind == .refresh)
        #expect(refresh?.title == "Refresh")
        #expect(refresh?.systemImage == "arrow.clockwise")
        #expect(refresh?.isEnabled == true)
    }

    @Test
    func refreshIsDisabledForHistory() {
        let refresh = LibraryActionRowPolicy.actions(selectedList: .history, isRefreshing: false).last

        #expect(refresh?.kind == .refresh)
        #expect(refresh?.title == "Refresh")
        #expect(refresh?.isEnabled == false)
    }

    @Test
    func refreshShowsProgressStateWhileRefreshing() {
        let refresh = LibraryActionRowPolicy.actions(selectedList: .favorites, isRefreshing: true).last

        #expect(refresh?.kind == .refresh)
        #expect(refresh?.title == "Refreshing...")
        #expect(refresh?.systemImage == "hourglass")
        #expect(refresh?.isEnabled == false)
    }
}

@Suite("Library Feedback Presentation Policy")
struct LibraryFeedbackPresentationPolicyTests {
    @Test
    func actionErrorTakesPrecedenceOverStatusCopy() {
        let appError = AppError.unknown("Couldn't move this title right now.")

        #expect(
            LibraryFeedbackPresentationPolicy.message(
                statusMessage: "Moved to Sci-Fi.",
                actionError: appError
            ) == .error(appError)
        )
    }

    @Test
    func statusCopyShowsWhenNoActionErrorExists() {
        #expect(
            LibraryFeedbackPresentationPolicy.message(
                statusMessage: "Folder order updated.",
                actionError: nil
            ) == .status("Folder order updated.")
        )

        #expect(
            LibraryFeedbackPresentationPolicy.message(
                statusMessage: nil,
                actionError: nil
            ) == nil
        )
    }

    @Test
    func libraryActionFailurePolicyProvidesReadableFallbackCopy() {
        let sampleError = NSError(domain: "VPStudioTests", code: 1)

        #expect(
            LibraryActionFailurePolicy.appError(
                for: sampleError,
                action: .createFolder
            ).errorDescription == "Couldn't create the folder."
        )

        #expect(
            LibraryActionFailurePolicy.appError(
                for: sampleError,
                action: .refreshTitles(listName: "Watchlist")
            ).errorDescription == "Couldn't refresh duplicate titles in Watchlist."
        )

        #expect(
            LibraryActionFailurePolicy.appError(
                for: sampleError,
                action: .removeTitle(listName: "Favorites")
            ).errorDescription == "Couldn't remove this title from Favorites."
        )
    }
}

@Suite("Library Folder Label Policy")
struct LibraryFolderLabelPolicyTests {
    @Test
    func systemRootUsesTopLevelTitle() {
        let root = makeFolder(
            id: LibraryFolder.systemFolderID(for: .watchlist),
            name: "Watchlist",
            parentId: nil,
            listType: .watchlist,
            folderKind: .systemRoot,
            isSystem: true
        )

        #expect(LibraryFolderLabelPolicy.chipTitle(for: root, in: [root]) == "Top Level")
        #expect(LibraryFolderLabelPolicy.fullPath(for: root, in: [root]) == "Top Level")
    }

    @Test
    func manualFolderUnderSystemRootKeepsSimpleName() {
        let root = makeFolder(
            id: LibraryFolder.systemFolderID(for: .favorites),
            name: "Favorites",
            parentId: nil,
            listType: .favorites,
            folderKind: .systemRoot,
            isSystem: true
        )
        let child = makeFolder(
            id: "manual-sci-fi",
            name: "Sci-Fi",
            parentId: root.id,
            listType: .favorites
        )

        #expect(LibraryFolderLabelPolicy.chipTitle(for: child, in: [root, child]) == "Sci-Fi")
    }

    @Test
    func manualChildFolderIncludesParentBreadcrumb() {
        let root = makeFolder(
            id: LibraryFolder.systemFolderID(for: .watchlist),
            name: "Watchlist",
            parentId: nil,
            listType: .watchlist,
            folderKind: .systemRoot,
            isSystem: true
        )
        let parent = makeFolder(
            id: "anime",
            name: "Anime",
            parentId: root.id,
            listType: .watchlist
        )
        let child = makeFolder(
            id: "spring-2026",
            name: "Spring 2026",
            parentId: parent.id,
            listType: .watchlist
        )

        #expect(LibraryFolderLabelPolicy.chipTitle(for: child, in: [root, parent, child]) == "Anime › Spring 2026")
    }

    @Test
    func multiLevelHierarchyProducesFullReadablePath() {
        let root = makeFolder(
            id: LibraryFolder.systemFolderID(for: .favorites),
            name: "Favorites",
            parentId: nil,
            listType: .favorites,
            folderKind: .systemRoot,
            isSystem: true
        )
        let parent = makeFolder(id: "marvel", name: "Marvel", parentId: root.id, listType: .favorites)
        let child = makeFolder(id: "phase-1", name: "Phase 1", parentId: parent.id, listType: .favorites)
        let grandchild = makeFolder(id: "origins", name: "Origins", parentId: child.id, listType: .favorites)

        #expect(
            LibraryFolderLabelPolicy.fullPath(for: grandchild, in: [root, parent, child, grandchild])
                == "Marvel › Phase 1 › Origins"
        )
    }

    @Test
    func duplicateChildNamesAreDisambiguatedByParentPath() {
        let root = makeFolder(
            id: LibraryFolder.systemFolderID(for: .watchlist),
            name: "Watchlist",
            parentId: nil,
            listType: .watchlist,
            folderKind: .systemRoot,
            isSystem: true
        )
        let movies = makeFolder(id: "movies", name: "Movies", parentId: root.id, listType: .watchlist)
        let tv = makeFolder(id: "tv", name: "TV", parentId: root.id, listType: .watchlist)
        let moviesFavorites = makeFolder(id: "movies-favorites", name: "Favorites", parentId: movies.id, listType: .watchlist)
        let tvFavorites = makeFolder(id: "tv-favorites", name: "Favorites", parentId: tv.id, listType: .watchlist)
        let folders = [root, movies, tv, moviesFavorites, tvFavorites]

        #expect(LibraryFolderLabelPolicy.chipTitle(for: moviesFavorites, in: folders) == "Movies › Favorites")
        #expect(LibraryFolderLabelPolicy.chipTitle(for: tvFavorites, in: folders) == "TV › Favorites")
    }

    @Test
    func missingParentFallsBackToFolderName() {
        let orphan = makeFolder(
            id: "orphan",
            name: "Loose Ends",
            parentId: "missing-parent",
            listType: .favorites
        )

        #expect(LibraryFolderLabelPolicy.chipTitle(for: orphan, in: [orphan]) == "Loose Ends")
    }

    private func makeFolder(
        id: String,
        name: String,
        parentId: String? = nil,
        listType: UserLibraryEntry.ListType,
        folderKind: LibraryFolder.FolderKind = .manual,
        isSystem: Bool = false
    ) -> LibraryFolder {
        LibraryFolder(
            id: id,
            name: name,
            parentId: parentId,
            listType: listType,
            folderKind: folderKind,
            isSystem: isSystem,
            sortOrder: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
