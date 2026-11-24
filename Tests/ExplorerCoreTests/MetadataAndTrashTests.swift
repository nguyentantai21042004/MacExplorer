import Darwin
import Foundation
import Testing
@testable import ExplorerCore

@Suite
struct MetadataAndTrashTests {
    private func makeRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("explorer-p2-\(name)-\(UUID())")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: FileMetadataInspector & Permissions

    @Test func inspectsFileSymlinkBrokenLinkAndQuarantine() throws {
        let root = try makeRoot("inspect")
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("sample.txt")
        try Data("abc".utf8).write(to: file)
        let quarantine = Data("0081;12345678;Safari;".utf8)
        #expect(quarantine.withUnsafeBytes { setxattr(file.path, "com.apple.quarantine", $0.baseAddress, quarantine.count, 0, 0) } == 0)

        let info = try FileMetadataInspector.inspect(file)
        #expect(info.name == "sample.txt")
        #expect(info.isRegularFile)
        #expect(!info.isDirectory)
        #expect(!info.isSymbolicLink)
        #expect(info.size == 3)
        #expect(info.quarantineSummary == "Quarantined (from Safari)")
        #expect(info.canModifyPermissions)

        let goodLink = root.appendingPathComponent("good-link")
        try FileManager.default.createSymbolicLink(at: goodLink, withDestinationURL: file)
        let goodInfo = try FileMetadataInspector.inspect(goodLink)
        #expect(goodInfo.isSymbolicLink)
        #expect(!goodInfo.symlinkBroken)
        #expect(goodInfo.symlinkTarget == file.path)
        #expect(!goodInfo.canModifyPermissions)

        let brokenLink = root.appendingPathComponent("broken-link")
        try FileManager.default.createSymbolicLink(atPath: brokenLink.path, withDestinationPath: "/nonexistent/target-\(UUID())")
        let brokenInfo = try FileMetadataInspector.inspect(brokenLink)
        #expect(brokenInfo.isSymbolicLink)
        #expect(brokenInfo.symlinkBroken)
    }

    @Test func togglesLockedHideExtensionAndPOSIXPermissionsSafely() throws {
        let root = try makeRoot("perms")
        defer { try? FileManager.default.removeItem(at: root) }

        let script = root.appendingPathComponent("run.sh")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        try FileMetadataInspector.setPermissions(0o755, at: script)

        let initial = try FileMetadataInspector.inspect(script)
        let perms = try #require(initial.permissions)
        #expect(perms.octalString == "0755")
        #expect(perms.symbolicString == "rwxr-xr-x")
        #expect(perms.ownerAccess == .readWrite)
        #expect(perms.groupAccess == .readOnly)
        #expect(perms.everyoneAccess == .readOnly)

        // Updating group to noAccess and everyone to noAccess preserves owner +x.
        let updatedMode = perms.updating(group: .noAccess, everyone: .noAccess)
        #expect(updatedMode == 0o700)
        try FileMetadataInspector.setPermissions(updatedMode, at: script)
        let after = try FileMetadataInspector.inspect(script)
        #expect(after.permissions?.octalString == "0700")
        #expect(after.permissions?.symbolicString == "rwx------")

        // Locked and hide extension flags round-trip.
        try FileMetadataInspector.setExtensionHidden(true, at: script)
        #expect(try FileMetadataInspector.inspect(script).isExtensionHidden == true)
        try FileMetadataInspector.setLocked(true, at: script)
        #expect(try FileMetadataInspector.inspect(script).isLocked == true)
        try FileMetadataInspector.setLocked(false, at: script)
        #expect(try FileMetadataInspector.inspect(script).isLocked == false)

        // Symlinks and protected system paths are refused.
        let link = root.appendingPathComponent("link.sh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: script)
        #expect(throws: Error.self) { try FileMetadataInspector.setPermissions(0o600, at: link) }
        #expect(throws: Error.self) { try FileMetadataInspector.setPermissions(0o755, at: URL(fileURLWithPath: "/Applications")) }
        #expect(throws: Error.self) { try FileMetadataInspector.setLocked(true, at: URL(fileURLWithPath: "/System")) }
    }

    @Test func customFinderTagsRoundTripAndRefuseSymlinks() throws {
        let root = try makeRoot("tags")
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("doc.md")
        try Data("# hi\n".utf8).write(to: file)

        let desired = [
            FinderTag(name: "Release", color: .green),
            FinderTag(name: "Urgent", color: .red),
            FinderTag(name: "urgent", color: .blue), // case-insensitive duplicate ignored
            FinderTag(name: "Backend", color: .none)
        ]
        try FinderColors.writeTagsList(desired, at: file)
        let readBack = try FinderColors.readTagsList(at: file)
        #expect(readBack == [
            FinderTag(name: "Release", color: .green),
            FinderTag(name: "Urgent", color: .red),
            FinderTag(name: "Backend", color: .none)
        ])

        // Clearing tags removes xattr cleanly.
        try FinderColors.writeTagsList([], at: file)
        #expect(try FinderColors.readTagsList(at: file).isEmpty)

        let link = root.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: Error.self) { try FinderColors.writeTagsList([FinderTag(name: "Bad", color: .red)], at: link) }
    }

    @Test func sha256ComputesKnownVectorAndRefusesFifos() async throws {
        let root = try makeRoot("sha256")
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        let digest = try await FileMetadataInspector.sha256Hex(of: file)
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        let fifo = root.appendingPathComponent("pipe.bin")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        await #expect(throws: SafeFileReader.Failure.notRegularFile) {
            _ = try await FileMetadataInspector.sha256Hex(of: fifo)
        }
    }

    // MARK: TrashJournal & TrashOperations

    @Test func trashJournalPersistsAcrossRestartAndPutBackRefusesOverwrite() async throws {
        let root = try makeRoot("trash")
        defer { try? FileManager.default.removeItem(at: root) }

        let work = root.appendingPathComponent("Work", isDirectory: true)
        let trash = root.appendingPathComponent("MockTrash", isDirectory: true)
        let journalFile = root.appendingPathComponent("journal.json")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)

        let original = work.appendingPathComponent("report.txt")
        try Data("important".utf8).write(to: original)

        let journal1 = TrashJournal(storageURL: journalFile)
        let engine = FileOperationEngine(
            trashItem: { url in
                let dst = trash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dst)
                return dst
            },
            onTrashed: { trashed, src in
                journal1.record(trashedURL: trashed, originalURL: src)
            }
        )

        let report = await engine.perform(.trash([original]))
        #expect(report.error == nil)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        let trashed = trash.appendingPathComponent("report.txt")
        #expect(FileManager.default.fileExists(atPath: trashed.path))

        // Reload a brand-new TrashJournal to simulate app restart.
        let journal2 = TrashJournal(storageURL: journalFile)
        #expect(journal2.originalURL(for: trashed)?.path == original.path)

        // If a conflicting file now occupies the original path, Put Back must refuse instead of overwriting.
        try Data("new version".utf8).write(to: original)
        #expect(throws: Error.self) { _ = try TrashOperations.putBack(trashed, journal: journal2) }
        #expect(try String(contentsOf: original, encoding: .utf8) == "new version")

        // Remove conflict and Put Back succeeds atomically.
        try FileManager.default.removeItem(at: original)
        let restored = try TrashOperations.putBack(trashed, journal: journal2)
        #expect(restored.path == original.path)
        #expect(try String(contentsOf: original, encoding: .utf8) == "important")
        #expect(!FileManager.default.fileExists(atPath: trashed.path))
        #expect(journal2.originalURL(for: trashed) == nil)
    }

    @Test func permanentDeleteConfinesToTrashRootsAndEmptyTrashClearsTrash() throws {
        let root = try makeRoot("trash-delete")
        defer { try? FileManager.default.removeItem(at: root) }

        let trash = root.appendingPathComponent("MockTrash", isDirectory: true)
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let journal = TrashJournal(storageURL: root.appendingPathComponent("journal.json"))
        let keepFile = outside.appendingPathComponent("keep.txt")
        let junk1 = trash.appendingPathComponent("junk1.txt")
        let junk2 = trash.appendingPathComponent("junk2.txt")
        try Data("keep".utf8).write(to: keepFile)
        try Data("1".utf8).write(to: junk1)
        try Data("2".utf8).write(to: junk2)
        journal.record(trashedURL: junk1, originalURL: outside.appendingPathComponent("junk1.txt"))

        // Refuses to permanently delete any item outside allowedTrashRoots.
        #expect(throws: Error.self) {
            _ = try TrashOperations.deletePermanently([keepFile], allowedTrashRoots: [trash], journal: journal)
        }
        #expect(FileManager.default.fileExists(atPath: keepFile.path))

        // Deletes item strictly inside Trash.
        let deletedOne = try TrashOperations.deletePermanently([junk1], allowedTrashRoots: [trash], journal: journal)
        #expect(deletedOne == 1)
        #expect(!FileManager.default.fileExists(atPath: junk1.path))
        #expect(journal.originalURL(for: junk1) == nil)

        // Empty Trash clears remaining items.
        let emptied = try TrashOperations.emptyTrash(directories: [trash], journal: journal)
        #expect(emptied == 1)
        #expect(!FileManager.default.fileExists(atPath: junk2.path))
    }

    // MARK: ServerURLValidator & Volume Ejectability

    @Test func serverURLValidatorAllowsNetworkSchemesAndBlocksDangerousOnes() {
        for valid in ["smb://nas.local/media", "nfs://10.0.0.5/export", "afp://files.local/share", "webdav://dav.example.com/root", "https://dav.example.com/files"] {
            #expect(ServerURLValidator.validate(valid) != nil, "Expected \(valid) to be valid")
        }
        for invalid in ["", "   ", "file:///etc/passwd", "javascript:alert(1)", "applescript://com.apple.scripteditor", "smb://", "smb://bad host/share", "ssh://root@box"] {
            #expect(ServerURLValidator.validate(invalid) == nil, "Expected \(invalid) to be rejected")
        }
    }

    @Test func ejectableFlagAppliesOnlyToExternalAndNetworkVolumes() {
        let rootDisk = StorageLocation(url: URL(fileURLWithPath: "/"), title: "Macintosh HD", kind: .internalDrive)
        let extDisk = StorageLocation(url: URL(fileURLWithPath: "/Volumes/USB"), title: "USB", kind: .externalDrive)
        let netShare = StorageLocation(url: URL(fileURLWithPath: "/Volumes/NAS"), title: "NAS", kind: .network)
        let gdrive = StorageLocation(url: URL(fileURLWithPath: "/Users/t/Library/CloudStorage/GoogleDrive"), title: "Google Drive", kind: .googleDrive)

        #expect(!rootDisk.isEjectable)
        #expect(extDisk.isEjectable)
        #expect(netShare.isEjectable)
        #expect(!gdrive.isEjectable)
    }
}
