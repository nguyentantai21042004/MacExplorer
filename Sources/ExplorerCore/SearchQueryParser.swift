import Foundation

public struct SearchFilter: Sendable, Equatable {
    public enum Comparison: Sendable, Equatable {
        case greaterThan(Int64)
        case greaterOrEqual(Int64)
        case lessThan(Int64)
        case lessOrEqual(Int64)

        func matches(_ value: Int64) -> Bool {
            switch self {
            case let .greaterThan(limit): value > limit
            case let .greaterOrEqual(limit): value >= limit
            case let .lessThan(limit): value < limit
            case let .lessOrEqual(limit): value <= limit
            }
        }
    }

    public enum ItemKindFilter: Sendable, Equatable {
        case folder, file
    }

    public var plainTerms: [String] = []
    public var extensions: Set<String> = []
    public var sizeComparison: Comparison?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?
    public var itemKind: ItemKindFilter?
    public var regexPattern: String?
    public var contentQuery: String?

    public var isEmpty: Bool {
        plainTerms.isEmpty && extensions.isEmpty && sizeComparison == nil &&
            modifiedAfter == nil && modifiedBefore == nil && itemKind == nil &&
            regexPattern == nil && contentQuery == nil
    }

    public var hasAdvancedTokens: Bool {
        !extensions.isEmpty || sizeComparison != nil || modifiedAfter != nil ||
            modifiedBefore != nil || itemKind != nil || regexPattern != nil || contentQuery != nil
    }

    /// Plain text used for UI substring highlighting.
    public var highlightText: String {
        if !plainTerms.isEmpty { return plainTerms.joined(separator: " ") }
        return contentQuery ?? ""
    }

    public func matchesMetadata(_ item: FileItem, regex: NSRegularExpression? = nil) -> Bool {
        if let itemKind {
            switch itemKind {
            case .folder: if !item.isNavigable { return false }
            case .file: if item.isNavigable { return false }
            }
        }
        if !extensions.isEmpty {
            let ext = item.url.pathExtension.lowercased()
            if item.isNavigable || !extensions.contains(ext) { return false }
        }
        if let sizeComparison {
            guard let size = item.size, sizeComparison.matches(size) else { return false }
        }
        if let modifiedAfter {
            guard let modified = item.modified, modified >= modifiedAfter else { return false }
        }
        if let modifiedBefore {
            guard let modified = item.modified, modified <= modifiedBefore else { return false }
        }
        if let regex {
            let range = NSRange(item.name.startIndex..<item.name.endIndex, in: item.name)
            if regex.firstMatch(in: item.name, options: [], range: range) == nil { return false }
        }
        for term in plainTerms where !item.name.localizedStandardContains(term) {
            return false
        }
        return true
    }

    public func compiledRegex() -> NSRegularExpression? {
        guard let regexPattern, !regexPattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive])
    }
}

public enum SearchQueryParser {
    public static func parse(_ raw: String, now: Date = Date()) -> SearchFilter {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchFilter() }
        var filter = SearchFilter()
        for token in tokenize(trimmed) {
            let lower = token.lowercased()
            if lower.hasPrefix("ext:") {
                let value = String(lower.dropFirst(4))
                let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty }
                filter.extensions.formUnion(parts)
            } else if lower.hasPrefix("size:") {
                if let cmp = parseSizeComparison(String(lower.dropFirst(5))) {
                    filter.sizeComparison = cmp
                } else {
                    filter.plainTerms.append(token)
                }
            } else if lower.hasPrefix("mod:") || lower.hasPrefix("modified:") {
                let spec = lower.hasPrefix("mod:") ? String(lower.dropFirst(4)) : String(lower.dropFirst(9))
                if !applyDateFilter(spec, now: now, to: &filter) {
                    filter.plainTerms.append(token)
                }
            } else if lower == "type:folder" || lower == "type:dir" || lower == "kind:folder" {
                filter.itemKind = .folder
            } else if lower == "type:file" || lower == "kind:file" {
                filter.itemKind = .file
            } else if lower.hasPrefix("regex:") {
                let pattern = String(token.dropFirst(6))
                if !pattern.isEmpty { filter.regexPattern = pattern }
            } else if lower.hasPrefix("content:") {
                let needle = String(token.dropFirst(8))
                if !needle.isEmpty { filter.contentQuery = needle }
            } else if lower.hasPrefix("in:") {
                let needle = String(token.dropFirst(3))
                if !needle.isEmpty { filter.contentQuery = needle }
            } else {
                filter.plainTerms.append(token)
            }
        }
        return filter
    }

    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in input {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch.isWhitespace && !inQuotes {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func parseSizeComparison(_ spec: String) -> SearchFilter.Comparison? {
        let s = spec.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix(">="), let bytes = parseByteSize(String(s.dropFirst(2))) { return .greaterOrEqual(bytes) }
        if s.hasPrefix("<="), let bytes = parseByteSize(String(s.dropFirst(2))) { return .lessOrEqual(bytes) }
        if s.hasPrefix(">"), let bytes = parseByteSize(String(s.dropFirst(1))) { return .greaterThan(bytes) }
        if s.hasPrefix("<"), let bytes = parseByteSize(String(s.dropFirst(1))) { return .lessThan(bytes) }
        if let bytes = parseByteSize(s) { return .greaterOrEqual(bytes) }
        return nil
    }

    private static func parseByteSize(_ raw: String) -> Int64? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let multipliers: [(String, Int64)] = [
            ("gb", 1_000_000_000), ("g", 1_000_000_000),
            ("mb", 1_000_000), ("m", 1_000_000),
            ("kb", 1_000), ("k", 1_000),
            ("b", 1)
        ]
        for (suffix, mult) in multipliers where s.hasSuffix(suffix) {
            let numStr = String(s.dropLast(suffix.count))
            if let value = Double(numStr), value >= 0 {
                return Int64(value * Double(mult))
            }
        }
        if let value = Int64(s), value >= 0 { return value }
        return nil
    }

    private static func applyDateFilter(_ spec: String, now: Date, to filter: inout SearchFilter) -> Bool {
        let s = spec.trimmingCharacters(in: .whitespaces).lowercased()
        // `<7d` means modified within last 7 days (after now - 7d).
        // `>7d` means modified more than 7 days ago (before now - 7d).
        let isWithin: Bool
        let rest: String
        if s.hasPrefix("<=") || s.hasPrefix("<") {
            isWithin = true
            rest = s.hasPrefix("<=") ? String(s.dropFirst(2)) : String(s.dropFirst(1))
        } else if s.hasPrefix(">=") || s.hasPrefix(">") {
            isWithin = false
            rest = s.hasPrefix(">=") ? String(s.dropFirst(2)) : String(s.dropFirst(1))
        } else {
            return false
        }
        guard let interval = parseDuration(rest) else { return false }
        let cutoff = now.addingTimeInterval(-interval)
        if isWithin { filter.modifiedAfter = cutoff }
        else { filter.modifiedBefore = cutoff }
        return true
    }

    private static func parseDuration(_ raw: String) -> TimeInterval? {
        let units: [(String, TimeInterval)] = [
            ("m", 30 * 86_400),
            ("w", 7 * 86_400),
            ("d", 86_400),
            ("h", 3_600)
        ]
        for (suffix, mult) in units where raw.hasSuffix(suffix) {
            if let count = Double(raw.dropLast(suffix.count)), count >= 0 {
                return count * mult
            }
        }
        return nil
    }
}
