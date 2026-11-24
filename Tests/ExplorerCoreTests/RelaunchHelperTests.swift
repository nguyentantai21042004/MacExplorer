import Foundation
import Testing
@testable import ExplorerCore

@Suite
struct RelaunchHelperTests {
    @Test func parsesValidArgumentsAndRejectsMalformedInput() {
        let valid = RelaunchHelper.parse(arguments: [
            "Explorer",
            RelaunchHelper.waitPidFlag, "12345",
            RelaunchHelper.bundlePathFlag, "/Applications/Explorer.app"
        ])
        #expect(valid?.pid == 12345)
        #expect(valid?.bundleURL.path == "/Applications/Explorer.app")

        #expect(RelaunchHelper.parse(arguments: ["Explorer"]) == nil)
        #expect(RelaunchHelper.parse(arguments: ["Explorer", RelaunchHelper.waitPidFlag, "-1", RelaunchHelper.bundlePathFlag, "/Applications/Explorer.app"]) == nil)
        #expect(RelaunchHelper.parse(arguments: ["Explorer", RelaunchHelper.waitPidFlag, "0", RelaunchHelper.bundlePathFlag, "/Applications/Explorer.app"]) == nil)
        #expect(RelaunchHelper.parse(arguments: ["Explorer", RelaunchHelper.waitPidFlag, "99", RelaunchHelper.bundlePathFlag, "/bin/sh"]) == nil)
    }

    @Test func waitForExitDetectsProcessTerminationAndTimeout() throws {
        let short = Process()
        short.executableURL = URL(fileURLWithPath: "/bin/sleep")
        short.arguments = ["0.1"]
        try short.run()
        let pid = short.processIdentifier
        short.waitUntilExit()
        #expect(RelaunchHelper.waitForExit(pid: pid, timeoutSeconds: 2, pollInterval: 0.05) == true)

        let long = Process()
        long.executableURL = URL(fileURLWithPath: "/bin/sleep")
        long.arguments = ["10"]
        try long.run()
        defer { long.terminate(); long.waitUntilExit() }
        #expect(RelaunchHelper.waitForExit(pid: long.processIdentifier, timeoutSeconds: 0.15, pollInterval: 0.05) == false)
    }
}
