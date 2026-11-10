import AppKit
import SwiftUI
import Testing
import SideBCore
@testable import SideB

@MainActor private func makeSidebarTestPlayer(_ directory: URL, preferences: UserDefaults) -> PlayerViewModel {
    PlayerViewModel(
        rustCore: nil,
        audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "sidebar-rec-tests"),
        playbackStore: PlaybackStateStore(directory: directory)
    )
}

@Test @MainActor func recommendationsStateIsClearedOnTrackChange() throws {
    let suite = "SideBRecTrackChange.\(UUID())"
    let prefs = try #require(UserDefaults(suiteName: suite))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer {
        prefs.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    let player = makeSidebarTestPlayer(directory, preferences: prefs)
    let trackA = SongItemRecord(videoId: "track_a", title: "A", artists: "A", album: nil, duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)
    let trackB = SongItemRecord(videoId: "track_b", title: "B", artists: "B", album: nil, duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil)

    player.currentTrack = trackA
    player.recommendedData = RecommendedData(artistName: "A", artistBrowseId: nil, artistSongs: [], albumTitle: nil, albumBrowseId: nil, albumSongs: [], similarSongs: [trackB], relatedArtists: [], loadedVideoId: "track_a")
    #expect(player.recommendedData != nil)

    // Changing track must automatically invalidate and nil out recommendations data
    player.currentTrack = trackB
    #expect(player.recommendedData == nil)
}

@Test @MainActor func stableTrackIdentitiesByOccurrence() throws {
    let sharedTrack = SongItemRecord(
        videoId: "shared_video_id",
        title: "Duplicate Across Shelves",
        artists: "Multi Artist",
        album: "Multi Album",
        duration: "3:10",
        thumbnail: nil,
        artistId: "art_multi",
        albumId: "alb_multi",
        setVideoId: nil
    )

    let data = RecommendedData(
        artistName: "Multi Artist",
        artistBrowseId: "art_multi",
        artistSongs: [sharedTrack],
        albumTitle: "Multi Album",
        albumBrowseId: "alb_multi",
        albumSongs: [sharedTrack],
        similarSongs: [sharedTrack],
        relatedArtists: (0..<15).map { BrowseCardRecord(kind: "artist", id: "artist-\($0)", title: "Artist", subtitle: nil, thumbnail: nil, duration: nil) },
        loadedVideoId: "seed_track"
    )

    let prepared = PreparedSidebarRecommendations(data: data)
    #expect(prepared.artists.count == 10)
    #expect(prepared.similarSongs.count == 1)
    #expect(prepared.artistSongs.count == 1)
    #expect(prepared.albumSongs.count == 1)

    let simId = prepared.similarSongs[0].id
    let artId = prepared.artistSongs[0].id
    let albId = prepared.albumSongs[0].id

    // Stable occurrence IDs must encode shelf, index and videoId
    #expect(simId == "similar-0-shared_video_id")
    #expect(artId == "artist-0-shared_video_id")
    #expect(albId == "album-0-shared_video_id")

    // Must be strictly unique across shelves to prevent SwiftUI ID collisions
    let allIds = [simId, artId, albId]
    #expect(Set(allIds).count == 3)
}

@Test func sidebarRecommendationScrollPolicyThresholds() {
    let reqKey = RecommendedRequestState.Key(videoID: "vid1", artistID: nil, albumID: nil, account: UUID())

    // 1. Fetch trigger policy
    #expect(!SidebarRecommendationScrollPolicy.shouldTriggerFetch(
        offsetY: 0,
        hasTrack: true,
        recommendationKey: reqKey,
        lastRequestedKey: nil
    ))
    #expect(!SidebarRecommendationScrollPolicy.shouldTriggerFetch(
        offsetY: 23.9,
        hasTrack: true,
        recommendationKey: reqKey,
        lastRequestedKey: nil
    ))
    #expect(SidebarRecommendationScrollPolicy.shouldTriggerFetch(
        offsetY: 24.0,
        hasTrack: true,
        recommendationKey: reqKey,
        lastRequestedKey: nil
    ))
    #expect(!SidebarRecommendationScrollPolicy.shouldTriggerFetch(
        offsetY: 50.0,
        hasTrack: true,
        recommendationKey: reqKey,
        lastRequestedKey: reqKey // Already requested
    ))

    // 2. Content activation policy (upperHeight = 500 -> thresholdOffset = 100, progress 0.35 = 175)
    let upperHeight: CGFloat = 500
    #expect(!SidebarRecommendationScrollPolicy.shouldActivateContent(offsetY: 0, upperHeight: upperHeight))
    #expect(!SidebarRecommendationScrollPolicy.shouldActivateContent(offsetY: 24, upperHeight: upperHeight))
    #expect(!SidebarRecommendationScrollPolicy.shouldActivateContent(offsetY: 99, upperHeight: upperHeight))
    #expect(SidebarRecommendationScrollPolicy.shouldActivateContent(offsetY: 100, upperHeight: upperHeight))
    #expect(SidebarRecommendationScrollPolicy.shouldActivateContent(offsetY: 200, upperHeight: upperHeight))
}

@Test @MainActor func sidebarArtworkScrollStateMaintainsActivation() {
    let state = SidebarArtworkScrollState()
    let key = SidebarArtworkOccurrenceKey(sessionID: UUID(), playbackID: UUID(), videoID: "vid1", occurrenceID: "occ1")
    state.synchronizeOccurrence(key)
    #expect(!state.isRecommendationsActive)
    #expect(state.isHeroVisible)
    #expect(state.quantizedProgress == 0)

    var fetchTriggered = false
    // Scroll slightly (below activation offset 24)
    state.evaluateScroll(offsetY: 10, hasTrack: true, recommendationKey: nil, upperHeight: 500) {
        fetchTriggered = true
    }
    #expect(!fetchTriggered)
    #expect(!state.isRecommendationsActive)

    // Scroll past activation offset 24 to 30 with key
    let reqKey = RecommendedRequestState.Key(videoID: "vid1", artistID: nil, albumID: nil, account: UUID())
    state.evaluateScroll(offsetY: 30, hasTrack: true, recommendationKey: reqKey, upperHeight: 500) {
        fetchTriggered = true
    }
    #expect(fetchTriggered)
    #expect(!state.isRecommendationsActive) // Content not activated yet (needs 100pt)

    // Scroll past 100pt
    state.evaluateScroll(offsetY: 110, hasTrack: true, recommendationKey: reqKey, upperHeight: 500) {}
    #expect(state.isRecommendationsActive)

    // Scrolling back up slightly must NOT flip isRecommendationsActive back to false
    state.evaluateScroll(offsetY: 80, hasTrack: true, recommendationKey: reqKey, upperHeight: 500) {}
    #expect(state.isRecommendationsActive)
}


@Test func sidebarShortHeroDoesNotActivateContentAtRest() {
    for height: CGFloat in [1, 200, 260, 400] {
        #expect(!SidebarRecommendationScrollPolicy.shouldActivateContent(offsetY: 0, upperHeight: height))
        #expect(!SidebarRecommendationScrollPolicy.shouldActivateContent(offsetY: 23, upperHeight: height))
        #expect(SidebarRecommendationScrollPolicy.shouldActivateContent(offsetY: 24, upperHeight: height))
    }
}
