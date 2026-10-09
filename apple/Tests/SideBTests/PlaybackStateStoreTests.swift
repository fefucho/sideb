import Foundation
import AVFoundation
import Testing
import SideBCore
@testable import SideB

@MainActor
@Test func playbackStateRoundTripAndAccountIsolation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PlaybackStateStore(directory: directory)
    let song = SongItemRecord(videoId: "track-1", title: "Canción", artists: "Artista",
                              album: "Álbum", duration: "3:20", thumbnail: nil,
                              artistId: "artist-1", albumId: "album-1", setVideoId: nil,
                              isVideo: false, isUpload: false, library: nil)
    let state = SavedPlaybackState(version: SavedPlaybackState.currentVersion,
                                   tracks: [.init(song)], currentIndex: 0,
                                   currentTrack: .init(song),
                                   context: .init(.album(browseId: "album-1", title: "Álbum")),
                                   contextTitle: "Álbum: Álbum", radioSeed: nil,
                                   isShuffle: true, isRepeat: false)

    store.activate("account:A")
    #expect(store.load() == nil)
    store.saveNow(state)
    let loaded = try #require(store.load())
    #expect(loaded.tracks.map(\.song) == [song])
    #expect(loaded.currentTrack?.song == song)
    #expect(loaded.context?.queueContext == .album(browseId: "album-1", title: "Álbum"))
    #expect(loaded.isShuffle)

    store.activate("guest")
    #expect(store.load() == nil)
    store.activate("account:B")
    #expect(store.load() == nil)
    store.activate("account:A")
    #expect(store.load()?.currentTrack?.videoId == "track-1")
}

@MainActor
@Test func playbackStateRejectsDamagedAndUnknownFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PlaybackStateStore(directory: directory)
    store.activate("guest")
    #expect(store.load() == nil)
    let state = SavedPlaybackState(version: SavedPlaybackState.currentVersion,
                                   tracks: [], currentIndex: 0, currentTrack: nil,
                                   context: nil, contextTitle: "Cola de reproducción",
                                   radioSeed: nil, isShuffle: false, isRepeat: false)
    store.saveNow(state)
    let file = try #require(FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil).first)
    try Data("{broken".utf8).write(to: file, options: .atomic)
    #expect(store.load() == nil)
    try Data("{\"version\":1,\"tracks\":[]}".utf8).write(to: file, options: .atomic)
    #expect(store.load() == nil)
    let future = SavedPlaybackState(version: 999, tracks: [], currentIndex: 0,
                                    currentTrack: nil, context: nil, contextTitle: "Cola",
                                    radioSeed: nil, isShuffle: false, isRepeat: false)
    try JSONEncoder().encode(future).write(to: file, options: .atomic)
    #expect(store.load() == nil)
}

@MainActor
@Test func volumeAndMuteSurviveNewAudioService() throws {
    let suite = "SideBPlaybackTests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }

    let first = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    #expect(first.volume == 1.0)
    first.volume = 0.42
    first.toggleMute()
    #expect(first.volume == 0)

    let restored = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    #expect(restored.volume == 0)
    restored.toggleMute()
    #expect(abs(restored.volume - 0.42) < 0.001)
}

@MainActor
@Test func playerRestoresPausedAndPlayStartsStreamResolution() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let preferences = try #require(UserDefaults(suiteName: "SideBPlaybackTests.\(UUID().uuidString)"))
    let song = SongItemRecord(videoId: "track-2", title: "Última", artists: "Artista",
                              album: nil, duration: "2:00", thumbnail: nil,
                              artistId: nil, albumId: nil, setVideoId: nil,
                              isVideo: false, isUpload: false, library: nil)
    do {
        let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
        let player = PlayerViewModel(rustCore: nil, audioService: audio,
                                     playbackStore: PlaybackStateStore(directory: directory))
        player.switchPlaybackSession(to: "account:A")
        player.queueManager.replaceQueue(with: [song], context: .custom(title: "Cola manual"))
        player.currentTrack = song
        player.flushPlaybackState()
    }

    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let restored = PlayerViewModel(rustCore: nil, audioService: audio,
                                    playbackStore: PlaybackStateStore(directory: directory))
    restored.switchPlaybackSession(to: "account:A")
    #expect(restored.currentTrack?.videoId == "track-2")
    #expect(restored.queueManager.queue.map(\.videoId) == ["track-2"])
    #expect(!restored.isPlaying)
    #expect(restored.currentTime == 0)
    #expect(audio.avPlayer.currentItem == nil)

    restored.switchPlaybackSession(to: "guest")
    #expect(restored.currentTrack == nil)
    #expect(restored.queueManager.queue.isEmpty)
    restored.switchPlaybackSession(to: "account:A")
    #expect(restored.currentTrack?.videoId == "track-2")

    restored.togglePlayPause()
    #expect(restored.errorMessage == L10n.text("player.error.coreUnavailable"))
    #expect(!restored.isPlaying)
}

@MainActor
@Test func rapidSkipsKeepQueueNavigableAfterResolutionError() throws {
    let preferences = try #require(UserDefaults(suiteName: "SideBPlaybackTests.\(UUID().uuidString)"))
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let player = PlayerViewModel(rustCore: nil, audioService: audio)
    let tracks = (0..<5).map { index in
        SongItemRecord(videoId: "track-\(index)", title: "Pista \(index)", artists: "Artista",
                       album: nil, duration: "2:00", thumbnail: nil, artistId: nil,
                       albumId: nil, setVideoId: nil, isVideo: false, isUpload: false,
                       library: nil)
    }
    player.queueManager.replaceQueue(with: tracks, context: .custom(title: "Prueba"))
    audio.play(urlString: "file:///tmp/sideb-no-existe.m4a")
    #expect(audio.avPlayer.currentItem != nil)

    player.playSongNow(tracks[0])
    for _ in 0..<4 { player.playNext() }

    #expect(player.queueManager.currentIndex == 4)
    #expect(player.currentTrack?.videoId == "track-4")
    #expect(player.errorMessage == L10n.text("player.error.coreUnavailable"))
    #expect(audio.avPlayer.currentItem == nil)
    player.playPrevious()
    #expect(player.queueManager.currentIndex == 3)
    #expect(player.currentTrack?.videoId == "track-3")
}

@MainActor
@Test func manualSkipAtTailContinuesWhenQueueExtends() throws {
    let preferences = try #require(UserDefaults(suiteName: "SideBPlaybackTests.\(UUID().uuidString)"))
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let player = PlayerViewModel(rustCore: nil, audioService: audio)
    let first = SongItemRecord(videoId: "first", title: "Primera", artists: "Artista",
                               album: nil, duration: nil, thumbnail: nil, artistId: nil,
                               albumId: nil, setVideoId: nil, isVideo: false, isUpload: false,
                               library: nil)
    let second = SongItemRecord(videoId: "second", title: "Segunda", artists: "Artista",
                                album: nil, duration: nil, thumbnail: nil, artistId: nil,
                                albumId: nil, setVideoId: nil, isVideo: false, isUpload: false,
                                library: nil)
    player.queueManager.replaceQueue(with: [first], context: .radio(seedVideoId: "first", title: "Radio", seedName: "Primera"))
    player.playSongNow(first)
    player.playNext()
    player.queueManager.appendRadioTracks([second])
    player.resumeAfterQueueExtension()

    #expect(player.queueManager.currentIndex == 1)
    #expect(player.currentTrack?.videoId == "second")
    player.resumeAfterQueueExtension()
    #expect(player.queueManager.currentIndex == 1)
}
