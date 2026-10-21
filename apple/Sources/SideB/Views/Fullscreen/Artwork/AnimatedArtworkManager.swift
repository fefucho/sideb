import Foundation
import Observation
import SideBCore

/// A clear is a barrier: every consumer releases its Rust lease before files are removed.
@MainActor @Observable
final class AnimatedArtworkManager {
    static let shared = AnimatedArtworkManager()
    private(set) var cacheRevision: UInt64 = 0
    private(set) var isClearing = false
    @ObservationIgnored private var consumers: [UUID: () -> Void] = [:]
    @ObservationIgnored private var clearTask: Task<UInt64, Error>?

    var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.fefucho.SideB", isDirectory: true)
            .appendingPathComponent("AnimatedArtwork", isDirectory: true)
    }

    func register(_ stop: @escaping () -> Void) -> UUID {
        let id = UUID()
        consumers[id] = stop
        return id
    }

    func unregister(_ id: UUID) { consumers.removeValue(forKey: id) }

    func size(core: SideBCore) async throws -> UInt64 {
        try await core.getAnimatedArtworkCacheSize(cacheDir: cacheDirectory.path)
    }

    @discardableResult
    func clear(core: SideBCore) async throws -> UInt64 {
        try await clear {
            try await core.clearAnimatedArtworkCache(cacheDir: self.cacheDirectory.path)
        }
    }

    /// Kept independent from UniFFI so the release-before-delete ordering is testable.
    @discardableResult
    func clear(using deleteFiles: @escaping @MainActor () async throws -> UInt64) async throws -> UInt64 {
        if let clearTask { return try await clearTask.value }
        isClearing = true
        defer { isClearing = false; clearTask = nil }
        cacheRevision &+= 1
        Array(consumers.values).forEach { $0() }
        let task = Task { @MainActor in try await deleteFiles() }
        clearTask = task
        return try await task.value
    }
}
