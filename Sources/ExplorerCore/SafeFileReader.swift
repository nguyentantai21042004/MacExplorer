import Foundation
import Darwin

/// Bounded reads that never block on FIFOs, sockets or device nodes.
///
/// `FileHandle(forReadingFrom:)` and `Data(contentsOf:)` call a blocking `open(2)`.
/// On a named pipe without a writer that call never returns, so a file named
/// `notes.txt` that is really a FIFO would freeze the preview or search worker.
/// This reader opens with `O_NONBLOCK`, checks the opened descriptor with `fstat`,
/// and reads only regular files, up to a caller-supplied byte limit.
public enum SafeFileReader {
    public enum Failure: Error, Equatable, Sendable {
        /// The path is a FIFO, socket, directory or device node.
        case notRegularFile
        /// The final path component is a symbolic link and links were refused.
        case symbolicLink
        /// The file is larger than `maxFileSize`.
        case tooLarge(Int64)
        /// `open`, `fstat` or `read` failed with this errno.
        case system(Int32)
    }

    /// Reads at most `limit` bytes from the start of a regular file.
    /// - Parameters:
    ///   - followSymlinks: When false, a symlink in the final path component fails with `.symbolicLink`.
    ///   - maxFileSize: When set, a file whose size exceeds it fails with `.tooLarge` before any read.
    public static func readPrefix(of url: URL, limit: Int, followSymlinks: Bool = true,
                                  maxFileSize: Int64? = nil) throws -> Data {
        precondition(limit >= 0, "limit must not be negative")
        var flags = O_RDONLY | O_NONBLOCK | O_CLOEXEC
        if !followSymlinks { flags |= O_NOFOLLOW }
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, flags)
        }
        guard fd >= 0 else {
            let code = errno
            throw code == ELOOP && !followSymlinks ? Failure.symbolicLink : Failure.system(code)
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure.system(errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw Failure.notRegularFile }
        if let maxFileSize, Int64(info.st_size) > maxFileSize { throw Failure.tooLarge(Int64(info.st_size)) }
        let capacity = min(limit, max(0, Int(clamping: info.st_size)))
        var data = Data(count: capacity)
        var total = 0
        while total < capacity {
            let count = data.withUnsafeMutableBytes { buffer -> Int in
                read(fd, buffer.baseAddress!.advanced(by: total), capacity - total)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure.system(errno)
            }
            if count == 0 { break }
            total += count
        }
        data.count = total
        return data
    }

    /// True when the path, after following symlinks, is a regular file. Never opens the file.
    public static func isRegularFile(_ url: URL) -> Bool {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return stat(path, &info)
        }
        return result == 0 && info.st_mode & S_IFMT == S_IFREG
    }
}
