import Darwin
import Foundation

public struct TrashRecord: Codable, Equatable, Sendable {
    public let trashedPath: String
    public let originalPath: String
    public let deletedAt: Date

    public init(trashedPath: String, originalPath: String, deletedAt: Date = Date()) {
        self.trashedPath = trashedPath
        self.originalPath = originalPath
        self.deletedAt = deletedAt
    }
}

/// Persists original paths for items sent to Trash by Explorer so "Put Back"
/// works across app restarts without relying on Finder's private `.DS_Store` format.
public final class TrashJournal: @unchecked Sendable {
    public static let shared = TrashJournal()
    public static let maxJournalBytes = 2 * 1024 * 1024

    public static var defaultStorageURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Explorer", isDirectory: true)
            .appendingPathComponent("trash-history.json")
    }

    private let lock = NSLock()
    private let storageURL: URL
    private var records: [String: TrashRecord] = [:]

    public init(storageURL: URL = TrashJournal.defaultStorageURL) {
        self.storageURL = storageURL
        load()
    }

    public func record(trashedURL: URL, originalURL: URL, deletedAt: Date = Date()) {
        let key = canonicalKey(trashedURL)
        let original = canonicalKey(originalURL)
        lock.lock()
        records[key] = TrashRecord(trashedPath: key, originalPath: original, deletedAt: deletedAt)
        saveLocked()
        lock.unlock()
    }

    public func record(for trashedURL: URL) -> TrashRecord? {
        let key = canonicalKey(trashedURL)
        lock.lock()
        defer { lock.unlock() }
        return records[key]
    }

    public func originalURL(for trashedURL: URL) -> URL? {
        record(for: trashedURL).map { URL(fileURLWithPath: $0.originalPath) }
    }

    public func remove(trashedURL: URL) {
        let key = canonicalKey(trashedURL)
        lock.lock()
        let removed = records.removeValue(forKey: key) != nil
        if removed { saveLocked() }
        lock.unlock()
    }

    public func prune(existingPaths: Set<String>) {
        lock.lock()
        let before = records.count
        records = records.filter { existingPaths.contains($0.key) }
        if records.count != before { saveLocked() }
        lock.unlock()
    }

    public func clearAll() {
        lock.lock()
        records.removeAll()
        saveLocked()
        lock.unlock()
    }

    private func canonicalKey(_ url: URL) -> String {
        let std = url.standardizedFileURL
        guard std.path != "/" else { return "/" }
        return std.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(std.lastPathComponent).path
    }

    private func load() {
        guard let data = try? SafeFileReader.readPrefix(
            of: storageURL,
            limit: Self.maxJournalBytes,
            followSymlinks: false,
            maxFileSize: Int64(Self.maxJournalBytes)
        ),
              let decoded = try? JSONDecoder().decode([TrashRecord].self, from: data) else { return }
        var map: [String: TrashRecord] = [:]
        for item in decoded { map[item.trashedPath] = item }
        lock.lock()
        records = map
        lock.unlock()
    }

    private func saveLocked() {
        let list = Array(records.values).sorted { $0.deletedAt > $1.deletedAt }
        guard let data = try? JSONEncoder().encode(list) else { return }
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: .atomic)
    }
}

public enum TrashOperations {
    public static func userTrashDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".Trash", isDirectory: true).standardizedFileURL
    }

    public static func trashDirectories(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                        volumes: [URL] = StorageDiscovery.volumeURLs(),
                                        uid: uid_t = getuid()) -> [URL] {
        var dirs: [URL] = []
        var seen = Set<String>()
        func appendIfPresent(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            var isDir = ObjCBool(false)
            if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue,
               seen.insert(resolved.path).inserted {
                dirs.append(resolved)
            }
        }
        appendIfPresent(userTrashDirectory(home: home))
        for volume in volumes where volume.path != "/" {
            let volumeTrash = volume.appendingPathComponent(".Trashes/\(uid)", isDirectory: true)
            appendIfPresent(volumeTrash)
        }
        return dirs
    }

    public static func isTrashDirectory(_ url: URL,
                                        trashRoots: [URL] = [userTrashDirectory()]) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return trashRoots.contains { $0.resolvingSymlinksInPath().standardizedFileURL.path == path }
    }

    public static func isInsideTrash(_ url: URL,
                                     trashRoots: [URL] = [userTrashDirectory()]) -> Bool {
        guard url.isFileURL else { return false }
        let parent = url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let itemPath = parent.appendingPathComponent(url.standardizedFileURL.lastPathComponent).path
        return trashRoots.contains { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return itemPath == rootPath || itemPath.hasPrefix(rootPath + "/")
        }
    }

    /// Restores a trashed item to its recorded original path using atomic `RENAME_EXCL`
    /// so an existing file at the original path is never silently overwritten.
    public static func putBack(_ trashedURL: URL, journal: TrashJournal = .shared) throws -> URL {
        guard let destination = journal.originalURL(for: trashedURL) else {
            throw FileOperationError("Original location is unknown for \(trashedURL.lastPathComponent). Drag it out of Trash to restore.")
        }
        let fm = FileManager.default
        let source = canonicalItem(trashedURL)
        guard (try? fm.attributesOfItem(atPath: source.path)) != nil else {
            journal.remove(trashedURL: source)
            throw FileOperationError("\(source.lastPathComponent) is no longer in Trash.")
        }
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let target = parent.resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent)

        let rc = source.withUnsafeFileSystemRepresentation { from in
            target.withUnsafeFileSystemRepresentation { to in
                renamex_np(from!, to!, UInt32(RENAME_EXCL))
            }
        }
        if rc == 0 {
            journal.remove(trashedURL: source)
            return target
        }
        let code = errno
        if code == EEXIST {
            throw FileOperationError("Cannot Put Back \(source.lastPathComponent) because an item already exists at \(target.path).")
        }
        if code == EXDEV {
            guard (try? fm.attributesOfItem(atPath: target.path)) == nil else {
                throw FileOperationError("Cannot Put Back \(source.lastPathComponent) because an item already exists at \(target.path).")
            }
            try fm.copyItem(at: source, to: target)
            try fm.removeItem(at: source)
            journal.remove(trashedURL: source)
            return target
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: target.path])
    }

    /// Permanently deletes items strictly confined inside `allowedTrashRoots`.
    /// Refuses any path outside Trash so permanent deletion can never escape Trash.
    @discardableResult
    public static func deletePermanently(_ urls: [URL],
                                         allowedTrashRoots: [URL] = trashDirectories(),
                                         journal: TrashJournal = .shared) throws -> Int {
        let fm = FileManager.default
        let resolvedRoots = allowedTrashRoots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        var deleted = 0
        for raw in urls {
            guard raw.isFileURL else { continue }
            let item = canonicalItem(raw)
            let isStrictlyInsideTrash = resolvedRoots.contains { root in
                item.path.hasPrefix(root + "/") && item.path != root
            }
            guard isStrictlyInsideTrash, !FileOperationEngine.isProtectedSystemPath(item) else {
                throw FileOperationError("Refused to permanently delete an item outside Trash: \(item.path)")
            }
            try fm.removeItem(at: item)
            journal.remove(trashedURL: item)
            deleted += 1
        }
        return deleted
    }

    /// Permanently removes every top-level entry in the provided trash directories.
    @discardableResult
    public static func emptyTrash(directories: [URL] = trashDirectories(),
                                  journal: TrashJournal = .shared) throws -> Int {
        let fm = FileManager.default
        var deleted = 0
        for dir in directories {
            let resolvedDir = dir.resolvingSymlinksInPath().standardizedFileURL
            guard let children = try? fm.contentsOfDirectory(at: resolvedDir, includingPropertiesForKeys: nil) else { continue }
            for child in children where child.lastPathComponent != ".DS_Store" {
                try fm.removeItem(at: child)
                journal.remove(trashedURL: child)
                deleted += 1
            }
        }
        return deleted
    }

    private static func canonicalItem(_ url: URL) -> URL {
        let std = url.standardizedFileURL
        guard std.path != "/" else { return std }
        return std.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(std.lastPathComponent)
    }
}
