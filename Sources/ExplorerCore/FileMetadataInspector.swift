import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

public struct POSIXPermissionsSummary: Equatable, Sendable {
    public enum AccessLevel: String, CaseIterable, Sendable {
        case readWrite
        case readOnly
        case writeOnly
        case noAccess

        public var title: String {
            switch self {
            case .readWrite: "Read & Write"
            case .readOnly: "Read only"
            case .writeOnly: "Write only"
            case .noAccess: "No Access"
            }
        }
    }

    public let mode: UInt16
    public let ownerID: uid_t
    public let groupID: gid_t
    public let ownerName: String
    public let groupName: String
    public let isDirectory: Bool

    public init(mode: UInt16, ownerID: uid_t, groupID: gid_t, ownerName: String, groupName: String, isDirectory: Bool) {
        self.mode = mode & 0o7777
        self.ownerID = ownerID
        self.groupID = groupID
        self.ownerName = ownerName
        self.groupName = groupName
        self.isDirectory = isDirectory
    }

    public var ownerAccess: AccessLevel { Self.accessLevel(bits: (mode >> 6) & 0o7) }
    public var groupAccess: AccessLevel { Self.accessLevel(bits: (mode >> 3) & 0o7) }
    public var everyoneAccess: AccessLevel { Self.accessLevel(bits: mode & 0o7) }

    public var octalString: String {
        String(format: "%04o", mode & 0o7777)
    }

    public var symbolicString: String {
        func triad(_ bits: UInt16) -> String {
            let r = (bits & 0o4) != 0 ? "r" : "-"
            let w = (bits & 0o2) != 0 ? "w" : "-"
            let x = (bits & 0o1) != 0 ? "x" : "-"
            return r + w + x
        }
        return triad((mode >> 6) & 0o7) + triad((mode >> 3) & 0o7) + triad(mode & 0o7)
    }

    public func updating(owner: AccessLevel? = nil, group: AccessLevel? = nil, everyone: AccessLevel? = nil) -> UInt16 {
        var result = mode & 0o7777
        if let owner {
            result = (result & ~UInt16(0o700)) | (Self.bits(for: owner, existing: (result >> 6) & 0o7, isDirectory: isDirectory) << 6)
        }
        if let group {
            result = (result & ~UInt16(0o070)) | (Self.bits(for: group, existing: (result >> 3) & 0o7, isDirectory: isDirectory) << 3)
        }
        if let everyone {
            result = (result & ~UInt16(0o007)) | Self.bits(for: everyone, existing: result & 0o7, isDirectory: isDirectory)
        }
        return result
    }

    private static func accessLevel(bits: UInt16) -> AccessLevel {
        let r = (bits & 0o4) != 0
        let w = (bits & 0o2) != 0
        switch (r, w) {
        case (true, true): return .readWrite
        case (true, false): return .readOnly
        case (false, true): return .writeOnly
        case (false, false): return .noAccess
        }
    }

    private static func bits(for level: AccessLevel, existing: UInt16, isDirectory: Bool) -> UInt16 {
        // Keep execute bit on files that already had it; directories need +x whenever readable or writable.
        let keepExec: UInt16
        switch level {
        case .noAccess:
            keepExec = 0
        case .readWrite, .readOnly, .writeOnly:
            keepExec = isDirectory ? 0o1 : (existing & 0o1)
        }
        switch level {
        case .readWrite: return 0o6 | keepExec
        case .readOnly: return 0o4 | keepExec
        case .writeOnly: return 0o2 | keepExec
        case .noAccess: return 0
        }
    }
}

public struct FileMetadataSnapshot: Equatable, Sendable {
    public let url: URL
    public let name: String
    public let kind: String
    public let contentTypeIdentifier: String?
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isSymbolicLink: Bool
    public let isRegularFile: Bool
    public let symlinkTarget: String?
    public let symlinkBroken: Bool
    public let size: Int64?
    public let allocatedSize: Int64?
    public let created: Date?
    public let modified: Date?
    public let lastOpened: Date?
    public let isLocked: Bool
    public let isExtensionHidden: Bool
    public let quarantineSummary: String?
    public let tags: [FinderTag]
    public let permissions: POSIXPermissionsSummary?
    public let canModifyPermissions: Bool
}

public enum FileMetadataInspector {
    public static func inspect(_ url: URL) throws -> FileMetadataSnapshot {
        let standardized = url.standardizedFileURL
        var st = stat()
        let statOK = standardized.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &st)
        }
        guard statOK == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: standardized.path])
        }

        let isSymlink = (st.st_mode & S_IFMT) == S_IFLNK
        let isRegular = (st.st_mode & S_IFMT) == S_IFREG
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .fileSizeKey, .fileAllocatedSizeKey,
            .creationDateKey, .contentModificationDateKey, .contentAccessDateKey,
            .isUserImmutableKey, .hasHiddenExtensionKey, .localizedTypeDescriptionKey, .contentTypeKey
        ]
        let values = try? standardized.resourceValues(forKeys: keys)

        var isDir = values?.isDirectory ?? ((st.st_mode & S_IFMT) == S_IFDIR)
        var symlinkTarget: String?
        var symlinkBroken = false
        if isSymlink {
            symlinkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: standardized.path)
            var targetIsDir = ObjCBool(false)
            if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &targetIsDir) {
                isDir = targetIsDir.boolValue
            } else {
                symlinkBroken = true
            }
        }

        let isPackage = values?.isPackage ?? false
        let kind: String = {
            if isSymlink { return symlinkBroken ? "Broken Symbolic Link" : "Symbolic Link" }
            if let localized = values?.localizedTypeDescription, !localized.isEmpty { return localized }
            if isDir && !isPackage { return L10n.text("Folder") }
            return standardized.pathExtension.isEmpty ? L10n.text("File") : "\(standardized.pathExtension.uppercased()) file"
        }()

        let ownerName: String = {
            if let pw = getpwuid(st.st_uid), let name = pw.pointee.pw_name {
                return String(cString: name)
            }
            return String(st.st_uid)
        }()
        let groupName: String = {
            if let gr = getgrgid(st.st_gid), let name = gr.pointee.gr_name {
                return String(cString: name)
            }
            return String(st.st_gid)
        }()

        let perms = POSIXPermissionsSummary(
            mode: UInt16(st.st_mode & 0o7777),
            ownerID: st.st_uid,
            groupID: st.st_gid,
            ownerName: ownerName,
            groupName: groupName,
            isDirectory: isDir && !isSymlink
        )
        let tags = isSymlink ? [] : ((try? FinderColors.readTagsList(at: standardized)) ?? [])
        let quarantine = readQuarantineSummary(at: standardized)
        let isProtected = FileOperationEngine.isProtectedSystemPath(standardized)

        return FileMetadataSnapshot(
            url: standardized,
            name: standardized.lastPathComponent.isEmpty ? standardized.path : standardized.lastPathComponent,
            kind: kind,
            contentTypeIdentifier: values?.contentType?.identifier,
            isDirectory: isDir,
            isPackage: isPackage,
            isSymbolicLink: isSymlink,
            isRegularFile: isRegular,
            symlinkTarget: symlinkTarget,
            symlinkBroken: symlinkBroken,
            size: isRegular ? Int64(st.st_size) : values?.fileSize.map(Int64.init),
            allocatedSize: values?.fileAllocatedSize.map(Int64.init),
            created: values?.creationDate,
            modified: values?.contentModificationDate,
            lastOpened: values?.contentAccessDate,
            isLocked: values?.isUserImmutable ?? false,
            isExtensionHidden: values?.hasHiddenExtension ?? false,
            quarantineSummary: quarantine,
            tags: tags,
            permissions: perms,
            canModifyPermissions: !isSymlink && !isProtected && (st.st_uid == geteuid() || geteuid() == 0)
        )
    }

    public static func setLocked(_ locked: Bool, at url: URL) throws {
        let target = url.standardizedFileURL
        guard !FileOperationEngine.isProtectedSystemPath(target) else {
            throw FileOperationError(L10n.text("The startup root and your home folder cannot be changed by Explorer."))
        }
        var mutableURL = URL(fileURLWithPath: target.path)
        var values = URLResourceValues()
        values.isUserImmutable = locked
        try mutableURL.setResourceValues(values)
    }

    public static func setExtensionHidden(_ hidden: Bool, at url: URL) throws {
        let target = url.standardizedFileURL
        guard !FileOperationEngine.isProtectedSystemPath(target) else {
            throw FileOperationError(L10n.text("The startup root and your home folder cannot be changed by Explorer."))
        }
        var mutableURL = URL(fileURLWithPath: target.path)
        var values = URLResourceValues()
        values.hasHiddenExtension = hidden
        try mutableURL.setResourceValues(values)
    }

    public static func setPermissions(_ mode: UInt16, at url: URL) throws {
        let target = url.standardizedFileURL
        guard !FileOperationEngine.isProtectedSystemPath(target) else {
            throw FileOperationError(L10n.text("The startup root and your home folder cannot be changed by Explorer."))
        }
        var st = stat()
        let statOK = target.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &st)
        }
        guard statOK == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: target.path])
        }
        guard (st.st_mode & S_IFMT) != S_IFLNK else {
            throw FileOperationError("Permissions on symbolic links cannot be changed directly.")
        }
        let safeMode = mode_t(mode & 0o7777)
        let rc = target.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return chmod(path, safeMode)
        }
        guard rc == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: target.path])
        }
    }

    /// Streams a regular file with `O_NONBLOCK` and computes its lowercase hex SHA-256 digest.
    /// Never blocks on FIFOs, sockets, or devices.
    public static func sha256Hex(of url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            }
            guard fd >= 0 else { throw SafeFileReader.Failure.system(errno) }
            defer { close(fd) }

            var info = stat()
            guard fstat(fd, &info) == 0 else { throw SafeFileReader.Failure.system(errno) }
            guard (info.st_mode & S_IFMT) == S_IFREG else { throw SafeFileReader.Failure.notRegularFile }

            var hasher = SHA256()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                try Task.checkCancellation()
                let count = buffer.withUnsafeMutableBytes { raw -> Int in
                    read(fd, raw.baseAddress!, raw.count)
                }
                if count < 0 {
                    if errno == EINTR { continue }
                    throw SafeFileReader.Failure.system(errno)
                }
                if count == 0 { break }
                hasher.update(data: buffer.prefix(count))
            }
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private static func readQuarantineSummary(at url: URL) -> String? {
        let key = "com.apple.quarantine"
        let count = getxattr(url.path, key, nil, 0, 0, XATTR_NOFOLLOW)
        guard count > 0, count <= 4096 else { return nil }
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, key, $0.baseAddress, count, 0, XATTR_NOFOLLOW) }
        guard read > 0 else { return nil }
        let raw = String(decoding: data.prefix(read), as: UTF8.self)
        let parts = raw.split(separator: ";", omittingEmptySubsequences: false)
        if parts.count >= 3, !parts[2].isEmpty {
            return "Quarantined (from \(parts[2]))"
        }
        return "Quarantined by macOS Gatekeeper"
    }
}
