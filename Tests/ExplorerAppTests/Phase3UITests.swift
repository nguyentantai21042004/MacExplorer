import AppKit
import ExplorerCore
import Testing
@testable import ExplorerApp

@Suite @MainActor
struct Phase3UITests {
    @Test func shareMenuBuildsItemForLocalFilesAndRejectsEmptyOrRemoteURLs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Share-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.txt")
        try Data("hi".utf8).write(to: file)

        #expect(ShareMenu.item(for: []) == nil)
        #expect(ShareMenu.item(for: [URL(string: "https://example.com")!]) == nil)
        let menuItem = try #require(ShareMenu.item(for: [file]))
        #expect(menuItem.submenu != nil || menuItem.action != nil)
    }

    @Test func columnViewExpandsNestedFolderSyncsSelectionAndContextMenu() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-Columns-\(UUID())").resolvingSymlinksInPath()
        let nested = root.appendingPathComponent("Projects/SubApp", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let childFile = nested.appendingPathComponent("main.swift")
        try Data("print(1)\n".utf8).write(to: childFile)
        defer { try? FileManager.default.removeItem(at: root) }

        let browser = BrowserViewController(urls: [root], active: 0)
        browser.tab.viewMode = .columns
        _ = browser.view
        defer { browser.suspend() }

        await browser.tab.loadTask?.value
        await browser.tab.sortTask?.value

        #expect(!browser.columnView.isHidden)
        #expect(browser.tableScroll.isHidden)
        #expect(browser.collectionScroll.isHidden)
        #expect(browser.columnView.columns.count == 1)

        // Select "Projects" in column 0 -> spawns column 1 asynchronously.
        let col0 = browser.columnView.columns[0]
        let projRow = try #require(col0.items.firstIndex { $0.name == "Projects" })
        col0.tableView.selectRowIndexes(IndexSet(integer: projRow), byExtendingSelection: false)
        browser.columnView.handleSelectionChange(in: 0)
        #expect(browser.columnView.columns.count == 2)
        await browser.columnView.columns[1].loadTask?.value
        #expect(browser.columnView.columns[1].items.map(\.name) == ["SubApp"])

        // Move right into column 1 -> selects SubApp and opens column 2.
        browser.columnView.focusNextColumn(from: 0)
        #expect(browser.columnView.activeColumnIndex == 1)
        #expect(browser.columnView.columns.count == 3)
        await browser.columnView.columns[2].loadTask?.value
        #expect(browser.columnView.columns[2].items.map(\.name) == ["main.swift"])

        // Move right into column 2 -> selects main.swift and syncs browser.selectedItems + folderDestination.
        browser.columnView.focusNextColumn(from: 1)
        #expect(browser.columnView.activeColumnIndex == 2)
        #expect(browser.selectedItems.map(\.name) == ["main.swift"])
        #expect(browser.folderDestination?.resolvingSymlinksInPath().path == nested.path)

        // Context menu includes Share and Properties.
        let menu = NSMenu()
        browser.populateContextMenu(menu)
        let titles = menu.items.map(\.title)
        #expect(titles.contains(L10n.text("Properties")))
        #expect(titles.contains(L10n.text("Quick Look")))
        #expect(titles.contains { $0.localizedCaseInsensitiveContains("Share") })

        // Move left returns to column 1.
        browser.columnView.focusPreviousColumn(from: 2)
        #expect(browser.columnView.activeColumnIndex == 1)
    }
}
