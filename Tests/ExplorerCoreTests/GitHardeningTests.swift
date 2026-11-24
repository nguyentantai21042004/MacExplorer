import Foundation
import Darwin
import Testing
@testable import ExplorerCore

/// Security tests for the git badge. Each hostile repository is real (`git init`), so
/// the tests prove behaviour against /usr/bin/git, not against a mock.
@Suite(.serialized)
struct GitHardeningTests {
    struct GitFailed: Error { let arguments: [String]; let status: Int32 }

    private func makeRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("explorer-\(name)-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL, fsmonitorAllowed: Bool = true) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=Explorer Tests", "-c", "user.email=tests@example.invalid",
                             "-c", "init.defaultBranch=trunk", "-C", directory.path] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "GIT_CONFIG_NOSYSTEM": "1"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GitFailed(arguments: arguments, status: process.terminationStatus) }
        return String(decoding: data, as: UTF8.self)
    }

    private func makeRepo(_ name: String) throws -> URL {
        let root = try makeRoot(name)
        try git(["init", "-q"], in: root)
        try Data("tracked\n".utf8).write(to: root.appendingPathComponent("tracked.txt"))
        try git(["add", "tracked.txt"], in: root)
        try git(["commit", "-q", "-m", "init"], in: root)
        return root
    }

    private func writeHook(at url: URL, touching marker: URL) throws {
        try "#!/bin/sh\n/usr/bin/touch '\(marker.path)'\n".write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
    }

    // MARK: Arguments and environment

    @Test func statusArgumentsDisableFsmonitorLocksAndSubmodules() throws {
        let args = GitRepoReader.statusArguments(root: URL(fileURLWithPath: "/tmp/repo"))
        let statusIndex = try #require(args.firstIndex(of: "status"))
        #expect(args.firstIndex(of: "--no-optional-locks")! < statusIndex)
        #expect(args.contains("core.fsmonitor=false"))
        #expect(args.contains("--ignore-submodules=all"))
        #expect(args.contains("--porcelain=v1"))
        // The repo path is one literal argument, never shell text.
        #expect(args[args.firstIndex(of: "-C")! + 1] == "/tmp/repo")
    }

    @Test func statusEnvironmentDropsInheritedGitVariables() {
        let env = GitRepoReader.statusEnvironment(home: "/Users/tester")
        #expect(Set(env.keys) == ["PATH", "HOME", "LC_ALL", "GIT_TERMINAL_PROMPT", "GIT_OPTIONAL_LOCKS", "GIT_CONFIG_NOSYSTEM"])
        #expect(env["PATH"] == "/usr/bin:/bin")
        #expect(env["GIT_TERMINAL_PROMPT"] == "0")
        #expect(env["GIT_DIR"] == nil && env["GIT_EXTERNAL_DIFF"] == nil && env["GIT_SSH_COMMAND"] == nil)
    }

    // MARK: Real repositories

    @Test func cleanAndDirtyRepositoriesReportCounts() async throws {
        let root = try makeRepo("git-counts")
        defer { try? FileManager.default.removeItem(at: root) }

        let clean = try #require(await GitRepoReader.readStatus(for: root))
        #expect(clean.isKnown)
        #expect(clean.isClean)
        #expect(clean.branch == "trunk")
        #expect(clean.badgeText == "trunk · clean")

        try Data("changed\n".utf8).write(to: root.appendingPathComponent("tracked.txt"))
        try Data("new\n".utf8).write(to: root.appendingPathComponent("untracked.txt"))
        let dirty = try #require(await GitRepoReader.readStatus(for: root))
        #expect(dirty.isKnown)
        #expect(dirty.modified == 1)
        #expect(dirty.untracked == 1)
        #expect(dirty.badgeText == "trunk · 1M 1?")
    }

    @Test func repositoryFsmonitorHookNeverRuns() async throws {
        let root = try makeRepo("git-fsmonitor")
        defer { try? FileManager.default.removeItem(at: root) }
        let hook = root.appendingPathComponent("hook.sh")
        let marker = root.appendingPathComponent("PWNED-fsmonitor")
        try writeHook(at: hook, touching: marker)
        try git(["config", "core.fsmonitor", hook.path], in: root)

        // Control: plain `git status` really runs the repository's hook.
        _ = try? git(["status", "--porcelain=v1"], in: root)
        #expect(FileManager.default.fileExists(atPath: marker.path), "control: plain git status should run core.fsmonitor")
        try FileManager.default.removeItem(at: marker)

        let status = try #require(await GitRepoReader.readStatus(for: root))
        #expect(!FileManager.default.fileExists(atPath: marker.path), "Explorer must not execute core.fsmonitor")
        #expect(status.isKnown)
    }

    @Test func repositoryFilterDriverSkipsStatusAndNeverRuns() async throws {
        let root = try makeRepo("git-filter")
        defer { try? FileManager.default.removeItem(at: root) }
        let hook = root.appendingPathComponent("clean.sh")
        let marker = root.appendingPathComponent("PWNED-filter")
        try writeHook(at: hook, touching: marker)
        try git(["config", "filter.evil.clean", hook.path], in: root)
        try Data("* filter=evil\n".utf8).write(to: root.appendingPathComponent(".gitattributes"))
        try Data("dirty\n".utf8).write(to: root.appendingPathComponent("tracked.txt"))

        #expect(GitRepoReader.untrustedConfigSection(gitDir: root.appendingPathComponent(".git")) == "filter")
        let status = try #require(await GitRepoReader.readStatus(for: root))
        #expect(!status.isKnown)
        #expect(!status.isClean, "an unknown status must never be shown as clean")
        #expect(status.badgeText == "trunk")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test(arguments: [("[include]\n\tpath = /tmp/elsewhere\n", "include"),
                      ("[includeIf \"gitdir:/tmp/\"]\n\tpath = /tmp/x\n", "includeif"),
                      ("[Filter \"lfs\"]\n\tprocess = x\n", "filter")])
    func untrustedConfigSectionsAreDetected(config: String, expected: String) throws {
        let gitDir = try makeRoot("git-config")
        defer { try? FileManager.default.removeItem(at: gitDir) }
        try Data("[core]\n\tbare = false\n\(config)".utf8).write(to: gitDir.appendingPathComponent("config"))
        #expect(GitRepoReader.untrustedConfigSection(gitDir: gitDir) == expected)
    }

    @Test func worktreeCommonConfigIsScanned() throws {
        let base = try makeRoot("git-worktree")
        defer { try? FileManager.default.removeItem(at: base) }
        let common = base.appendingPathComponent("common"), worktree = common.appendingPathComponent("worktrees/wt")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("../..\n".utf8).write(to: worktree.appendingPathComponent("commondir"))
        try Data("[filter \"x\"]\n\tclean = y\n".utf8).write(to: common.appendingPathComponent("config"))
        #expect(GitRepoReader.repositoryConfigFiles(gitDir: worktree).map(\.path).contains(common.appendingPathComponent("config").path))
        #expect(GitRepoReader.untrustedConfigSection(gitDir: worktree) == "filter")
    }

    // MARK: HEAD parsing

    @Test func headThatIsAFifoReturnsWithoutBlocking() throws {
        let root = try makeRoot("git-fifo")
        defer { try? FileManager.default.removeItem(at: root) }
        let dotGit = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)
        #expect(mkfifo(dotGit.appendingPathComponent("HEAD").path, 0o600) == 0)
        #expect(GitRepoReader.readBranchFast(at: root) == nil)
    }

    @Test func headSymlinkOversizedAndGarbageAreRejected() throws {
        let root = try makeRoot("git-head")
        defer { try? FileManager.default.removeItem(at: root) }
        let dotGit = root.appendingPathComponent(".git"), head = dotGit.appendingPathComponent("HEAD")
        try FileManager.default.createDirectory(at: dotGit, withIntermediateDirectories: true)

        let target = root.appendingPathComponent("elsewhere")
        try Data("ref: refs/heads/main\n".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: head, withDestinationURL: target)
        #expect(GitRepoReader.readBranchFast(at: root) == nil, "HEAD symlink is not followed")

        try FileManager.default.removeItem(at: head)
        try Data(repeating: 0x61, count: GitRepoReader.metadataReadLimit + 1).write(to: head)
        #expect(GitRepoReader.readBranchFast(at: root) == nil, "oversized HEAD is refused")

        try Data("not a ref at all\n".utf8).write(to: head)
        #expect(GitRepoReader.readBranchFast(at: root) == nil)

        try Data("0123456789abcdef0123456789abcdef01234567\n".utf8).write(to: head)
        #expect(GitRepoReader.readBranchFast(at: root) == "0123456")
    }

    @Test func gitdirPointerFileResolvesRelativeToRepo() throws {
        let root = try makeRoot("git-pointer")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("modules/sub")
        let work = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Data("ref: refs/heads/feature/x\n".utf8).write(to: real.appendingPathComponent("HEAD"))
        try Data("gitdir: ../modules/sub\n".utf8).write(to: work.appendingPathComponent(".git"))
        #expect(GitRepoReader.readBranchFast(at: work) == "feature/x")
    }
}

@Suite
struct BoundedProcessTests {
    @Test func slowChildIsKilledAtTheTimeout() throws {
        let start = Date()
        #expect(throws: BoundedProcess.Failure.timedOut) {
            _ = try BoundedProcess.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], environment: [:], timeout: 0.3)
        }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func outputIsCappedAndMarkedTruncated() throws {
        let result = try BoundedProcess.run(URL(fileURLWithPath: "/usr/bin/head"), arguments: ["-c", "200000", "/dev/zero"],
                                            environment: [:], timeout: 5, outputLimit: 1000)
        #expect(result.status == 0)
        #expect(result.output.count == 1000)
        #expect(result.truncated)
    }

    @Test func childSeesOnlyTheGivenEnvironment() throws {
        setenv("EXPLORER_LEAK_CHECK", "leaked", 1)
        defer { unsetenv("EXPLORER_LEAK_CHECK") }
        let result = try BoundedProcess.run(URL(fileURLWithPath: "/usr/bin/env"), arguments: [],
                                            environment: ["ONLY": "this"], timeout: 5)
        let text = String(decoding: result.output, as: UTF8.self)
        #expect(text.contains("ONLY=this"))
        #expect(!text.contains("EXPLORER_LEAK_CHECK"))
    }

    @Test func missingExecutableFailsToLaunch() {
        #expect(throws: BoundedProcess.Failure.self) {
            _ = try BoundedProcess.run(URL(fileURLWithPath: "/nonexistent/tool"), arguments: [], environment: [:], timeout: 1)
        }
    }
}
