import Foundation

public struct SpotlightSearchResult: Sendable {
    public let matches: [FileItem]
    public let scanned: Int
    public let reachedLimit: Bool
    public let timedOut: Bool

    public init(matches: [FileItem], scanned: Int, reachedLimit: Bool, timedOut: Bool) {
        self.matches = matches
        self.scanned = scanned
        self.reachedLimit = reachedLimit
        self.timedOut = timedOut
    }
}

/// Safe wrapper over macOS Spotlight (`NSMetadataQuery`).
/// All user terms are passed through parameterized `NSPredicate` arguments (`%@`)
/// with wildcard characters escaped so user input can never inject predicate syntax.
public enum SpotlightSearch {
    public static let maxTerms = 8

    /// Escapes `\`, `*`, and `?` for safe literal matching inside `LIKE[cd]`.
    public static func escapeLikePattern(_ term: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(term.count)
        for ch in term {
            if ch == "\\" || ch == "*" || ch == "?" {
                escaped.append("\\")
            }
            escaped.append(ch)
        }
        return escaped
    }

    /// Builds a parameterized Spotlight predicate matching filename or indexed text content.
    public static func makePredicate(query: String) -> NSPredicate? {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
            .prefix(maxTerms)
        guard !terms.isEmpty else { return nil }

        let subpredicates: [NSPredicate] = terms.map { term in
            let pattern = "*\(escapeLikePattern(term))*"
            return NSPredicate(
                format: "kMDItemFSName LIKE[cd] %@ OR kMDItemTextContent CONTAINS[cd] %@",
                pattern, term
            )
        }
        if subpredicates.count == 1 { return subpredicates[0] }
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }

    @MainActor
    public static func run(query: String,
                           filter: SearchFilter = SearchFilter(),
                           scopeURL: URL? = nil,
                           showHidden: Bool = false,
                           maxResults: Int = 500,
                           timeout: TimeInterval = 5.0) async -> SpotlightSearchResult {
        guard let predicate = makePredicate(query: query) else {
            return SpotlightSearchResult(matches: [], scanned: 0, reachedLimit: false, timedOut: false)
        }

        let mdQuery = NSMetadataQuery()
        mdQuery.predicate = predicate
        if let scopeURL, scopeURL.isFileURL, scopeURL.path != "/" {
            mdQuery.searchScopes = [scopeURL]
        } else {
            mdQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        }

        let box = QueryBox(query: mdQuery)
        let timedOut: Bool = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                box.start(timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in
                box.finish(timedOut: false)
            }
        }

        mdQuery.disableUpdates()
        defer { mdQuery.stop() }

        let rawCount = mdQuery.resultCount
        let regex = filter.compiledRegex()
        var matches: [FileItem] = []
        matches.reserveCapacity(min(rawCount, maxResults))
        var reachedLimit = false

        for idx in 0..<rawCount {
            if Task.isCancelled { break }
            guard let item = mdQuery.result(at: idx) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            let isHidden = name.hasPrefix(".")
            if !showHidden && isHidden { continue }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
            let isDir = values?.isDirectory ?? false
            let isPkg = values?.isPackage ?? false
            let isSym = values?.isSymbolicLink ?? false
            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date

            let fileItem = FileItem(
                url: url,
                name: name,
                isDirectory: isDir,
                isPackage: isPkg,
                isHidden: isHidden,
                isSymbolicLink: isSym,
                modified: modified,
                created: created,
                size: isDir ? nil : size
            )
            if filter.matchesMetadata(fileItem, regex: regex) {
                matches.append(fileItem)
                if matches.count >= maxResults {
                    reachedLimit = true
                    break
                }
            }
        }

        return SpotlightSearchResult(
            matches: matches,
            scanned: rawCount,
            reachedLimit: reachedLimit,
            timedOut: timedOut
        )
    }
}

@MainActor
private final class QueryBox {
    private let query: NSMetadataQuery
    private var observer: NSObjectProtocol?
    private var timeoutTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var finished = false

    init(query: NSMetadataQuery) {
        self.query = query
    }

    func start(timeout: TimeInterval, continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finish(timedOut: false)
            }
        }
        timeoutTask = Task { @MainActor [weak self] in
            let nanos = UInt64(max(0.05, timeout) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            self?.finish(timedOut: true)
        }
        if !query.start() {
            finish(timedOut: false)
        }
    }

    func finish(timedOut: Bool) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        query.stop()
        continuation?.resume(returning: timedOut)
        continuation = nil
    }
}
