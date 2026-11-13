import Foundation

/// Runs the separate `spotify-jam` executable and exchanges JSON lines with it. The host knows
/// nothing about Spotify; closing stdin makes the plugin leave the Jam and exit.
final class JamProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    let events: AsyncStream<JamEvent>

    init(executable: URL) throws {
        // A plugin that already exited must surface as a failed write, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        var continuation: AsyncStream<JamEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        process.executableURL = executable
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = ["PATH": "/usr/bin:/bin"]
        try process.run()
        let handle = output.fileHandleForReading
        let stream = continuation!
        Task.detached {
            let decoder = JSONDecoder()
            do {
                for try await line in handle.bytes.lines {
                    if let event = try? decoder.decode(JamEvent.self, from: Data(line.utf8)) { stream.yield(event) }
                }
            } catch {}
            stream.finish()
        }
    }

    func send(_ object: [String: Any]) {
        guard process.isRunning, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    private var isStopped = false

    /// Asks the plugin to leave (for both `join` and `watchInvites`), then makes sure it does not outlive the session.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        send(["type": "leave"])
        try? input.fileHandleForWriting.close()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
            if process.isRunning { process.terminate() }
        }
    }

    static func locateExecutable() -> URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["SIDEB_JAM_BINARY"] { candidates.append(URL(fileURLWithPath: override)) }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("SessionProviders/spotify-jam/sideb-spotify-jam") { candidates.append(bundled) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
