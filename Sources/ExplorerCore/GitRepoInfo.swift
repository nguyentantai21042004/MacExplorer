import Foundation

public struct GitRepoStatus: Sendable, Equatable {
    public let root: URL
    public let branch: String
    public let modified: Int
    public let untracked: Int
    /// False when `git status` was skipped or failed. Counts are then zero and must not
    /// be shown as "clean".
    public let isKnown: Bool

    public init(root: URL, branch: String, modified: Int, untracked: Int, isKnown: Bool = true) {
        self.root = root; self.branch = branch
        self.modified = modified; self.untracked = untracked; self.isKnown = isKnown
    }

    public var isClean: Bool { isKnown && modified == 0 && untracked == 0 }

    public var badgeText: String {
        guard isKnown else { return branch }
        if isClean { return "\(branch) · clean" }
        var parts: [String] = []
        if modified > 0 { parts.append("\(modified)M") }
        if untracked > 0 { parts.append("\(untracked)?") }
        return "\(branch) · " + parts.joined(separator: " ")
    }
}

public enum GitRepoReader {
    /// Git metadata files (HEAD, config, gitdir pointers) are tiny; refuse anything bigger.
    static let metadataReadLimit = 64 * 1024
    static let statusTimeout: TimeInterval = 3
    static let gitExecutable = URL(fileURLWithPath: "/usr/bin/git")

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

    /// Resolves `.git` to the real git directory, following a `gitdir:` pointer file
    /// used by worktrees and submodules.
    static func gitDirectory(at repoRoot: URL) -> URL? {
        let dotGit = repoRoot.appendingPathComponent(".git")
        var isDir = ObjCBool(false)
        guard FileManager().fileExists(atPath: dotGit.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }
        guard let text = readMetadata(dotGit) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gitdir:") else { return nil }
        let target = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        let base = URL(fileURLWithPath: repoRoot.path, isDirectory: true)
        return URL(fileURLWithPath: target, relativeTo: base).standardizedFileURL
    }

    /// Reads a small git metadata file. Never blocks on a FIFO and never follows a
    /// symlink in the final component.
    static func readMetadata(_ url: URL) -> String? {
        guard let data = try? SafeFileReader.readPrefix(of: url, limit: metadataReadLimit, followSymlinks: false,
                                                        maxFileSize: Int64(metadataReadLimit)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Reads `.git/HEAD` directly without spawning a subprocess.
    public static func readBranchFast(at repoRoot: URL) -> String? {
        guard let gitDir = gitDirectory(at: repoRoot),
              let head = readMetadata(gitDir.appendingPathComponent("HEAD")) else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        // A ref name never contains whitespace or control characters; anything else is not a HEAD file.
        guard !line.isEmpty, !line.contains(where: { $0.isNewline }) else { return nil }
        if line.hasPrefix("ref: refs/heads/") {
            return String(line.dropFirst("ref: refs/heads/".count))
        }
        if line.hasPrefix("ref: ") {
            return String(line.dropFirst(5)).split(separator: "/").last.map(String.init)
        }
        if line.count >= 7, line.allSatisfy(\.isHexDigit) {
            return String(line.prefix(7))
        }
        return nil
    }

    /// Arguments for a read-only status that cannot run repository-supplied commands
    /// through the fsmonitor hook and never takes `index.lock`.
    static func statusArguments(root: URL) -> [String] {
        ["--no-optional-locks",
         "-c", "core.fsmonitor=false",
         "-c", "core.untrackedCache=false",
         "-c", "status.showUntrackedFiles=normal",
         "-C", root.path,
         "status", "--porcelain=v1", "--ignore-submodules=all"]
    }

    /// Minimal environment. Inherited `GIT_DIR`, `GIT_WORK_TREE`, `GIT_EXTERNAL_DIFF` or
    /// `GIT_SSH_COMMAND` from the launching shell never reach the child.
    static func statusEnvironment(home: String = NSHomeDirectory()) -> [String: String] {
        ["PATH": "/usr/bin:/bin",
         "HOME": home,
         "LC_ALL": "C",
         "GIT_TERMINAL_PROMPT": "0",
         "GIT_OPTIONAL_LOCKS": "0",
         "GIT_CONFIG_NOSYSTEM": "1"]
    }

    /// Repository config sections that make `git status` run commands taken from the
    /// repository itself: clean/process filters run for stat-dirty files, and include
    /// directives can pull in config from anywhere. Global config stays trusted.
    static let untrustedConfigSections = ["filter", "include", "includeif"]

    /// Config files that a repository controls, including linked worktrees.
    static func repositoryConfigFiles(gitDir: URL) -> [URL] {
        var dirs = [gitDir]
        if let common = readMetadata(gitDir.appendingPathComponent("commondir"))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !common.isEmpty {
            let base = URL(fileURLWithPath: gitDir.path, isDirectory: true)
            dirs.append(URL(fileURLWithPath: common, relativeTo: base).standardizedFileURL)
        }
        return dirs.flatMap { [$0.appendingPathComponent("config"), $0.appendingPathComponent("config.worktree")] }
    }

    /// Returns the first untrusted section found in the repository's own config, or nil.
    /// A config file that exists but cannot be read safely is treated as untrusted.
    static func untrustedConfigSection(gitDir: URL) -> String? {
        for file in repositoryConfigFiles(gitDir: gitDir) {
            guard FileManager().fileExists(atPath: file.path) else { continue }
            guard let text = readMetadata(file) else { return "unreadable \(file.lastPathComponent)" }
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("[") else { continue }
                let header = line.dropFirst().prefix { $0 != "]" && $0 != " " && $0 != "\t" && $0 != "\"" }
                let section = header.split(separator: ".").first.map { $0.lowercased() } ?? ""
                if untrustedConfigSections.contains(section) { return section }
            }
        }
        return nil
    }

    static func isLocalVolume(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) ?? false
    }

    static func parsePorcelain(_ output: String) -> (modified: Int, untracked: Int) {
        var modified = 0, untracked = 0
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("??") { untracked += 1 } else { modified += 1 }
        }
        return (modified, untracked)
    }

    /// Reads the branch and runs a hardened `git status --porcelain=v1` in the background.
    /// Status is skipped (branch only, `isKnown == false`) on network volumes and for
    /// repositories whose own config declares filters or includes.
    public static func readStatus(for url: URL) async -> GitRepoStatus? {
        guard let root = findRepoRoot(for: url),
              let branch = readBranchFast(at: root) else { return nil }
        return await Task.detached(priority: .utility) {
            let unknown = GitRepoStatus(root: root, branch: branch, modified: 0, untracked: 0, isKnown: false)
            guard isLocalVolume(root), let gitDir = gitDirectory(at: root),
                  untrustedConfigSection(gitDir: gitDir) == nil else { return unknown }
            guard let result = try? BoundedProcess.run(gitExecutable, arguments: statusArguments(root: root),
                                                       environment: statusEnvironment(), timeout: statusTimeout),
                  result.status == 0, !result.truncated,
                  let output = String(data: result.output, encoding: .utf8) else { return unknown }
            let counts = parsePorcelain(output)
            return GitRepoStatus(root: root, branch: branch, modified: counts.modified, untracked: counts.untracked)
        }.value
    }
}
