import Foundation
import Testing
@testable import ExplorerCore

@Suite
struct SpotlightSearchTests {
    @Test func searchQueryParserHandlesSpotAndSpotlightTokens() {
        let single = SearchQueryParser.parse("spot:invoice ext:pdf size:>10kb")
        #expect(single.spotlightQuery == "invoice")
        #expect(single.extensions == ["pdf"])
        #expect(single.sizeComparison == .greaterThan(10_000))
        #expect(!single.isEmpty)
        #expect(single.hasAdvancedTokens)
        #expect(single.highlightText == "invoice")

        let quoted = SearchQueryParser.parse("spotlight:\"tax 2026\" type:file")
        #expect(quoted.spotlightQuery == "tax 2026")
        #expect(quoted.itemKind == .file)

        let blank = SearchQueryParser.parse("spot:")
        #expect(blank.spotlightQuery == nil)
        #expect(blank.isEmpty)
    }

    @Test func escapeLikePatternEscapesWildcardsAndBackslash() {
        #expect(SpotlightSearch.escapeLikePattern("plain") == "plain")
        #expect(SpotlightSearch.escapeLikePattern("a*b?c\\d") == "a\\*b\\?c\\\\d")
    }

    @Test func makePredicateBuildsParameterizedPredicateAndBlocksInjection() throws {
        #expect(SpotlightSearch.makePredicate(query: "   ") == nil)

        let simple = try #require(SpotlightSearch.makePredicate(query: "report"))
        #expect(simple.predicateFormat.contains("kMDItemFSName LIKE[cd] \"*report*\""))
        #expect(simple.predicateFormat.contains("kMDItemTextContent CONTAINS[cd] \"report\""))

        let multi = try #require(SpotlightSearch.makePredicate(query: "tax 2026"))
        let compound = try #require(multi as? NSCompoundPredicate)
        #expect(compound.compoundPredicateType == .and)
        #expect(compound.subpredicates.count == 2)

        // Hostile predicate-injection text (" OR kMDItemFSName == "*) splits into 5 literal terms inside parameterized args.
        let hostile = "\" OR kMDItemFSName == \"*"
        let safe = try #require(SpotlightSearch.makePredicate(query: hostile))
        let safeCompound = try #require(safe as? NSCompoundPredicate)
        #expect(safeCompound.compoundPredicateType == .and)
        #expect(safeCompound.subpredicates.count == 5)
        // Term count cap prevents excessive compound predicates.
        let manyTerms = (0..<20).map { "t\($0)" }.joined(separator: " ")
        let capped = try #require(SpotlightSearch.makePredicate(query: manyTerms) as? NSCompoundPredicate)
        #expect(capped.subpredicates.count == SpotlightSearch.maxTerms)
    }

    @Test @MainActor func liveSpotlightRunCompletesCleanlyAndHonoursCancellation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("explorer-spot-\(UUID())")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Empty query returns immediately.
        let empty = await SpotlightSearch.run(query: "   ", scopeURL: root, timeout: 0.5)
        #expect(empty.matches.isEmpty)
        #expect(!empty.timedOut)

        // Real scoped NSMetadataQuery completes or times out cleanly without hanging.
        let start = Date()
        let result = await SpotlightSearch.run(query: "unlikely_token_\(UUID().uuidString)", scopeURL: root, timeout: 0.5)
        #expect(Date().timeIntervalSince(start) < 2.0)
        #expect(result.matches.isEmpty)

        // Cancelling mid-flight finishes cleanly without leaking continuations.
        let task = Task { @MainActor in
            await SpotlightSearch.run(query: "Explorer", scopeURL: nil, timeout: 3.0)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.value
    }
}
