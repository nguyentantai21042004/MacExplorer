import AppKit
import ExplorerCore

/// Loads user folder appearance rules from `~/.config/explorer/folder-rules.json`,
/// memoizes path matches in a bounded dictionary, and caches rendered vector icons in a bounded NSCache.
@MainActor
final class FolderRulesStore {
    static let shared = FolderRulesStore()
    static let changed = Notification.Name("ExplorerFolderRulesChanged")

    static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/explorer/folder-rules.json")
    }

    let configURL: URL
    private(set) var matcher = FolderAppearanceMatcher(rules: [])
    private(set) var lastError: String?

    private var pathCache: [String: FolderAppearanceStyle?] = [:]
    private let maxPathCacheEntries = 512
    private let iconCache = NSCache<NSString, NSImage>()
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var reloadTask: Task<Void, Never>?

    init(configURL: URL = FolderRulesStore.defaultConfigURL, watch: Bool = true) {
        self.configURL = configURL
        iconCache.countLimit = 64
        reload(notify: false)
        if watch {
            attachWatcherIfDirectoryExists()
        }
    }

    var ruleCount: Int { matcher.ruleCount }

    func style(for url: URL) -> FolderAppearanceStyle? {
        guard !matcher.isEmpty, url.isFileURL else { return nil }
        let key = url.standardizedFileURL.path
        if let cached = pathCache[key] {
            return cached
        }
        let result = matcher.match(path: key)
        if pathCache.count >= maxPathCacheEntries {
            pathCache.removeAll(keepingCapacity: true)
        }
        pathCache[key] = result
        return result
    }

    func color(forHex hex: String?) -> NSColor? {
        guard let hex, hex.count == 7, hex.hasPrefix("#"),
              let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }

    func folderIcon(tint: NSColor?, tintKey: String, symbol: String?) -> NSImage {
        let key = "\(tintKey)|\(symbol ?? "")" as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        let image = Palette.makeFolderIcon(tint: tint, symbol: symbol)
        iconCache.setObject(image, forKey: key)
        return image
    }

    func reload(notify: Bool = true) {
        pathCache.removeAll(keepingCapacity: true)
        iconCache.removeAllObjects()
        lastError = nil

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            matcher = FolderAppearanceMatcher(rules: [])
            if notify { NotificationCenter.default.post(name: Self.changed, object: self) }
            return
        }
        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try JSONDecoder().decode(FolderAppearanceRulesFile.self, from: data)
            matcher = FolderAppearanceMatcher(rules: decoded.rules)
        } catch {
            lastError = error.localizedDescription
            matcher = FolderAppearanceMatcher(rules: [])
        }
        if notify {
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }

    func ensureConfigFileExists() throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configURL.path) {
            let starter = """
            {
              "rules": [
                { "root": "~/Projects", "depth": 0, "color": "#0EA5E9", "symbol": "square.grid.2x2.fill" },
                { "root": "~/Projects", "depth": 1, "nameRegex": "(?i)(api|backend|service)", "color": "#10B981", "symbol": "server.rack" },
                { "root": "~/Projects", "depth": 1, "nameRegex": "(?i)(web|ui|portal|frontend)", "color": "#EC4899", "symbol": "globe" },
                { "root": "~/Projects", "depth": 1, "color": "#38BDF8", "symbol": "folder.fill" }
              ]
            }
            """
            try starter.write(to: configURL, atomically: true, encoding: .utf8)
        }
        attachWatcherIfDirectoryExists()
    }

    private func attachWatcherIfDirectoryExists() {
        guard dirWatcher == nil else { return }
        let dirPath = configURL.deletingLastPathComponent().path
        guard FileManager.default.fileExists(atPath: dirPath) else { return }
        let fd = open(dirPath, O_EVTONLY | O_NONBLOCK)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleReload()
            }
        }
        source.setCancelHandler { close(fd) }
        dirWatcher = source
        source.resume()
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reload(notify: true)
        }
    }
}
