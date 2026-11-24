import Foundation
import Darwin

/// Uses macOS's libarchive-backed bsdtar. No shell, extra installation, or
/// password prompt; every output stays private until the engine commits it.
enum ZIPArchives {
    struct PreflightSummary: Equatable, Sendable {
        let entryCount: UInt64
        let compressedBytes: UInt64
        let uncompressedBytes: UInt64
    }

    struct PreflightLimits: Sendable {
        let maxEntries: UInt64
        let maxUncompressedBytes: UInt64
        let maxExpansionRatio: Double
        let minBytesForRatioCheck: UInt64

        static let standard = Self(
            maxEntries: 100_000,
            maxUncompressedBytes: 10 * 1024 * 1024 * 1024, // 10 GiB
            maxExpansionRatio: 100.0,
            minBytesForRatioCheck: 100 * 1024 * 1024 // 100 MiB
        )
    }

    static func compress(_ sources: [URL], to output: URL, workspace: URL) async throws {
        guard let first = sources.first else { throw FileOperationError(L10n.text("Select at least one item to compress.")) }
        var parent = first.deletingLastPathComponent()
        while sources.contains(where: { !($0.path.hasPrefix(parent.path == "/" ? "/" : parent.path + "/")) }) {
            parent.deleteLastPathComponent()
        }
        // NUL-delimited relative paths support newlines, leading dashes and @.
        // A common parent also retains distinct paths for search-result selections.
        let prefix = parent.path == "/" ? "/" : parent.path + "/"
        let paths = sources.map { "./" + $0.path.dropFirst(prefix.count) }
        let list = workspace.appendingPathComponent("inputs")
        try Data((paths.joined(separator: "\0") + "\0").utf8).write(to: list)
        try await run(["-c", "--format", "zip", "--no-mac-metadata", "-f", output.path,
                       "--null", "-T", list.path], directory: parent, workspace: workspace)
    }

    static func extract(_ source: URL, to output: URL, workspace: URL) async throws {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw FileOperationError(L10n.text("Choose a regular ZIP file to extract.")) }
        let file = try FileHandle(forReadingFrom: source); defer { try? file.close() }
        let header = try file.read(upToCount: 4) ?? Data()
        guard [Data([0x50, 0x4b, 3, 4]), Data([0x50, 0x4b, 5, 6]), Data([0x50, 0x4b, 7, 8])].contains(header) else {
            throw FileOperationError(L10n.text("This file is not a supported ZIP archive."))
        }
        try validateBeforeExtract(source, destinationParent: output.deletingLastPathComponent())
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        // Never use -P or -U: bsdtar's default checks reject ../ paths and writes
        // through symlinks; absolute names are confined by stripping their root.
        try await run(["-x", "-f", source.path, "--no-same-owner", "--no-same-permissions",
                       "--no-mac-metadata", "--no-xattrs", "--no-acls", "--no-fflags", "--safe-writes"],
                      directory: output, workspace: workspace)
        guard try FileManager.default.attributesOfItem(atPath: output.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw FileOperationError(L10n.text("The ZIP attempted to replace the extraction folder."))
        }
        try propagateQuarantine(from: source, to: output)
    }

    private static func run(_ arguments: [String], directory: URL, workspace: URL) async throws {
        try Task.checkCancellation()
        let log = workspace.appendingPathComponent("archive.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errors = try FileHandle(forWritingTo: log); defer { try? errors.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments; process.currentDirectoryURL = directory
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8", "COPYFILE_DISABLE": "1"]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        do {
            while process.isRunning { try await Task.sleep(for: .milliseconds(50)) }
            try Task.checkCancellation()
        } catch {
            if process.isRunning { process.terminate() }
            var waits = 0
            while process.isRunning {
                if waits == 20 { kill(process.processIdentifier, SIGKILL) }
                // A detached sleep lets the child exit before staging is removed,
                // even though the parent operation has already been cancelled.
                await Task.detached { try? await Task.sleep(for: .milliseconds(50)) }.value
                waits += 1
            }
            throw error
        }
        guard process.terminationStatus == 0 else {
            let reader = try FileHandle(forReadingFrom: log); defer { try? reader.close() }
            let data = try reader.read(upToCount: 4096) ?? Data()
            let detail = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw FileOperationError(L10n.text("The ZIP operation could not finish. Password-protected archives are not supported.\n\n%1$@", detail))
        }
    }

    /// Reads the ZIP Central Directory without decompressing any payload to detect
    /// zip bombs (extreme compression ratio, excessive entry count, or insufficient free space).
    static func inspect(_ source: URL) throws -> PreflightSummary? {
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { return nil }

        let tailSize = min(fileSize, 65_557)
        try handle.seek(toOffset: fileSize - tailSize)
        guard let tail = try handle.read(upToCount: Int(tailSize)), tail.count >= 22 else { return nil }

        // Scan backwards for End of Central Directory signature 0x06054b50.
        var eocdIndex: Int?
        var idx = tail.count - 22
        while idx >= 0 {
            if tail[idx] == 0x50 && tail[idx + 1] == 0x4b && tail[idx + 2] == 0x05 && tail[idx + 3] == 0x06 {
                let commentLen = Int(readUInt16(tail, at: idx + 20))
                if idx + 22 + commentLen == tail.count {
                    eocdIndex = idx
                    break
                }
            }
            idx -= 1
        }
        guard let eocd = eocdIndex else { return nil }

        var entryCount = UInt64(readUInt16(tail, at: eocd + 10))
        var cdSize = UInt64(readUInt32(tail, at: eocd + 12))
        var cdOffset = UInt64(readUInt32(tail, at: eocd + 16))

        // Check for ZIP64 EOCD Locator (20 bytes right before EOCD).
        if (entryCount == 0xffff || cdSize == 0xffff_ffff || cdOffset == 0xffff_ffff), eocd >= 20 {
            let loc = eocd - 20
            if tail[loc] == 0x50 && tail[loc + 1] == 0x4b && tail[loc + 2] == 0x06 && tail[loc + 3] == 0x07 {
                let zip64Offset = readUInt64(tail, at: loc + 8)
                if zip64Offset + 56 <= fileSize {
                    try handle.seek(toOffset: zip64Offset)
                    if let z64 = try handle.read(upToCount: 56), z64.count == 56,
                       z64[0] == 0x50 && z64[1] == 0x4b && z64[2] == 0x06 && z64[3] == 0x06 {
                        entryCount = readUInt64(z64, at: 32)
                        cdSize = readUInt64(z64, at: 40)
                        cdOffset = readUInt64(z64, at: 48)
                    }
                }
            }
        }

        // Empty archive (no central directory entries).
        if entryCount == 0 && cdSize == 0 {
            return PreflightSummary(entryCount: 0, compressedBytes: 0, uncompressedBytes: 0)
        }
        // Cap Central Directory read to 64 MiB to protect memory.
        let maxCentralDirBytes: UInt64 = 64 * 1024 * 1024
        guard cdSize <= maxCentralDirBytes, cdOffset <= fileSize, cdSize <= fileSize - cdOffset else {
            throw FileOperationError(L10n.text("This archive’s directory exceeds Explorer’s safety limits."))
        }

        try handle.seek(toOffset: cdOffset)
        guard let cd = try handle.read(upToCount: Int(cdSize)), cd.count == Int(cdSize) else { return nil }

        var cursor = 0
        var parsedEntries: UInt64 = 0
        var totalCompressed: UInt64 = 0
        var totalUncompressed: UInt64 = 0

        while cursor + 46 <= cd.count {
            guard cd[cursor] == 0x50 && cd[cursor + 1] == 0x4b && cd[cursor + 2] == 0x01 && cd[cursor + 3] == 0x02 else {
                break
            }
            var comp = UInt64(readUInt32(cd, at: cursor + 20))
            var uncomp = UInt64(readUInt32(cd, at: cursor + 24))
            let nameLen = Int(readUInt16(cd, at: cursor + 28))
            let extraLen = Int(readUInt16(cd, at: cursor + 30))
            let commentLen = Int(readUInt16(cd, at: cursor + 32))
            let headerEnd = cursor + 46 + nameLen + extraLen + commentLen
            guard headerEnd <= cd.count else { break }

            if uncomp == 0xffff_ffff || comp == 0xffff_ffff {
                var ex = cursor + 46 + nameLen
                let exEnd = ex + extraLen
                while ex + 4 <= exEnd {
                    let id = readUInt16(cd, at: ex)
                    let len = Int(readUInt16(cd, at: ex + 2))
                    let fieldStart = ex + 4
                    guard fieldStart + len <= exEnd else { break }
                    if id == 0x0001 {
                        var off = fieldStart
                        if uncomp == 0xffff_ffff, off + 8 <= fieldStart + len {
                            uncomp = readUInt64(cd, at: off); off += 8
                        }
                        if comp == 0xffff_ffff, off + 8 <= fieldStart + len {
                            comp = readUInt64(cd, at: off)
                        }
                        break
                    }
                    ex = fieldStart + len
                }
            }

            parsedEntries += 1
            let (cSum, cOver) = totalCompressed.addingReportingOverflow(comp)
            let (uSum, uOver) = totalUncompressed.addingReportingOverflow(uncomp)
            if cOver || uOver {
                throw FileOperationError(L10n.text("This archive’s uncompressed size exceeds Explorer’s safety limits."))
            }
            totalCompressed = cSum
            totalUncompressed = uSum
            cursor = headerEnd
        }

        let effectiveEntries = max(entryCount, parsedEntries)
        return PreflightSummary(entryCount: effectiveEntries, compressedBytes: totalCompressed, uncompressedBytes: totalUncompressed)
    }

    static func validateBeforeExtract(_ source: URL, destinationParent: URL,
                                      limits: PreflightLimits = .standard,
                                      availableSpace: UInt64? = nil) throws {
        guard let summary = try inspect(source) else { return }
        if summary.entryCount > limits.maxEntries {
            throw FileOperationError(L10n.text("This archive contains too many items to extract safely (%1$@ items).", summary.entryCount))
        }
        if summary.uncompressedBytes > limits.maxUncompressedBytes {
            throw FileOperationError(L10n.text("This archive expands to %1$@, which exceeds Explorer’s safety limit.", L10n.byteCount(Int64(clamping: summary.uncompressedBytes))))
        }
        if summary.uncompressedBytes >= limits.minBytesForRatioCheck {
            let compressedBasis = max(summary.compressedBytes, 1)
            let ratio = Double(summary.uncompressedBytes) / Double(compressedBasis)
            if ratio > limits.maxExpansionRatio {
                throw FileOperationError(L10n.text("This archive has an unusually high compression ratio (%1$@x) and was blocked for safety.", Int(ratio)))
            }
        }
        let freeBytes: UInt64? = availableSpace ?? {
            let values = try? destinationParent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return UInt64(important) }
            if let avail = values?.volumeAvailableCapacity, avail > 0 { return UInt64(avail) }
            return nil
        }()
        if let freeBytes, summary.uncompressedBytes > freeBytes {
            throw FileOperationError(L10n.text("Not enough free disk space to extract this archive (%1$@ needed).", L10n.byteCount(Int64(clamping: summary.uncompressedBytes))))
        }
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(readUInt32(data, at: offset)) | (UInt64(readUInt32(data, at: offset + 4)) << 32)
    }

    /// Downloaded contents must retain the archive's Gatekeeper quarantine.
    private static func propagateQuarantine(from source: URL, to folder: URL) throws {
        let key = "com.apple.quarantine"
        let count = getxattr(source.path, key, nil, 0, 0, 0)
        if count < 0 {
            if errno == ENOATTR || errno == ENOTSUP { return }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard count <= 65_536 else { throw FileOperationError(L10n.text("The ZIP’s quarantine information could not be preserved.")) }
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { getxattr(source.path, key, $0.baseAddress, count, 0, 0) }
        guard read == count else { throw FileOperationError(L10n.text("The ZIP’s quarantine information changed. Try extracting again.")) }
        func apply(_ url: URL) throws {
            try Task.checkCancellation()
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            // Never follow an archive symlink when applying metadata.
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink { return }
            let result = data.withUnsafeBytes { setxattr(url.path, key, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
            guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            if attributes[.type] as? FileAttributeType == .typeDirectory {
                for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { try apply(child) }
            }
        }
        try apply(folder)
    }
}
