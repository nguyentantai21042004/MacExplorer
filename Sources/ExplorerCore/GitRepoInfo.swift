import Foundation

public struct GitRepoStatus: Sendable, Equatable {
    public let root: URL
    public let branch: String
    public let modified: Int
    public let untracked: Int

    public var isClean: Bool { modified == 0 && untracked == 0 }

    public var badgeText: String {
        if isClean { return "\(branch) · clean" }
        var parts: [String] = []
        if modified > 0 { parts.append("\(modified)M") }
        if untracked > 0 { parts.append("\(untracked)?") }
        return "\(branch) · " + parts.joined(separator: " ")
    }
}

public enum GitRepoReader {
    /// Walks upward from `url` to find a directory containing `.git`.
    public static func findRepoRoot(for url: URL) -> URL? {
        var current = url.standardizedFileURL
        let fm = FileManager()
        var isDir = ObjCBool(false)
        if fm.fileExists(atPath: current.path, isDirectory: &isDir), !isDir.boolValue {
            current.deleteLastPathComponent()
        }
        while true {
            let dotGit = current.appendingPathComponent(".git")
            if fm.fileExists(atPath: dotGit.path) { return current }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || current.path == "/" { break }
            current = parent
        }
        return nil
    }

    /// Reads `.git/HEAD` directly without spawning a subprocess.
    public static func readBranchFast(at repoRoot: URL) -> String? {
        let dotGit = repoRoot.appendingPathComponent(".git")
        var isDir = ObjCBool(false)
        guard FileManager().fileExists(atPath: dotGit.path, isDirectory: &isDir) else { return nil }
        let headURL: URL
        if isDir.boolValue {
            headURL = dotGit.appendingPathComponent("HEAD")
        } else if let text = try? String(contentsOf: dotGit, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("gitdir:") {
                let target = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
                let resolved = URL(fileURLWithPath: target, relativeTo: repoRoot).standardizedFileURL
                headURL = resolved.appendingPathComponent("HEAD")
            } else {
                return nil
            }
        } else {
            return nil
        }
        guard let head = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") {
            return String(line.dropFirst("ref: refs/heads/".count))
        }
        if line.hasPrefix("ref: ") {
            return String(line.dropFirst(5)).split(separator: "/").last.map(String.init)
        }
        if line.count >= 7 {
            return String(line.prefix(7))
        }
        return nil
    }

    /// Reads branch and runs `git status --porcelain=v1` on a background thread.
    public static func readStatus(for url: URL) async -> GitRepoStatus? {
        guard let root = findRepoRoot(for: url),
              let branch = readBranchFast(at: root) else { return nil }
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path, "status", "--porcelain=v1"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let output = String(data: data, encoding: .utf8) else {
                    return GitRepoStatus(root: root, branch: branch, modified: 0, untracked: 0)
                }
                var modified = 0
                var untracked = 0
                for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
                    if line.hasPrefix("??") { untracked += 1 }
                    else { modified += 1 }
                }
                return GitRepoStatus(root: root, branch: branch, modified: modified, untracked: untracked)
            } catch {
                return GitRepoStatus(root: root, branch: branch, modified: 0, untracked: 0)
            }
        }.value
    }
}
