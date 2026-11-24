import Foundation
import Darwin

/// Runs a helper executable with a fixed environment, a wall-clock timeout and an
/// output cap. Used for read-only helpers such as `git status`, where a slow network
/// volume or a hostile repository must never hang a worker thread indefinitely.
public enum BoundedProcess {
    public struct Result: Sendable, Equatable {
        public let status: Int32
        public let output: Data
        /// True when output exceeded the cap and the remainder was discarded.
        public let truncated: Bool
    }

    public enum Failure: Error, Equatable, Sendable {
        case launch(String)
        case timedOut
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var truncated = false
        let limit: Int
        init(limit: Int) { self.limit = limit }
        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            let room = limit - data.count
            if chunk.count > room { truncated = true }
            if room > 0 { data.append(chunk.prefix(room)) }
        }
        var snapshot: (Data, Bool) { lock.lock(); defer { lock.unlock() }; return (data, truncated) }
    }

    /// Blocking: call from a detached task, never the main actor.
    public static func run(_ executable: URL, arguments: [String], environment: [String: String],
                           currentDirectory: URL? = nil, timeout: TimeInterval,
                           outputLimit: Int = 1 << 20) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { throw Failure.launch(error.localizedDescription) }

        let collector = Collector(limit: outputLimit)
        let drained = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        // Drain continuously so a chatty child never blocks on a full pipe buffer.
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                collector.append(chunk)
            }
            drained.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
            throw Failure.timedOut
        }
        // A grandchild can inherit the pipe and keep it open; do not wait on it forever.
        _ = drained.wait(timeout: .now() + 1)
        let (output, truncated) = collector.snapshot
        return Result(status: process.terminationStatus, output: output, truncated: truncated)
    }
}
