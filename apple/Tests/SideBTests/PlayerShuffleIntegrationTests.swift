import Foundation
import AVFoundation
import Testing
import SideBCore
@testable import SideB

private func shuffleFixture(_ index: Int, videoID: String? = nil) -> SongItemRecord {
    SongItemRecord(videoId: videoID ?? "shuffle-\(index)", title: "Pista \(index)", artists: "Artista",
                   album: nil, duration: nil, thumbnail: nil, artistId: nil,
                   albumId: nil, setVideoId: "occurrence-\(index)", isVideo: false, isUpload: false, library: nil)
}

@MainActor
@Test func playerShufflePreservesAudioTimeItemAndExactDuplicateOccurrence() throws {
    let suite = "SideBShuffle.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let player = PlayerViewModel(rustCore: nil, audioService: audio)
    let songs = (0..<12).map { shuffleFixture($0, videoID: "duplicate") }
    player.queueManager.replaceQueue(with: songs, startingAt: 6, context: .album(browseId: "album", title: "Álbum"))
    player.currentTrack = songs[6]
    // Install an item without starting playback or making a network request.
    let item = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/sideb-shuffle-fixture.m4a"))
    audio.avPlayer.replaceCurrentItem(with: item)
    audio.currentTime = 38.5
    audio.duration = 180
    let occurrence = player.queueManager.currentOccurrenceID
    let queueToken = player.queueManager.queueToken
    player.queueManager.setShuffle(true, seed: 87)
    player.queueManager.setShuffle(false)
    player.queueManager.setShuffle(true, seed: 99)
    #expect(audio.avPlayer.currentItem === item)
    #expect(player.currentTime == 38.5)
    #expect(player.currentTrack == songs[6])
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(player.queueManager.queueToken == queueToken)
    #expect(player.errorMessage == nil)
    audio.stop()
}

@MainActor
@Test func playerShuffleSessionRoundTripRestoresFullOrderAndManualPlacements() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "SideBShuffle.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let songs = (0..<2000).map { shuffleFixture($0, videoID: $0 == 700 ? "shuffle-0" : nil) }
    let first = PlayerViewModel(rustCore: nil,
        audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "first"),
        playbackStore: PlaybackStateStore(directory: directory))
    first.switchPlaybackSession(to: "account:A")
    first.queueManager.replaceQueue(with: songs, startingAt: 700, context: .playlist(browseId: "playlist", title: "Lista"))
    first.currentTrack = songs[700]
    let active = first.queueManager.currentOccurrenceID
    first.queueManager.playNext([shuffleFixture(3000), shuffleFixture(3001)])
    first.queueManager.setShuffle(true, seed: 123)
    let snapshot = first.queueManager.orderSnapshot
    first.flushPlaybackState()
    let restored = PlayerViewModel(rustCore: nil,
        audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "second"),
        playbackStore: PlaybackStateStore(directory: directory))
    restored.switchPlaybackSession(to: "account:A")
    #expect(restored.queueManager.orderSnapshot == snapshot)
    #expect(restored.queueManager.queue.count == 2002)
    #expect(restored.queueManager.isShuffle)
    #expect(restored.currentTrack == songs[700])
    #expect(restored.audioService.avPlayer.currentItem == nil)
    restored.queueManager.setShuffle(false)
    #expect(restored.queueManager.currentOccurrenceID == active)
    #expect(restored.queueManager.currentIndex == 700)
    #expect(Array(restored.queueManager.queue[701...702]).map(\.videoId) == ["shuffle-3000", "shuffle-3001"])
    #expect(restored.queueManager.queue.filter { $0.setVideoId != "occurrence-3000" && $0.setVideoId != "occurrence-3001" } == songs)
    restored.switchPlaybackSession(to: "account:B")
    #expect(restored.queueManager.queue.isEmpty)
    restored.switchPlaybackSession(to: "account:A")
    #expect(restored.queueManager.currentOccurrenceID == active)
}

@MainActor
@Test func legacyShuffledSessionDoesNotInventAnOriginalSourceOrder() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let songs = [shuffleFixture(9), shuffleFixture(2), shuffleFixture(5)]
    let store = PlaybackStateStore(directory: directory)
    store.activate("account:legacy")
    store.saveNow(SavedPlaybackState(version: 1, tracks: songs.map(SavedPlaybackState.Track.init),
        currentIndex: 1, currentTrack: .init(songs[1]), context: .init(.custom(title: "Legado")),
        contextTitle: "Legado", radioSeed: nil, isShuffle: true, isRepeat: false))
    #expect(store.load()?.version == 1)
    let suite = "SideBShuffle.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let player = PlayerViewModel(rustCore: nil,
        audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "test"), playbackStore: store)
    player.switchPlaybackSession(to: "account:legacy")
    #expect(player.queueManager.isShuffle)
    player.queueManager.setShuffle(false)
    #expect(player.queueManager.queue == songs)
    #expect(player.queueManager.currentIndex == 1)
}

@MainActor
@Test func albumAndArtistEntryPointsKeepCanonicalSourceForRestoration() throws {
    let suite = "SideBShuffle.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let player = PlayerViewModel(rustCore: nil, audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "test"))
    let songs = (0..<12).map { shuffleFixture($0) }
    player.playAlbum(browseId: "album", title: "Álbum", tracks: songs, shuffle: true)
    let albumActive = player.queueManager.currentOccurrenceID
    player.queueManager.setShuffle(false)
    #expect(player.queueManager.queue == songs)
    #expect(player.queueManager.currentOccurrenceID == albumActive)
    player.playCollection(tracks: songs, title: "Artista", artistBrowseId: "artist", shuffle: true)
    let artistActive = player.queueManager.currentOccurrenceID
    player.queueManager.setShuffle(false)
    #expect(player.queueManager.queue == songs)
    #expect(player.queueManager.currentOccurrenceID == artistActive)
    #expect(player.currentArtistBrowseId == "artist")
}
