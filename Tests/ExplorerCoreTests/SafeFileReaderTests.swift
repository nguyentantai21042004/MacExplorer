import Foundation
import Darwin
import Testing
@testable import ExplorerCore

/// Each test that touches a FIFO would hang forever under the old
/// `FileHandle(forReadingFrom:)` / `Data(contentsOf:)` code, because `open(2)`
/// on a pipe without a writer blocks. Passing quickly is the proof.
@Suite
struct SafeFileReaderTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-safe-read-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func readsAPrefixOfARegularFile() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        try Data("hello world".utf8).write(to: file)
        #expect(try SafeFileReader.readPrefix(of: file, limit: 5) == Data("hello".utf8))
        #expect(try SafeFileReader.readPrefix(of: file, limit: 1000) == Data("hello world".utf8))
        #expect(try SafeFileReader.readPrefix(of: file, limit: 0) == Data())
    }

    @Test func fifoIsRefusedWithoutBlocking() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fifo = root.appendingPathComponent("notes.txt")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let start = Date()
        #expect(throws: SafeFileReader.Failure.notRegularFile) { try SafeFileReader.readPrefix(of: fifo, limit: 100) }
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(!SafeFileReader.isRegularFile(fifo))
    }

    @Test func symlinkToFifoIsRefusedEvenWhenFollowing() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fifo = root.appendingPathComponent("pipe")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let link = root.appendingPathComponent("readme.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fifo)
        #expect(throws: SafeFileReader.Failure.notRegularFile) { try SafeFileReader.readPrefix(of: link, limit: 100) }
    }

    @Test func symlinkPolicyIsHonoured() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.txt"), link = root.appendingPathComponent("link.txt")
        try Data("secret".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try SafeFileReader.readPrefix(of: link, limit: 100) == Data("secret".utf8))
        #expect(throws: SafeFileReader.Failure.symbolicLink) {
            try SafeFileReader.readPrefix(of: link, limit: 100, followSymlinks: false)
        }
    }

    @Test func directoriesMissingFilesAndSizeCapsFail() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: SafeFileReader.Failure.notRegularFile) { try SafeFileReader.readPrefix(of: root, limit: 10) }
        #expect(throws: SafeFileReader.Failure.system(ENOENT)) {
            try SafeFileReader.readPrefix(of: root.appendingPathComponent("missing"), limit: 10)
        }
        let big = root.appendingPathComponent("big.bin")
        try Data(count: 2048).write(to: big)
        #expect(throws: SafeFileReader.Failure.tooLarge(2048)) {
            try SafeFileReader.readPrefix(of: big, limit: 10, maxFileSize: 1024)
        }
    }

    @Test func unixSocketIsRefused() throws {
        // sockaddr_un.sun_path is 104 bytes, so keep the socket path short.
        let path = "/tmp/explorer-sock-\(getpid())-\(UInt32.random(in: 0...UInt32.max))"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { close(fd); unlink(path) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            path.utf8CString.withUnsafeBytes { buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count))) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(bound == 0)
        #expect(throws: SafeFileReader.Failure.self) { try SafeFileReader.readPrefix(of: URL(fileURLWithPath: path), limit: 10) }
    }
}

@Suite
struct PreviewTextTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-preview-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func textPreviewReturnsContent() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("main.swift")
        try Data("let x = 1\n".utf8).write(to: file)
        #expect(PreviewText.snippet(of: file) == "let x = 1\n")
    }

    @Test func exactLimitIsNotMarkedTruncatedButLargerIs() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let exact = root.appendingPathComponent("exact.txt"), larger = root.appendingPathComponent("larger.txt")
        try Data(repeating: 0x61, count: PreviewText.byteLimit).write(to: exact)
        try Data(repeating: 0x61, count: PreviewText.byteLimit + 10).write(to: larger)
        #expect(PreviewText.snippet(of: exact)?.hasSuffix(PreviewText.truncationNote) == false)
        let long = try #require(PreviewText.snippet(of: larger))
        #expect(long.hasSuffix(PreviewText.truncationNote))
        #expect(long.utf8.count == PreviewText.byteLimit + PreviewText.truncationNote.utf8.count)
    }

    @Test func binaryAndFifoFallBackToThumbnail() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appendingPathComponent("data.json")
        try Data([0x7b, 0x00, 0x7d]).write(to: binary)
        #expect(PreviewText.snippet(of: binary) == nil)
        let fifo = root.appendingPathComponent("server.log")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(PreviewText.snippet(of: fifo) == nil)
    }

    @Test func contentSearchSkipsFifosAndStillFindsRealFiles() async throws {
        actor Collector {
            var names: [String] = []
            func append(_ items: [FileItem]) { names += items.map(\.name) }
        }
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("needle here".utf8).write(to: root.appendingPathComponent("real.txt"))
        #expect(mkfifo(root.appendingPathComponent("pipe.txt").path, 0o600) == 0)
        let collector = Collector()
        _ = try await DirectorySearch.run(root: root, query: "content:needle") { await collector.append($0.matches) }
        #expect(await collector.names == ["real.txt"])
    }
}
