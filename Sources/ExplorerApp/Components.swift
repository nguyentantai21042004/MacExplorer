import AppKit
import ExplorerCore

@MainActor
enum Palette {
    private static func hex(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
    }
    private static func dynamic(light: @escaping @Sendable () -> NSColor, dark: @escaping @Sendable () -> NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark() : light()
        }
    }
    private static var currentTheme: AppTheme { AppPreferences.shared.theme }

    static let chrome = NSColor(name: "ExplorerChrome") { appearance in
        switch currentTheme {
        case .system:
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.12, alpha: 1) : hex(204, 224, 237)
        case .slateCyan: return hex(23, 27, 30)
        case .tokyoNight: return hex(21, 22, 30)
        case .nord: return hex(36, 41, 51)
        case .catppuccin: return hex(17, 17, 27)
        }
    }
    static let sidebar = NSColor(name: "ExplorerSidebar") { appearance in
        switch currentTheme {
        case .system:
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.13, alpha: 1) : NSColor(calibratedWhite: 1, alpha: 1)
        case .slateCyan: return hex(22, 29, 34)
        case .tokyoNight: return hex(22, 22, 30)
        case .nord: return hex(39, 44, 54)
        case .catppuccin: return hex(24, 24, 37)
        }
    }
    static let navigation = NSColor(name: "ExplorerNavigation") { appearance in
        switch currentTheme {
        case .system:
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.18, alpha: 1) : hex(246, 251, 254)
        case .slateCyan: return hex(32, 36, 40)
        case .tokyoNight: return hex(31, 35, 53)
        case .nord: return hex(59, 66, 82)
        case .catppuccin: return hex(37, 37, 56)
        }
    }
    static let surface = NSColor(name: "ExplorerSurface") { appearance in
        switch currentTheme {
        case .system: return .controlBackgroundColor
        case .slateCyan: return hex(30, 30, 30)
        case .tokyoNight: return hex(26, 27, 38)
        case .nord: return hex(46, 52, 64)
        case .catppuccin: return hex(30, 30, 46)
        }
    }
    static let surfaceAlt = NSColor(name: "ExplorerSurfaceAlt") { appearance in
        switch currentTheme {
        case .system:
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.17, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)
        case .slateCyan: return hex(40, 40, 42)
        case .tokyoNight: return hex(31, 35, 53)
        case .nord: return hex(53, 60, 74)
        case .catppuccin: return hex(36, 36, 54)
        }
    }
    static let inspector = NSColor(name: "ExplorerInspector") { appearance in
        switch currentTheme {
        case .system:
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.98, alpha: 1)
        case .slateCyan: return hex(41, 44, 48)
        case .tokyoNight: return hex(29, 32, 48)
        case .nord: return hex(50, 57, 70)
        case .catppuccin: return hex(34, 34, 52)
        }
    }
    static let line = NSColor(name: "ExplorerLine") { appearance in
        switch currentTheme {
        case .system:
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.26, alpha: 1) : hex(212, 222, 230)
        case .slateCyan: return hex(51, 56, 62)
        case .tokyoNight: return hex(47, 53, 73)
        case .nord: return hex(67, 76, 94)
        case .catppuccin: return hex(49, 50, 68)
        }
    }
    static let accent = NSColor(name: "ExplorerAccent") { _ in
        switch currentTheme {
        case .system: return .systemBlue
        case .slateCyan: return hex(30, 161, 224)
        case .tokyoNight: return hex(122, 162, 247)
        case .nord: return hex(136, 192, 208)
        case .catppuccin: return hex(137, 180, 250)
        }
    }
    static let groupText = NSColor(name: "ExplorerGroupText") { appearance in
        switch currentTheme {
        case .system:
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemBlue : hex(33, 82, 166)
        case .slateCyan: return hex(30, 161, 224)
        case .tokyoNight: return hex(122, 162, 247)
        case .nord: return hex(136, 192, 208)
        case .catppuccin: return hex(137, 180, 250)
        }
    }
    static let selected = NSColor(name: "ExplorerSelected") { _ in
        switch currentTheme {
        case .system: return NSColor.systemBlue.withAlphaComponent(0.14)
        case .slateCyan: return hex(0, 131, 196, a: 0.30)
        case .tokyoNight: return hex(122, 162, 247, a: 0.24)
        case .nord: return hex(136, 192, 208, a: 0.24)
        case .catppuccin: return hex(137, 180, 250, a: 0.24)
        }
    }
    static let folderIcon = makeFolderIcon()
    static func makeFolderIcon(tint: NSColor? = nil, symbol: String? = nil) -> NSImage {
      NSImage(size: NSSize(width: 64, height: 52), flipped: false) { _ in
        let back = NSBezierPath(roundedRect: NSRect(x: 3, y: 6, width: 58, height: 35), xRadius: 4, yRadius: 4)
        (tint?.blended(withFraction: 0.22, of: .black) ?? NSColor(calibratedRed: 0.90, green: 0.56, blue: 0.08, alpha: 1)).setFill(); back.fill()
        NSBezierPath(roundedRect: NSRect(x: 3, y: 30, width: 26, height: 17), xRadius: 4, yRadius: 4).fill()
        NSColor(calibratedWhite: 1, alpha: 0.92).setFill(); NSRect(x: 7, y: 29, width: 50, height: 7).fill()
        let front = NSBezierPath(roundedRect: NSRect(x: 3, y: 5, width: 58, height: 31), xRadius: 4, yRadius: 4)
        NSGradient(starting: tint?.blended(withFraction: 0.25, of: .white) ?? NSColor(calibratedRed: 1, green: 0.83, blue: 0.25, alpha: 1), ending: tint ?? NSColor(calibratedRed: 0.98, green: 0.68, blue: 0.08, alpha: 1))?.draw(in: front, angle: -90)
        if let symbol, !symbol.isEmpty,
           let baseGlyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)) {
            let glyphSize = baseGlyph.size
            let scale = min(1, min(22 / max(1, glyphSize.width), 17 / max(1, glyphSize.height)))
            let w = glyphSize.width * scale
            let h = glyphSize.height * scale
            let target = NSRect(x: 32 - w / 2, y: 20 - h / 2, width: w, height: h)
            let tintedGlyph = NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
                baseGlyph.draw(in: r)
                NSColor.black.withAlphaComponent(0.32).setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            tintedGlyph.draw(in: target)
        }
        return true
      }
    }
    static func symbol(_ name: String, size: CGFloat = 15) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }
    static func buttonSymbol(_ name: String, size: CGFloat = 15, canvas: CGFloat = 20) -> NSImage? {
        guard let symbol = symbol(name, size: size) else { return nil }
        // NSButtonCell crops configured SF Symbols to their font cap height on
        // some macOS versions. A template drawing preserves the complete symbol
        // and gives every toolbar icon the same, centered image box.
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { bounds in
            let scale = min(1, min(bounds.width / symbol.size.width, bounds.height / symbol.size.height))
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                  width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
class Surface: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }
    var border = false
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill(); bounds.fill()
        if border { let pixel = 1 / (window?.backingScaleFactor ?? 2); Palette.line.setFill(); NSRect(x: 0, y: bounds.height - pixel, width: bounds.width, height: pixel).fill() }
    }
    override var isFlipped: Bool { true }
}

@MainActor
class TitlebarSurface: Surface {
    // Only mouseDown on empty titlebar space explicitly starts a system drag.
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
}

@MainActor
final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var hovering = false
    var active = false { didSet { needsDisplay = true } }
    init(_ title: String = "", symbol: String? = nil, tooltip: String, maximumWidth: CGFloat? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title; self.toolTip = tooltip; self.actionBlock = action
        self.target = self; self.action = #selector(invoke)
        isBordered = false; bezelStyle = .regularSquare
        font = .systemFont(ofSize: 12)
        if let symbol { image = Palette.buttonSymbol(symbol) }
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        imageHugsTitle = true
        setAccessibilityLabel(title.isEmpty ? tooltip : title)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        if title.isEmpty { widthAnchor.constraint(equalToConstant: 32).isActive = true }
        else if let maximumWidth { widthAnchor.constraint(equalToConstant: min(intrinsicContentSize.width + 16, maximumWidth)).isActive = true }
        else { widthAnchor.constraint(greaterThanOrEqualToConstant: intrinsicContentSize.width + 16).isActive = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { actionBlock?() }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if active || (hovering && isEnabled) {
            (active ? Palette.selected : NSColor.labelColor.withAlphaComponent(0.055)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        super.draw(dirtyRect)
    }
}

@MainActor
final class FlatMenuButton: NSPopUpButton {
    override init(frame: NSRect, pullsDown flag: Bool) {
        super.init(frame: frame, pullsDown: flag)
        isBordered = false; bezelStyle = .regularSquare; font = .systemFont(ofSize: 12)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class ExplorerSplitView: NSSplitView {
    override var dividerColor: NSColor { Palette.line }
}

@MainActor
final class SidebarRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        Palette.selected.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 3, yRadius: 3).fill()
    }
}

@MainActor
final class FileRowView: NSTableRowView {
    var contentSeparator = false { didSet { needsDisplay = true } }
    var alternatingTint = false { didSet { needsDisplay = true } }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawBackground(in dirtyRect: NSRect) {
        let fill: NSColor
        if AppPreferences.shared.theme != .system && alternatingTint {
            fill = Palette.surfaceAlt
        } else {
            fill = Palette.surface
        }
        fill.setFill()
        dirtyRect.fill()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        Palette.selected.setFill(); bounds.fill()
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if contentSeparator {
            Palette.line.withAlphaComponent(0.65).setFill()
            NSRect(x: 14, y: isFlipped ? bounds.height - 0.5 : 0, width: max(0, bounds.width - 28), height: 0.5).fill()
        }
    }
}

@MainActor
final class BrowserTabView: FolderDropSurface {
    override var mouseDownCanMoveWindow: Bool { false }
    private let tabLabel = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private var closeButton: ActionButton!
    private var active = false
    let id: UUID
    weak var browser: BrowserViewController?
    private var pressPoint: NSPoint?
    var select: (() -> Void)?
    var close: (() -> Void)?
    init(id: UUID, title: String, active: Bool, select: @escaping () -> Void, close: @escaping () -> Void) {
        self.id = id; self.select = select; self.close = close
        super.init(frame: .zero)
        icon.image = Palette.symbol("folder.fill")
        icon.contentTintColor = .systemYellow
        tabLabel.lineBreakMode = .byTruncatingMiddle
        tabLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        closeButton = ActionButton(symbol: "xmark", tooltip: L10n.text("Close %1$@ tab", title), action: close)
        for child in [icon, tabLabel, closeButton!] { addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5), closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            tabLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9), tabLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            tabLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        registerForDraggedTypes([.fileURL, TabDragSession.pasteboardType])
        setAccessibilityElement(true); setAccessibilityRole(.button)
        update(title: title, active: active)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setOverviewIcon(_ overview: Bool) {
        icon.image = Palette.symbol(overview ? "desktopcomputer" : "folder.fill")
        icon.contentTintColor = overview ? .systemBlue : .systemYellow
    }
    func update(title: String, active: Bool) {
        self.active = active; tabLabel.stringValue = title; toolTip = title
        closeButton.toolTip = L10n.text("Close %1$@ tab", title); closeButton.setAccessibilityLabel(L10n.text("Close %1$@ tab", title))
        tabLabel.font = .systemFont(ofSize: 12, weight: active ? .semibold : .regular)
        tabLabel.textColor = active ? .labelColor : .secondaryLabelColor
        setAccessibilityLabel(L10n.text(active ? "%1$@ tab, selected" : "%1$@ tab", title)); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if active {
            NSGraphicsContext.saveGraphicsState(); bounds.clip()
            // Share the navigation row's fill and leave the bottom edge open
            // so the selected tab joins that surface without a border or seam.
            Palette.navigation.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height + 8), xRadius: 8, yRadius: 8).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === closeButton || hit.isDescendant(of: closeButton) ? hit : self
    }
    override func mouseDown(with event: NSEvent) {
        pressPoint = event.locationInWindow; select?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let pressPoint, let browser,
              hypot(event.locationInWindow.x - pressPoint.x, event.locationInWindow.y - pressPoint.y) >= 5 else { return }
        self.pressPoint = nil
        TabDragSession.begin(from: self, browser: browser, event: event)
    }
    override func mouseUp(with event: NSEvent) { pressPoint = nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.types?.contains(TabDragSession.pasteboardType) == true
            ? browser?.tabBar?.updateInsertion(sender) ?? [] : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { browser?.tabBar?.clearInsertion(); super.draggingExited(sender) }
    override func draggingEnded(_ sender: NSDraggingInfo) { browser?.tabBar?.clearInsertion(); super.draggingEnded(sender) }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(TabDragSession.pasteboardType) == true
            ? !(browser?.tabBar?.updateInsertion(sender).isEmpty ?? true) : super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(TabDragSession.pasteboardType) == true
            ? browser?.tabBar?.acceptTab(sender) ?? false : super.performDragOperation(sender)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let browser, let index = browser.tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let menu = NSMenu(); menu.autoenablesItems = false
        for (title, action, enabled) in [(L10n.text("Move Tab Left"), #selector(moveTabLeft), index > 0),
                                        (L10n.text("Move Tab Right"), #selector(moveTabRight), index < browser.tabs.count - 1),
                                        (L10n.text("Move Tab to New Window"), #selector(detach), true)] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
            item.isEnabled = enabled && browser.canTransferTabs; menu.addItem(item)
        }
        return menu
    }
    @objc private func moveTabLeft() {
        guard let browser, let index = browser.tabs.firstIndex(where: { $0.id == id }) else { return }
        browser.reorderTab(id: id, before: index - 1)
    }
    @objc private func moveTabRight() {
        guard let browser, let index = browser.tabs.firstIndex(where: { $0.id == id }) else { return }
        browser.reorderTab(id: id, before: index + 2)
    }
    @objc private func detach() { browser?.moveTabToNewWindow(id: id) }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { close?() } else { super.otherMouseDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { select?(); return true }
}

@MainActor
final class PathBar: Surface, NSTextFieldDelegate {
    var onNavigate: ((URL) -> Void)?
    var onCommit: ((String) -> Void)?
    private let crumbs = NSStackView()
    private let field = NSTextField()
    private var url = FileManager.default.homeDirectoryForCurrentUser
    private var editing = false
    private var searchResults: String?
    private let suggestions = PathSuggestionPopup()
    private(set) var suggestionTask: Task<Void, Never>?
    /// What the user typed, kept while arrow keys preview suggestions in the field.
    private var typedText = ""
    override init(frame: NSRect) {
        super.init(frame: frame)
        suggestions.onChoose = { [weak self] text in self?.chooseSuggestion(text) }
        color = Palette.surface; wantsLayer = true; layer?.cornerRadius = 5
        layer?.borderWidth = 0.5; layer?.borderColor = Palette.line.cgColor
        crumbs.orientation = .horizontal; crumbs.spacing = 0
        field.isBordered = false; field.drawsBackground = false; field.font = .systemFont(ofSize: 12)
        field.delegate = self; field.target = self; field.action = #selector(commit)
        field.setAccessibilityLabel(L10n.text("Folder path")); field.isHidden = true
        let edit = ActionButton(symbol: "pencil", tooltip: L10n.text("Edit folder path (⌘L)")) { [weak self] in self?.beginEditing() }
        for view in [crumbs, field, edit] { addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            edit.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2), edit.centerYAnchor.constraint(equalTo: centerYAnchor),
            crumbs.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7), crumbs.trailingAnchor.constraint(lessThanOrEqualTo: edit.leadingAnchor), crumbs.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), field.trailingAnchor.constraint(equalTo: edit.leadingAnchor, constant: -4), field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // Like Windows Explorer: a click on empty bar space (not on a crumb button) switches to the editable path.
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        if editing {
            super.mouseDown(with: event)
            return
        }
        beginEditing()
    }
    func refreshTheme() {
        color = Palette.surface
        layer?.borderColor = Palette.line.cgColor
        needsDisplay = true
    }
    func update(_ url: URL, searchResults: String? = nil) {
        self.searchResults = searchResults
        self.url = url; field.stringValue = BrowserLocation.isThisMac(url) ? L10n.text("This Mac") : url.path
        dismissSuggestions()
        editing = false; field.isHidden = true; crumbs.isHidden = false
        crumbs.arrangedSubviews.forEach { crumbs.removeArrangedSubview($0); $0.removeFromSuperview() }
        if let searchResults {
            let icon = NSImageView(image: Palette.symbol("magnifyingglass") ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            let label = NSTextField(labelWithString: L10n.text("Search Results in %1$@", searchResults))
            label.font = .systemFont(ofSize: 12); label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            crumbs.spacing = 9; crumbs.addArrangedSubview(icon); crumbs.addArrangedSubview(label)
            toolTip = L10n.text("Search Results in %1$@", url.path); return
        }
        crumbs.spacing = 0; toolTip = url.path
        if BrowserLocation.isThisMac(url) {
            crumbs.addArrangedSubview(ActionButton(L10n.text("This Mac"), symbol: "desktopcomputer", tooltip: L10n.text("Devices, drives and network locations")) { [weak self] in self?.onNavigate?(BrowserLocation.thisMac) })
            return
        }
        var chain: [URL] = []; var current = url.standardizedFileURL
        while current.path != "/" { chain.insert(current, at: 0); current.deleteLastPathComponent() }
        let root = ActionButton(symbol: "internaldrive", tooltip: "/") { [weak self] in self?.onNavigate?(URL(fileURLWithPath: "/")) }
        crumbs.addArrangedSubview(root)
        if chain.count > 4 {
            let ellipsis = ActionButton("…", tooltip: L10n.text("Edit full path")) { [weak self] in self?.beginEditing() }
            crumbs.addArrangedSubview(ellipsis); chain = Array(chain.suffix(4))
        }
        for component in chain {
            let chevron = NSImageView(image: Palette.symbol("chevron.right", size: 9) ?? NSImage())
            chevron.contentTintColor = .tertiaryLabelColor; crumbs.addArrangedSubview(chevron)
            let name = component.lastPathComponent
            let button = ActionButton(name, tooltip: component.path, maximumWidth: 140) { [weak self] in self?.onNavigate?(component) }
            button.lineBreakMode = .byTruncatingMiddle
            crumbs.addArrangedSubview(button)
        }
    }
    func beginEditing() {
        dismissSuggestions()
        editing = true; crumbs.isHidden = true; field.isHidden = false
        field.stringValue = BrowserLocation.isThisMac(url) ? L10n.text("This Mac") : url.path; typedText = field.stringValue
        // selectText(_:) would end the session makeFirstResponder just started, and ending it reverts to breadcrumbs.
        window?.makeFirstResponder(field); field.currentEditor()?.selectAll(nil)
    }
    @objc private func commit() {
        dismissSuggestions()
        let text = field.stringValue; window?.makeFirstResponder(nil)
        onCommit?(text)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            return moveSuggestionSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            return moveSuggestionSelection(by: -1)
        case #selector(NSResponder.insertTab(_:)):
            // Tab completes the highlighted (or first) folder, like Windows Explorer.
            guard suggestions.isVisible, let completion = suggestions.highlightedOrFirst else {
                return false
            }
            let completedPath = completion + "/"
            field.stringValue = completedPath; typedText = completedPath
            textView.selectedRange = NSRange(location: (completedPath as NSString).length, length: 0)
            refreshSuggestions()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // First Esc closes the list and restores what was typed; the next one leaves editing.
            if suggestions.isVisible {
                dismissSuggestions()
                field.stringValue = typedText
                return true
            }
            update(url, searchResults: searchResults); window?.makeFirstResponder(nil)
            return true
        default:
            return false
        }
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        // Keep the typed path until the commit action has handled Return.
        if let movement = obj.userInfo?["NSTextMovement"] as? Int, movement == NSReturnTextMovement {
            dismissSuggestions()
            return
        }
        if editing { update(url, searchResults: searchResults) }
    }
    func controlTextDidChange(_ obj: Notification) {
        typedText = field.stringValue
        refreshSuggestions()
    }
    private func refreshSuggestions() {
        dismissSuggestions()
        let text = typedText
        let base = url
        guard !text.isEmpty else { return }
        // Listing a slow network folder must not stall typing.
        suggestionTask = Task.detached(priority: .userInitiated) { [weak self] in
            let items = FolderPath.suggestions(for: text, relativeTo: base)
            guard !items.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self, self.editing, !Task.isCancelled else { return }
                self.suggestions.show(items, below: self)
            }
        }
    }
    private func dismissSuggestions() {
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestions.hide()
    }
    private func moveSuggestionSelection(by delta: Int) -> Bool {
        guard suggestions.isVisible else {
            return false
        }
        if let text = suggestions.moveSelection(by: delta) {
            field.stringValue = text
        } else {
            field.stringValue = typedText
        }
        field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        return true
    }
    private func chooseSuggestion(_ text: String) {
        field.stringValue = text
        commit()
    }
}

/// Windows Explorer-style folder list shown below the address bar while typing a path.
@MainActor
final class PathSuggestionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var onChoose: ((String) -> Void)?
    private var items: [String] = []
    private let rowHeight: CGFloat = 24
    private let maximumVisibleRows = 10
    private lazy var table: SuggestionTableView = {
        let table = SuggestionTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        table.addTableColumn(column); table.headerView = nil
        table.rowHeight = rowHeight; table.intercellSpacing = NSSize(width: 0, height: 0)
        table.style = .plain; table.backgroundColor = .clear; table.focusRingType = .none
        table.dataSource = self; table.delegate = self
        table.onClickRow = { [weak self] row in
            guard let self, self.items.indices.contains(row) else {
                return
            }
            self.onChoose?(self.items[row])
        }
        return table
    }()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = false; panel.hasShadow = true; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.becomesKeyOnlyIfNeeded = true; panel.hidesOnDeactivate = true
        let effect = NSVisualEffectView()
        effect.material = .menu; effect.state = .active; effect.wantsLayer = true
        effect.layer?.cornerRadius = 6; effect.layer?.masksToBounds = true
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.autohidesScrollers = true; scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        scroll.automaticallyAdjustsContentInsets = false
        effect.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: effect.topAnchor), scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        panel.contentView = effect
        return panel
    }()
    var isVisible: Bool { panel.isVisible }
    func show(_ items: [String], below anchor: NSView) {
        guard let window = anchor.window else {
            return
        }
        self.items = items
        table.reloadData(); table.deselectAll(nil); table.scrollRowToVisible(0)
        let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let height = CGFloat(min(items.count, maximumVisibleRows)) * rowHeight + 8
        panel.setFrame(NSRect(x: anchorRect.minX, y: anchorRect.minY - 2 - height, width: anchorRect.width, height: height), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }
    func hide() {
        guard panel.isVisible || panel.parent != nil else {
            return
        }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        items = []
    }
    /// Moves the highlighted row and returns its path, or nil when moving back above the first row.
    func moveSelection(by delta: Int) -> String? {
        let next = table.selectedRow + delta
        if next < 0 {
            table.deselectAll(nil)
            return nil
        }
        let row = min(next, items.count - 1)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        return items[row]
    }
    var highlightedOrFirst: String? {
        items.indices.contains(table.selectedRow) ? items[table.selectedRow] : items.first
    }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("suggestion")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView(); cell.identifier = id
            let icon = NSImageView(image: NSImage(named: NSImage.folderName) ?? NSImage())
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 12); label.lineBreakMode = .byTruncatingHead
            for view in [icon, label] as [NSView] { cell.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.imageView = icon; cell.textField = label
            return cell
        }()
        cell.textField?.stringValue = items[row]
        return cell
    }
}

/// Acts on a click immediately; the popup never becomes key, so the path field keeps typing focus.
@MainActor
final class SuggestionTableView: NSTableView {
    var onClickRow: ((Int) -> Void)?
    private var hoverArea: NSTrackingArea?
    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            onClickRow?(row)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseMoved(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && row != selectedRow {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class ExplorerTableHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        Palette.surface.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
        // Cover any trailing header space to the right of the last visible column
        // with the theme surface so custom themes never show a mismatched strip.
        if draggedColumn == -1, let tableView {
            let lastVisible = tableView.tableColumns.indices.reversed().first { !tableView.tableColumns[$0].isHidden }
            let trailingStart = lastVisible.map { headerRect(ofColumn: $0).maxX } ?? 0
            if trailingStart < bounds.maxX {
                let trailingRect = NSRect(x: trailingStart, y: bounds.minY, width: bounds.maxX - trailingStart, height: bounds.height)
                if trailingRect.intersects(dirtyRect) {
                    Palette.surface.setFill()
                    trailingRect.intersection(dirtyRect).fill()
                }
            }
        }
        let pixel = 1 / (window?.backingScaleFactor ?? 2)
        Palette.line.setFill()
        NSRect(x: dirtyRect.minX, y: bounds.maxY - pixel, width: dirtyRect.width, height: pixel).fill()
    }
}

@MainActor
final class CenteredTableHeaderCell: NSTableHeaderCell {
    private static let sortIndicatorWidth: CGFloat = 14
    private static let sortIndicatorTrailingMargin: CGFloat = 6
    private static let horizontalPadding: CGFloat = 6
    private static let sortIndicatorGap: CGFloat = 4

    override init(textCell string: String) {
        super.init(textCell: string)
        alignment = .center
        lineBreakMode = .byTruncatingTail
        font = .systemFont(ofSize: 11, weight: .medium)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        alignment = .center
        lineBreakMode = .byTruncatingTail
    }

    private func primarySortAscending(in controlView: NSView?) -> Bool? {
        guard let headerView = controlView as? NSTableHeaderView,
              let tableView = headerView.tableView,
              let descriptor = tableView.sortDescriptors.first,
              let primaryKey = descriptor.key,
              let column = tableView.tableColumns.first(where: { $0.headerCell === self }),
              column.sortDescriptorPrototype?.key == primaryKey else {
            return nil
        }
        return descriptor.ascending
    }

    private func isPrimarySorted(in controlView: NSView?) -> Bool {
        primarySortAscending(in: controlView) != nil
    }

    private func shouldDrawTrailingSeparator(in controlView: NSView?) -> Bool {
        guard let headerView = controlView as? NSTableHeaderView,
              let tableView = headerView.tableView else {
            return true
        }
        return tableView.tableColumns.last(where: { !$0.isHidden })?.headerCell !== self
    }

    private func styledTitle(sorted: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = lineBreakMode
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: sorted ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: stringValue, attributes: attributes)
    }

    override func sortIndicatorRect(forBounds theRect: NSRect) -> NSRect {
        let width = min(Self.sortIndicatorWidth, theRect.width)
        let x = max(theRect.minX, theRect.maxX - Self.sortIndicatorTrailingMargin - width)
        return NSRect(x: x, y: theRect.minY, width: width, height: theRect.height)
    }

    func centeredTitleRect(forBounds bounds: NSRect, sorted: Bool, scale: CGFloat = 2) -> NSRect {
        let title = styledTitle(sorted: sorted)
        let textSize = title.size()
        let leftLimit = bounds.minX + Self.horizontalPadding
        let rightLimit = sorted
            ? min(bounds.maxX - Self.horizontalPadding, sortIndicatorRect(forBounds: bounds).minX - Self.sortIndicatorGap)
            : bounds.maxX - Self.horizontalPadding
        let availableWidth = max(0, rightLimit - leftLimit)

        let naturalWidth = ceil(textSize.width)
        let centeredMinX = bounds.midX - naturalWidth / 2
        let centeredMaxX = bounds.midX + naturalWidth / 2

        let x: CGFloat
        let width: CGFloat
        if naturalWidth <= availableWidth && centeredMinX >= leftLimit && centeredMaxX <= rightLimit {
            x = bounds.minX + Self.horizontalPadding
            width = max(0, bounds.width - Self.horizontalPadding * 2)
        } else {
            x = leftLimit
            width = availableWidth
        }

        let textHeight = ceil(textSize.height)
        let rawY = bounds.minY + (bounds.height - textHeight) / 2
        let y = round(rawY * scale) / scale
        return NSRect(x: x, y: y, width: width, height: min(textHeight, bounds.height))
    }

    override func titleRect(forBounds theRect: NSRect) -> NSRect {
        centeredTitleRect(forBounds: theRect, sorted: false)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Palette.surface.setFill()
        cellFrame.fill()

        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            cellFrame.fill()
        }

        let scale = controlView.window?.backingScaleFactor ?? 2
        let pixel = 1 / scale

        if shouldDrawTrailingSeparator(in: controlView) {
            Palette.line.withAlphaComponent(0.8).setFill()
            let insetY: CGFloat = 5
            let sepHeight = max(0, cellFrame.height - insetY * 2)
            NSRect(x: cellFrame.maxX - pixel, y: cellFrame.minY + insetY, width: pixel, height: sepHeight).fill()
        }

        Palette.line.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - pixel, width: cellFrame.width, height: pixel).fill()

        drawInterior(withFrame: cellFrame, in: controlView)
        if let ascending = primarySortAscending(in: controlView) {
            drawSortIndicator(withFrame: cellFrame, in: controlView, ascending: ascending, priority: 0)
        }
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let sorted = isPrimarySorted(in: controlView)
        let scale = controlView.window?.backingScaleFactor ?? 2
        let rect = centeredTitleRect(forBounds: cellFrame, sorted: sorted, scale: scale)
        guard rect.width > 0, rect.height > 0 else { return }
        styledTitle(sorted: sorted).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func drawSortIndicator(withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int) {
        guard priority == 0 else { return }
        let indicatorRect = sortIndicatorRect(forBounds: cellFrame)
        let symbolName = ascending ? "chevron.up" : "chevron.down"
        let config = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
            .applying(.init(paletteColors: [.secondaryLabelColor]))
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            super.drawSortIndicator(withFrame: cellFrame, in: controlView, ascending: ascending, priority: priority)
            return
        }
        let scale = controlView.window?.backingScaleFactor ?? 2
        let size = symbol.size
        let drawX = round((indicatorRect.midX - size.width / 2) * scale) / scale
        let drawY = round((indicatorRect.midY - size.height / 2) * scale) / scale
        let target = NSRect(x: drawX, y: drawY, width: size.width, height: size.height)
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor
final class FileTableView: NSTableView {
    var onOpen: (() -> Void)?
    var onBack: (() -> Void)?
    var onPreview: (() -> Void)?
    var onFileAction: ((FileAction) -> Void)?
    var canFileAction: ((FileAction) -> Bool)?
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        // Folder links act on the clicked result without first selecting its row.
        if responder is FolderLocationLink { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }
    @objc func cut(_ sender: Any?) { onFileAction?(.cut) }
    @objc func copy(_ sender: Any?) { onFileAction?(.copy) }
    @objc func paste(_ sender: Any?) { onFileAction?(.paste) }
    @objc func undo(_ sender: Any?) { onFileAction?(.undo) }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let actions: [Selector: FileAction] = [#selector(cut): .cut, #selector(copy(_:)): .copy, #selector(paste): .paste, #selector(undo): .undo]
        if let action = item.action, let fileAction = actions[action] {
            if fileAction == .undo, let menu = item as? NSMenuItem {
                menu.title = FileOperationController.shared.undoTitle.map { L10n.text("Undo %1$@", $0) } ?? L10n.text("Undo")
            }
            return canFileAction?(fileAction) == true
        }
        return true
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 36 || event.keyCode == 76 { onOpen?(); return }
            if event.keyCode == 51 { onBack?(); return }
            if event.keyCode == 49 { onPreview?(); return }
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var opening: Task<Void, Never>?
    private(set) var needsRetry = false
    init(url: URL, changed: @escaping @MainActor () -> Void) {
        let startedAt = Date()
        // Opening a protected or unavailable network directory can wait inside the kernel.
        // Never let that prevent the window (or a macOS access prompt) from appearing.
        opening = Task { [weak self] in
            let result: (fd: Int32, modifiedAfterStart: Bool) = await Task.detached(priority: .utility) {
                let fd = open(url.path, O_EVTONLY | O_NONBLOCK | O_CLOEXEC)
                guard fd >= 0 else { return (-1, false) }
                var st = stat()
                var changedWhileOpening = false
                if fstat(fd, &st) == 0 {
                    let mod = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000)
                    changedWhileOpening = mod > startedAt
                }
                return (fd, changedWhileOpening)
            }.value
            guard let self, !Task.isCancelled else { if result.fd >= 0 { close(result.fd) }; return }
            guard result.fd >= 0 else { self.needsRetry = true; return }
            let fd = result.fd
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .attrib, .revoke], queue: .main)
            source.setEventHandler { [weak self, weak source] in
                MainActor.assumeIsolated {
                    let flags = source?.data ?? []
                    if flags.contains(.delete) || flags.contains(.revoke) || flags.contains(.rename) {
                        self?.source?.cancel()
                        self?.source = nil
                        self?.needsRetry = true
                    }
                    changed()
                }
            }
            source.setCancelHandler { close(fd) }
            self.source = source; source.resume()
            if result.modifiedAfterStart {
                changed() // Reconcile only if the directory actually changed while attaching.
            }
        }
    }
    func waitUntilReady() async { await opening?.value }
    deinit { opening?.cancel(); source?.cancel() }
}
