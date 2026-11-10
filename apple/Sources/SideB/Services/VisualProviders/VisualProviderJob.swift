import Foundation
import Darwin

/// A trusted, explicitly installed executable, not a sandbox. Each job owns one private directory.
/// Termination closes the process before cleanup; release after AVPlayer teardown drops its lease.
final class VisualProviderJob: @unchecked Sendable {
    let directory: URL
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var finished = false

    init(directory: URL) { self.directory = directory }

    func cancel() {
        lock.lock()
        cancelled = true
        let cleanup = finished
        if process.isRunning { process.terminate() }
        lock.unlock()
        if cleanup { removeDirectory() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [self] in
            lock.lock(); defer { lock.unlock() }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
    }
    private func isCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }; return cancelled
    }
    private func finish() {
        lock.lock(); finished = true; let cleanup = cancelled; lock.unlock()
        if cleanup { removeDirectory() }
    }
    private func removeDirectory() { try? FileManager.default.removeItem(at: directory) }

    func run(executable: URL, input: Data) throws -> Data {
        defer { finish() }
        guard input.count <= 32768, !isCancelled() else { throw VisualProviderFailure.cancelled }
        let stdin = Pipe(), stdout = Pipe()
        process.executableURL = executable
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.environment = [:] // Credentials never go in argv, env, or stderr.
        lock.lock()
        do { try process.run() } catch { lock.unlock(); throw error }
        if cancelled { process.terminate() }
        lock.unlock()
        defer {
            try? stdin.fileHandleForWriting.close()
            try? stdout.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        try stdin.fileHandleForWriting.write(contentsOf: input)
        try stdin.fileHandleForWriting.close()
        var output = Data()
        while let chunk = try stdout.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
            guard output.count + chunk.count <= 16384, !isCancelled() else {
                throw VisualProviderFailure.invalid
            }
            output.append(chunk)
        }
        process.waitUntilExit()
        guard !isCancelled(), process.terminationStatus == 0 else { throw VisualProviderFailure.unavailable }
        return output
    }
}
