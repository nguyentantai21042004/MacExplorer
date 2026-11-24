import AppKit
import ExplorerCore

@MainActor
enum VolumeActions {
    private static let recentServersKey = "explorer.recentServers"
    private static let maxRecentServers = 10

    static var recentServers: [String] {
        UserDefaults.standard.stringArray(forKey: recentServersKey) ?? []
    }

    static func recordRecentServer(_ address: String) {
        var list = recentServers.filter { $0.caseInsensitiveCompare(address) != .orderedSame }
        list.insert(address, at: 0)
        if list.count > maxRecentServers { list = Array(list.prefix(maxRecentServers)) }
        UserDefaults.standard.set(list, forKey: recentServersKey)
    }

    static func eject(_ location: StorageLocation, window: NSWindow?) {
        guard location.isEjectable else { return }
        let targetURL = location.url
        let name = location.title
        Task { @MainActor in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: targetURL)
                }.value
                StorageStore.shared.refresh()
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn’t Eject “\(name)”"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L10n.text("OK"))
                if let window, window.attachedSheet == nil { _ = await alert.beginSheetModal(for: window) }
                else { alert.runModal() }
            }
        }
    }

    static func showConnectToServer(window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Connect to Server"
        alert.informativeText = "Enter a server address (smb://, nfs://, afp://, webdav://, or https://). macOS will handle credentials and mount the share."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: L10n.text("Cancel"))

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.frame = NSRect(x: 0, y: 0, width: 340, height: recentServers.isEmpty ? 30 : 62)

        let field = NSTextField(string: recentServers.first ?? "")
        field.placeholderString = "smb://server.local/share"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 340).isActive = true
        container.addArrangedSubview(field)

        if !recentServers.isEmpty {
            let popup = NSPopUpButton(frame: .zero, pullsDown: true)
            popup.addItem(withTitle: "Recent Servers…")
            for server in recentServers { popup.addItem(withTitle: server) }
            popup.target = ConnectRecentTarget.shared
            ConnectRecentTarget.shared.onPick = { picked in field.stringValue = picked }
            popup.action = #selector(ConnectRecentTarget.picked(_:))
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.widthAnchor.constraint(equalToConstant: 340).isActive = true
            container.addArrangedSubview(popup)
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = field

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            ConnectRecentTarget.shared.onPick = nil
            guard response == .alertFirstButtonReturn else { return }
            let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = ServerURLValidator.validate(raw) else {
                let err = NSAlert()
                err.alertStyle = .warning
                err.messageText = "Invalid Server Address"
                err.informativeText = "Use a supported network scheme such as smb://, nfs://, afp://, webdav://, or https:// with a valid host name."
                err.addButton(withTitle: L10n.text("OK"))
                if let window, window.attachedSheet == nil { err.beginSheetModal(for: window) }
                else { err.runModal() }
                return
            }
            recordRecentServer(url.absoluteString)
            NSWorkspace.shared.open(url)
        }

        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }
}

@MainActor
private final class ConnectRecentTarget: NSObject {
    static let shared = ConnectRecentTarget()
    var onPick: ((String) -> Void)?

    @objc func picked(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index > 0, let title = sender.itemTitle(at: index) as String? else { return }
        onPick?(title)
    }
}
