import Foundation

/// Size-capped JSONL diagnostics for the Jam sync, written off the main thread.
/// Holds no credentials or user names: only track identifiers, drift and engine decisions.
final class JamSyncLog: @unchecked Sendable {
    static let shared = JamSyncLog()
    static let maxBytes = 2_000_000

    let url: URL
    private let queue = DispatchQueue(label: "sideb.jam.synclog", qos: .utility)
    private var size: Int?

    init(url: URL = HomeLabConfiguration.appSupportURL.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("jam-sync.jsonl")) {
        self.url = url
    }

    func write(_ fields: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(fields),
              var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        queue.async { [self] in append(data) }
    }

    /// Last `count` lines, joined with newlines.
    func tail(_ count: Int) -> String {
        queue.sync {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return text.split(separator: "\n", omittingEmptySubsequences: true).suffix(count).joined(separator: "\n")
        }
    }

    private func append(_ data: Data) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if size == nil {
            size = ((try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
        }
        if (size ?? 0) + data.count > Self.maxBytes {
            // Rotate: keep one previous generation, so the total stays under about twice the cap.
            let old = url.deletingPathExtension().appendingPathExtension("old.jsonl")
            try? fileManager.removeItem(at: old)
            try? fileManager.moveItem(at: url, to: old)
            size = 0
        }
        if !fileManager.fileExists(atPath: url.path) { fileManager.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        size = (size ?? 0) + data.count
    }
}
