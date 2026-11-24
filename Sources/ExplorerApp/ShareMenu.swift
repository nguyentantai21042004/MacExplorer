import AppKit
import ExplorerCore

/// Provides the native macOS Share menu (AirDrop, Mail, Messages, Notes, Share Extensions)
/// using `NSSharingServicePicker.standardShareMenuItem`.
@MainActor
enum ShareMenu {
    static func item(for urls: [URL]) -> NSMenuItem? {
        let local = urls.filter(\.isFileURL)
        guard !local.isEmpty else { return nil }
        let picker = NSSharingServicePicker(items: local)
        let menuItem = picker.standardShareMenuItem
        if menuItem.image == nil {
            menuItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: menuItem.title)
        }
        return menuItem
    }
}
