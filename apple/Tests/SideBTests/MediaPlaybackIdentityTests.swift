import AVFoundation
import Foundation
import SideBCore
import Testing
@testable import SideB

@Test func mediaCardsDistinguishRadioOriginFromCollectionContext() {
    let radio: QueueContext = .radio(seedVideoId: "origin", title: "Radio", seedName: "Origin")
    #expect(MediaPlaybackIdentity.isRadioOrigin(videoID: "origin", context: radio))
    #expect(!MediaPlaybackIdentity.isRadioOrigin(videoID: "next", context: radio))
    #expect(!MediaPlaybackIdentity.isCollectionActive(kind: "album", id: "album", context: radio))
    #expect(!MediaPlaybackIdentity.isRadioOrigin(videoID: "origin", context: .album(browseId: "origin", title: "Album")))
    #expect(!MediaPlaybackIdentity.isRadioOrigin(videoID: "", context: .radio(seedVideoId: "", title: "Radio", seedName: "")))
}

@Test func mediaCardsShareCanonicalCollectionIdentityWithoutCrossingTypes() {
    let playlist: QueueContext = .playlist(browseId: "PL123", title: "Playlist")
    #expect(MediaPlaybackIdentity.isCollectionActive(kind: "playlist", id: "VLPL123", context: playlist))
    #expect(MediaPlaybackIdentity.isCollectionActive(kind: "mix", id: " PL123 ", context: playlist))
    #expect(!MediaPlaybackIdentity.isCollectionActive(kind: "album", id: "PL123", context: playlist))
    #expect(!MediaPlaybackIdentity.isCollectionActive(kind: "playlist", id: "PL124", context: playlist))
    #expect(!MediaPlaybackIdentity.isCollectionActive(kind: "album", id: "album", context: nil))
}

private func mediaSong(_ id: String) -> SongItemRecord {
    SongItemRecord(videoId: id, title: id, artists: "Artist", album: nil, duration: nil,
        thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
        isVideo: false, isUpload: false, library: nil)
}

@Test @MainActor func mediaRadioOriginControlPreservesAdvancedQueueAndAudioItem() throws {
    let suite = "MediaRadio.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let player = PlayerViewModel(rustCore: nil, audioService: audio,
                               playbackStore: PlaybackStateStore(directory: directory))
    let origin = mediaSong("origin"), next = mediaSong("next")
    player.queueManager.replaceQueue(with: [origin, next], startingAt: 1,
        context: .radio(seedVideoId: origin.videoId, title: "Radio", seedName: origin.title))
    player.currentTrack = next
    let item = AVPlayerItem(url: URL(fileURLWithPath: "/tmp/sideb-media-fixture.m4a"))
    audio.avPlayer.replaceCurrentItem(with: item)
    audio.currentTime = 37
    let queueToken = player.queueManager.queueToken
    let occurrence = player.queueManager.currentOccurrenceID
    player.activateMediaRadio(origin)
    #expect(player.currentTrack == next)
    #expect(player.queueManager.queueToken == queueToken)
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(audio.avPlayer.currentItem === item)
    #expect(player.currentTime == 37)
    player.activateMediaCollection(id: "VLPL-other", kind: "unsupported")
    #expect(player.queueManager.queueToken == queueToken)
    audio.stop()
}

@Test @MainActor func mediaActiveCollectionControlDoesNotReloadOrResetQueue() throws {
    let suite = "MediaCollection.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let audio = AudioPlayerService(preferences: preferences, preferencePrefix: "test")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let player = PlayerViewModel(rustCore: nil, audioService: audio,
                               playbackStore: PlaybackStateStore(directory: directory))
    let songs = [mediaSong("first"), mediaSong("second")]
    player.queueManager.replaceQueue(with: songs, startingAt: 1,
                                    context: .playlist(browseId: "PL-active", title: "Playlist"))
    player.currentTrack = songs[1]
    let token = player.queueManager.queueToken
    let occurrence = player.queueManager.currentOccurrenceID
    player.activateMediaCollection(id: "VLPL-active", kind: "playlist")
    #expect(player.queueManager.queueToken == token)
    #expect(player.queueManager.currentOccurrenceID == occurrence)
    #expect(player.currentTrack == songs[1])
    #expect(player.loadingRecommendedPlaylistID == nil)
    audio.stop()
}
