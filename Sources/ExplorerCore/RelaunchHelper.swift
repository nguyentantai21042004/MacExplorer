import Foundation
import Darwin

/// Handles shell-free app relaunch after a language change. The running app spawns
/// its own executable with `--relaunch-after-pid`, which polls `kill(pid, 0)` until
/// the old instance finishes saving its session and then invokes `/usr/bin/open -n`.
public enum RelaunchHelper {
    public static let waitPidFlag = "--relaunch-after-pid"
    public static let bundlePathFlag = "--relaunch-bundle"

    public struct Request: Equatable, Sendable {
        public let pid: pid_t
        public let bundleURL: URL
    }

    public static func parse(arguments: [String]) -> Request? {
        guard let pidIndex = arguments.firstIndex(of: waitPidFlag),
              pidIndex + 1 < arguments.count,
              let pid = pid_t(arguments[pidIndex + 1]), pid > 0,
              let bundleIndex = arguments.firstIndex(of: bundlePathFlag),
              bundleIndex + 1 < arguments.count else { return nil }
        let path = arguments[bundleIndex + 1]
        let url = URL(fileURLWithPath: path)
        guard !path.isEmpty, url.pathExtension == "app" else { return nil }
        return Request(pid: pid, bundleURL: url)
    }

    public static func waitForExit(pid: pid_t, timeoutSeconds: TimeInterval = 60, pollInterval: TimeInterval = 0.2) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while true {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    public static func launchApp(at bundleURL: URL) throws {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = ["-n", bundleURL.path]
        opener.environment = ["PATH": "/usr/bin:/bin"]
        opener.standardInput = FileHandle.nullDevice
        opener.standardOutput = FileHandle.nullDevice
        opener.standardError = FileHandle.nullDevice
        try opener.run()
    }

    public static func scheduleSelfRelaunch(executableURL: URL, bundleURL: URL, currentPID: pid_t) throws {
        let helper = Process()
        helper.executableURL = executableURL
        helper.arguments = [waitPidFlag, String(currentPID), bundlePathFlag, bundleURL.path]
        helper.environment = ["PATH": "/usr/bin:/bin"]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }
}
