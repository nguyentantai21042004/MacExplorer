import Foundation

/// Compiles user-supplied regular expressions while rejecting patterns known to
/// trigger catastrophic backtracking (ReDoS), excessive repetition counts, or
/// unbounded input scans.
public enum SafeRegex {
    public static let maxPatternLength = 256
    public static let maxInputLength = 4096
    public static let maxQuantifierBound = 100

    public enum Rejection: Error, Equatable, Sendable, LocalizedError {
        case tooLong
        case unsafePattern
        case invalidSyntax(String)

        public var errorDescription: String? {
            switch self {
            case .tooLong: "Regular expression is too long."
            case .unsafePattern: "Regular expression uses unsupported nesting or backreferences."
            case let .invalidSyntax(detail): detail
            }
        }
    }

    private struct GroupFrame {
        var hasInnerQuantifier = false
    }

    /// Validates `pattern` against length, backreference, quantifier bound and
    /// nested-quantifier limits before handing it to ICU (`NSRegularExpression`).
    public static func validate(_ pattern: String) throws {
        guard pattern.count <= maxPatternLength else { throw Rejection.tooLong }
        let chars = Array(pattern)
        var i = 0
        var inCharClass = false
        var stack: [GroupFrame] = [GroupFrame()]

        func markQuantifierInCurrentGroup() {
            stack[stack.count - 1].hasInnerQuantifier = true
        }

        func consumeRepeatQuantifier(at index: Int) throws -> (isRepeating: Bool, nextIndex: Int)? {
            guard index < chars.count else { return nil }
            let ch = chars[index]
            if ch == "*" || ch == "+" {
                var next = index + 1
                if next < chars.count && (chars[next] == "?" || chars[next] == "+") { next += 1 }
                return (true, next)
            }
            if ch == "?" {
                var next = index + 1
                if next < chars.count && (chars[next] == "?" || chars[next] == "+") { next += 1 }
                return (false, next)
            }
            if ch == "{" {
                var j = index + 1
                var minStr = ""
                while j < chars.count && chars[j].isASCII && chars[j].isNumber {
                    minStr.append(chars[j]); j += 1
                }
                guard !minStr.isEmpty, j < chars.count else { return nil }
                var hasComma = false
                var maxStr = ""
                if chars[j] == "," {
                    hasComma = true
                    j += 1
                    while j < chars.count && chars[j].isASCII && chars[j].isNumber {
                        maxStr.append(chars[j]); j += 1
                    }
                }
                guard j < chars.count && chars[j] == "}" else { return nil }
                guard let minVal = Int(minStr), minVal <= maxQuantifierBound else { throw Rejection.unsafePattern }
                let repeating: Bool
                if hasComma {
                    if maxStr.isEmpty {
                        repeating = true
                    } else {
                        guard let maxVal = Int(maxStr), maxVal <= maxQuantifierBound else { throw Rejection.unsafePattern }
                        repeating = maxVal > 1
                    }
                } else {
                    repeating = minVal > 1
                }
                var next = j + 1
                if next < chars.count && (chars[next] == "?" || chars[next] == "+") { next += 1 }
                return (repeating, next)
            }
            return nil
        }

        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" {
                let next = i + 1
                guard next < chars.count else { break }
                if !inCharClass {
                    let escaped = chars[next]
                    // Backreferences (\1..\9, \k<name>) can cause exponential backtracking.
                    if escaped >= "1" && escaped <= "9" { throw Rejection.unsafePattern }
                    if escaped == "k" && next + 1 < chars.count && chars[next + 1] == "<" {
                        throw Rejection.unsafePattern
                    }
                }
                i += 2
                continue
            }
            if inCharClass {
                if ch == "]" { inCharClass = false }
                i += 1
                continue
            }
            if ch == "[" {
                inCharClass = true
                i += 1
                if i < chars.count && chars[i] == "^" { i += 1 }
                if i < chars.count && chars[i] == "]" { i += 1 }
                continue
            }
            if ch == "(" {
                stack.append(GroupFrame())
                i += 1
                // Skip group header like (?: ...), (?i), (?i:...), (?=...), (?!...)
                if i < chars.count && chars[i] == "?" {
                    i += 1
                    while i < chars.count {
                        let h = chars[i]
                        if h == ":" || h == "=" || h == "!" || h == ">" {
                            i += 1
                            break
                        }
                        if h == ")" {
                            // Inline flag toggle such as (?i) closes immediately.
                            break
                        }
                        if h == "<" {
                            // Named group (?<name>...) or lookbehind (?<= / ?<!)
                            i += 1
                            if i < chars.count && (chars[i] == "=" || chars[i] == "!") {
                                i += 1; break
                            }
                            while i < chars.count && chars[i] != ">" { i += 1 }
                            if i < chars.count { i += 1 }
                            break
                        }
                        if h.isLetter || h == "-" {
                            i += 1
                            continue
                        }
                        break
                    }
                }
                continue
            }
            if ch == ")" {
                if stack.count > 1 {
                    let closed = stack.removeLast()
                    i += 1
                    if let quant = try consumeRepeatQuantifier(at: i) {
                        if quant.isRepeating && closed.hasInnerQuantifier {
                            throw Rejection.unsafePattern
                        }
                        markQuantifierInCurrentGroup()
                        i = quant.nextIndex
                    } else if closed.hasInnerQuantifier {
                        markQuantifierInCurrentGroup()
                    }
                } else {
                    i += 1
                }
                continue
            }
            if let quant = try consumeRepeatQuantifier(at: i) {
                markQuantifierInCurrentGroup()
                i = quant.nextIndex
                continue
            }
            i += 1
        }
    }

    public static func compile(_ pattern: String, options: NSRegularExpression.Options = []) throws -> NSRegularExpression {
        try validate(pattern)
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw Rejection.invalidSyntax(error.localizedDescription)
        }
    }

    public static func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        guard text.count <= maxInputLength else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
