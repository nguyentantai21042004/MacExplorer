import AppKit
import ExplorerCore
import Testing
@testable import ExplorerApp

@Suite @MainActor
struct Phase2UITests {
    @Test func getInfoWindowHandlesMultiSelectionAndSingleItem() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-P2UI-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let a = root.appendingPathComponent("a.txt")
        let b = root.appendingPathComponent("b.txt")
        try Data("hello".utf8).write(to: a)
        try Data("world!".utf8).write(to: b)

        let single = GetInfoWindowController(urls: [a], key: a.path)
        defer { single.close() }
        #expect(single.window?.title == "a.txt Info")
        #expect(single.snapshot?.size == 5)

        let multi = GetInfoWindowController(urls: [a, b], key: "multi-test")
        defer { multi.close() }
        #expect(multi.window?.title == "2 Items Info")
    }

    @Test func browserFormatsTrashTitleForUserTrashDirectory() {
        _ = NSApplication.shared
        let browser = BrowserViewController(urls: [BrowserLocation.thisMac], active: 0)
        _ = browser.view
        defer { browser.suspend() }
        let trash = TrashOperations.userTrashDirectory()
        #expect(browser.title(for: trash) == L10n.text("Trash"))
    }
}
