import AppKit
import ExplorerCore

@MainActor
enum QuickJumpAction {
    case navigate(URL, newTab: Bool)
    case switchTab(UUID)
    case toggleDualPane
    case togglePreviewPane
    case toggleFolderSizes
    case batchRename
    case openTerminal
    case setTheme(AppTheme)
}

@MainActor
struct QuickJumpItem {
    let title: String
    let subtitle: String
    let symbol: String
    let execute: (_ openInNewTab: Bool) -> QuickJumpAction
}

@MainActor
final class QuickJumpPanelController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = QuickJumpPanelController()

    var allItems: [QuickJumpItem] = []
    var filtered: [QuickJumpItem] = []
    private var handler: ((QuickJumpAction) -> Void)?
    private weak var hostWindow: NSWindow?

    private lazy var panel: NSPanel = {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 380),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.hasShadow = true
        p.hidesOnDeactivate = true
        p.backgroundColor = .clear
        p.isOpaque = false

        let container = Surface()
        container.color = Palette.navigation
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = Palette.line.cgColor
        p.contentView = container

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 15)
        searchField.placeholderString = L10n.text("Jump to folder, tab, theme, or action…")
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let divider = Surface()
        divider.color = Palette.line
        divider.translatesAutoresizingMaskIntoConstraints = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        col.width = 550
        table.addTableColumn(col)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 36
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(commitSelection)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(searchField)
        container.addSubview(divider)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            divider.heightAnchor.constraint(equalToConstant: 1),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return p
    }()

    let searchField = NSTextField()
    let table = NSTableView()

    func show(in window: NSWindow, items: [QuickJumpItem], onSelect: @escaping (QuickJumpAction) -> Void) {
        self.allItems = items
        self.filtered = items
        self.handler = onSelect
        self.hostWindow = window

        (panel.contentView as? Surface)?.color = Palette.navigation
        (panel.contentView as? Surface)?.layer?.borderColor = Palette.line.cgColor
        searchField.stringValue = ""
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }

        let wf = window.frame
        let pw: CGFloat = 580, ph: CGFloat = 380
        let x = wf.midX - pw / 2
        let y = wf.maxY - ph - 88
        panel.setFrame(NSRect(x: x, y: y, width: pw, height: ph), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        handler = nil
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filtered = allItems
        } else {
            let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
            filtered = allItems.filter { item in
                let hay = item.title + " " + item.subtitle
                return terms.allSatisfy { hay.localizedStandardContains($0) }
            }
        }
        table.reloadData()
        if !filtered.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            guard !filtered.isEmpty else { return true }
            let next = min(filtered.count - 1, max(0, table.selectedRow + 1))
            table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            table.scrollRowToVisible(next)
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard !filtered.isEmpty else { return true }
            let prev = max(0, table.selectedRow - 1)
            table.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
            table.scrollRowToVisible(prev)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            commitSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }

    @objc func commitSelection() {
        let row = table.selectedRow >= 0 ? table.selectedRow : 0
        guard filtered.indices.contains(row) else { hide(); return }
        let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        let action = filtered[row].execute(newTab)
        let callback = handler
        hide()
        callback?(action)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let item = filtered[row]
        let id = NSUserInterfaceItemIdentifier("quickjump")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let v = NSTableCellView(); v.identifier = id
            let icon = NSImageView(); icon.translatesAutoresizingMaskIntoConstraints = false
            let title = NSTextField(labelWithString: ""); title.font = .systemFont(ofSize: 13, weight: .medium); title.lineBreakMode = .byTruncatingMiddle
            let sub = NSTextField(labelWithString: ""); sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor; sub.lineBreakMode = .byTruncatingMiddle
            sub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            [icon, title, sub].forEach { v.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10), icon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
                title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), title.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                sub.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 10),
                sub.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12), sub.centerYAnchor.constraint(equalTo: v.centerYAnchor)
            ])
            v.imageView = icon; v.textField = title; sub.tag = 99
            return v
        }()
        cell.imageView?.image = Palette.symbol(item.symbol, size: 14)
        cell.imageView?.contentTintColor = Palette.accent
        cell.textField?.stringValue = item.title
        (cell.viewWithTag(99) as? NSTextField)?.stringValue = item.subtitle
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SidebarRowView() }
}
