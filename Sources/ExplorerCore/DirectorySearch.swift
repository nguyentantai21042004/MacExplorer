import Foundation

public enum SearchScope: String, Codable, Sendable { case folder, subfolders }

public struct SearchUpdate: Sendable {
    public let matches: [FileItem]
    public let scanned: Int
    public let unreadableFolders: Int
    public let reachedLimit: Bool
}

public enum DirectorySearch {
    /// Heavy dependency / build / VCS cache directories skipped during default recursive search
    /// unless hidden files are enabled or the query explicitly mentions them.
    private static let defaultSkippedDirectories: Set<String> = [
        "node_modules", ".git", ".hg", ".svn", ".build", "DerivedData",
        "__pycache__", ".venv", ".next", ".nuxt", ".turbo", ".cache", "Pods"
    ]

    /// Known binary extensions skipped immediately before opening files in `content:` search.
    private static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "ico", "icns", "bmp", "tiff", "tif",
        "mp4", "mov", "mkv", "avi", "webm", "mp3", "wav", "flac", "aac", "m4a", "ogg",
        "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "iso",
        "pdf", "psd", "ai", "sketch", "fig", "ttf", "otf", "woff", "woff2",
        "o", "a", "dylib", "so", "dll", "exe", "class", "jar", "pyc", "wasm",
        "sqlite", "sqlite3", "db", "bin", "dat", "car", "nib", "DS_Store"
    ]

    private static let maxContentScanBytes: Int64 = 1_048_576

    /// Runs on a worker task. Directory symlinks and packages are returned as results,
    /// but never descended into. Uses lightweight directory enumeration so Finder xattr/tag
    /// metadata is only read for actual matching items rather than every scanned file.
    public static func run(root: URL, query: String, showHidden: Bool = false, resultLimit: Int = 20_000,
                           onUpdate: @Sendable (SearchUpdate) async -> Void) async throws -> SearchUpdate {
        let filter = SearchQueryParser.parse(query)
        guard !filter.isEmpty, resultLimit > 0 else {
            return SearchUpdate(matches: [], scanned: 0, unreadableFolders: 0, reachedLimit: false)
        }
        let regex = filter.compiledRegex()
        try Task.checkCancellation()
        let searchRoot = URL(fileURLWithPath: root.resolvingSymlinksInPath().path, isDirectory: true)
        try FileSystem.validateDirectory(searchRoot)

        let queryLower = query.lowercased()
        let needsDate = filter.modifiedAfter != nil || filter.modifiedBefore != nil
        let needsSize = filter.sizeComparison != nil || filter.contentQuery != nil
        var scanKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey]
        if needsDate { scanKeys.insert(.contentModificationDateKey) }
        if needsSize { scanKeys.insert(.fileSizeKey) }
        let scanKeysArray = Array(scanKeys)
        let matchMetaKeys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .labelNumberKey]

        let manager = FileManager()
        var folders = [searchRoot], batch: [FileItem] = [], scanned = 0, unreadable = 0, found = 0
        var lastUpdate = ContinuousClock.now, limited = false

        scan: while let folder = folders.popLast() {
            try Task.checkCancellation()
            let urls: [URL]
            do {
                urls = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: scanKeysArray)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if folder == searchRoot { throw error }
                unreadable += 1
                continue
            }

            for url in urls {
                if (scanned & 0x3F) == 0 {
                    try Task.checkCancellation()
                }
                let name = url.lastPathComponent
                let values = try? url.resourceValues(forKeys: scanKeys)
                let isHidden = values?.isHidden == true || name.hasPrefix(".")
                guard showHidden || !isHidden else { continue }

                var isDirectory = values?.isDirectory ?? false
                let isSymlink = values?.isSymbolicLink ?? false
                let isPackage = values?.isPackage ?? false
                if isSymlink {
                    var targetIsDirectory = ObjCBool(false)
                    if manager.fileExists(atPath: url.path, isDirectory: &targetIsDirectory) {
                        isDirectory = targetIsDirectory.boolValue
                    }
                }
                let isNavigable = isDirectory && !isPackage
                scanned += 1

                let candidate = FileItem(
                    url: url,
                    name: name,
                    isDirectory: isDirectory,
                    isPackage: isPackage,
                    isHidden: isHidden,
                    isSymbolicLink: isSymlink,
                    modified: values?.contentModificationDate,
                    created: nil,
                    size: isDirectory ? nil : values?.fileSize.map(Int64.init),
                    finderColors: FinderColorSummary()
                )

                if filter.matchesMetadata(candidate, regex: regex) && matchesContent(candidate, needle: filter.contentQuery) {
                    let fullValues = try? url.resourceValues(forKeys: matchMetaKeys)
                    let matchedItem = FileItem(
                        url: url,
                        name: name,
                        isDirectory: isDirectory,
                        isPackage: isPackage,
                        isHidden: isHidden,
                        isSymbolicLink: isSymlink,
                        modified: fullValues?.contentModificationDate ?? candidate.modified,
                        created: fullValues?.creationDate,
                        size: isDirectory ? nil : (fullValues?.fileSize.map(Int64.init) ?? candidate.size),
                        finderColors: FinderColors.summary(at: url, legacyLabel: fullValues?.labelNumber ?? 0)
                    )
                    batch.append(matchedItem)
                    found += 1
                    if found >= resultLimit { limited = true; break scan }
                }

                if isNavigable && !isSymlink {
                    let skipHeavy = !showHidden && defaultSkippedDirectories.contains(name) && !queryLower.contains(name.lowercased())
                    if !skipHeavy {
                        folders.append(url)
                    }
                }

                if batch.count >= 100 || lastUpdate.duration(to: .now) >= .milliseconds(250) {
                    try Task.checkCancellation()
                    await onUpdate(SearchUpdate(matches: batch, scanned: scanned, unreadableFolders: unreadable, reachedLimit: false))
                    batch.removeAll(keepingCapacity: true)
                    lastUpdate = .now
                }
            }
        }

        try Task.checkCancellation()
        let final = SearchUpdate(matches: batch, scanned: scanned, unreadableFolders: unreadable, reachedLimit: limited)
        await onUpdate(final)
        return SearchUpdate(matches: [], scanned: scanned, unreadableFolders: unreadable, reachedLimit: limited)
    }

    private static func matchesContent(_ item: FileItem, needle: String?) -> Bool {
        guard let needle, !needle.isEmpty else { return true }
        guard !item.isDirectory, !item.isPackage, !item.isSymbolicLink else { return false }
        let ext = item.url.pathExtension.lowercased()
        if !ext.isEmpty && binaryExtensions.contains(ext) { return false }
        if let size = item.size, size <= 0 || size > maxContentScanBytes { return false }
        guard let data = try? Data(contentsOf: item.url, options: [.mappedIfSafe]),
              !data.isEmpty,
              data.count <= Int(maxContentScanBytes),
              !data.prefix(2048).contains(0),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    public static func location(of item: URL, relativeTo root: URL) -> String {
        var parent = item.deletingLastPathComponent().standardizedFileURL.path, base = root.standardizedFileURL.path
        // Enumeration can return a physical path when the search root uses an alias
        // such as /tmp or a user-created directory symlink.
        if parent != base && !parent.hasPrefix(base == "/" ? "/" : base + "/") {
            parent = item.deletingLastPathComponent().resolvingSymlinksInPath().path
            base = root.resolvingSymlinksInPath().path
        }
        if parent == base { return root.lastPathComponent.isEmpty ? "/" : root.lastPathComponent }
        let prefix = base == "/" ? "/" : base + "/"
        return parent.hasPrefix(prefix) ? String(parent.dropFirst(prefix.count)) : parent
    }
}
