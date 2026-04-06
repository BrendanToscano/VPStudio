import Foundation
import Testing
@testable import VPStudio

@Suite(.serialized)
struct AppStateServiceLifecycleTests {
    private final class NotificationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func markPosted() {
            lock.lock()
            value = true
            lock.unlock()
        }

        func didPost() -> Bool {
            lock.lock()
            let posted = value
            lock.unlock()
            return posted
        }
    }

    private static let cases = ExhaustiveMode.choose(
        fast: Array(0..<8),
        full: Array(0..<24)
    )

    private static func contents(of relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    @Test(arguments: cases)
    @MainActor
    func serviceIdentityIsStable(_: Int) {
        let appState = AppState()

        let db1 = appState.database
        let db2 = appState.database
        #expect(ObjectIdentifier(db1) == ObjectIdentifier(db2))

        let debrid1 = appState.debridManager
        let debrid2 = appState.debridManager
        #expect(ObjectIdentifier(debrid1) == ObjectIdentifier(debrid2))

        let indexer1 = appState.indexerManager
        let indexer2 = appState.indexerManager
        #expect(ObjectIdentifier(indexer1) == ObjectIdentifier(indexer2))

        let downloads1 = appState.downloadManager
        let downloads2 = appState.downloadManager
        #expect(ObjectIdentifier(downloads1) == ObjectIdentifier(downloads2))

        let env1 = appState.environmentCatalogManager
        let env2 = appState.environmentCatalogManager
        #expect(ObjectIdentifier(env1) == ObjectIdentifier(env2))
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<8), full: Array(0..<16)))
    @MainActor
    func reloadIndexersPostsNotification(index: Int) async {
        let _ = index
        let appState = AppState(
            testHooks: .init(
                initializeIndexers: {
                    // no-op success path
                }
            )
        )

        let flag = NotificationFlag()
        let token = NotificationCenter.default.addObserver(
            forName: .indexersDidChange,
            object: nil,
            queue: nil
        ) { _ in
            flag.markPosted()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await appState.reloadIndexers()
        #expect(flag.didPost())
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<8), full: Array(0..<16)))
    @MainActor
    func traktSyncRefreshHelperPostsLibraryAndTasteNotifications(index: Int) async {
        let _ = index
        let appState = AppState(testHooks: .init())

        let libraryFlag = NotificationFlag()
        let tasteFlag = NotificationFlag()
        let libraryToken = NotificationCenter.default.addObserver(
            forName: .libraryDidChange,
            object: nil,
            queue: nil
        ) { _ in
            libraryFlag.markPosted()
        }
        let tasteToken = NotificationCenter.default.addObserver(
            forName: .tasteProfileDidChange,
            object: nil,
            queue: nil
        ) { _ in
            tasteFlag.markPosted()
        }
        defer {
            NotificationCenter.default.removeObserver(libraryToken)
            NotificationCenter.default.removeObserver(tasteToken)
        }

        appState.applyTraktSyncLocalRefresh(
            for: .init(localRefreshTargets: [.library, .tasteProfile])
        )

        #expect(libraryFlag.didPost())
        #expect(tasteFlag.didPost())
    }

    @Test(arguments: ExhaustiveMode.choose(fast: Array(0..<8), full: Array(0..<16)))
    @MainActor
    func traktSyncRefreshHelperTreatsRetentionSweepAsLibraryInvalidation(index: Int) async {
        let _ = index
        let appState = AppState(testHooks: .init())

        let libraryFlag = NotificationFlag()
        let tasteFlag = NotificationFlag()
        let libraryToken = NotificationCenter.default.addObserver(
            forName: .libraryDidChange,
            object: nil,
            queue: nil
        ) { _ in
            libraryFlag.markPosted()
        }
        let tasteToken = NotificationCenter.default.addObserver(
            forName: .tasteProfileDidChange,
            object: nil,
            queue: nil
        ) { _ in
            tasteFlag.markPosted()
        }
        defer {
            NotificationCenter.default.removeObserver(libraryToken)
            NotificationCenter.default.removeObserver(tasteToken)
        }

        appState.applyTraktSyncLocalRefresh(
            for: .init(),
            removedHistoryEntryCount: 1
        )

        #expect(libraryFlag.didPost())
        #expect(tasteFlag.didPost() == false)
    }

    @Test
    func traktSyncEntryPointsShareTheSameRefreshHelper() throws {
        let appStateSource = try Self.contents(of: "VPStudio/App/AppState.swift")
        let settingsSource = try Self.contents(of: "VPStudio/Views/Windows/Settings/Destinations/TraktSettingsView.swift")

        #expect(appStateSource.contains("_ = await self.performTraktSyncAndRefreshLocalState()"))
        #expect(settingsSource.contains("await appState.performTraktSyncAndRefreshLocalState()"))
    }
}
