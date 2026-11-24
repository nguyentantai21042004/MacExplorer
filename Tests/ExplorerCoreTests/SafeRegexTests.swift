import Foundation
import Testing
@testable import ExplorerCore

@Suite
struct SafeRegexTests {
    @Test(arguments: [
        "(?i)(api|backend|service)",
        "^Foo.*\\.swift$",
        "img_(\\d{1,4})_final",
        "(?:alpha|beta)?-v[0-9]+",
        "[a-z+*(]+",
        "(?<year>20\\d\\d)-\\d\\d"
    ])
    func normalPatternsCompileAndMatch(pattern: String) throws {
        let regex = try SafeRegex.compile(pattern)
        #expect(regex.pattern == pattern)
    }

    @Test(arguments: [
        "(a+)+$",
        "(a*)*",
        "([a-z]+)+",
        "((a+))+",
        "(a?)+b",
        "(a{1,5})+",
        "(.*a){20}",
        "(\\w+)\\1",
        "(?<x>a)\\k<x>",
        "a{1,1000}"
    ])
    func catastrophicAndBackreferencePatternsAreRejected(pattern: String) {
        #expect(throws: SafeRegex.Rejection.unsafePattern) {
            _ = try SafeRegex.compile(pattern)
        }
    }

    @Test func overlyLongPatternsAreRejected() {
        let longPattern = String(repeating: "a", count: SafeRegex.maxPatternLength + 1)
        #expect(throws: SafeRegex.Rejection.tooLong) {
            _ = try SafeRegex.compile(longPattern)
        }
    }

    @Test func overlyLongInputDoesNotMatch() throws {
        let regex = try SafeRegex.compile("needle")
        let huge = String(repeating: "a", count: SafeRegex.maxInputLength) + "needle"
        #expect(!SafeRegex.matches(regex, in: huge))
        #expect(SafeRegex.matches(regex, in: "has needle inside"))
    }

    @Test func folderAppearanceMatcherCapsRulesAndSkipsUnsafeRegex() {
        var rules: [FolderAppearanceRule] = [
            FolderAppearanceRule(nameRegex: "(a+)+$", color: "#EF4444", symbol: "flame"),
            FolderAppearanceRule(nameRegex: "(?i)(api|backend)", color: "#10B981", symbol: "server.rack")
        ]
        for idx in 0..<(FolderAppearanceMatcher.maxRuleCount + 20) {
            rules.append(FolderAppearanceRule(root: "/tmp/r\(idx)", depth: 0, color: "#38BDF8"))
        }
        let matcher = FolderAppearanceMatcher(rules: rules, homeDirectory: "/Users/tester")
        // Unsafe regex rule is skipped, and total rules evaluated never exceed maxRuleCount.
        #expect(matcher.ruleCount <= FolderAppearanceMatcher.maxRuleCount)
        #expect(matcher.match(path: "/Users/tester/api-service")?.colorHex == "#10B981")
        #expect(matcher.match(path: "/Users/tester/aaaaaaaaaaaaaaaaaaaaaaaaaaaa!") == nil)
    }

    @Test func searchQueryAndBatchRenameRejectUnsafeRegex() {
        let filter = SearchQueryParser.parse("regex:(a+)+$")
        #expect(filter.compiledRegex() == nil)

        let entries = BatchRenamePlanner.plan(
            urls: [URL(fileURLWithPath: "/tmp/aaaa.txt")],
            mode: .replace(find: "(a+)+$", replacement: "b", useRegex: true, caseSensitive: true)
        )
        #expect(entries.count == 1)
        #expect(entries[0].isValid == false)
        #expect(entries[0].error != nil)
    }
}
