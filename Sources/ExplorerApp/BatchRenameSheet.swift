import AppKit
import ExplorerCore

@MainActor
final class BatchRenameSheetController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let urls: [URL]
    private var entries: [BatchRenameEntry] = []
    private let onApply: ([(URL, String)]) -> Void

    private let modeSegment = NSSegmentedControl(labels: [
        L10n.text("Find & Replace"),
        L10n.text("Prefix / Suffix"),
        L10n.text("Sequence")
    ], trackingMode: .selectOne, target: nil, action: nil)

    private let primaryField = NSTextField()
    private let secondaryField = NSTextField()
    private let primaryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let startNumberField = NSTextField(string: "1")
    private let padWidthField = NSTextField(string: "3")
    private let sequenceOptionsRow = NSStackView()

    private let regexCheck = NSButton(checkboxWithTitle: L10n.text("Use regex"), target: nil, action: nil)
    private let caseCheck = NSButton(checkboxWithTitle: L10n.text("Case sensitive"), target: nil, action: nil)
    private let includeExtCheck = NSButton(checkboxWithTitle: L10n.text("Include extension"), target: nil, action: nil)
    private let summaryLabel = NSTextField(labelWithString: "")
    private let previewTable = NSTableView()
    private let applyButton = NSButton(title: L10n.text("Rename"), target: nil, action: nil)

    init(urls: [URL], onApply: @escaping ([(URL, String)]) -> Void) {
        self.urls = urls
        self.onApply = onApply
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Batch Rename")
        super.init(window: window)
        buildUI()
        updateModeUI()
        recomputePlan()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        modeSegment.selectedSegment = 0
        modeSegment.target = self
        modeSegment.action = #selector(modeChanged)

        for field in [primaryField, secondaryField, startNumberField, padWidthField] {
            field.target = self
            field.action = #selector(inputsChanged)
            NotificationCenter.default.addObserver(self, selector: #selector(inputsChanged), name: NSControl.textDidChangeNotification, object: field)
        }
        for check in [regexCheck, caseCheck, includeExtCheck] {
            check.target = self
            check.action = #selector(inputsChanged)
        }

        primaryLabel.widthAnchor.constraint(equalToConstant: 90).isActive = true
        secondaryLabel.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let row1 = NSStackView(views: [primaryLabel, primaryField])
        let row2 = NSStackView(views: [secondaryLabel, secondaryField])
        row1.orientation = .horizontal; row2.orientation = .horizontal
        row1.spacing = 10; row2.spacing = 10

        let startLabel = NSTextField(labelWithString: L10n.text("Start at:"))
        let padLabel = NSTextField(labelWithString: L10n.text("Digits:"))
        startNumberField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        padWidthField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        sequenceOptionsRow.orientation = .horizontal
        sequenceOptionsRow.spacing = 10
        [startLabel, startNumberField, padLabel, padWidthField, NSView()].forEach { sequenceOptionsRow.addArrangedSubview($0) }

        let optionsRow = NSStackView(views: [regexCheck, caseCheck, includeExtCheck, NSView()])
        optionsRow.orientation = .horizontal
        optionsRow.spacing = 14

        for (id, title, width) in [("before", L10n.text("Current Name"), 270.0), ("after", L10n.text("New Name"), 300.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            previewTable.addTableColumn(col)
        }
        previewTable.dataSource = self
        previewTable.delegate = self
        previewTable.rowHeight = 24
        previewTable.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = previewTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor

        let cancelButton = NSButton(title: L10n.text("Cancel"), target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        applyButton.target = self
        applyButton.action = #selector(apply)
        applyButton.keyEquivalent = "\r"
        applyButton.bezelStyle = .rounded

        let footer = NSStackView(views: [summaryLabel, NSView(), cancelButton, applyButton])
        footer.orientation = .horizontal
        footer.spacing = 10

        let stack = NSStackView(views: [modeSegment, row1, row2, sequenceOptionsRow, optionsRow, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        for v in [row1, row2, sequenceOptionsRow, optionsRow, scroll, footer] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @objc private func modeChanged() {
        updateModeUI()
        recomputePlan()
    }

    @objc private func inputsChanged() { recomputePlan() }

    private func updateModeUI() {
        switch modeSegment.selectedSegment {
        case 0:
            primaryLabel.stringValue = L10n.text("Find:")
            secondaryLabel.stringValue = L10n.text("Replace:")
            primaryField.placeholderString = L10n.text("Text or regex pattern")
            secondaryField.placeholderString = L10n.text("Replacement")
            secondaryLabel.isHidden = false; secondaryField.isHidden = false
            sequenceOptionsRow.isHidden = true
            regexCheck.isHidden = false; caseCheck.isHidden = false
        case 1:
            primaryLabel.stringValue = L10n.text("Prefix:")
            secondaryLabel.stringValue = L10n.text("Suffix:")
            primaryField.placeholderString = L10n.text("Before filename")
            secondaryField.placeholderString = L10n.text("After filename")
            secondaryLabel.isHidden = false; secondaryField.isHidden = false
            sequenceOptionsRow.isHidden = true
            regexCheck.isHidden = true; caseCheck.isHidden = true
        default:
            primaryLabel.stringValue = L10n.text("Base name:")
            primaryField.placeholderString = L10n.text("e.g. photo-")
            secondaryLabel.isHidden = true; secondaryField.isHidden = true
            sequenceOptionsRow.isHidden = false
            regexCheck.isHidden = true; caseCheck.isHidden = true
        }
    }

    private func currentMode() -> BatchRenameMode {
        switch modeSegment.selectedSegment {
        case 0:
            return .replace(
                find: primaryField.stringValue,
                replacement: secondaryField.stringValue,
                useRegex: regexCheck.state == .on,
                caseSensitive: caseCheck.state == .on
            )
        case 1:
            return .affix(prefix: primaryField.stringValue, suffix: secondaryField.stringValue)
        default:
            let start = Int(startNumberField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 1
            let pad = max(1, min(8, Int(padWidthField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 3))
            return .sequence(base: primaryField.stringValue, start: start, padWidth: pad)
        }
    }

    private func recomputePlan() {
        entries = BatchRenamePlanner.plan(urls: urls, mode: currentMode(), includeExtension: includeExtCheck.state == .on)
        previewTable.reloadData()
        let invalidCount = entries.filter { !$0.isValid }.count
        let changedCount = entries.filter(\.changed).count
        if invalidCount > 0 {
            summaryLabel.stringValue = "\(invalidCount) invalid or duplicate name(s)"
            summaryLabel.textColor = .systemRed
        } else {
            summaryLabel.stringValue = "\(changedCount) of \(entries.count) item(s) will be renamed"
            summaryLabel.textColor = .secondaryLabelColor
        }
        applyButton.isEnabled = invalidCount == 0 && changedCount > 0
    }

    @objc private func cancel() {
        guard let window, let parent = window.sheetParent else { window?.close(); return }
        parent.endSheet(window, returnCode: .cancel)
    }

    @objc private func apply() {
        let pairs = entries.filter(\.changed).map { ($0.source, $0.newName) }
        guard !pairs.isEmpty, entries.allSatisfy(\.isValid) else { return }
        if let window, let parent = window.sheetParent {
            parent.endSheet(window, returnCode: .OK)
        } else {
            window?.close()
        }
        onApply(pairs)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let entry = entries[row]
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(id), owner: self) as? NSTableCellView) ?? {
            let v = NSTableCellView(); v.identifier = NSUserInterfaceItemIdentifier(id)
            let tf = NSTextField(labelWithString: ""); tf.font = .systemFont(ofSize: 12); tf.lineBreakMode = .byTruncatingMiddle
            tf.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(tf); v.textField = tf
            NSLayoutConstraint.activate([tf.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6), tf.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6), tf.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
            return v
        }()
        if id == "before" {
            cell.textField?.stringValue = entry.originalName
            cell.textField?.textColor = .secondaryLabelColor
        } else {
            if let error = entry.error {
                cell.textField?.stringValue = "\(entry.newName) (\(error))"
                cell.textField?.textColor = .systemRed
            } else {
                cell.textField?.stringValue = entry.newName
                cell.textField?.textColor = entry.changed ? .labelColor : .tertiaryLabelColor
            }
        }
        return cell
    }
}
