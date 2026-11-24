import Foundation

/// Represents the local/cloud sync state of an iCloud Drive or FileProvider item.
public enum CloudItemStatus: String, Sendable, Equatable {
    case local
    case downloaded
    case cloudOnly
    case downloading
    case uploading
    case outdated

    public var isCloudManaged: Bool { self != .local }
    public var canDownload: Bool { self == .cloudOnly || self == .outdated }
    public var canEvict: Bool { self == .downloaded }

    public var symbolName: String? {
        switch self {
        case .local: nil
        case .downloaded: "icloud"
        case .cloudOnly, .outdated: "icloud.and.arrow.down"
        case .downloading: "arrow.down.circle"
        case .uploading: "icloud.and.arrow.up"
        }
    }

    public var displayLabel: String? {
        switch self {
        case .local: nil
        case .downloaded: "Downloaded (Cloud)"
        case .cloudOnly: "In Cloud"
        case .downloading: "Downloading…"
        case .uploading: "Uploading…"
        case .outdated: "Update Available"
        }
    }
}

public enum CloudStorageHelper {
    /// Returns true when the directory sits inside iCloud Drive or a macOS FileProvider root.
    /// Checking this first keeps local filesystem enumeration free of extra ubiquitous syscalls.
    public static func isCloudPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/Library/Mobile Documents")
            || path.contains("/Library/CloudStorage")
            || path.contains("/GoogleDrive")
            || path.contains("/Google Drive")
    }

    public static func status(from values: URLResourceValues?) -> CloudItemStatus {
        guard let values, values.isUbiquitousItem == true else { return .local }
        if values.ubiquitousItemIsDownloading == true { return .downloading }
        if values.ubiquitousItemIsUploading == true { return .uploading }
        switch values.ubiquitousItemDownloadingStatus {
        case .notDownloaded: return .cloudOnly
        case .downloaded: return .outdated
        case .current: return .downloaded
        default: return .downloaded
        }
    }

    public static func status(at url: URL) -> CloudItemStatus {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemIsUploadingKey
        ]
        return status(from: try? url.resourceValues(forKeys: keys))
    }

    public static func startDownloading(_ urls: [URL]) throws {
        let fm = FileManager.default
        for url in urls where url.isFileURL {
            try fm.startDownloadingUbiquitousItem(at: url)
        }
    }

    public static func removeDownload(_ urls: [URL]) throws {
        let fm = FileManager.default
        for url in urls where url.isFileURL {
            try fm.evictUbiquitousItem(at: url)
        }
    }
}
