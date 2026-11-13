import Foundation
import SideBCore
import Testing
@testable import SideB

@Suite("Jam: Spotify track to YouTube Music match")
struct JamMatcherTests {
    private func song(_ id: String, _ title: String, _ artists: String, _ duration: String, video: Bool = false) -> SongItemRecord {
        SongItemRecord(videoId: id, title: title, artists: artists, album: nil, duration: duration,
                       thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil, isVideo: video, isUpload: false,
                       library: nil, artistRuns: [], contentRating: .unknown)
    }
    private func track(_ title: String, _ artists: [String], seconds: Double) -> JamTrack {
        JamTrack(uri: "spotify:track:x", title: title, artists: artists, album: nil, durationMs: seconds * 1000, isrc: nil, provider: nil)
    }

    @Test("Same recording wins over a video and over another version")
    func prefersSameRecording() {
        let ranked = JamMatcher.rank(track: track("Sueño Stereo", ["Soda Stereo"], seconds: 200), candidates: [
            song("video", "Sueño Stereo", "Soda Stereo", "3:20", video: true),
            song("live", "Sueño Stereo (En Vivo)", "Soda Stereo", "5:02"),
            song("album", "Sueno Stereo - Remasterizado 2007", "Soda Stereo", "3:20"),
        ])
        #expect(ranked.first?.song.videoId == "album")
        #expect(ranked.first?.isConfident == true)
        #expect(ranked.first?.durationDelta == 0)
    }

    @Test("An unrelated result is not accepted")
    func rejectsUnrelated() {
        let ranked = JamMatcher.rank(track: track("Persiana Americana", ["Soda Stereo"], seconds: 290), candidates: [
            song("other", "Otra canción", "Otro artista", "2:10"),
        ])
        #expect(ranked.first?.isConfident == false)
    }

    @Test("Durations and names are normalised")
    func normalises() {
        #expect(JamMatcher.seconds("3:20") == 200)
        #expect(JamMatcher.seconds("1:02:03") == 3723)
        #expect(JamMatcher.seconds("x") == nil)
        #expect(JamMatcher.normalize("Canción (feat. Otro) [Deluxe]") == "cancion")
        #expect(JamMatcher.query(for: track("A", ["B", "C"], seconds: 1)) == "A B")
    }

    @Test("Live position advances only while playing")
    func livePosition() {
        let playing = JamPlaybackState(positionMs: 30_000, atLocalMs: 1_000, paused: false, durationMs: nil)
        #expect(playing.livePositionSeconds(nowMs: 3_500) == 32.5)
        let paused = JamPlaybackState(positionMs: 30_000, atLocalMs: 1_000, paused: true, durationMs: nil)
        #expect(paused.livePositionSeconds(nowMs: 3_500) == 30)
    }
}
