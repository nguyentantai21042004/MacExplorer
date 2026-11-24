import Foundation

/// Text shown in the Inspector preview. Reads through `SafeFileReader`, so a FIFO,
/// socket or device node with a text-like name returns nil instead of blocking.
public enum PreviewText {
    public static let byteLimit = 32_768
    public static let truncationNote = "\n\n… (truncated at 32 KB)"

    /// Returns nil for non-regular files, unreadable files and binary data
    /// (a NUL byte in the first 1 KB). The caller then falls back to a thumbnail.
    public static func snippet(of url: URL, limit: Int = byteLimit) -> String? {
        // Read one byte past the limit so an exactly-32 KB file is not marked truncated.
        guard let data = try? SafeFileReader.readPrefix(of: url, limit: limit + 1),
              !data.prefix(1024).contains(0) else { return nil }
        let truncated = data.count > limit
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        return truncated ? text + truncationNote : text
    }
}
