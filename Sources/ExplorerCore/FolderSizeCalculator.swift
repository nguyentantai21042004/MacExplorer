import Foundation
import Darwin

public struct FolderSizeResult: Sendable, Equatable {
    public let bytes: Int64
    public let itemCount: Int
    public init(bytes: Int64, itemCount: Int) {
        self.bytes = bytes
        self.itemCount = itemCount
    }
}

public enum FolderSizeCalculator {
    private static let skippedExactPaths: Set<String> = [
        "/", "/System", "/Library", "/Users", "/Volumes",
        "/private", "/usr", "/var", "/dev", "/cores", "/opt", "/Network"
    ]

    /// Avoid automatic background traversal of massive OS or multi-user roots
    /// where walking the entire filesystem would burn CPU and SSD I/O.
    public static func shouldSkipAutomaticMeasurement(_ directory: URL) -> Bool {
        let path = directory.standardizedFileURL.path
        if skippedExactPaths.contains(path) { return true }
        let homeLibrary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path
        if path == homeLibrary { return true }
        return false
    }

    /// Measures allocated bytes and regular file count inside `directory` using POSIX `fts_open`
    /// (zero CFURL / Objective-C allocations and no symlink traversal or cross-volume jumps).
    public static func measure(_ directory: URL) throws -> FolderSizeResult {
        try Task.checkCancellation()
        let path = directory.standardizedFileURL.path
        return try path.withCString { cPath -> FolderSizeResult in
            var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cPath), nil]
            defer { if let p = paths[0] { free(p) } }
            guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
                return FolderSizeResult(bytes: 0, itemCount: 0)
            }
            defer { fts_close(fts) }

            var totalBytes: Int64 = 0
            var count = 0
            var steps = 0

            while let entry = fts_read(fts) {
                steps &+= 1
                if (steps & 0x1FF) == 0 {
                    try Task.checkCancellation()
                }
                if Int32(entry.pointee.fts_info) == FTS_F, let statPtr = entry.pointee.fts_statp {
                    let st = statPtr.pointee
                    let allocated = Int64(st.st_blocks) * 512
                    totalBytes += allocated > 0 ? allocated : Int64(max(0, st.st_size))
                    count += 1
                }
            }
            return FolderSizeResult(bytes: totalBytes, itemCount: count)
        }
    }
}

public actor FolderSizeCache {
    public static let shared = FolderSizeCache()
    private struct Entry: Sendable {
        let modified: Date?
        let result: FolderSizeResult
        let storedAt: ContinuousClock.Instant
    }
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<FolderSizeResult?, Never>] = [:]
    private let maxEntries = 512
    private let ttl: Duration = .seconds(120)

    public init() {}

    public func cached(for url: URL, modified: Date?) -> FolderSizeResult? {
        let key = url.standardizedFileURL.path
        guard let entry = entries[key] else { return nil }
        if entry.storedAt.duration(to: .now) > ttl {
            entries.removeValue(forKey: key)
            return nil
        }
        if let modified, let storedMod = entry.modified, storedMod != modified {
            return nil
        }
        return entry.result
    }

    public func store(_ result: FolderSizeResult, for url: URL, modified: Date?) {
        let key = url.standardizedFileURL.path
        if entries.count >= maxEntries, entries[key] == nil {
            let now = ContinuousClock.now
            let expired = entries.filter { $0.value.storedAt.duration(to: now) > ttl }.map(\.key)
            for k in expired { entries.removeValue(forKey: k) }
            if entries.count >= maxEntries, let oldest = entries.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
                entries.removeValue(forKey: oldest)
            }
        }
        entries[key] = Entry(modified: modified, result: result, storedAt: .now)
    }

    /// Coalesces concurrent measurements of the same folder so browser & inspector
    /// never traverse the same directory tree twice at once.
    public func measureIfNeeded(for url: URL, modified: Date?) async -> FolderSizeResult? {
        if let hit = cached(for: url, modified: modified) { return hit }
        let key = url.standardizedFileURL.path
        if let existing = inFlight[key] {
            return await existing.value
        }
        let target = url
        let task = Task.detached(priority: .background) {
            try? FolderSizeCalculator.measure(target)
        }
        inFlight[key] = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            // Only cancel the detached walk if no other caller is awaiting it?
            // Keeping cooperative cancellation responsive prevents lingering background CPU.
            task.cancel()
        }
        inFlight.removeValue(forKey: key)
        if let result {
            store(result, for: url, modified: modified)
        }
        return result
    }

    public func invalidate(for url: URL) {
        let key = url.standardizedFileURL.path
        entries.removeValue(forKey: key)
        inFlight[key]?.cancel()
        inFlight.removeValue(forKey: key)
    }

    public func clear() {
        entries.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }
}
