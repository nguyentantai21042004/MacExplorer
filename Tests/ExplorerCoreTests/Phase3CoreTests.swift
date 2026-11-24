import Foundation
import Testing
@testable import ExplorerCore

@Suite
struct Phase3CoreTests {
    @Test func cloudPathDetectionAndStatusCapabilities() {
        #expect(CloudStorageHelper.isCloudPath(URL(fileURLWithPath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Docs")))
        #expect(CloudStorageHelper.isCloudPath(URL(fileURLWithPath: "/Users/me/Library/CloudStorage/GoogleDrive-a@b.com")))
        #expect(CloudStorageHelper.isCloudPath(URL(fileURLWithPath: "/Users/me/Library/CloudStorage/OneDrive-Personal")))
        #expect(!CloudStorageHelper.isCloudPath(URL(fileURLWithPath: "/Users/me/Workspaces/mac-explorer")))
        #expect(!CloudStorageHelper.isCloudPath(URL(fileURLWithPath: "/tmp")))

        #expect(!CloudItemStatus.local.isCloudManaged)
        #expect(!CloudItemStatus.local.canDownload)
        #expect(!CloudItemStatus.local.canEvict)
        #expect(CloudItemStatus.local.symbolName == nil)

        #expect(CloudItemStatus.cloudOnly.isCloudManaged)
        #expect(CloudItemStatus.cloudOnly.canDownload)
        #expect(!CloudItemStatus.cloudOnly.canEvict)
        #expect(CloudItemStatus.cloudOnly.symbolName == "icloud.and.arrow.down")

        #expect(CloudItemStatus.downloaded.isCloudManaged)
        #expect(!CloudItemStatus.downloaded.canDownload)
        #expect(CloudItemStatus.downloaded.canEvict)
        #expect(CloudItemStatus.downloaded.symbolName == "icloud")

        #expect(CloudItemStatus.outdated.canDownload)
        #expect(CloudItemStatus.downloading.symbolName == "arrow.down.circle")
        #expect(CloudItemStatus.uploading.symbolName == "icloud.and.arrow.up")
    }

    @Test func columnViewModePropertiesAndRawValue() {
        let mode = FileViewMode.columns
        #expect(mode.usesColumns)
        #expect(!mode.usesTable)
        #expect(FileViewMode(rawValue: "columns") == .columns)
        #expect(!mode.title.isEmpty)
        #expect(FileViewMode.allCases.contains(.columns))
    }
}
