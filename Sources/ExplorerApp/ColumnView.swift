import AppKit
import ExplorerCore

/// Finder-style Miller Columns view built with themed `NSTableView` columns so it
/// seamlessly matches Explorer's 5 themes, custom folder rules, Quick Look, and Inspector.
@MainActor
final class MillerColumnsView: NSView {
    private static let columnWidth: CGFloat = 235

    let scrollView = NSScrollView()
    private let stack = NSStackView()
    private(set) var columns: [ColumnPane] = []
    private(set) var activeColumnIndex: Int = 0
    private var rootURL: URL?
    private var sort: FileSort = FileSort()
    private var showHidden: Bool = false
    private var cutPaths: Set<String> = []
    private var sharedMenu: NSMenu?

    var onSelectionChange: (() -> Void)?
    var onOpenItem: ((FileItem, Bool) -> Void)?
    var onPreview: (() -> Void)?
    var onNavigateUp: (() -> Void)?

    var selectedItems: [FileItem] {
        guard columns.indices.contains(activeColumnIndex) else { return [] }
        return columns[activeColumnIndex].selectedItems
    }

    var activeDirectoryURL: URL? {
        guard columns.indices.contains(activeColumnIndex) else { return rootURL }
        return columns[activeColumnIndex].directoryURL
    }

    var activeTableView: NSTableView? {
        guard columns.indices.contains(activeColumnIndex) else { return nil }
        return columns[activeColumnIndex].tableView
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.surface
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let doc = ColumnDocumentView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scrollView.documentView = doc
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            doc.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            doc.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            doc.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            doc.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContextMenu(_ menu: NSMenu) {
        sharedMenu = menu
        for pane in columns { pane.tableView.menu = menu }
    }

    func configureRoot(url: URL, items: [FileItem], sort: FileSort, showHidden: Bool, cutPaths: Set<String>, selectedIDs: Set<String>) {
        self.sort = sort
        self.showHidden = showHidden
        self.cutPaths = cutPaths
        let sameRoot = rootURL?.standardizedFileURL.path == url.standardizedFileURL.path
        rootURL = url

        if !sameRoot || columns.isEmpty {
            clearColumns()
            let first = makePane(index: 0, directoryURL: url, items: items)
            appendPane(first)
            activeColumnIndex = 0
            first.selectItems(ids: selectedIDs)
            if selectedIDs.count == 1, let item = first.selectedItems.first, item.isNavigable {
                openChildColumn(from: 0, folder: item.url)
            }
        } else {
            columns[0].update(items: items, cutPaths: cutPaths)
            if activeColumnIndex == 0, !selectedIDs.isEmpty {
                columns[0].selectItems(ids: selectedIDs)
            }
        }
    }

    func refreshTheme() {
        scrollView.backgroundColor = Palette.surface
        for pane in columns { pane.refreshTheme() }
    }

    func selectAllInActiveColumn() {
        activeTableView?.selectAll(nil)
    }

    func cancelTasks() {
        for pane in columns { pane.cancelLoad() }
    }

    private func clearColumns() {
        for pane in columns {
            pane.cancelLoad()
            stack.removeArrangedSubview(pane)
            pane.removeFromSuperview()
        }
        columns.removeAll()
        activeColumnIndex = 0
    }

    private func trimColumns(after index: Int) {
        while columns.count > index + 1 {
            let last = columns.removeLast()
            last.cancelLoad()
            stack.removeArrangedSubview(last)
            last.removeFromSuperview()
        }
    }

    private func appendPane(_ pane: ColumnPane) {
        columns.append(pane)
        pane.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(pane)
        NSLayoutConstraint.activate([
            pane.widthAnchor.constraint(equalToConstant: Self.columnWidth),
            pane.heightAnchor.constraint(equalTo: stack.heightAnchor)
        ])
        layoutSubtreeIfNeeded()
        scrollToShow(columnIndex: columns.count - 1)
    }

    private func scrollToShow(columnIndex: Int) {
        guard columns.indices.contains(columnIndex) else { return }
        let frame = columns[columnIndex].frame
        scrollView.contentView.scrollToVisible(frame)
    }

    private func makePane(index: Int, directoryURL: URL, items: [FileItem]) -> ColumnPane {
        let pane = ColumnPane(columnIndex: index, directoryURL: directoryURL, items: items, cutPaths: cutPaths)
        pane.tableView.menu = sharedMenu
        pane.onSelectionChange = { [weak self] colIndex in
            self?.handleSelectionChange(in: colIndex)
        }
        pane.onDoubleClick = { [weak self] item in
            let commandHeld = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            self?.onOpenItem?(item, commandHeld)
        }
        pane.onKeyNavigateRight = { [weak self] colIndex in
            self?.focusNextColumn(from: colIndex)
        }
        pane.onKeyNavigateLeft = { [weak self] colIndex in
            self?.focusPreviousColumn(from: colIndex)
        }
        pane.onPreview = { [weak self] in self?.onPreview?() }
        return pane
    }

    func handleSelectionChange(in columnIndex: Int) {
        guard columns.indices.contains(columnIndex) else { return }
        activeColumnIndex = columnIndex
        let selected = columns[columnIndex].selectedItems
        if selected.count == 1, let single = selected.first, single.isNavigable {
            openChildColumn(from: columnIndex, folder: single.url)
        } else {
            trimColumns(after: columnIndex)
        }
        onSelectionChange?()
    }

    private func openChildColumn(from parentIndex: Int, folder: URL) {
        let nextIndex = parentIndex + 1
        if columns.indices.contains(nextIndex),
           columns[nextIndex].directoryURL.standardizedFileURL.path == folder.standardizedFileURL.path {
            trimColumns(after: nextIndex)
            scrollToShow(columnIndex: nextIndex)
            return
        }
        trimColumns(after: parentIndex)
        let childPane = makePane(index: nextIndex, directoryURL: folder, items: [])
        appendPane(childPane)
        let sort = self.sort
        let showHidden = self.showHidden
        let cutPaths = self.cutPaths
        childPane.loadTask = Task { [weak childPane] in
            let loaded: [FileItem] = await Task.detached(priority: .userInitiated) {
                guard let raw = try? FileSystem.list(folder) else { return [] }
                return sort.apply(to: raw, query: "", showHidden: showHidden)
            }.value
            guard !Task.isCancelled, let childPane else { return }
            childPane.update(items: loaded, cutPaths: cutPaths)
        }
    }

    func focusNextColumn(from index: Int) {
        let next = index + 1
        guard columns.indices.contains(next) else {
            if let item = selectedItems.first, item.isNavigable {
                openChildColumn(from: index, folder: item.url)
            }
            return
        }
        activeColumnIndex = next
        let pane = columns[next]
        if pane.tableView.selectedRowIndexes.isEmpty && !pane.items.isEmpty {
            pane.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        window?.makeFirstResponder(pane.tableView)
        scrollToShow(columnIndex: next)
        handleSelectionChange(in: next)
    }

    func focusPreviousColumn(from index: Int) {
        guard index > 0 else {
            onNavigateUp?()
            return
        }
        let prev = index - 1
        activeColumnIndex = prev
        let pane = columns[prev]
        window?.makeFirstResponder(pane.tableView)
        scrollToShow(columnIndex: prev)
        onSelectionChange?()
    }
}

private final class ColumnDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ColumnPane: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let columnIndex: Int
    let directoryURL: URL
    private(set) var items: [FileItem]
    private var cutPaths: Set<String>
    var loadTask: Task<Void, Never>?

    let scrollView = NSScrollView()
    let tableView = ColumnTableView()
    private let divider = Surface()
    private var suppressSelection = false

    var onSelectionChange: ((Int) -> Void)?
    var onDoubleClick: ((FileItem) -> Void)?
    var onKeyNavigateRight: ((Int) -> Void)?
    var onKeyNavigateLeft: ((Int) -> Void)?
    var onPreview: (() -> Void)?

    var selectedItems: [FileItem] {
        tableView.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    init(columnIndex: Int, directoryURL: URL, items: [FileItem], cutPaths: Set<String>) {
        self.columnIndex = columnIndex
        self.directoryURL = directoryURL
        self.items = items
        self.cutPaths = cutPaths
        super.init(frame: .zero)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.style = .plain
        tableView.backgroundColor = Palette.surface
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
        tableView.onRightArrow = { [weak self] in guard let self else { return }; self.onKeyNavigateRight?(self.columnIndex) }
        tableView.onLeftArrow = { [weak self] in guard let self else { return }; self.onKeyNavigateLeft?(self.columnIndex) }
        tableView.onSpace = { [weak self] in self?.onPreview?() }
        tableView.onReturn = { [weak self] in self?.doubleClicked() }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.surface
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        divider.color = Palette.line
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(divider)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    func update(items: [FileItem], cutPaths: Set<String>) {
        let selectedIDs = Set(selectedItems.map(\.id))
        self.items = items
        self.cutPaths = cutPaths
        suppressSelection = true
        tableView.reloadData()
        selectItems(ids: selectedIDs)
        suppressSelection = false
    }

    func selectItems(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let indexes = IndexSet(items.enumerated().compactMap { ids.contains($0.element.id) ? $0.offset : nil })
        suppressSelection = true
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        if let first = indexes.first { tableView.scrollRowToVisible(first) }
        suppressSelection = false
    }

    func refreshTheme() {
        tableView.backgroundColor = Palette.surface
        scrollView.backgroundColor = Palette.surface
        divider.color = Palette.line
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row]
        let cellID = NSUserInterfaceItemIdentifier("ColumnCell")
        let cell: ColumnCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? ColumnCellView {
            cell = reused
        } else {
            cell = ColumnCellView()
            cell.identifier = cellID
        }
        let dimmed = cutPaths.contains(FileOperationController.itemPath(item.url))
        cell.configure(item: item, dimmed: dimmed)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection else { return }
        onSelectionChange?(columnIndex)
    }

    @objc private func doubleClicked() {
        guard let item = selectedItems.first else { return }
        onDoubleClick?(item)
    }
}

@MainActor
final class ColumnTableView: NSTableView {
    var onRightArrow: (() -> Void)?
    var onLeftArrow: (() -> Void)?
    var onSpace: (() -> Void)?
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 124: onRightArrow?() // Right arrow
        case 123: onLeftArrow?()  // Left arrow
        case 49: onSpace?()       // Space
        case 36, 76: onReturn?()  // Return / Enter
        default: super.keyDown(with: event)
        }
    }
}

@MainActor
private final class ColumnCellView: NSTableCellView {
    private let iconImg = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let trailingImg = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconImg.imageScaling = .scaleProportionallyDown
        nameLabel.font = .systemFont(ofSize: 12.5)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        trailingImg.imageScaling = .scaleProportionallyDown
        trailingImg.contentTintColor = .tertiaryLabelColor

        for sub in [iconImg, nameLabel, trailingImg] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sub)
        }
        NSLayoutConstraint.activate([
            iconImg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconImg.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImg.widthAnchor.constraint(equalToConstant: 16),
            iconImg.heightAnchor.constraint(equalToConstant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: iconImg.trailingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: trailingImg.leadingAnchor, constant: -4),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingImg.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            trailingImg.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingImg.widthAnchor.constraint(equalToConstant: 12),
            trailingImg.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: FileItem, dimmed: Bool) {
        iconImg.image = FileColors.icon(item)
        nameLabel.stringValue = item.name
        alphaValue = dimmed ? 0.45 : 1
        if item.isNavigable {
            trailingImg.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            trailingImg.isHidden = false
        } else if let cloudSym = item.cloudStatus.symbolName {
            trailingImg.image = NSImage(systemSymbolName: cloudSym, accessibilityDescription: item.cloudStatus.displayLabel)
            trailingImg.isHidden = false
        } else {
            trailingImg.image = nil
            trailingImg.isHidden = true
        }
    }
}
