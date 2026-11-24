import Foundation

public struct FolderAppearanceRule: Codable, Equatable, Sendable {
    public let root: String?
    public let depth: Int?
    public let pathRegex: String?
    public let nameRegex: String?
    public let color: String?
    public let symbol: String?

    public init(
        root: String? = nil,
        depth: Int? = nil,
        pathRegex: String? = nil,
        nameRegex: String? = nil,
        color: String? = nil,
        symbol: String? = nil
    ) {
        self.root = root
        self.depth = depth
        self.pathRegex = pathRegex
        self.nameRegex = nameRegex
        self.color = color
        self.symbol = symbol
    }
}

public struct FolderAppearanceRulesFile: Codable, Equatable, Sendable {
    public let rules: [FolderAppearanceRule]
    public init(rules: [FolderAppearanceRule]) { self.rules = rules }
}

public struct FolderAppearanceStyle: Equatable, Hashable, Sendable {
    public let colorHex: String?
    public let symbol: String?

    public init(colorHex: String?, symbol: String?) {
        self.colorHex = colorHex
        self.symbol = symbol
    }

    public var isEmpty: Bool { colorHex == nil && symbol == nil }
}

/// Immutable, pre-compiled folder appearance matcher.
/// All regexes and root prefixes are compiled once at load time so cell rendering
/// never pays compilation overhead and rejects non-matching paths via O(1) prefix/depth checks.
public final class FolderAppearanceMatcher: @unchecked Sendable {
    public static let maxRuleCount = 256

    private struct CompiledRule {
        let expandedRoot: String?
        let expandedRootWithSlash: String?
        let depth: Int?
        let pathRegex: NSRegularExpression?
        let pathRegexExpectsAbsolute: Bool
        let nameRegex: NSRegularExpression?
        let style: FolderAppearanceStyle
    }

    private static let namedColors: [String: String] = [
        "cyan": "#06B6D4",
        "sky": "#38BDF8",
        "blue": "#3B82F6",
        "indigo": "#6366F1",
        "purple": "#A855F7",
        "violet": "#8B5CF6",
        "pink": "#EC4899",
        "rose": "#F43F5E",
        "red": "#EF4444",
        "orange": "#F97316",
        "amber": "#F59E0B",
        "yellow": "#EAB308",
        "lime": "#84CC16",
        "green": "#22C55E",
        "emerald": "#10B981",
        "teal": "#14B8A6",
        "slate": "#64748B",
        "gray": "#94A3B8"
    ]

    private let homePath: String
    private let homePrefix: String
    private let compiled: [CompiledRule]
    private let anyRuleUsesPathRegex: Bool

    public var ruleCount: Int { compiled.count }
    public var isEmpty: Bool { compiled.isEmpty }

    public init(rules: [FolderAppearanceRule], homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        let normalizedHome = Self.trimTrailingSlash(homeDirectory)
        self.homePath = normalizedHome
        self.homePrefix = normalizedHome == "/" ? "/" : normalizedHome + "/"

        var list: [CompiledRule] = []
        let boundedRules = rules.prefix(Self.maxRuleCount)
        list.reserveCapacity(boundedRules.count)
        var usesPathRegex = false

        for rule in boundedRules {
            let colorHex = Self.resolveHexColor(rule.color)
            let symbol = rule.symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanSymbol = (symbol?.isEmpty == false) ? symbol : nil
            let style = FolderAppearanceStyle(colorHex: colorHex, symbol: cleanSymbol)
            guard !style.isEmpty else { continue }

            let expandedRoot = rule.root.map { Self.expandRoot($0, home: normalizedHome) }
            let expandedRootWithSlash = expandedRoot.map { $0 == "/" ? "/" : $0 + "/" }

            var compiledPath: NSRegularExpression?
            var expectsAbsolute = false
            if let pattern = rule.pathRegex, !pattern.isEmpty {
                guard let regex = try? SafeRegex.compile(pattern) else { continue }
                compiledPath = regex
                expectsAbsolute = pattern.hasPrefix("/") || pattern.hasPrefix("^/")
                usesPathRegex = true
            }

            var compiledName: NSRegularExpression?
            if let pattern = rule.nameRegex, !pattern.isEmpty {
                guard let regex = try? SafeRegex.compile(pattern) else { continue }
                compiledName = regex
            }

            // Require at least one selector so an accidental empty rule doesn't paint the whole disk.
            guard expandedRoot != nil || rule.depth != nil || compiledPath != nil || compiledName != nil else { continue }

            list.append(CompiledRule(
                expandedRoot: expandedRoot,
                expandedRootWithSlash: expandedRootWithSlash,
                depth: rule.depth,
                pathRegex: compiledPath,
                pathRegexExpectsAbsolute: expectsAbsolute,
                nameRegex: compiledName,
                style: style
            ))
        }

        self.compiled = list
        self.anyRuleUsesPathRegex = usesPathRegex
    }

    public func match(url: URL) -> FolderAppearanceStyle? {
        guard !compiled.isEmpty, url.isFileURL else { return nil }
        return match(path: url.standardizedFileURL.path)
    }

    public func match(path rawPath: String) -> FolderAppearanceStyle? {
        guard !compiled.isEmpty else { return nil }
        let path = Self.trimTrailingSlash(rawPath)
        let name: String = {
            if path == "/" { return "/" }
            if let slash = path.lastIndex(of: "/") {
                return String(path[path.index(after: slash)...])
            }
            return path
        }()

        var cachedTildePath: String?
        func tildePath() -> String {
            if let existing = cachedTildePath { return existing }
            let computed: String
            if path == homePath {
                computed = "~"
            } else if path.hasPrefix(homePrefix) {
                computed = "~/" + path.dropFirst(homePrefix.count)
            } else {
                computed = path
            }
            cachedTildePath = computed
            return computed
        }

        for rule in compiled {
            // 1. O(1) root prefix & zero-allocation integer depth check before any regex work.
            if let root = rule.expandedRoot, let rootSlash = rule.expandedRootWithSlash {
                if let expectedDepth = rule.depth {
                    if expectedDepth == 0 {
                        guard path == root else { continue }
                    } else {
                        guard path.hasPrefix(rootSlash) else { continue }
                        let rel = path.dropFirst(rootSlash.count)
                        guard !rel.isEmpty else { continue }
                        var slashes = 0
                        for byte in rel.utf8 where byte == 0x2F { slashes += 1 }
                        guard slashes + 1 == expectedDepth else { continue }
                    }
                } else {
                    guard path == root || path.hasPrefix(rootSlash) else { continue }
                }
            } else if let expectedDepth = rule.depth {
                if expectedDepth == 0 {
                    guard path == "/" else { continue }
                } else {
                    var slashes = 0
                    for byte in path.utf8 where byte == 0x2F { slashes += 1 }
                    guard slashes == expectedDepth else { continue }
                }
            }

            // 2. Optional name regex.
            if let nameRegex = rule.nameRegex {
                guard SafeRegex.matches(nameRegex, in: name) else { continue }
            }

            // 3. Optional path regex (against ~/... by default, or absolute path if pattern starts with /).
            if let pathRegex = rule.pathRegex {
                let candidate = rule.pathRegexExpectsAbsolute ? path : tildePath()
                guard SafeRegex.matches(pathRegex, in: candidate) else { continue }
            }

            return rule.style
        }

        return nil
    }

    public static func resolveHexColor(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let mapped = namedColors[trimmed] { return mapped }
        let hexBody = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        if hexBody.count == 6, hexBody.allSatisfy(\.isHexDigit) {
            return "#" + hexBody.uppercased()
        }
        if hexBody.count == 3, hexBody.allSatisfy(\.isHexDigit) {
            let expanded = hexBody.map { "\($0)\($0)" }.joined().uppercased()
            return "#" + expanded
        }
        return nil
    }

    private static func expandRoot(_ raw: String, home: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return trimTrailingSlash(home + "/" + trimmed.dropFirst(2))
        }
        return trimTrailingSlash(trimmed)
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        var end = path.endIndex
        while end > path.index(after: path.startIndex), path[path.index(before: end)] == "/" {
            end = path.index(before: end)
        }
        return String(path[..<end])
    }
}
