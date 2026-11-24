import AppKit
import ExplorerCore
import UniformTypeIdentifiers

/// Native Get Info window (`⌘I`) with zero Finder/AppleScript dependency.
/// Supports single-item full inspection & editing (name, locked, hide extension,
/// custom Finder tags, Open With + Change All, POSIX permissions, symlink target,
/// Gatekeeper quarantine status, streaming SHA-256) and multi-item summary info.
@MainActor
final class GetInfoWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private static var openControllers: [String: GetInfoWindowController] = [:]

    let urls: [URL]
    private var primaryURL: URL { urls[0] }
    private var key: String
    private(set) var snapshot: FileMetadataSnapshot?

    private let stack = NSStackView()
    private let iconView = NSImageView()
    private let nameField = NSTextField()
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let quarantineBanner = NSTextField(wrappingLabelWithString: "")

    private let sizeValue = NSTextField(labelWithString: "")
    private let lockedCheckbox = NSButton(checkboxWithTitle: "Locked", target: nil, action: nil)
    private let hideExtCheckbox = NSButton(checkboxWithTitle: "Hide extension", target: nil, action: nil)

    private let tagsField = NSTextField()
    private let tagsHint = NSTextField(wrappingLabelWithString: "Comma-separated tags (e.g. Work, Red, Important). Press Return to save.")

    private let openWithPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let changeAllButton = NSButton(title: "Change All…", target: nil, action: nil)
    private var openWithApps: [URL] = []

    private let ownerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let groupPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let everyonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modeLabel = NSTextField(labelWithString: "")

    private let checksumField = NSTextField(labelWithString: "")
    private let checksumButton = NSButton(title: "Compute SHA-256", target: nil, action: nil)
    private let copyChecksumButton = NSButton(title: "Copy", target: nil, action: nil)

    private var sizeTask: Task<Void, Never>?
    private var checksumTask: Task<Void, Never>?

    static func show(urls: [URL], relativeTo parentWindow: NSWindow? = nil) {
        let local = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !local.isEmpty else { return }
        let key = local.count == 1 ? local[0].path : "multi:\(local.map(\.path).sorted().joined(separator: "|"))"
        if let existing = openControllers[key], let win = existing.window {
            existing.reloadMetadata()
            win.makeKeyAndOrderFront(nil)
            return
        }
        let controller = GetInfoWindowController(urls: local, key: key)
        openControllers[key] = controller
        if let parent = parentWindow, let win = controller.window {
            let offset = CGFloat((openControllers.count - 1) % 6) * 24
            let origin = NSPoint(x: parent.frame.minX + 60 + offset, y: max(80, parent.frame.maxY - win.frame.height - 60 - offset))
            win.setFrameOrigin(origin)
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    init(urls: [URL], key: String) {
        self.urls = urls
        self.key = key
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: urls.count == 1 ? 580 : 280),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 340, height: 240)
        panel.maxSize = NSSize(width: 560, height: 900)
        panel.isFloatingPanel = false
        panel.title = urls.count == 1 ? "\(urls[0].lastPathComponent) Info" : "\(urls.count) Items Info"
        panel.backgroundColor = Palette.inspector
        super.init(window: panel)
        panel.delegate = self
        buildUI()
        reloadMetadata()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        sizeTask?.cancel()
        checksumTask?.cancel()
        Self.openControllers.removeValue(forKey: key)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        contentView.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor)
        ])
    }

    func reloadMetadata() {
        sizeTask?.cancel()
        checksumTask?.cancel()
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }

        if urls.count > 1 {
            renderMultipleSummary()
            return
        }

        do {
            let info = try FileMetadataInspector.inspect(primaryURL)
            self.snapshot = info
            window?.title = "\(info.name) Info"
            renderSingle(info)
        } catch {
            let msg = NSTextField(wrappingLabelWithString: error.localizedDescription)
            msg.textColor = .systemRed
            stack.addArrangedSubview(msg)
        }
    }

    private func renderMultipleSummary() {
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 10
        header.alignment = .centerY
        iconView.image = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: nil)
        iconView.contentTintColor = Palette.accent
        iconView.widthAnchor.constraint(equalToConstant: 36).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let title = NSTextField(labelWithString: L10n.count("%lld items selected", urls.count))
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let snapshots = urls.compactMap { try? FileMetadataInspector.inspect($0) }
        let fileCount = snapshots.filter { !$0.isDirectory || $0.isPackage }.count
        let folderCount = snapshots.count - fileCount
        let knownBytes = snapshots.compactMap(\.size).reduce(0, +)
        subtitleLabel.stringValue = "\(folderCount) folders · \(fileCount) files"
        subtitleLabel.font = .systemFont(ofSize: 11.5)
        subtitleLabel.textColor = .secondaryLabelColor

        let textCol = NSStackView(views: [title, subtitleLabel])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2
        header.addArrangedSubview(iconView)
        header.addArrangedSubview(textCol)
        addFullWidth(header)
        addDivider()

        sizeValue.stringValue = folderCount > 0 ? "\(L10n.byteCount(knownBytes)) + calculating folders…" : L10n.byteCount(knownBytes)
        addSectionHeader("General")
        addKeyValue("Total Size", view: sizeValue)
        addKeyValue("Where", text: primaryURL.deletingLastPathComponent().path, selectable: true)

        if folderCount > 0 {
            let folderURLs = snapshots.filter { $0.isDirectory && !$0.isPackage && !$0.isSymbolicLink }.map { ($0.url, $0.modified) }
            sizeTask = Task { [weak self] in
                var total = knownBytes
                for (folder, mod) in folderURLs {
                    guard !Task.isCancelled else { return }
                    if let measured = await FolderSizeCache.shared.measureIfNeeded(for: folder, modified: mod) {
                        total += measured.bytes
                    }
                }
                guard !Task.isCancelled, let self else { return }
                self.sizeValue.stringValue = L10n.byteCount(total)
            }
        }
    }

    private func renderSingle(_ info: FileMetadataSnapshot) {
        // 1. Header
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 10
        header.alignment = .centerY
        iconView.image = NSWorkspace.shared.icon(forFile: info.url.path)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.widthAnchor.constraint(equalToConstant: 40).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 40).isActive = true

        nameField.stringValue = info.name
        nameField.font = .systemFont(ofSize: 13.5, weight: .semibold)
        nameField.isEditable = !FileOperationEngine.isProtectedSystemPath(info.url)
        nameField.isBordered = true
        nameField.bezelStyle = .roundedBezel
        nameField.delegate = self

        subtitleLabel.stringValue = info.kind
        subtitleLabel.font = .systemFont(ofSize: 11.5)
        subtitleLabel.textColor = .secondaryLabelColor

        let titleCol = NSStackView(views: [nameField, subtitleLabel])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 3
        header.addArrangedSubview(iconView)
        header.addArrangedSubview(titleCol)
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        addFullWidth(header)

        if let quarantine = info.quarantineSummary {
            quarantineBanner.stringValue = quarantine
            quarantineBanner.font = .systemFont(ofSize: 11, weight: .medium)
            quarantineBanner.textColor = .systemOrange
            addFullWidth(quarantineBanner)
        }

        addDivider()

        // 2. General
        addSectionHeader("General")
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        if info.isDirectory && !info.isPackage && !info.isSymbolicLink {
            sizeValue.stringValue = L10n.text("Calculating…")
            let url = info.url, mod = info.modified
            sizeTask = Task { [weak self] in
                let measured = await FolderSizeCache.shared.measureIfNeeded(for: url, modified: mod)
                guard !Task.isCancelled, let self else { return }
                if let measured {
                    self.sizeValue.stringValue = "\(L10n.byteCount(measured.bytes)) (\(measured.itemCount) items)"
                } else {
                    self.sizeValue.stringValue = "—"
                }
            }
        } else if let size = info.size {
            if let allocated = info.allocatedSize, allocated > 0 {
                sizeValue.stringValue = "\(L10n.byteCount(size)) (\(L10n.byteCount(allocated)) on disk)"
            } else {
                sizeValue.stringValue = L10n.byteCount(size)
            }
        } else {
            sizeValue.stringValue = "—"
        }
        sizeValue.font = .systemFont(ofSize: 12)
        sizeValue.isSelectable = true
        addKeyValue("Size", view: sizeValue)

        let whereRow = NSStackView()
        whereRow.orientation = .horizontal
        whereRow.spacing = 6
        whereRow.alignment = .centerY
        let whereLabel = NSTextField(wrappingLabelWithString: info.url.deletingLastPathComponent().path)
        whereLabel.font = .systemFont(ofSize: 11.5)
        whereLabel.textColor = .secondaryLabelColor
        whereLabel.isSelectable = true
        let copyPathBtn = NSButton(title: "Copy Path", target: self, action: #selector(copyFullPath))
        copyPathBtn.bezelStyle = .rounded
        copyPathBtn.controlSize = .small
        whereRow.addArrangedSubview(whereLabel)
        whereRow.addArrangedSubview(copyPathBtn)
        addKeyValue("Where", view: whereRow)

        if let created = info.created { addKeyValue("Created", text: df.string(from: created)) }
        if let modified = info.modified { addKeyValue("Modified", text: df.string(from: modified)) }
        if let opened = info.lastOpened { addKeyValue("Last Opened", text: df.string(from: opened)) }

        if let target = info.symlinkTarget {
            let targetText = info.symlinkBroken ? "\(target) (broken link)" : target
            let symRow = NSStackView()
            symRow.orientation = .horizontal
            symRow.spacing = 6
            let symLabel = NSTextField(wrappingLabelWithString: targetText)
            symLabel.font = .systemFont(ofSize: 11.5)
            symLabel.textColor = info.symlinkBroken ? .systemRed : .secondaryLabelColor
            symLabel.isSelectable = true
            symRow.addArrangedSubview(symLabel)
            if !info.symlinkBroken {
                let revealBtn = NSButton(title: "Reveal", target: self, action: #selector(revealSymlinkTarget))
                revealBtn.bezelStyle = .rounded
                revealBtn.controlSize = .small
                symRow.addArrangedSubview(revealBtn)
            }
            addKeyValue("Original", view: symRow)
        }

        lockedCheckbox.state = info.isLocked ? .on : .off
        lockedCheckbox.isEnabled = !FileOperationEngine.isProtectedSystemPath(info.url) && !info.isSymbolicLink
        lockedCheckbox.target = self
        lockedCheckbox.action = #selector(toggleLocked)

        hideExtCheckbox.state = info.isExtensionHidden ? .on : .off
        hideExtCheckbox.isEnabled = !FileOperationEngine.isProtectedSystemPath(info.url) && !info.url.pathExtension.isEmpty
        hideExtCheckbox.target = self
        hideExtCheckbox.action = #selector(toggleHideExtension)

        let flagsRow = NSStackView(views: [lockedCheckbox, hideExtCheckbox])
        flagsRow.orientation = .horizontal
        flagsRow.spacing = 16
        addFullWidth(flagsRow)

        addDivider()

        // 3. Finder Tags
        addSectionHeader("Finder Tags")
        tagsField.stringValue = info.tags.map(\.name).joined(separator: ", ")
        tagsField.placeholderString = "Add tags separated by commas…"
        tagsField.font = .systemFont(ofSize: 12)
        tagsField.isEditable = !info.isSymbolicLink
        tagsField.target = self
        tagsField.action = #selector(saveTags)
        tagsHint.font = .systemFont(ofSize: 10.5)
        tagsHint.textColor = .secondaryLabelColor
        addFullWidth(tagsField)
        addFullWidth(tagsHint)

        // 4. Open With (for non-directory files)
        if !info.isDirectory || info.isPackage {
            addDivider()
            addSectionHeader("Open With")
            let choices = OpenWithMenu.applications(for: [info.url])
            openWithApps = choices.apps
            openWithPopup.removeAllItems()
            for app in choices.apps {
                let suffix = (app == choices.defaultApp) ? " (Default)" : ""
                openWithPopup.addItem(withTitle: ExternalApplications.name(of: app) + suffix)
            }
            if choices.apps.isEmpty {
                openWithPopup.addItem(withTitle: L10n.text("No Registered Applications"))
                openWithPopup.isEnabled = false
                changeAllButton.isEnabled = false
            } else {
                openWithPopup.isEnabled = true
                if let def = choices.defaultApp, let idx = choices.apps.firstIndex(of: def) {
                    openWithPopup.selectItem(at: idx)
                }
                changeAllButton.isEnabled = info.contentTypeIdentifier != nil
            }
            changeAllButton.bezelStyle = .rounded
            changeAllButton.controlSize = .small
            changeAllButton.target = self
            changeAllButton.action = #selector(changeAllOpenWith)

            let openRow = NSStackView(views: [openWithPopup, changeAllButton])
            openRow.orientation = .horizontal
            openRow.spacing = 8
            addFullWidth(openRow)
        }

        // 5. Sharing & Permissions
        if let perms = info.permissions {
            addDivider()
            addSectionHeader("Sharing & Permissions")
            configurePermissionPopup(ownerPopup, selected: perms.ownerAccess, enabled: info.canModifyPermissions, tag: 0)
            configurePermissionPopup(groupPopup, selected: perms.groupAccess, enabled: info.canModifyPermissions, tag: 1)
            configurePermissionPopup(everyonePopup, selected: perms.everyoneAccess, enabled: info.canModifyPermissions, tag: 2)

            addKeyValue("\(perms.ownerName) (Me)", view: ownerPopup)
            addKeyValue(perms.groupName, view: groupPopup)
            addKeyValue("Everyone", view: everyonePopup)

            modeLabel.stringValue = "POSIX \(perms.octalString) (\(perms.symbolicString))"
            modeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            modeLabel.textColor = .secondaryLabelColor
            modeLabel.isSelectable = true
            addFullWidth(modeLabel)
        }

        // 6. Security Checksum (regular files)
        if info.isRegularFile {
            addDivider()
            addSectionHeader("Integrity (SHA-256)")
            checksumField.stringValue = "Not computed"
            checksumField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            checksumField.textColor = .secondaryLabelColor
            checksumField.isSelectable = true
            checksumField.lineBreakMode = .byCharWrapping
            checksumField.maximumNumberOfLines = 2

            checksumButton.bezelStyle = .rounded
            checksumButton.controlSize = .small
            checksumButton.target = self
            checksumButton.action = #selector(computeChecksum)

            copyChecksumButton.bezelStyle = .rounded
            copyChecksumButton.controlSize = .small
            copyChecksumButton.isEnabled = false
            copyChecksumButton.target = self
            copyChecksumButton.action = #selector(copyChecksum)

            let row = NSStackView(views: [checksumButton, copyChecksumButton])
            row.orientation = .horizontal
            row.spacing = 8
            addFullWidth(checksumField)
            addFullWidth(row)
        }
    }

    private func configurePermissionPopup(_ popup: NSPopUpButton, selected: POSIXPermissionsSummary.AccessLevel, enabled: Bool, tag: Int) {
        popup.removeAllItems()
        for level in POSIXPermissionsSummary.AccessLevel.allCases {
            popup.addItem(withTitle: level.title)
        }
        if let idx = POSIXPermissionsSummary.AccessLevel.allCases.firstIndex(of: selected) {
            popup.selectItem(at: idx)
        }
        popup.isEnabled = enabled
        popup.controlSize = .small
        popup.tag = tag
        popup.target = self
        popup.action = #selector(permissionChanged(_:))
    }

    private func addSectionHeader(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        addFullWidth(label)
    }

    private func addDivider() {
        let line = NSBox()
        line.boxType = .separator
        addFullWidth(line)
    }

    private func addFullWidth(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
    }

    private func addKeyValue(_ key: String, text: String, selectable: Bool = false) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.isSelectable = selectable
        addKeyValue(key, view: label)
    }

    private func addKeyValue(_ key: String, view valueView: NSView) {
        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.alignment = .right
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        keyLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let row = NSStackView(views: [keyLabel, valueView])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        addFullWidth(row)
    }

    // MARK: Actions

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === nameField,
              let info = snapshot else { return }
        let newName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != info.name else {
            nameField.stringValue = info.name
            return
        }
        guard let win = window else { return }
        FileOperationController.shared.run(.rename(info.url, to: newName), window: win)
        // Close this stale path controller if renamed cleanly; user can reopen on new item.
        let newURL = info.url.deletingLastPathComponent().appendingPathComponent(newName)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            if FileManager.default.fileExists(atPath: newURL.path) {
                self.close()
                GetInfoWindowController.show(urls: [newURL])
            } else {
                self.reloadMetadata()
            }
        }
    }

    @objc private func copyFullPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primaryURL.path, forType: .string)
    }

    @objc private func revealSymlinkTarget() {
        let resolved = primaryURL.resolvingSymlinksInPath()
        (NSApp.delegate as? AppDelegate)?.current?.browser.openExternal([resolved])
    }

    @objc private func toggleLocked() {
        let desired = lockedCheckbox.state == .on
        do {
            try FileMetadataInspector.setLocked(desired, at: primaryURL)
            reloadMetadata()
        } catch {
            lockedCheckbox.state = desired ? .off : .on
            presentErrorAlert(error)
        }
    }

    @objc private func toggleHideExtension() {
        let desired = hideExtCheckbox.state == .on
        do {
            try FileMetadataInspector.setExtensionHidden(desired, at: primaryURL)
            reloadMetadata()
        } catch {
            hideExtCheckbox.state = desired ? .off : .on
            presentErrorAlert(error)
        }
    }

    @objc private func saveTags() {
        guard let existing = snapshot?.tags else { return }
        let colorByName = Dictionary(uniqueKeysWithValues: FinderColor.allCases.filter { $0 != .none }.map { ($0.name.lowercased(), $0) })
        let existingByName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name.lowercased(), $0.color) })
        let names = tagsField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let desired = names.map { name -> FinderTag in
            let lower = name.lowercased()
            let color = colorByName[lower] ?? existingByName[lower] ?? .none
            return FinderTag(name: name, color: color)
        }
        do {
            try FinderColors.writeTagsList(desired, at: primaryURL)
            reloadMetadata()
        } catch {
            presentErrorAlert(error)
        }
    }

    @objc private func changeAllOpenWith() {
        let idx = openWithPopup.indexOfSelectedItem
        guard openWithApps.indices.contains(idx),
              let uti = snapshot?.contentTypeIdentifier,
              let contentType = UTType(uti) else { return }
        let appURL = openWithApps[idx]
        Task { @MainActor [weak self] in
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: contentType)
                self?.reloadMetadata()
            } catch {
                self?.presentErrorAlert(error)
            }
        }
    }

    @objc private func permissionChanged(_ sender: NSPopUpButton) {
        guard let perms = snapshot?.permissions else { return }
        let levels = POSIXPermissionsSummary.AccessLevel.allCases
        let selectedIdx = sender.indexOfSelectedItem
        guard levels.indices.contains(selectedIdx) else { return }
        let chosen = levels[selectedIdx]
        let newMode: UInt16
        switch sender.tag {
        case 0: newMode = perms.updating(owner: chosen)
        case 1: newMode = perms.updating(group: chosen)
        default: newMode = perms.updating(everyone: chosen)
        }
        do {
            try FileMetadataInspector.setPermissions(newMode, at: primaryURL)
            reloadMetadata()
        } catch {
            presentErrorAlert(error)
            reloadMetadata()
        }
    }

    @objc private func computeChecksum() {
        checksumTask?.cancel()
        checksumButton.isEnabled = false
        copyChecksumButton.isEnabled = false
        checksumField.stringValue = "Computing SHA-256…"
        let url = primaryURL
        checksumTask = Task { @MainActor [weak self] in
            do {
                let hex = try await FileMetadataInspector.sha256Hex(of: url)
                guard !Task.isCancelled, let self else { return }
                self.checksumField.stringValue = hex
                self.checksumField.textColor = .labelColor
                self.checksumButton.isEnabled = true
                self.copyChecksumButton.isEnabled = true
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.checksumField.stringValue = "Failed: \(error.localizedDescription)"
                self.checksumField.textColor = .systemRed
                self.checksumButton.isEnabled = true
            }
        }
    }

    @objc private func copyChecksum() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(checksumField.stringValue, forType: .string)
    }

    private func presentErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Couldn’t Update Properties")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.text("OK"))
        if let win = window, win.attachedSheet == nil {
            alert.beginSheetModal(for: win)
        } else {
            alert.runModal()
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
enum FileProperties {
    static func show(_ urls: [URL], window: NSWindow?) {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return }
        GetInfoWindowController.show(urls: urls, relativeTo: window)
    }

    static func item(urls: [URL], window: NSWindow?) -> NSMenuItem {
        ContextMenu.item(L10n.text("Properties"), symbol: "info.circle") { [weak window] in show(urls, window: window) }
    }
}
