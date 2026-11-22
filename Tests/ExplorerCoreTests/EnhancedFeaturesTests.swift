import Foundation
import Testing
@testable import ExplorerCore

@Suite
struct EnhancedFeaturesTests {
    @Test func searchQueryParserHandlesTokensAndPlainTerms() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let filter = SearchQueryParser.parse("ext:swift,go size:>1mb mod:<7d type:file regex:^Foo content:hello order", now: now)
        #expect(filter.extensions == ["swift", "go"])
        #expect(filter.sizeComparison == .greaterThan(1_000_000))
        #expect(filter.modifiedAfter == now.addingTimeInterval(-7 * 86_400))
        #expect(filter.itemKind == .file)
        #expect(filter.regexPattern == "^Foo")
        #expect(filter.contentQuery == "hello")
        #expect(filter.plainTerms == ["order"])

        let matching = FileItem(
            url: URL(fileURLWithPath: "/tmp/FooOrder.swift"),
            name: "FooOrder.swift",
            isDirectory: false,
            modified: now.addingTimeInterval(-3600),
            size: 2_000_000
        )
        let tooSmall = FileItem(
            url: URL(fileURLWithPath: "/tmp/FooOrder.swift"),
            name: "FooOrder.swift",
            isDirectory: false,
            modified: now.addingTimeInterval(-3600),
            size: 500
        )
        let regex = filter.compiledRegex()
        #expect(filter.matchesMetadata(matching, regex: regex))
        #expect(!filter.matchesMetadata(tooSmall, regex: regex))
    }

    @Test func directorySearchSupportsContentAndExtensionTokens() async throws {
        actor Collector {
            var items: [FileItem] = []
            func append(_ matches: [FileItem]) { items.append(contentsOf: matches) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-adv-search-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let goFile = root.appendingPathComponent("main.go")
        let mdFile = root.appendingPathComponent("notes.md")
        try Data("package main\nfunc helloWorld() {}".utf8).write(to: goFile)
        try Data("helloWorld in markdown".utf8).write(to: mdFile)

        let collector = Collector()
        _ = try await DirectorySearch.run(root: root, query: "ext:go content:helloWorld") { update in
            await collector.append(update.matches)
        }
        let matches = await collector.items
        #expect(matches.map(\.name) == ["main.go"])
    }

    @Test func folderSizeCalculatorMeasuresRegularFilesAndCaches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-size-\(UUID())")
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(repeating: 65, count: 4096).write(to: root.appendingPathComponent("a.bin"))
        try Data(repeating: 66, count: 4096).write(to: sub.appendingPathComponent("b.bin"))

        let result = try FolderSizeCalculator.measure(root)
        #expect(result.itemCount == 2)
        #expect(result.bytes >= 8192)

        let cache = FolderSizeCache()
        let stamp = Date()
        await cache.store(result, for: root, modified: stamp)
        #expect(await cache.cached(for: root, modified: stamp) == result)
        #expect(await cache.cached(for: root, modified: stamp.addingTimeInterval(5)) == nil)
    }

    @Test func batchRenamePlannerAndEngineExecuteWithSingleUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-batch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let a = root.appendingPathComponent("img_1.txt")
        let b = root.appendingPathComponent("img_2.txt")
        try Data("one".utf8).write(to: a)
        try Data("two".utf8).write(to: b)

        let plan = BatchRenamePlanner.plan(urls: [a, b], mode: .replace(find: "img_", replacement: "photo_", useRegex: false, caseSensitive: false))
        #expect(plan.allSatisfy { $0.isValid })
        #expect(plan.map(\.newName) == ["photo_1.txt", "photo_2.txt"])

        let duplicatePlan = BatchRenamePlanner.plan(urls: [a, b], mode: .affix(prefix: "", suffix: ""), includeExtension: false)
        #expect(duplicatePlan.allSatisfy { !$0.changed })

        let engine = FileOperationEngine()
        let pairs = plan.map { ($0.source, $0.newName) }
        let report = await engine.perform(.batchRename(pairs))
        #expect(report.error == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("photo_1.txt").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("photo_2.txt").path))
        #expect(await engine.undoTitle == "Batch Rename")

        let undoReport = await engine.undo()
        #expect(undoReport.error == nil)
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    @Test func gitRepoReaderDetectsBranchFromHead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-git-\(UUID())")
        let dotGit = root.appendingPathComponent(".git")
        let nested = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("ref: refs/heads/feat/custom-ui\n".utf8).write(to: dotGit.appendingPathComponent("HEAD"))
        let foundRoot = GitRepoReader.findRepoRoot(for: nested)
        #expect(foundRoot?.standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(GitRepoReader.readBranchFast(at: root) == "feat/custom-ui")
    }

    @Test func favoritesReorderAndInsertAtPosition() {
        let a = Favorite(url: URL(fileURLWithPath: "/tmp/A"))
        let b = Favorite(url: URL(fileURLWithPath: "/tmp/B"))
        let c = Favorite(url: URL(fileURLWithPath: "/tmp/C"))
        var favs = Favorites([a, b, c])

        favs.move(c.id, to: 0)
        #expect(favs.items.map(\.name) == ["C", "A", "B"])

        favs.move(c.id, to: 2)
        #expect(favs.items.map(\.name) == ["A", "B", "C"])

        let d = URL(fileURLWithPath: "/tmp/D")
        favs.insert(d, at: 1)
        #expect(favs.items.map(\.name) == ["A", "D", "B", "C"])

        // Re-inserting an existing URL moves it instead of duplicating.
        favs.insert(d, at: 4)
        #expect(favs.items.map(\.name) == ["A", "B", "C", "D"])
    }

    @Test func directorySearchSkipsNoisyBuildDirsByDefaultAndCoalescesFolderSizes() async throws {
        actor Collector {
            var items: [FileItem] = []
            func append(_ matches: [FileItem]) { items.append(contentsOf: matches) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-skip-\(UUID())")
        let nm = root.appendingPathComponent("node_modules/pkg")
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("export const needle = 1".utf8).write(to: nm.appendingPathComponent("index.js"))
        try Data("export const needle = 2".utf8).write(to: src.appendingPathComponent("app.js"))

        let defaultCollector = Collector()
        _ = try await DirectorySearch.run(root: root, query: "content:needle") { update in
            await defaultCollector.append(update.matches)
        }
        #expect(await defaultCollector.items.map(\.name) == ["app.js"])

        #expect(FolderSizeCalculator.shouldSkipAutomaticMeasurement(URL(fileURLWithPath: "/")))
        #expect(FolderSizeCalculator.shouldSkipAutomaticMeasurement(URL(fileURLWithPath: "/System")))
        #expect(!FolderSizeCalculator.shouldSkipAutomaticMeasurement(root))

        let cache = FolderSizeCache()
        let first = await cache.measureIfNeeded(for: src, modified: nil)
        let second = await cache.measureIfNeeded(for: src, modified: nil)
        #expect(first == second)
        #expect(first?.itemCount == 1)
    }
}
