import AppKit
import CoreServices
import ExplorerCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
private final class SettingsWindow: NSWindow {
    weak var recorder: ShortcutRecorder?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recorder?.isRecording == true { recorder?.capture(event); return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class SettingsPageController: NSViewController {
    var onDisappear: (() -> Void)?
    override func viewWillDisappear() { super.viewWillDisappear(); onDisappear?() }
}

@MainActor
final class ShortcutRecorder: NSButton {
    private(set) var isRecording = false
    var onBegin: (() -> Void)?
    var onFinish: ((LaunchShortcut?) -> Void)?
    var onInvalid: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded; font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        target = self; action = #selector(begin)
        setAccessibilityLabel(L10n.text("Record global shortcut"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func begin() {
        guard !isRecording else { return }
        onBegin?(); isRecording = true; title = L10n.text("Press shortcut…")
        window?.makeFirstResponder(self)
    }
    func cancel() {
        guard isRecording else { return }
        isRecording = false; onFinish?(nil)
    }
    func capture(_ event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 { cancel(); return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let shortcut = LaunchShortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue,
                                      character: (event.charactersIgnoringModifiers ?? "").uppercased())
        guard shortcut.isValid else { onInvalid?(); return }
        isRecording = false; onFinish?(shortcut)
    }
    override func keyDown(with event: NSEvent) {
        if isRecording { capture(event) } else { super.keyDown(with: event) }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: AppPreferences
    private let shortcutController: GlobalShortcutController
    private let recorder = ShortcutRecorder()
    private let shortcutEnabled = NSButton(checkboxWithTitle: L10n.text("Enable global shortcut"), target: nil, action: nil)
    private let shortcutStatus = NSTextField(wrappingLabelWithString: "")
    private let launchAtLogin = NSButton(checkboxWithTitle: L10n.text("Open Explorer at login"), target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let loginSettings = NSButton(title: L10n.text("Open Login Items Settings…"), target: nil, action: nil)
    private let hidden = NSButton(checkboxWithTitle: L10n.text("Show hidden files and folders"), target: nil, action: nil)
    private let languages = InterfaceLanguage.available
    private let language = NSPopUpButton()
    var onLanguageRestart: (() -> Void)? { didSet { refreshLanguage() } }
    private let languageRestart = NSButton(title: L10n.text("Apply and Restart"), target: nil, action: nil)
    private let languageInstall = NSButton(title: L10n.text("Install Language Packs…"), target: nil, action: nil)
    private let languageRestartControls = NSStackView()
    private let languageRestartNote = NSTextField(wrappingLabelWithString: L10n.text("Quit and reopen Explorer to apply the language change."))
    private let startup = NSPopUpButton(), appearance = NSPopUpButton(), theme = NSPopUpButton(), viewMode = NSPopUpButton(), scope = NSPopUpButton(), shortcutAction = NSPopUpButton()
    private let previewPane = NSButton(checkboxWithTitle: L10n.text("Show preview & inspector panel"), target: nil, action: nil)
    private let calculateFolderSizes = NSButton(checkboxWithTitle: L10n.text("Calculate folder sizes in background"), target: nil, action: nil)
    private let editFolderRulesButton = NSButton(title: L10n.text("Edit Folder Rules…"), target: nil, action: nil)
    private let reloadFolderRulesButton = NSButton(title: L10n.text("Reload"), target: nil, action: nil)
    private let folderRulesStatus = NSTextField(labelWithString: "")
    private let terminalApplication = NSPopUpButton(), editorApplication = NSPopUpButton()
    private let folderDefaultButton = NSButton(title: L10n.text("Set as Default…"), target: nil, action: nil)
    private let folderDefaultStatus = NSTextField(wrappingLabelWithString: "")
    private var changingFolderDefault = false
    private var folderDefaultFailure: String?

    init(preferences: AppPreferences = .shared, shortcutController: GlobalShortcutController) {
        self.preferences = preferences; self.shortcutController = shortcutController
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 540),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L10n.text("Explorer Settings"); window.isReleasedWhenClosed = false
        window.delegate = self; window.recorder = recorder; window.setFrameAutosaveName("Explorer.Settings")
        let tabs = NSTabViewController(); tabs.tabStyle = .toolbar
        let general = NSViewController(); general.view = generalView()
        let keyboard = SettingsPageController(); keyboard.view = keyboardView()
        keyboard.onDisappear = { [weak self] in self?.recorder.cancel() }
        let applications = NSViewController(); applications.view = applicationsView()
        for (controller, title, symbol) in [(general, L10n.text("General"), "gearshape"), (applications, L10n.text("Applications"), "app.badge"), (keyboard, L10n.text("Shortcut"), "keyboard")] {
            let item = NSTabViewItem(viewController: controller); item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); tabs.addTabViewItem(item)
        }
        tabs.preferredContentSize = NSSize(width: 590, height: 540)
        window.contentViewController = tabs; window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: AppPreferences.changed, object: preferences)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: FolderRulesStore.changed, object: FolderRulesStore.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didBecomeActiveNotification, object: nil)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func page(_ title: String, subtitle: String, content: [NSView]) -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 590, height: 540))
        let heading = NSTextField(labelWithString: title); heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let caption = note(subtitle)
        let stack = NSStackView(views: [heading, caption] + content)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.setCustomSpacing(5, after: heading); stack.setCustomSpacing(24, after: caption)
        root.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
                                     stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
                                     stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 25)])
        for child in stack.arrangedSubviews { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return root
    }
    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor; return label
    }
    private func row(_ title: String, control: NSView) -> NSView {
        let label = NSTextField(wrappingLabelWithString: title); label.font = .systemFont(ofSize: 13)
        label.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let stack = NSStackView(views: [label, control]); stack.orientation = .horizontal; stack.spacing = 14
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }
    private func popup(_ popup: NSPopUpButton, titles: [String], action: Selector, label: String) {
        popup.addItems(withTitles: titles); popup.target = self; popup.action = action
        popup.setAccessibilityLabel(label)
    }
    private func generalView() -> NSView {
        popup(language, titles: [L10n.text("Automatic (macOS)")] + languages.map(\.title),
              action: #selector(languageChanged), label: L10n.text("Interface language"))
        languageRestart.bezelStyle = .rounded
        languageRestart.target = self; languageRestart.action = #selector(applyLanguage)
        languageInstall.bezelStyle = .rounded
        languageInstall.target = self; languageInstall.action = #selector(chooseLanguagePacks)
        languageRestartControls.addArrangedSubview(languageInstall)
        languageRestartControls.addArrangedSubview(languageRestart)
        languageRestartControls.addArrangedSubview(NSView())
        languageRestartNote.font = .systemFont(ofSize: 12)
        languageRestartNote.textColor = .secondaryLabelColor
        popup(startup, titles: StartupLocation.allCases.map(\.title), action: #selector(startupChanged), label: L10n.text("Open new windows to"))
        popup(appearance, titles: AppAppearance.allCases.map(\.title), action: #selector(appearanceChanged), label: L10n.text("Appearance"))
        popup(theme, titles: AppTheme.allCases.map(\.title), action: #selector(themeChanged), label: L10n.text("Color theme"))
        popup(viewMode, titles: FileViewMode.allCases.map(\.title), action: #selector(viewChanged), label: L10n.text("Default folder view"))
        popup(scope, titles: [L10n.text("Current folder"), L10n.text("All subfolders")], action: #selector(scopeChanged), label: L10n.text("Default search scope"))
        hidden.target = self; hidden.action = #selector(hiddenChanged)
        previewPane.target = self; previewPane.action = #selector(previewPaneChanged)
        calculateFolderSizes.target = self; calculateFolderSizes.action = #selector(calculateFolderSizesChanged)
        editFolderRulesButton.bezelStyle = .rounded; editFolderRulesButton.target = self; editFolderRulesButton.action = #selector(editFolderRules)
        reloadFolderRulesButton.bezelStyle = .rounded; reloadFolderRulesButton.target = self; reloadFolderRulesButton.action = #selector(reloadFolderRules)
        folderRulesStatus.font = .systemFont(ofSize: 11); folderRulesStatus.textColor = .secondaryLabelColor
        let folderRulesRow = NSStackView(views: [editFolderRulesButton, reloadFolderRulesButton, folderRulesStatus])
        folderRulesRow.orientation = .horizontal; folderRulesRow.spacing = 8; folderRulesRow.alignment = .centerY
        launchAtLogin.target = self; launchAtLogin.action = #selector(loginChanged)
        launchAtLogin.isEnabled = !DemoData.active
        loginStatus.font = .systemFont(ofSize: 12); loginStatus.textColor = .secondaryLabelColor
        loginSettings.bezelStyle = .rounded; loginSettings.target = self; loginSettings.action = #selector(openLoginSettings)
        return page(L10n.text("Make Explorer yours"), subtitle: L10n.text("Changes are saved automatically."), content: [
            row(L10n.text("Open new windows to"), control: startup), row(L10n.text("Color theme"), control: theme), row(L10n.text("Appearance"), control: appearance),
            row(L10n.text("Default folder view"), control: viewMode), row(L10n.text("Default search scope"), control: scope),
            row(L10n.text("Interface language"), control: language), languageRestartControls, languageRestartNote,
            row(L10n.text("Folder icon rules"), control: folderRulesRow),
            hidden, previewPane, calculateFolderSizes, note(L10n.text("View and search defaults apply to new tabs. Existing tabs keep their layout; the View menu also updates the folder-view default.")),
            launchAtLogin, loginStatus, loginSettings
        ])
    }
    private func keyboardView() -> NSView {
        shortcutEnabled.target = self; shortcutEnabled.action = #selector(enabledChanged)
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 155).isActive = true
        recorder.onBegin = { [weak self] in
            try? self?.shortcutController.apply(nil)
            self?.showShortcutStatus(L10n.text("Press Command, Control, or Option plus a letter or number. Escape cancels."))
        }
        recorder.onFinish = { [weak self] binding in self?.finishRecording(binding) }
        recorder.onInvalid = { [weak self] in self?.showShortcutStatus(ShortcutError.invalid.localizedDescription, error: true) }
        let reset = NSButton(title: L10n.text("Use ⌘E"), target: self, action: #selector(resetShortcut)); reset.bezelStyle = .rounded
        let controls = NSStackView(views: [recorder, reset]); controls.orientation = .horizontal; controls.spacing = 10
        popup(shortcutAction, titles: [L10n.text("Show existing window"), L10n.text("Open a new window")], action: #selector(shortcutActionChanged), label: L10n.text("Shortcut action"))
        shortcutStatus.font = .systemFont(ofSize: 12); shortcutStatus.textColor = .secondaryLabelColor
        return page(L10n.text("Explorer, one shortcut away"), subtitle: L10n.text("Open Explorer from any app, like Windows + E."), content: [
            shortcutEnabled, row(L10n.text("Keyboard shortcut"), control: controls), row(L10n.text("When pressed"), control: shortcutAction),
            shortcutStatus,
            note(L10n.text("Click the shortcut to record a new combination. While enabled, it takes precedence over the same shortcut in other apps.")),
            note(L10n.text("Explorer must be running. Closing all browser windows keeps the shortcut available; quitting Explorer disables it until the next launch. Enable Open Explorer at login in General to make it available after signing in."))
        ])
    }
    private func applicationsView() -> NSView {
        terminalApplication.target = self; terminalApplication.action = #selector(applicationChanged(_:)); terminalApplication.tag = 0
        editorApplication.target = self; editorApplication.action = #selector(applicationChanged(_:)); editorApplication.tag = 1
        terminalApplication.setAccessibilityLabel(L10n.text("Preferred terminal application"))
        editorApplication.setAccessibilityLabel(L10n.text("Preferred text editor"))
        folderDefaultButton.bezelStyle = .rounded
        folderDefaultButton.target = self; folderDefaultButton.action = #selector(changeFolderDefault)
        folderDefaultStatus.font = .systemFont(ofSize: 12); folderDefaultStatus.textColor = .secondaryLabelColor
        let folderDefaultControls = NSStackView(views: [folderDefaultButton, NSView()])
        return page(L10n.text("Open with your favorite apps"), subtitle: L10n.text("Choose your folder, terminal, and editor apps."), content: [
            row(L10n.text("Default app for folders"), control: folderDefaultControls),
            folderDefaultStatus,
            note(L10n.text("This applies when an app opens a folder using the macOS default. Reveal in Finder still opens Finder.")),
            row(L10n.text("Terminal"), control: terminalApplication),
            note(L10n.text("Open a folder in Terminal, iTerm2, or another terminal that supports opening folders. Right-click empty space to use the current folder.")),
            row(L10n.text("Text editor"), control: editorApplication),
            note(L10n.text("Open text, code, JSON, YAML, and configuration files in your preferred editor. Unrecognized files offer Open as Text.")),
            note(L10n.text("These choices apply only to Explorer’s terminal and editor actions. Double-click and Open continue to use macOS file associations."))
        ])
    }
    @discardableResult private func refreshFolderDefault() -> String? {
        let current = NSWorkspace.shared.urlForApplication(toOpen: UTType.folder)
        let identifier = current.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let isExplorer = identifier.map { $0 == Bundle.main.bundleIdentifier } ?? false
        folderDefaultButton.title = isExplorer ? L10n.text("Use Finder…") : L10n.text("Set as Default…")
        folderDefaultButton.isEnabled = !changingFolderDefault && Bundle.main.bundleURL.pathExtension == "app"
        let status = current.map {
            L10n.text("%1$@ currently opens folders by default.", ExternalApplications.name(of: $0))
        } ?? L10n.text("macOS did not report a default app for folders.")
        folderDefaultStatus.stringValue = [status, folderDefaultFailure].compactMap { $0 }.joined(separator: "\n")
        return identifier
    }
    @objc private func changeFolderDefault() {
        guard !changingFolderDefault, let explorerID = Bundle.main.bundleIdentifier else { return }
        let workspace = NSWorkspace.shared
        let isExplorer = refreshFolderDefault() == explorerID
        let targetID = isExplorer ? "com.apple.finder" : explorerID
        guard let target = isExplorer ? workspace.urlForApplication(withBundleIdentifier: targetID) : Bundle.main.bundleURL else {
            folderDefaultFailure = L10n.text("Finder is unavailable.")
            refreshFolderDefault()
            return
        }

        changingFolderDefault = true
        folderDefaultFailure = nil
        refreshFolderDefault()
        Task {
            defer {
                changingFolderDefault = false
                refreshFolderDefault()
            }
            do {
                try await workspace.setDefaultApplication(at: target, toOpen: .folder)
                if refreshFolderDefault() != targetID {
                    folderDefaultFailure = L10n.text("macOS did not apply the change.")
                }
            } catch {
                let error = error as NSError
                let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError ?? error
                switch (underlying.domain, underlying.code) {
                case (NSCocoaErrorDomain, NSUserCancelledError), (NSOSStatusErrorDomain, Int(userCanceledErr)):
                    break
                case (NSOSStatusErrorDomain, Int(kLSUnknownTypeErr)), (NSOSStatusErrorDomain, Int(paramErr)):
                    folderDefaultFailure = L10n.text("macOS rejected the request to change the default app for folders.")
                default:
                    folderDefaultFailure = L10n.text("Couldn’t change the default folder app. %1$@", error.localizedDescription)
                }
            }
        }
    }
    private func refreshApplications() {
        for (role, popup) in [(ExternalApplicationRole.terminal, terminalApplication), (.editor, editorApplication)] {
            popup.removeAllItems()
            popup.addItem(withTitle: L10n.text("%1$@ (default)", role.defaultName))
            let selected = ExternalApplications.choice(for: role, preferences: preferences)
            var choices = role.installedCandidates.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            if let selected {
                let url = selected.resolvedURL ?? URL(fileURLWithPath: selected.path)
                if !choices.contains(url) { choices.append(url) }
            }
            var seen = Set<String>()
            for url in choices where seen.insert(url.path).inserted {
                let choice = ApplicationChoice(url: url)
                let isSelected = selected.map { $0.resolvedURL == url || $0.path == url.path } ?? false
                let missing = !ApplicationChoice.isApplication(url)
                popup.addItem(withTitle: ExternalApplications.name(of: url) + (missing ? L10n.text(" (not found)") : ""))
                popup.lastItem?.representedObject = isSelected ? (selected ?? choice) : choice
                if isSelected { popup.select(popup.lastItem) }
            }
            popup.menu?.addItem(.separator())
            popup.addItem(withTitle: L10n.text("Choose Application…")); popup.lastItem?.tag = 999
        }
    }
    @objc private func applicationChanged(_ sender: NSPopUpButton) {
        let role: ExternalApplicationRole = sender.tag == 0 ? .terminal : .editor
        guard sender.selectedItem?.tag == 999 else {
            setApplication(sender.selectedItem?.representedObject as? ApplicationChoice, role: role); return
        }
        refreshApplications()
        guard let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = L10n.text("Choose"); panel.message = role == .terminal ? L10n.text("Choose your terminal application.") : L10n.text("Choose your text editor.")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard ApplicationChoice.isApplication(url), Bundle(url: url)?.bundleIdentifier != Bundle.main.bundleIdentifier else {
                DispatchQueue.main.async { ExternalApplications.showError(L10n.text("Choose a terminal or text editor application other than Explorer."), window: window) }
                return
            }
            self?.setApplication(ApplicationChoice(url: url), role: role)
        }
    }
    private func setApplication(_ choice: ApplicationChoice?, role: ExternalApplicationRole) {
        if role == .terminal { preferences.terminalApplication = choice }
        else { preferences.editorApplication = choice }
    }
    @objc private func refresh() {
        refreshLanguage()
        startup.selectItem(at: StartupLocation.allCases.firstIndex(of: preferences.startupLocation) ?? 0)
        theme.selectItem(at: AppTheme.allCases.firstIndex(of: preferences.theme) ?? 0)
        appearance.selectItem(at: AppAppearance.allCases.firstIndex(of: preferences.appearance) ?? 0)
        appearance.isEnabled = !preferences.theme.forcesDarkAppearance
        viewMode.selectItem(at: FileViewMode.allCases.firstIndex(of: preferences.viewMode) ?? 0)
        scope.selectItem(at: preferences.searchScope == .folder ? 0 : 1)
        hidden.state = preferences.showHidden ? .on : .off
        previewPane.state = preferences.showPreviewPane ? .on : .off
        calculateFolderSizes.state = preferences.calculateFolderSizes ? .on : .off
        shortcutEnabled.state = preferences.shortcutEnabled ? .on : .off
        shortcutAction.selectItem(at: preferences.shortcutOpensNewWindow ? 1 : 0)
        if !recorder.isRecording { recorder.title = preferences.shortcut.title; updateShortcutStatus() }
        refreshLoginStatus()
        refreshFolderRulesStatus()
        refreshApplications()
        refreshFolderDefault()
    }
    private func refreshFolderRulesStatus() {
        let store = FolderRulesStore.shared
        if let err = store.lastError {
            folderRulesStatus.stringValue = L10n.text("Invalid JSON: %1$@", err)
            folderRulesStatus.textColor = .systemRed
        } else if store.ruleCount == 0 {
            folderRulesStatus.stringValue = "~/.config/explorer/folder-rules.json"
            folderRulesStatus.textColor = .secondaryLabelColor
        } else {
            folderRulesStatus.stringValue = "\(store.ruleCount) rules active"
            folderRulesStatus.textColor = .secondaryLabelColor
        }
    }
    @objc private func editFolderRules() {
        do {
            try FolderRulesStore.shared.ensureConfigFileExists()
            FolderRulesStore.shared.reload()
            ExternalApplications.openEditor(files: [FolderRulesStore.shared.configURL], window: window)
        } catch {
            ExternalApplications.showError(error.localizedDescription, window: window)
        }
    }
    @objc private func reloadFolderRules() {
        FolderRulesStore.shared.reload()
        refreshFolderRulesStatus()
    }
    private func refreshLoginStatus() {
        let state = SMAppService.mainApp.status
        launchAtLogin.state = state == .enabled || state == .requiresApproval ? .on : .off
        loginSettings.isHidden = state != .requiresApproval
        switch state {
        case .enabled: loginStatus.stringValue = L10n.text("Explorer will open when you sign in.")
        case .requiresApproval: loginStatus.stringValue = L10n.text("Allow Explorer in macOS Login Items to finish enabling this.")
        case .notRegistered: loginStatus.stringValue = L10n.text("Off. Enable to have the global shortcut ready after login.")
        case .notFound: loginStatus.stringValue = L10n.text("Off. Enable to register this copy of Explorer for login.")
        @unknown default: loginStatus.stringValue = L10n.text("Login status is unavailable.")
        }
    }
    private func showShortcutStatus(_ text: String, error: Bool = false) {
        shortcutStatus.stringValue = text; shortcutStatus.textColor = error ? .systemRed : .secondaryLabelColor
    }
    private func updateShortcutStatus() {
        if !preferences.shortcutEnabled { showShortcutStatus(L10n.text("Global shortcut is off.")) }
        else if shortcutController.activeShortcut == preferences.shortcut { showShortcutStatus(L10n.text("%1$@ is ready to open Explorer.", preferences.shortcut.title)) }
        else { showShortcutStatus(L10n.text("The shortcut is unavailable. Choose another combination or turn it off and on to retry."), error: true) }
    }
    private func finishRecording(_ binding: LaunchShortcut?) {
        do {
            try shortcutController.apply(preferences.shortcutEnabled ? (binding ?? preferences.shortcut) : nil)
            if let binding { preferences.shortcut = binding }
            recorder.title = preferences.shortcut.title; updateShortcutStatus()
        } catch {
            let message = error.localizedDescription
            // Recording temporarily releases the old key; restore it on failure/cancel.
            try? shortcutController.apply(preferences.shortcutEnabled ? preferences.shortcut : nil)
            recorder.title = preferences.shortcut.title
            showShortcutStatus(message + (shortcutController.activeShortcut != nil ? L10n.text(" Your previous shortcut is still active.") : ""), error: true)
        }
    }
    @objc private func enabledChanged() {
        recorder.cancel()
        do {
            let enabled = shortcutEnabled.state == .on
            try shortcutController.apply(enabled ? preferences.shortcut : nil)
            preferences.shortcutEnabled = enabled; updateShortcutStatus()
        } catch {
            shortcutEnabled.state = preferences.shortcutEnabled ? .on : .off
            showShortcutStatus(error.localizedDescription, error: true)
        }
    }
    @objc private func resetShortcut() { recorder.cancel(); finishRecording(.defaultShortcut) }
    private func refreshLanguage() {
        let selection = preferences.interfaceLanguage
        language.selectItem(at: selection.flatMap { languages.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        let languageChanged = InterfaceLanguage.resolve(selection) != L10n.current.language
        languageRestart.isHidden = !languageChanged || onLanguageRestart == nil
        languageRestartNote.isHidden = !languageChanged || onLanguageRestart != nil
    }
    @objc private func languageChanged() {
        let index = language.indexOfSelectedItem
        guard (0...languages.count).contains(index) else { return }
        preferences.interfaceLanguage = index == 0 ? nil : languages[index - 1]
        refreshLanguage()
    }
    @objc private func chooseLanguagePacks() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.message = L10n.text("Choose a language pack folder or a folder containing language packs.")
        panel.prompt = L10n.text("Choose")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.installLanguagePacks(from: url)
        }
    }

    private func installLanguagePacks(from url: URL, replacing confirmed: Set<String> = []) {
        guard let window else { return }
        let alert = NSAlert()
        do {
            if try LocalizationCatalog.install(from: url, replacing: confirmed) {
                alert.messageText = L10n.text("Language packs installed")
                alert.informativeText = L10n.text("Quit and reopen Explorer to apply the language change.")
                if onLanguageRestart != nil {
                    alert.addButton(withTitle: L10n.text("Apply and Restart"))
                    alert.addButton(withTitle: L10n.text("Keep Explorer Open"))
                    alert.beginSheetModal(for: window) { [weak self] response in
                        if response == .alertFirstButtonReturn { self?.onLanguageRestart?() }
                    }
                    return
                }
            } else {
                alert.messageText = L10n.text("No language packs found")
                alert.informativeText = L10n.text("Choose a language pack folder or a folder containing language packs.")
            }
        } catch let replacement as LocalizationCatalog.ReplacementRequired {
            confirmLanguagePackReplacement(replacement.identifiers, from: url, replacing: confirmed, in: window)
            return
        } catch {
            alert.messageText = L10n.text("Couldn’t Install Language Packs")
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: L10n.text("OK"))
        alert.beginSheetModal(for: window)
    }

    private func confirmLanguagePackReplacement(_ identifiers: [String], from url: URL,
                                                replacing confirmed: Set<String>, in window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("Replace installed language packs?")
        let languages = identifiers.map { "\(InterfaceLanguage(identifier: $0).title) (\($0))" }.joined(separator: "\n")
        alert.informativeText = L10n.text("This will replace the installed copies and their custom translations.\n\n%1$@", languages)
        let cancel = alert.addButton(withTitle: L10n.text("Cancel"))
        cancel.keyEquivalent = "\u{1b}"
        let replace = alert.addButton(withTitle: L10n.text("Replace and Install"))
        replace.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn else { return }
            self?.installLanguagePacks(from: url, replacing: confirmed.union(identifiers))
        }
    }

    @objc private func applyLanguage() { onLanguageRestart?() }
    @objc private func startupChanged() { preferences.startupLocation = StartupLocation.allCases[startup.indexOfSelectedItem] }
    @objc private func themeChanged() { preferences.theme = AppTheme.allCases[theme.indexOfSelectedItem] }
    @objc private func appearanceChanged() { preferences.appearance = AppAppearance.allCases[appearance.indexOfSelectedItem] }
    @objc private func viewChanged() { preferences.viewMode = FileViewMode.allCases[viewMode.indexOfSelectedItem] }
    @objc private func scopeChanged() { preferences.searchScope = scope.indexOfSelectedItem == 0 ? .folder : .subfolders }
    @objc private func hiddenChanged() { preferences.showHidden = hidden.state == .on }
    @objc private func previewPaneChanged() { preferences.showPreviewPane = previewPane.state == .on }
    @objc private func calculateFolderSizesChanged() { preferences.calculateFolderSizes = calculateFolderSizes.state == .on }
    @objc private func shortcutActionChanged() { preferences.shortcutOpensNewWindow = shortcutAction.indexOfSelectedItem == 1 }
    @objc private func loginChanged() {
        do {
            if launchAtLogin.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus(); loginStatus.stringValue = L10n.text("Could not update login settings: %1$@", error.localizedDescription)
        }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func windowWillClose(_ notification: Notification) { recorder.cancel() }
    func windowDidResignKey(_ notification: Notification) { recorder.cancel() }
}
