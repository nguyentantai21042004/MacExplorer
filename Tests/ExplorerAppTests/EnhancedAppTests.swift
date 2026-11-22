import AppKit
import ExplorerCore
import Testing
@testable import ExplorerApp

@Suite @MainActor
struct EnhancedAppTests {
    @Test func workspaceInspectorShowsCodePreviewGitBadgeAndToggles() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-AppUI-\(UUID())")
        let subdir = root.appendingPathComponent("Module")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let swiftFile = root.appendingPathComponent("hello.swift")
        let nestedFile = subdir.appendingPathComponent("data.bin")
        try "struct Hello {\n    let value = 42\n}\n".write(to: swiftFile, atomically: true, encoding: .utf8)
        try Data(repeating: 0xAB, count: 2048).write(to: nestedFile)

        // Create minimal .git structure so GitRepoReader reads a repo without invoking git CLI.
        let gitDir = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/feature/enhanced-ui\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        let savedPreview = AppPreferences.shared.showPreviewPane
        let savedSizes = AppPreferences.shared.calculateFolderSizes
        AppPreferences.shared.showPreviewPane = true
        AppPreferences.shared.calculateFolderSizes = true

        let workspace = WorkspaceViewController(session: WorkspaceSession(left: PaneSession(paths: [root.path])))
        _ = workspace.view
        let browser = workspace.left
        defer {
            browser.suspend()
            workspace.right?.suspend()
            AppPreferences.shared.showPreviewPane = savedPreview
            AppPreferences.shared.calculateFolderSizes = savedSizes
            try? FileManager.default.removeItem(at: root)
        }

        await browser.tab.loadTask?.value
        await browser.tab.sortTask?.value
        for _ in 0..<40 where browser.gitBadge.isHidden || !browser.gitBadge.stringValue.contains("feature/enhanced-ui") {
            await browser.tab.loadTask?.value
            await browser.gitStatusTask?.value
            if !browser.gitBadge.isHidden { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        // Git badge should detect the branch and remain visible.
        #expect(!browser.gitBadge.isHidden)
        #expect(browser.gitBadge.stringValue.contains("feature/enhanced-ui"))

        // Folder size calculation should populate size for Module.
        let moduleItem = try #require(browser.tab.visible.first { $0.name == "Module" })
        for _ in 0..<25 where browser.folderSizes[moduleItem.id] == nil {
            try await Task.sleep(for: .milliseconds(20))
            await browser.folderSizeTask?.value
        }
        let measured = try #require(browser.folderSizes[moduleItem.id])
        #expect(measured.itemCount == 1)
        #expect(measured.bytes >= 2048)

        // Select hello.swift and verify Inspector displays its text preview.
        let row = try #require(browser.tab.visible.firstIndex { $0.name == "hello.swift" })
        browser.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        workspace.updateInspector(from: browser)

        // Wait briefly for the async text file preview load inside PreviewInspectorController.
        for _ in 0..<40 where !workspace.inspector.textView.string.contains("let value = 42") {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(workspace.inspector.titleLabel.stringValue == "hello.swift")
        #expect(!workspace.inspector.textScroll.isHidden)
        #expect(workspace.inspector.textView.string.contains("let value = 42"))

        // Toggle dual pane and preview panel on/off cleanly.
        #expect(!workspace.dualPane)
        workspace.toggleDualPane()
        #expect(workspace.dualPane)
        #expect(workspace.right != nil)
        workspace.toggleDualPane()
        #expect(!workspace.dualPane)

        workspace.togglePreviewPane()
        #expect(!AppPreferences.shared.showPreviewPane)
        workspace.togglePreviewPane()
        #expect(AppPreferences.shared.showPreviewPane)
    }

    @Test func browserSearchSupportsExtFilterAndContentFilter() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-SearchUI-\(UUID())")
        let sub = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "let token = \"magic_needle_99\"".write(to: sub.appendingPathComponent("Engine.swift"), atomically: true, encoding: .utf8)
        try "hello world".write(to: sub.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)

        let browser = BrowserViewController(urls: [root], active: 0)
        browser.tab.searchScope = .folder
        _ = browser.view
        defer {
            browser.suspend()
            try? FileManager.default.removeItem(at: root)
        }

        await browser.tab.loadTask?.value
        await browser.tab.sortTask?.value

        // Search content: forces recursive subfolder search automatically.
        browser.search.stringValue = "ext:swift content:magic_needle_99"
        browser.searchQueryChanged()
        #expect(browser.tab.isRecursiveSearch)

        await browser.tab.searchTask?.value
        await browser.tab.sortTask?.value

        #expect(browser.tab.visible.map(\.name) == ["Engine.swift"])
    }

    @Test func batchRenameSheetPlansDetectsDuplicatesAppliesAndUndoes() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Explorer-BatchSheet-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let u1 = root.appendingPathComponent("item_one.txt")
        let u2 = root.appendingPathComponent("item_two.txt")
        try Data("a".utf8).write(to: u1)
        try Data("b".utf8).write(to: u2)
        defer { try? FileManager.default.removeItem(at: root) }

        var appliedPairs: [(URL, String)] = []
        let sheet = BatchRenameSheetController(urls: [u1, u2]) { pairs in
            appliedPairs = pairs
        }
        _ = sheet.window

        // Switch to Sequence mode -> check live preview updates and apply enabled.
        sheet.modeSegment.selectedSegment = 2
        sheet.modeChanged()
        sheet.primaryField.stringValue = "shot_"
        sheet.startNumberField.stringValue = "10"
        sheet.padWidthField.stringValue = "2"
        sheet.inputsChanged()

        #expect(sheet.entries.map(\.newName) == ["shot_10.txt", "shot_11.txt"])
        #expect(sheet.applyButton.isEnabled)
        #expect(sheet.previewTable.numberOfRows == 2)

        // Force a duplicate name in Find & Replace -> Apply should disable.
        sheet.modeSegment.selectedSegment = 0
        sheet.modeChanged()
        sheet.primaryField.stringValue = "one|two"
        sheet.regexCheck.state = .on
        sheet.secondaryField.stringValue = "same"
        sheet.inputsChanged()
        #expect(!sheet.applyButton.isEnabled)

        // Revert to valid Prefix / Suffix and apply through FileOperationEngine (with single-shot Undo).
        sheet.modeSegment.selectedSegment = 1
        sheet.modeChanged()
        sheet.primaryField.stringValue = "v2_"
        sheet.secondaryField.stringValue = "_ok"
        sheet.inputsChanged()
        #expect(sheet.applyButton.isEnabled)
        sheet.apply()

        #expect(appliedPairs.map(\.1) == ["v2_item_one_ok.txt", "v2_item_two_ok.txt"])

        let engine = FileOperationEngine()
        let report = await engine.perform(.batchRename(appliedPairs), resolve: { _ in ConflictResolution(.cancel) }, progress: { _ in })
        #expect(report.completed.count == 2)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("v2_item_one_ok.txt").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("v2_item_two_ok.txt").path))
        #expect(await engine.undoTitle == L10n.text("Batch Rename"))

        _ = await engine.undo(progress: { _ in })
        #expect(FileManager.default.fileExists(atPath: u1.path))
        #expect(FileManager.default.fileExists(atPath: u2.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("v2_item_one_ok.txt").path))
    }

    @Test func themePreferencesAndQuickJumpFilterWorkCleanly() throws {
        let suiteName = "Explorer.ThemeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.theme == .slateCyan)
        #expect(prefs.showPreviewPane)
        #expect(prefs.calculateFolderSizes)

        prefs.theme = .tokyoNight
        #expect(AppPreferences(defaults: defaults).theme == .tokyoNight)
        #expect(prefs.theme.forcesDarkAppearance)
        #expect(prefs.effectiveAppearance?.name == .darkAqua)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var pickedAction: QuickJumpAction?
        let items = [
            QuickJumpItem(title: "Workspaces", subtitle: "~/Workspaces", symbol: "folder", execute: { .navigate(URL(fileURLWithPath: "/tmp"), newTab: $0) }),
            QuickJumpItem(title: "Theme: Nord", subtitle: "Command", symbol: "paintpalette", execute: { _ in .setTheme(.nord) })
        ]
        QuickJumpPanelController.shared.show(in: window, items: items) { pickedAction = $0 }
        QuickJumpPanelController.shared.searchField.stringValue = "nord"
        QuickJumpPanelController.shared.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(QuickJumpPanelController.shared.filtered.count == 1)
        QuickJumpPanelController.shared.commitSelection()

        if case .setTheme(let chosen) = pickedAction {
            #expect(chosen == .nord)
        } else {
            Issue.record("Expected QuickJumpPanelController to emit .setTheme(.nord)")
        }
        QuickJumpPanelController.shared.hide()
        window.close()
    }

    @Test func pathBarShowsRealUsernameAndSidebarFavoritesUseSafeReorderPasteboard() throws {
        _ = NSApplication.shared
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pathBar = PathBar(frame: NSRect(x: 0, y: 0, width: 520, height: 30))
        pathBar.update(home)

        let buttons = pathBar.subviews
            .compactMap { $0 as? NSStackView }
            .flatMap(\.arrangedSubviews)
            .compactMap { $0 as? ActionButton }
        let titles = buttons.map(\.title).filter { !$0.isEmpty }
        #expect(titles.contains("Users"))
        #expect(titles.contains(home.lastPathComponent))
        #expect(!titles.contains(L10n.text("Home")))

        // Verify dragging a Favorite row writes ONLY the private favorite-id type, never .fileURL!
        let sidebar = FolderSidebar()
        _ = sidebar.view
        let favSection = try #require(sidebar.outline.item(atRow: 0) as? FolderNode)
        let firstFav = try #require(favSection.children?.first)
        let writer = try #require(sidebar.outlineView(sidebar.outline, pasteboardWriterForItem: firstFav))
        let pbItem = try #require(writer as? NSPasteboardItem)
        #expect(pbItem.types.contains(NSPasteboard.PasteboardType("io.bquick.explorer.favorite-id")))
        #expect(!pbItem.types.contains(.fileURL))
    }
}
