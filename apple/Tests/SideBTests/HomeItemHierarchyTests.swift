import AppKit
import SideBCore
import XCTest
@testable import SideB

@MainActor
final class HomeItemHierarchyTests: XCTestCase {
    private func configure(_ card: HomeItemView, id: String, kind: String = "song",
                           style: HomeSectionStyle, album: String? = nil,
                           explicit: Bool = false, onArtist: @escaping () -> Void = {},
                           onAlbum: @escaping () -> Void = {},
                           currentTrackID: String? = nil, currentAlbumBrowseId: String? = nil,
                           queueContext: QueueContext? = nil, isPlaying: Bool = false) {
        card.configure(record: HomeItemRecord(
            kind: kind, id: id, title: id, subtitle: kind == "playlist" ? "Publisher • 10 songs" : "Artist", thumbnail: nil,
            duration: nil, artists: "Artist", artistId: "artist-id", album: album,
            albumId: album == nil ? nil : "album-id", artistRuns: [], explicit: explicit),
            style: style, currentTrackID: currentTrackID, currentAlbumBrowseId: currentAlbumBrowseId,
            isPlaying: isPlaying, queueContext: queueContext,
            onCard: {}, onCover: {}, onTitle: {}, onArtist: onArtist, onAlbum: onAlbum,
            menuProvider: { nil })
        card.layoutSubtreeIfNeeded()
    }

    private func labels(in card: HomeItemView) -> [NSTextField] {
        card.subviews.compactMap { $0 as? NSTextField }
    }

    func testFormatReuseRemountsSameMetadataControlsWithNewActions() throws {
        let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: 330, height: 56))
        let artist = card.artist
        var actions: [String] = []
        configure(card, id: "first", style: .compactSong, album: "Album", explicit: true,
                  onArtist: { actions.append("first artist") }, onAlbum: { actions.append("first album") })
        let album = try XCTUnwrap(card.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Album" })
        let badge = try XCTUnwrap(labels(in: card).first { $0.stringValue == "E" })
        artist.performClick(nil)
        album.performClick(nil)

        card.frame.size = NSSize(width: 140, height: 234)
        configure(card, id: "large", kind: "album", style: .largeCard)
        XCTAssertNil(album.superview)
        XCTAssertNil(badge.superview)
        XCTAssertTrue(artist.superview === card)
        let artistLabel = try XCTUnwrap(labels(in: card).first { $0.stringValue == "Artist" })
        let labelIndex = try XCTUnwrap(card.subviews.firstIndex { $0 === artistLabel })
        let buttonIndex = try XCTUnwrap(card.subviews.firstIndex { $0 === artist })
        XCTAssertLessThan(labelIndex, buttonIndex) // The transparent artist action remains above its label.

        card.frame.size = NSSize(width: 330, height: 56)
        configure(card, id: "second", style: .compactSong, album: "Album", explicit: true,
                  onArtist: { actions.append("second artist") }, onAlbum: { actions.append("second album") })
        XCTAssertTrue(artist === card.artist)
        XCTAssertTrue(album.superview === card)
        XCTAssertTrue(badge.superview === card)
        XCTAssertNil(artistLabel.superview)
        artist.performClick(nil)
        album.performClick(nil)
        XCTAssertEqual(actions, ["first artist", "first album", "second artist", "second album"])
        XCTAssertEqual(album.accessibilityLabel(), "Ver álbum: Album")
        XCTAssertNil(card.window)
    }

    func testCompactAndUnlinkedPlaylistDoNotMountUnusedMetadata() throws {
        let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: 330, height: 56))
        configure(card, id: "compact", style: .compactSong)
        XCTAssertEqual(labels(in: card).map(\.stringValue), ["compact"])
        let compactControlCount = card.subviews.filter { $0 is NSControl }.count
        XCTAssertEqual(compactControlCount, 7)
        let title = try XCTUnwrap(labels(in: card).first { $0.stringValue == "compact" })
        let titlePoint = NSPoint(x: title.frame.midX, y: title.frame.midY)
        XCTAssertTrue(card.hitTest(titlePoint) === card.cardButton)
        XCTAssertTrue(card.cardButton.accessibilityLabel()?.contains("compact") == true)

        card.frame.size = NSSize(width: 140, height: 234)
        configure(card, id: "playlist", kind: "playlist", style: .largeCard)
        XCTAssertNil(card.artist.superview) // No linked creator; native subtitle remains visible.
        XCTAssertEqual(Set(labels(in: card).map(\.stringValue)), ["playlist", L10n.text("metadata.playlist"), "Publisher • 10 songs", "•"])
        XCTAssertFalse(card.subviews.contains { $0.isHidden && $0 is NSTextField })

        card.frame.size = NSSize(width: 330, height: 56)
        configure(card, id: "compact again", style: .compactSong)
        XCTAssertTrue(card.artist.superview === card)
        XCTAssertEqual(labels(in: card).map(\.stringValue), ["compact again"])
        XCTAssertEqual(card.subviews.filter { $0 is NSControl }.count, compactControlCount)
    }

    func testSongActivityFollowsRadioSeedAfterTrackAdvances() {
        let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: 140, height: 234))
        configure(card, id: "radio-seed", style: .largeCard, currentTrackID: "later-track",
                  queueContext: .radio(seedVideoId: "radio-seed", title: "Radio", seedName: "Seed"), isPlaying: true)
        XCTAssertFalse(card.equalizerOverlay.isHidden)

        card.updatePlayback(currentTrackID: "radio-seed", isPlaying: true,
                            queueContext: .radio(seedVideoId: "another-seed", title: "Radio", seedName: "Other"))
        XCTAssertTrue(card.equalizerOverlay.isHidden)
    }

    func testPausedRadioKeepsSeedIndicatorAndRevealsPlayOnHover() throws {
        let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: 140, height: 234))
        configure(card, id: "radio-seed", style: .largeCard,
                  queueContext: .radio(seedVideoId: "radio-seed", title: "Radio", seedName: "Seed"), isPlaying: false)
        XCTAssertFalse(card.equalizerOverlay.isHidden)

        let play = try XCTUnwrap(card.subviews.compactMap { $0 as? HomePlayHitButton }.first)
        XCTAssertEqual(play.frame.midX, 70, accuracy: 0.1)
        XCTAssertEqual(play.frame.midY, 70, accuracy: 0.1)
        let playPoint = NSPoint(x: play.frame.midX, y: play.frame.midY)
        let idleTarget = try XCTUnwrap(card.hitTest(playPoint))
        card.setHovered(true)
        card.updateHoverLocation(playPoint)
        card.layoutSubtreeIfNeeded()
        let hoverTarget = try XCTUnwrap(card.hitTest(playPoint))
        XCTAssertFalse(idleTarget === hoverTarget)
        XCTAssertTrue(hoverTarget === play)
        XCTAssertTrue(card.equalizerOverlay.isHidden)
    }

    func testCollectionActivityRequiresItsQueueContextAndCanonicalIdentity() {
        let albumCard = HomeItemView(frame: NSRect(x: 0, y: 0, width: 140, height: 234))
        configure(albumCard, id: "MPRE-album", kind: "album", style: .largeCard,
                  currentAlbumBrowseId: "MPRE-album",
                  queueContext: .radio(seedVideoId: "song", title: "Radio", seedName: "Song"), isPlaying: true)
        XCTAssertTrue(albumCard.equalizerOverlay.isHidden)

        albumCard.updatePlayback(currentTrackID: "song", currentAlbumBrowseId: nil, isPlaying: true,
                                 queueContext: .album(browseId: "MPRE-album", title: "Album"))
        XCTAssertFalse(albumCard.equalizerOverlay.isHidden)

        let playlistCard = HomeItemView(frame: NSRect(x: 0, y: 0, width: 140, height: 234))
        configure(playlistCard, id: "VLPL123", kind: "playlist", style: .largeCard,
                  queueContext: .playlist(browseId: "PL123", title: "Playlist"), isPlaying: true)
        XCTAssertFalse(playlistCard.equalizerOverlay.isHidden)
    }

    func testPlayAndMoreHitTargetsStaySeparateFromCardAndCredits() throws {
        let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: 140, height: 234))
        configure(card, id: "album", kind: "album", style: .largeCard)
        card.layoutSubtreeIfNeeded()
        let play = try XCTUnwrap(card.subviews.compactMap { $0 as? HomePlayHitButton }.first)
        let playPoint = NSPoint(x: play.frame.midX, y: play.frame.midY)
        let title = try XCTUnwrap(labels(in: card).first { $0.stringValue == "album" })
        let more = try XCTUnwrap(card.subviews.compactMap { $0 as? NSButton }.first {
            $0.accessibilityLabel() == "Más opciones"
        })
        let morePoint = NSPoint(x: more.frame.midX, y: more.frame.midY)
        XCTAssertLessThan(play.frame.maxY, 140)
        XCTAssertGreaterThan(play.frame.midX, 70)
        XCTAssertFalse(play.frame.intersects(more.frame))
        let titlePoint = NSPoint(x: title.frame.midX, y: title.frame.midY)
        let idlePlayTarget = try XCTUnwrap(card.hitTest(playPoint))
        let idleMoreTarget = try XCTUnwrap(card.hitTest(morePoint))
        XCTAssertFalse(idleMoreTarget === more)
        card.setHovered(true)
        card.updateHoverLocation(playPoint)
        let playTarget = try XCTUnwrap(card.hitTest(playPoint))
        XCTAssertFalse(idlePlayTarget === playTarget)
        XCTAssertTrue(playTarget === play)
        card.updateHoverLocation(morePoint)
        XCTAssertTrue(card.hitTest(morePoint) === more)
        XCTAssertTrue(card.hitTest(titlePoint) === card.cardButton)
    }

    func testFocusWithinCardIncludesItsInteractiveButtonsWithoutWindow() throws {
        let card = HomeItemView(frame: NSRect(x: 0, y: 0, width: 140, height: 234))
        configure(card, id: "focus", style: .largeCard)
        let play = try XCTUnwrap(card.subviews.compactMap { $0 as? HomePlayHitButton }.first)
        let more = try XCTUnwrap(card.subviews.compactMap { $0 as? HomeInteractiveLinkButton }.first {
            $0.accessibilityLabel() == "Más opciones"
        })
        let unrelated = NSView(frame: .zero)

        XCTAssertTrue(card.containsResponderInCard(card.artist))
        XCTAssertTrue(card.containsResponderInCard(play))
        XCTAssertTrue(card.containsResponderInCard(more))
        XCTAssertTrue(card.containsResponderInCard(card.cardButton))
        XCTAssertFalse(card.containsResponderInCard(unrelated))
        XCTAssertNil(card.window)
    }
}
