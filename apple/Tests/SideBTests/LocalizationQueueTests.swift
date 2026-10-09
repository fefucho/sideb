import XCTest
import SideBCore
@testable import SideB

@MainActor
final class LocalizationQueueTests: XCTestCase {
    func testInterpolatedQueueLabelPersistsArgumentsWithoutChangingContextIdentity() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)
        let queue = QueueManager()
        let context = QueueContext.custom(title: "Original Artist (Aleatorio)")
        queue.replaceQueue(with: [song("artist")], context: context)
        queue.setContextLocalizationKey("player.shuffledArtist", args: ["Original Artist"])
        let spanish = queue.displayContextTitle
        let saved = try XCTUnwrap(SavedPlaybackState.Context(context, localizationKey: queue.contextLocalizationKey,
            localizationArguments: queue.contextLocalizationArguments))
        let restored = try JSONDecoder().decode(SavedPlaybackState.Context.self, from: JSONEncoder().encode(saved))
        AppLanguageStore.shared.setLanguage(.en)
        XCTAssertNotEqual(queue.displayContextTitle, spanish)
        XCTAssertEqual(queue.displayContextTitle, L10n.text("player.shuffledArtist", args: ["Original Artist"]))
        XCTAssertEqual(queue.context, context)
        XCTAssertEqual(restored.queueContext, context)
        XCTAssertEqual(restored.localizationArguments, ["Original Artist"])
        queue.setContextLocalizationKey("player.shuffledArtist")
        XCTAssertNil(queue.contextLocalizationKey, "Reject a descriptor with the wrong parameter count.")
    }

    func testLanguageChangePreservesQueueOccurrencesOrderModesAndNotifications() {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)
        let queue = QueueManager()
        let duplicate = song("duplicate")
        queue.addTracksToQueue([duplicate, duplicate, song("tail")])
        _ = queue.selectTrack(at: 1)
        queue.setShuffle(true, seed: 7)
        queue.isRepeat = true
        queue.continuationToken = "provider-token"
        let token = queue.queueToken
        let context = queue.context
        let order = queue.orderSnapshot
        let tracks = queue.queue
        let currentTrack = queue.currentTrack
        var notifications = 0
        queue.onStateChange = { notifications += 1 }

        XCTAssertEqual(queue.displayContextTitle, "Cola manual")
        AppLanguageStore.shared.setLanguage(.en)
        XCTAssertEqual(queue.displayContextTitle, "Manual queue")
        XCTAssertEqual(queue.queueToken, token)
        XCTAssertEqual(queue.context, context)
        XCTAssertEqual(queue.orderSnapshot, order)
        XCTAssertEqual(queue.queue, tracks)
        XCTAssertEqual(queue.currentTrack, currentTrack)
        XCTAssertEqual(queue.continuationToken, "provider-token")
        XCTAssertTrue(queue.isShuffle)
        XCTAssertTrue(queue.isRepeat)
        XCTAssertEqual(notifications, 0)
    }

    func testContextPresentationMetadataIsOptionalAndDoesNotGuessUserTitles() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        let context = QueueContext.custom(title: "Historial")
        let saved = try XCTUnwrap(SavedPlaybackState.Context(context, localizationKey: "history.title"))
        let decoded = try JSONDecoder().decode(SavedPlaybackState.Context.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.queueContext, context)
        XCTAssertEqual(decoded.localizationKey, "history.title")
        let legacy = try JSONDecoder().decode(SavedPlaybackState.Context.self,
            from: Data(#"{"kind":"custom","title":"Historial"}"#.utf8))
        XCTAssertNil(legacy.localizationKey)
        XCTAssertEqual(legacy.queueContext, context)

        let queue = QueueManager()
        queue.replaceQueue(with: [song("one")], context: legacy.queueContext)
        AppLanguageStore.shared.setLanguage(.en)
        XCTAssertEqual(queue.displayContextTitle, "Historial")
        queue.setContextLocalizationKey("history.title")
        XCTAssertEqual(queue.displayContextTitle, "History")
        queue.context = .custom(title: "Cola manual")
        XCTAssertNil(queue.contextLocalizationKey)
        XCTAssertEqual(queue.displayContextTitle, "Cola manual")
        queue.setContextLocalizationKey("missing.untrusted.key")
        XCTAssertNil(queue.contextLocalizationKey)
    }

    func testPlayerPersistsOwnedQueueLabelAndRestoresItInSelectedLanguage() throws {
        let previous = L10n.language
        defer { AppLanguageStore.shared.setLanguage(previous) }
        AppLanguageStore.shared.setLanguage(.es)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SideB.Localization.Playback.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            preferences.removePersistentDomain(forName: suite)
        }
        let track = song("saved")
        let first = PlayerViewModel(rustCore: nil,
            audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "test"),
            playbackStore: PlaybackStateStore(directory: directory))
        first.switchPlaybackSession(to: "fixture")
        first.queueManager.addTracksToQueue([track])
        first.currentTrack = track
        first.flushPlaybackState()
        AppLanguageStore.shared.setLanguage(.en)
        let restored = PlayerViewModel(rustCore: nil,
            audioService: AudioPlayerService(preferences: preferences, preferencePrefix: "test"),
            playbackStore: PlaybackStateStore(directory: directory))
        restored.switchPlaybackSession(to: "fixture")
        XCTAssertEqual(restored.queueManager.context, first.queueManager.context)
        XCTAssertEqual(restored.queueManager.orderSnapshot, first.queueManager.orderSnapshot)
        XCTAssertEqual(restored.queueManager.contextLocalizationKey, "queue.manual")
        XCTAssertEqual(restored.queueManager.displayContextTitle, "Manual queue")
        XCTAssertEqual(restored.currentTrack, track)
        XCTAssertFalse(restored.isPlaying)
    }

    private func song(_ id: String) -> SongItemRecord {
        SongItemRecord(videoId: id, title: "Original \(id)", artists: "Artist", album: nil,
            duration: nil, thumbnail: nil, artistId: nil, albumId: nil, setVideoId: nil,
            isVideo: false, isUpload: false, library: nil)
    }
}
