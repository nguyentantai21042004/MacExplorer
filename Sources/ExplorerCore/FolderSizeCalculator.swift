import Foundation

public struct FolderSizeResult: Sendable, Equatable {
    public let bytes: Int64
    public let itemCount: Int
    public init(bytes: Int64, itemCount: Int) {
        self.bytes = bytes
        self.itemCount = itemCount
    }
}

public enum FolderSizeCalculator {
    /// Measures allocated bytes and regular file count inside `directory`.
    /// Skips packages' internal traversal only if treated as files, and skips symlinks to avoid cycles.
    public static func measure(_ directory: URL) throws -> FolderSizeResult {
        try Task.checkCancellation()
        let fm = FileManager()
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return FolderSizeResult(bytes: 0, itemCount: 0)
        }
        var totalBytes: Int64 = 0
        var count = 0
        while let obj = enumerator.nextObject() {
            try Task.checkCancellation()
            guard let url = obj as? URL else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            if values?.isRegularFile == true {
                let fileBytes = values?.totalFileAllocatedSize
                    ?? values?.fileAllocatedSize
                    ?? values?.fileSize
                    ?? 0
                totalBytes += Int64(max(0, fileBytes))
                count += 1
            }
        }
        return FolderSizeResult(bytes: totalBytes, itemCount: count)
    }
}

public actor FolderSizeCache {
    public static let shared = FolderSizeCache()
    private struct Entry: Sendable {
        let modified: Date?
        let result: FolderSizeResult
    }
    private var entries: [String: Entry] = [:]

    public init() {}

    public func cached(for url: URL, modified: Date?) -> FolderSizeResult? {
        guard let entry = entries[url.path], entry.modified == modified else { return nil }
        return entry.result
    }

    public func store(_ result: FolderSizeResult, for url: URL, modified: Date?) {
        if entries.count > 4000 { entries.removeAll(keepingCapacity: true) }
        entries[url.path] = Entry(modified: modified, result: result)
    }

    public func invalidate(pathPrefix: String? = nil) {
        guard let pathPrefix else {
            entries.removeAll(keepingCapacity: true)
            return
        }
        entries = entries.filter { !$0.key.hasPrefix(pathPrefix) }
    }
}
