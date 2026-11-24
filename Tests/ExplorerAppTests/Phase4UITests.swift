import AppKit
import ExplorerCore
import Testing
@testable import ExplorerApp

@Suite @MainActor
struct Phase4UITests {
    @Test func browserRoutesSpotQueryToSpotlightModeAndCancelsCleanly() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Explorer-SpotUI-\(UUID())")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let browser = BrowserViewController(urls: [root], active: 0)
        _ = browser.view
        defer { browser.suspend() }
        await browser.tab.loadTask?.value
        await browser.tab.sortTask?.value

        // Even when scope is `.folder`, `spot:` triggers recursive/Spotlight search mode.
        browser.tab.searchScope = .folder
        browser.tab.query = "spot:unlikely_\(UUID().uuidString)"
        #expect(browser.tab.isRecursiveSearch)

        browser.startSearch(debounce: false)
        await browser.tab.searchTask?.value
        #expect(!browser.tab.loading)
        #expect(browser.tab.error == nil)

        browser.closeSearch(focusFiles: false)
        #expect(browser.tab.query.isEmpty)
        #expect(!browser.tab.isRecursiveSearch)
    }

    @Test func directoryWatcherClosesDescriptorAndFlagsRetryWhenFolderIsDeleted() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Explorer-WatcherDelete-\(UUID())")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var fired = false
        let watcher = DirectoryWatcher(url: dir) {
            fired = true
        }
        await watcher.waitUntilReady()
        #expect(!watcher.needsRetry)

        try FileManager.default.removeItem(at: dir)
        for _ in 0..<40 where !watcher.needsRetry {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(fired)
        #expect(watcher.needsRetry)
    }
}
