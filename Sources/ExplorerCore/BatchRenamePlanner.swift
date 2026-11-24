import Foundation

public enum BatchRenameMode: Sendable, Equatable {
    case replace(find: String, replacement: String, useRegex: Bool, caseSensitive: Bool)
    case affix(prefix: String, suffix: String)
    case sequence(base: String, start: Int, padWidth: Int)
}

public struct BatchRenameEntry: Sendable, Equatable {
    public let source: URL
    public let originalName: String
    public let newName: String
    public let error: String?

    public var changed: Bool { originalName != newName }
    public var isValid: Bool { error == nil }
}

public enum BatchRenamePlanner {
    public static func plan(urls: [URL], mode: BatchRenameMode, includeExtension: Bool = false) -> [BatchRenameEntry] {
        var proposed: [(url: URL, original: String, candidate: String, syntaxError: String?)] = []
        var regex: NSRegularExpression?
        var regexError: String?
        if case let .replace(find, _, true, caseSensitive) = mode, !find.isEmpty {
            do {
                regex = try SafeRegex.compile(find, options: caseSensitive ? [] : [.caseInsensitive])
            } catch {
                regexError = error.localizedDescription
            }
        }

        for (index, url) in urls.enumerated() {
            let original = url.lastPathComponent
            let ext = url.pathExtension
            let hasExt = !ext.isEmpty && !original.hasPrefix(".")
            let stem = (hasExt && !includeExtension) ? String(original.dropLast(ext.count + 1)) : original
            let tail = (hasExt && !includeExtension) ? ".\(ext)" : ""

            let newStem: String
            switch mode {
            case let .replace(find, replacement, useRegex, caseSensitive):
                if find.isEmpty {
                    newStem = stem
                } else if useRegex {
                    if let regex {
                        let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
                        newStem = regex.stringByReplacingMatches(in: stem, options: [], range: range, withTemplate: replacement)
                    } else {
                        newStem = stem
                    }
                } else {
                    let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
                    newStem = stem.replacingOccurrences(of: find, with: replacement, options: options)
                }
            case let .affix(prefix, suffix):
                newStem = prefix + stem + suffix
            case let .sequence(base, start, padWidth):
                let number = start + index
                let padded = padWidth > 1 ? String(format: "%0\(padWidth)d", number) : "\(number)"
                newStem = base + padded
            }

            let candidate = newStem + tail
            var syntaxError = regexError
            if syntaxError == nil {
                do { try FileOperationEngine.validateName(candidate) }
                catch { syntaxError = error.localizedDescription }
            }
            proposed.append((url, original, candidate, syntaxError))
        }

        var counts: [String: Int] = [:]
        for item in proposed {
            let key = item.url.deletingLastPathComponent().path + "/" + item.candidate.lowercased()
            counts[key, default: 0] += 1
        }

        return proposed.map { item in
            let key = item.url.deletingLastPathComponent().path + "/" + item.candidate.lowercased()
            let err = item.syntaxError ?? ((counts[key] ?? 0) > 1 ? L10n.text("Duplicate target name") : nil)
            return BatchRenameEntry(source: item.url, originalName: item.original, newName: item.candidate, error: err)
        }
    }
}
