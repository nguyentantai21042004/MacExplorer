import Foundation

/// Groups incoming external URLs (from Finder replacement / `NSFileViewer` / `open`)
/// by target folder so revealing multiple files in the same directory opens one tab
/// with every requested file selected instead of spawning duplicate tabs.
public struct ExternalOpenTarget: Equatable, Sendable {
    public let folder: URL
    public let selectedItems: [URL]

    public init(folder: URL, selectedItems: [URL] = []) {
        self.folder = folder
        self.selectedItems = selectedItems
    }
}

public enum ExternalOpenPlan {
    public static func isNavigableFolder(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    public static func group(_ urls: [URL], isNavigableFolder: (URL) -> Bool = Self.isNavigableFolder) -> [ExternalOpenTarget] {
        var order: [String] = []
        var folders: [String: URL] = [:]
        var selections: [String: [URL]] = [:]
        var seenSelections: [String: Set<String>] = [:]

        for rawURL in urls where rawURL.isFileURL {
            let url = rawURL.standardizedFileURL
            if isNavigableFolder(url) {
                let key = folderKey(url)
                if folders[key] == nil {
                    order.append(key)
                    folders[key] = url
                    selections[key] = []
                    seenSelections[key] = []
                }
            } else {
                let parent = url.deletingLastPathComponent().standardizedFileURL
                let key = folderKey(parent)
                if folders[key] == nil {
                    order.append(key)
                    folders[key] = parent
                    selections[key] = []
                    seenSelections[key] = []
                }
                let itemKey = url.path
                if seenSelections[key]?.insert(itemKey).inserted == true {
                    selections[key, default: []].append(url)
                }
            }
        }

        return order.compactMap { key in
            guard let folder = folders[key] else { return nil }
            return ExternalOpenTarget(folder: folder, selectedItems: selections[key] ?? [])
        }
    }

    public static func folderKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
