import Foundation
import Testing
@testable import SideB

@MainActor
@Test func queueExperimentCoalescesDeferredSnapshotsAndKeepsStoreDirectoryIsolated() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let stable = root.appendingPathComponent("Playback", isDirectory: true)
    let experiment = root.appendingPathComponent("PlaybackQueueExperiment", isDirectory: true)
    let store = PlaybackStateStore(directory: experiment)
    store.activate("account:experiment")
    var mapped = "primero"
    var snapshots = 0
    store.scheduleSave(snapshot: {
        snapshots += 1
        return queueState(title: mapped)
    })
    mapped = "último"
    try await Task.sleep(for: .milliseconds(500))
    #expect(snapshots == 1)
    #expect(store.load()?.contextTitle == "último")
    #expect(FileManager.default.fileExists(atPath: stable.path) == false)
    let saved = try #require(FileManager.default.contentsOfDirectory(at: experiment, includingPropertiesForKeys: nil).first)
    #expect(try FileManager.default.attributesOfItem(atPath: saved.path)[.posixPermissions] as? Int == 0o600)
}

@MainActor
@Test func queueExperimentFlushesPriorAccountBeforeActivationAndReadsV2() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = PlaybackStateStore(directory: dir)
    store.activate("account:A")
    store.scheduleSave(snapshot: { queueState(title: "A pending") })
    store.activate("account:B")
    #expect(store.load() == nil)
    store.activate("account:A")
    #expect(store.load()?.contextTitle == "A pending")

    let v2 = SavedPlaybackState(version: 2, tracks: [], currentIndex: 0, currentTrack: nil,
                                context: nil, contextTitle: "v2", radioSeed: "seed",
                                isShuffle: false, isRepeat: false)
    store.saveNow(v2)
    #expect(store.load()?.radioSeed == "seed")
}

private func queueState(title: String) -> SavedPlaybackState {
    SavedPlaybackState(version: SavedPlaybackState.currentVersion, tracks: [], currentIndex: 0,
                       currentTrack: nil, context: nil, contextTitle: title, radioSeed: nil,
                       isShuffle: false, isRepeat: false)
}
