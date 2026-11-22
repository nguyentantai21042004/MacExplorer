import AppKit
import ExplorerCore
import QuickLookThumbnailing

@MainActor
final class PreviewInspectorController: NSViewController {
    var onOpen: (() -> Void)?
    var onOpenInEditor: (([URL]) -> Void)?
    var onOpenInTerminal: ((URL) -> Void)?
    var onProperties: (([URL]) -> Void)?

    private let surface = Surface()
    private let scroll = NSScrollView()
    private let contentStack = NSStackView()
    let previewContainer = Surface()
    let previewImage = NSImageView()
    let textScroll = NSScrollView()
    let textView = NSTextView()
    let titleLabel = NSTextField(wrappingLabelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    private let tagsStack = NSStackView()
    private let metaStack = NSStackView()
    private let actionsStack = NSStackView()
    private let copyPathButton = ActionButton(L10n.text("Copy Path"), symbol: "link", tooltip: L10n.text("Copy full path")) {}
    private let openExternalButton = ActionButton(L10n.text("Open"), symbol: "arrow.up.forward.app", tooltip: L10n.text("Open")) {}
    private let propertiesButton = ActionButton(L10n.text("Info"), symbol: "info.circle", tooltip: L10n.text("Properties (⌘I)")) {}

    private var currentItems: [FileItem] = []
    private var currentFolder: URL?
    private var previewTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var thumbnailRequest: QLThumbnailGenerator.Request?
    private var generation = UUID()
    private var sizeValueLabel: NSTextField?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = L10n.locale; f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    override func loadView() {
        surface.color = Palette.inspector
        view = surface

        let divider = Surface()
        divider.color = Palette.line
        divider.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(divider)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(scroll)

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            divider.topAnchor.constraint(equalTo: surface.topAnchor),
            divider.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            scroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: surface.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])

        let doc = Surface()
        doc.color = .clear
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 16, right: 14)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(contentStack)

        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            contentStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: doc.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor)
        ])

        previewContainer.color = Palette.surface
        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 8
        previewContainer.layer?.borderWidth = 1
        previewContainer.layer?.borderColor = Palette.line.cgColor
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.heightAnchor.constraint(equalToConstant: 190).isActive = true

        previewImage.imageScaling = .scaleProportionallyUpOrDown
        previewImage.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewImage)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textScroll.documentView = textView
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.isHidden = true
        textScroll.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(textScroll)

        NSLayoutConstraint.activate([
            previewImage.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            previewImage.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            previewImage.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12),
            previewImage.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -12),
            textScroll.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            textScroll.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            textScroll.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            textScroll.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
        ])

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.maximumNumberOfLines = 3
        titleLabel.lineBreakMode = .byTruncatingMiddle

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor

        tagsStack.orientation = .horizontal
        tagsStack.spacing = 7
        tagsStack.alignment = .centerY

        metaStack.orientation = .vertical
        metaStack.alignment = .leading
        metaStack.spacing = 6

        actionsStack.orientation = .horizontal
        actionsStack.spacing = 6
        copyPathButton.actionBlock = { [weak self] in self?.copySelectedPath() }
        openExternalButton.actionBlock = { [weak self] in self?.openPrimaryTarget() }
        propertiesButton.actionBlock = { [weak self] in self?.showProperties() }
        [openExternalButton, copyPathButton, propertiesButton].forEach { actionsStack.addArrangedSubview($0) }

        contentStack.addArrangedSubview(previewContainer)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.addArrangedSubview(tagsStack)
        contentStack.addArrangedSubview(metaStack)
        contentStack.addArrangedSubview(actionsStack)
        previewContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -28).isActive = true
        metaStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -28).isActive = true
    }

    func refreshTheme() {
        surface.color = Palette.inspector
        previewContainer.color = Palette.surface
        previewContainer.layer?.borderColor = Palette.line.cgColor
        textView.textColor = .labelColor
        surface.needsDisplay = true
    }

    func update(items: [FileItem], currentFolder: URL?, cachedFolderSizes: [String: FolderSizeResult]) {
        generation = UUID()
        let activeGeneration = generation
        previewTask?.cancel()
        sizeTask?.cancel()
        if let req = thumbnailRequest { QLThumbnailGenerator.shared.cancel(req); thumbnailRequest = nil }

        self.currentItems = items
        self.currentFolder = currentFolder
        guard isViewLoaded else { return }

        if items.count > 1 {
            renderMultiple(items)
            return
        }
        if let item = items.first {
            renderSingle(item, cachedFolderSize: cachedFolderSizes[item.id], generation: activeGeneration)
            return
        }
        if let currentFolder, !BrowserLocation.isThisMac(currentFolder) {
            let folderItem = FileItem(
                url: currentFolder,
                name: currentFolder.lastPathComponent.isEmpty ? currentFolder.path : currentFolder.lastPathComponent,
                isDirectory: true
            )
            renderSingle(folderItem, cachedFolderSize: cachedFolderSizes[folderItem.id], generation: activeGeneration, isCurrentFolder: true)
            return
        }
        renderThisMac()
    }

    private func renderThisMac() {
        textScroll.isHidden = true
        previewImage.isHidden = false
        previewImage.image = Palette.symbol("desktopcomputer", size: 48)
        previewImage.contentTintColor = Palette.accent
        titleLabel.stringValue = L10n.text("This Mac")
        subtitleLabel.stringValue = L10n.text("Drives and network locations")
        rebuildTags(for: [])
        rebuildMetadata([])
        actionsStack.isHidden = true
    }

    private func renderMultiple(_ items: [FileItem]) {
        textScroll.isHidden = true
        previewImage.isHidden = false
        previewImage.image = Palette.symbol("square.stack.3d.up.fill", size: 44)
        previewImage.contentTintColor = Palette.accent
        titleLabel.stringValue = L10n.count("%lld items selected", items.count)
        let knownSizes = items.compactMap(\.size)
        if knownSizes.count == items.count {
            subtitleLabel.stringValue = L10n.byteCount(knownSizes.reduce(0, +))
        } else {
            let folders = items.filter(\.isNavigable).count
            subtitleLabel.stringValue = folders > 0 ? "\(folders) folders · \(items.count - folders) files" : "\(items.count) files"
        }
        rebuildTags(for: items)
        rebuildMetadata([("Location", items[0].url.deletingLastPathComponent().path)])
        actionsStack.isHidden = false
        openExternalButton.isHidden = true
    }

    private func renderSingle(_ item: FileItem, cachedFolderSize: FolderSizeResult?, generation: UUID, isCurrentFolder: Bool = false) {
        titleLabel.stringValue = item.name
        subtitleLabel.stringValue = isCurrentFolder ? L10n.text("Current folder") : item.kind
        actionsStack.isHidden = false
        openExternalButton.isHidden = false
        if item.isNavigable {
            openExternalButton.title = L10n.text("Terminal")
            openExternalButton.image = Palette.buttonSymbol("terminal")
        } else if ExternalApplications.canEdit([item]) && isTextPreviewable(item.url) {
            openExternalButton.title = ExternalApplications.name(for: .editor)
            openExternalButton.image = Palette.buttonSymbol("square.and.pencil")
        } else {
            openExternalButton.title = L10n.text("Open")
            openExternalButton.image = Palette.buttonSymbol("arrow.up.forward.app")
        }

        rebuildTags(for: isCurrentFolder ? [] : [item])

        var rows: [(String, String)] = []
        let sizeText: String
        if item.isNavigable {
            sizeText = cachedFolderSize.map { "\(L10n.byteCount($0.bytes)) (\($0.itemCount.formatted(.number.locale(L10n.locale))) files)" } ?? L10n.text("Calculating…")
        } else {
            sizeText = item.size.map { L10n.byteCount($0) } ?? "—"
        }
        rows.append((L10n.text("Size"), sizeText))
        if let modified = item.modified { rows.append((L10n.text("Modified"), dateFormatter.string(from: modified))) }
        if let created = item.created { rows.append((L10n.text("Created"), dateFormatter.string(from: created))) }
        rows.append((L10n.text("Path"), item.url.path))
        rebuildMetadata(rows, sizeRowIndex: 0)

        loadPreviewContent(for: item, generation: generation)

        if item.isNavigable && !item.isSymbolicLink && cachedFolderSize == nil {
            let targetURL = item.url
            let modDate = item.modified
            sizeTask = Task { [weak self] in
                if let cached = await FolderSizeCache.shared.cached(for: targetURL, modified: modDate) {
                    await MainActor.run { [weak self] in
                        guard let self, self.generation == generation else { return }
                        self.sizeValueLabel?.stringValue = "\(L10n.byteCount(cached.bytes)) (\(cached.itemCount.formatted(.number.locale(L10n.locale))) files)"
                    }
                    return
                }
                let measured = await Task.detached(priority: .utility) {
                    try? FolderSizeCalculator.measure(targetURL)
                }.value
                guard !Task.isCancelled, let measured else { return }
                await FolderSizeCache.shared.store(measured, for: targetURL, modified: modDate)
                await MainActor.run { [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.sizeValueLabel?.stringValue = "\(L10n.byteCount(measured.bytes)) (\(measured.itemCount.formatted(.number.locale(L10n.locale))) files)"
                }
            }
        }
    }

    private func loadPreviewContent(for item: FileItem, generation: UUID) {
        if !item.isDirectory && !item.isPackage && isTextPreviewable(item.url) {
            previewImage.isHidden = true
            textScroll.isHidden = false
            textView.string = L10n.text("Loading preview…")
            let url = item.url
            previewTask = Task { [weak self] in
                let snippet = await Task.detached(priority: .userInitiated) { () -> String? in
                    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
                    defer { try? handle.close() }
                    let data = try? handle.read(upToCount: 32_768)
                    guard let data, !data.prefix(1024).contains(0) else { return nil }
                    let text = String(decoding: data, as: UTF8.self)
                    return data.count == 32_768 ? text + "\n\n… (truncated at 32 KB)" : text
                }.value
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                if let snippet {
                    self.textView.string = snippet
                } else {
                    self.showThumbnail(for: item, generation: generation)
                }
            }
            return
        }
        showThumbnail(for: item, generation: generation)
    }

    private func showThumbnail(for item: FileItem, generation: UUID) {
        textScroll.isHidden = true
        previewImage.isHidden = false
        previewImage.contentTintColor = nil
        previewImage.image = FileColors.icon(item)

        guard !item.isDirectory else { return }
        let scale = view.window?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 280, height: 180),
            scale: scale,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )
        thumbnailRequest = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            let cg = rep?.cgImage
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.thumbnailRequest = nil
                if let cg {
                    self.previewImage.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
            }
        }
    }

    private func isTextPreviewable(_ url: URL) -> Bool {
        TextFileTypes.recognizes(url)
    }

    private func rebuildTags(for items: [FileItem]) {
        tagsStack.arrangedSubviews.forEach { tagsStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        tagsStack.isHidden = items.isEmpty
        guard !items.isEmpty else { return }
        let label = NSTextField(labelWithString: L10n.text("Tags"))
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        tagsStack.addArrangedSubview(label)
        let activeColors = Set(items.flatMap(\.finderColors.colors))
        for color in FinderColor.menuOrder where color != .none {
            let dot = TagDotButton(color: FileColors.color(color), selected: activeColors.contains(color), tooltip: color.displayName) { [weak self] in
                guard let self, let window = self.view.window, window.attachedSheet == nil, !FileOperationController.shared.busy else { return }
                let targetColor: FinderColor = activeColors.contains(color) && activeColors.count == 1 ? .none : color
                FileOperationController.shared.run(.color(items.map(\.url), targetColor), window: window)
            }
            tagsStack.addArrangedSubview(dot)
        }
    }

    private func rebuildMetadata(_ rows: [(String, String)], sizeRowIndex: Int? = nil) {
        sizeValueLabel = nil
        metaStack.arrangedSubviews.forEach { metaStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (idx, row) in rows.enumerated() {
            let keyLabel = NSTextField(labelWithString: row.0)
            keyLabel.font = .systemFont(ofSize: 11, weight: .medium)
            keyLabel.textColor = .secondaryLabelColor
            keyLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

            let valueLabel = NSTextField(wrappingLabelWithString: row.1)
            valueLabel.font = .systemFont(ofSize: 11)
            valueLabel.textColor = .labelColor
            valueLabel.isSelectable = true
            valueLabel.lineBreakMode = .byTruncatingMiddle
            if sizeRowIndex == idx { sizeValueLabel = valueLabel }

            let hStack = NSStackView(views: [keyLabel, valueLabel])
            hStack.orientation = .horizontal
            hStack.alignment = .top
            hStack.spacing = 8
            metaStack.addArrangedSubview(hStack)
            hStack.widthAnchor.constraint(equalTo: metaStack.widthAnchor).isActive = true
        }
    }

    private func copySelectedPath() {
        let urls = currentItems.isEmpty ? [currentFolder].compactMap { $0 } : currentItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        let original = copyPathButton.title
        copyPathButton.title = L10n.text("Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.copyPathButton.title = original
        }
    }

    private func openPrimaryTarget() {
        if let item = currentItems.first {
            if item.isNavigable { onOpenInTerminal?(item.url) }
            else if ExternalApplications.canEdit([item]) && isTextPreviewable(item.url) { onOpenInEditor?([item.url]) }
            else { onOpen?() }
        } else if let currentFolder {
            onOpenInTerminal?(currentFolder)
        }
    }

    private func showProperties() {
        let targets = currentItems.isEmpty ? [currentFolder].compactMap { $0 } : currentItems.map(\.url)
        if !targets.isEmpty { onProperties?(targets) }
    }
}

@MainActor
private final class TagDotButton: NSButton {
    private let dotColor: NSColor
    private let isChosen: Bool
    private let onTap: () -> Void

    init(color: NSColor, selected: Bool, tooltip: String, onTap: @escaping () -> Void) {
        self.dotColor = color
        self.isChosen = selected
        self.onTap = onTap
        super.init(frame: .zero)
        self.toolTip = tooltip
        isBordered = false
        title = ""
        target = self
        action = #selector(pressed)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { onTap() }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        dotColor.setFill()
        circle.fill()
        if isChosen {
            NSColor.white.setStroke()
            circle.lineWidth = 1.8
            circle.stroke()
        }
    }
}
