import AppKit
import SideBCore
import SwiftUI
import XCTest
@testable import SideB

@MainActor
final class HomeFeaturedIdentityTests: XCTestCase {
    private func item(_ kind: String, index: Int) -> HomeItemRecord {
        HomeItemRecord(kind: kind, id: "\(kind)-\(index)", title: "\(kind) \(index)", subtitle: nil,
            thumbnail: nil, duration: nil, artists: nil, artistId: nil, album: nil, albumId: nil,
            artistRuns: [], explicit: false)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    func testAlbumControlsRetainIdentityAcrossColumnsAndStackedPanels() throws {
        let songs = (0..<9).map { item("song", index: $0) }
        let albums = (0..<36).map { item("album", index: $0) }
        func featured(width: CGFloat) -> HomeFeaturedView {
            HomeFeaturedView(songs: songs, collections: albums, collectionKind: .albums,
                width: width, resetKey: "session", loadingCollectionID: nil, core: nil,
                onSong: { _ in }, onCollection: { _ in }, onArtist: { _ in },
                onPlayCollection: { _, _ in }, menuProvider: { NSMenu(title: $0.id) })
        }
        let host = NSHostingView(rootView: featured(width: 1100))
        host.sizingOptions = []
        func menus(at width: CGFloat) -> [String: Set<ObjectIdentifier>] {
            host.rootView = featured(width: width)
            let height = HomeFeaturedLayout.height(width: width, hasSongs: true, hasAlbums: true,
                                                   songCount: songs.count, albumCount: albums.count)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            var identities: [String: Set<ObjectIdentifier>] = [:]
            for view in descendants(host).compactMap({ $0 as? NativeContextMenuNSView }) {
                if let id = view.menuBuilder?()?.title {
                    identities[id, default: []].insert(ObjectIdentifier(view))
                }
            }
            return identities
        }
        let initial = menus(at: 1100)
        let retainedInitialViews = descendants(host).compactMap { $0 as? NativeContextMenuNSView }
        defer { withExtendedLifetime(retainedInitialViews) {} }
        XCTAssertEqual(initial.keys.filter { $0.hasPrefix("album-") }.count, 2)
        let firstAlbum = try XCTUnwrap(initial["album-0"])
        let secondAlbum = try XCTUnwrap(initial["album-1"])
        XCTAssertFalse(firstAlbum.isEmpty)

        let sizes: [(CGFloat, Int)] = [(1512, 4), (1920, 6), (1512, 4), (899, 2), (900, 2), (1100, 2)]
        for (width, albumCount) in sizes {
            let current = menus(at: width)
            XCTAssertEqual(current.keys.filter { $0.hasPrefix("album-") }.count, albumCount)
            XCTAssertEqual(current["album-0"], firstAlbum, "First album recreated at width \(width)")
            XCTAssertEqual(current["album-1"], secondAlbum, "Second album recreated at width \(width)")
            for song in songs {
                XCTAssertEqual(current[song.id], initial[song.id], "Speed Dial recreated at width \(width)")
            }
        }
        XCTAssertNil(host.window) // Lifecycle evidence, no app/window interaction or FPS assertion.
    }
}
